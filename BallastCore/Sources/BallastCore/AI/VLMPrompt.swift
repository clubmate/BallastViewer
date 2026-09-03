import Foundation

/// U49: the text side of a profile run — pure functions, pinned by tests.
/// The model sees ONE prompt per photo and profile: the profile's
/// instructions, then every question with its allowed answers, then the
/// exact JSON shape to return. Answers come back keyed "q1", "q2", … in
/// question order; the parser maps them back to answer records.
public enum VLMPrompt {
    /// The default system prompt — editable in Settings ▸ AI (the app stores
    /// the user's version; this is what Reset restores).
    public static let systemPrompt =
        "You are a photo cataloguing assistant. Look at the photo and answer every question by choosing exactly one of the allowed answers. Answer with a single JSON object and nothing else."

    /// Bumped whenever the rendered prompt TEMPLATE changes (wording around
    /// the questions, the return shape) so cached replies from the old
    /// template are not mistaken for answers to the new one.
    public static let promptVersion = 2

    /// Fingerprint of the run settings that change a reply without touching
    /// the profile — system prompt, thinking, image resolution, template
    /// version. Combined with `questionnaireHash` for the reply-cache key.
    public static func settingsHash(systemPrompt: String, thinking: Bool, fullResolution: Bool) -> String {
        FNV1a.hex(
            [systemPrompt, thinking ? "think" : "direct", fullResolution ? "full" : "768", "v\(promptVersion)"]
                .joined(separator: "\u{1E}")
        )
    }

    /// JSON key of the question at `index` (0-based) — "q1", "q2", ….
    public static func key(forQuestionAt index: Int) -> String { "q\(index + 1)" }

    /// The user message for one profile (the photo is attached alongside).
    public static func userPrompt(for profile: AIProfile) -> String {
        var lines: [String] = []
        let instructions = profile.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            lines.append(instructions)
            lines.append("")
        }
        lines.append("Questions (answer each with exactly one of its allowed values):")
        for (index, question) in profile.questions.enumerated() {
            let values = question.answers.map { "\"\($0.value)\"" }.joined(separator: ", ")
            lines.append("\(index + 1). \"\(key(forQuestionAt: index))\": \(question.text) One of: \(values)")
        }
        // The allowed values repeat INSIDE the return shape: small models
        // copy the shape literally, which keeps answers on the list.
        let shape = profile.questions.enumerated()
            .map { index, question in
                "\"\(key(forQuestionAt: index))\": \"\(question.answers.map(\.value).joined(separator: "|"))\""
            }
            .joined(separator: ", ")
        lines.append("Return exactly this shape, one value per key: {\(shape)}")
        return lines.joined(separator: "\n")
    }

    /// Fingerprint of everything that changes what the model is ASKED — the
    /// cache key of a raw answer. Keyword mappings are deliberately left out:
    /// re-mapping an answer to another keyword must reuse cached answers.
    public static func questionnaireHash(for profile: AIProfile) -> String {
        var parts: [String] = [profile.instructions]
        for question in profile.questions {
            parts.append(question.text)
            parts.append(question.answers.map(\.value).joined(separator: "\u{1F}"))
        }
        let joined = parts.joined(separator: "\u{1E}")
        return FNV1a.hex(joined)
    }
}

/// Parses the model's reply. Lenient on purpose — small models wrap JSON in
/// fences or prose, change case or add a trailing period — but strict on
/// the values: an answer that is not one of the allowed values counts as
/// "no answer" for that question, never as a guess.
public enum VLMAnswerParser {
    /// Chosen answer per question id (questions the model skipped or answered
    /// off-list are absent). A chosen answer with `stopsProfile` ends the
    /// questionnaire: later questions are dropped even if answered.
    public static func parse(_ reply: String, profile: AIProfile) -> [Int64: AIAnswerRecord] {
        guard let object = extractObject(from: reply, keys: profile.questions.indices.map(VLMPrompt.key)) else {
            return [:]
        }
        var result: [Int64: AIAnswerRecord] = [:]
        for (index, question) in profile.questions.enumerated() {
            guard let questionId = question.id else { continue }
            let key = VLMPrompt.key(forQuestionAt: index)
            guard let raw = object[key] else { continue }
            let text: String
            switch raw {
            case let string as String: text = string
            case let number as NSNumber: text = number.stringValue
            default: continue
            }
            if let answer = match(text, in: question.answers) {
                result[questionId] = answer
                if answer.stopsProfile { break }
            }
        }
        return result
    }

    /// Keyword ids the parsed answers assign (answers without a keyword
    /// contribute nothing).
    public static func keywordIds(in parsed: [Int64: AIAnswerRecord]) -> Set<Int64> {
        Set(parsed.values.compactMap(\.keywordId))
    }

    /// Digits answered for number words ("1" for "one") — small models do.
    static let numberWords: [String: String] = [
        "0": "none", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
        "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten",
    ]

    static func match(_ text: String, in answers: [AIAnswerRecord]) -> AIAnswerRecord? {
        var needle = normalize(text)
        guard !needle.isEmpty else { return nil }
        if let word = numberWords[needle], answers.contains(where: { normalize($0.value) == word }) {
            needle = word
        }
        if let exact = answers.first(where: { normalize($0.value) == needle }) { return exact }
        // "face cut off" answered as "face_cut_off" or "Face cut-off".
        let squeezed = needle.filter(\.isLetter)
        return answers.first(where: { normalize($0.value).filter(\.isLetter) == squeezed && !squeezed.isEmpty })
    }

    static func normalize(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".\"'"))
    }

    /// The answer object in the reply. A thinking model first writes a
    /// `<think>…</think>` trace (which may itself contain braces), so the
    /// trace is dropped and the LAST {…} carrying one of the expected keys
    /// is preferred (a nested or unrelated trailing object falls through to
    /// the outermost span); a reply whose thinking never closed (token
    /// budget exhausted) has no answer.
    static func extractObject(from reply: String, keys: [String] = []) -> [String: Any]? {
        var text = reply
        // Qwen's chat template opens the trace in the prompt, so a reply may
        // start mid-thought and carry only the closing tag: everything up to
        // the last `</think>` is trace. An opening tag without a closing one
        // is a trace that ran out of tokens.
        if let lastClose = text.range(of: "</think>", options: .backwards) {
            text = String(text[lastClose.upperBound...])
        } else if text.contains("<think>") {
            return nil
        }
        guard let close = text.lastIndex(of: "}") else { return nil }
        func carriesAKey(_ object: [String: Any]) -> Bool {
            keys.isEmpty || keys.contains { object[$0] != nil }
        }
        if let open = text[...close].lastIndex(of: "{"), let object = decode(text[open ... close]), carriesAKey(object) {
            return object
        }
        guard let open = text.firstIndex(of: "{"), open < close, let object = decode(text[open ... close]) else {
            return nil
        }
        return carriesAKey(object) ? object : nil
    }

    private static func decode(_ slice: Substring) -> [String: Any]? {
        guard let data = String(slice).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// 64-bit FNV-1a — a stable, dependency-free fingerprint for cache keys.
enum FNV1a {
    static func hex(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
