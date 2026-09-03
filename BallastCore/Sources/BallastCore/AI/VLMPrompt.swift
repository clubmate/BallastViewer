import Foundation

/// U49: the text side of a profile run — pure functions, pinned by tests.
/// The model sees ONE prompt per photo and profile: the profile's
/// instructions, then every question with its allowed answers, then the
/// exact JSON shape to return. Answers come back keyed "q1", "q2", … in
/// question order; the parser maps them back to answer records.
public enum VLMPrompt {
    public static let systemPrompt =
        "You are a photo cataloguing assistant. Look at the photo and answer every question by choosing exactly one of the allowed answers. Answer with a single JSON object and nothing else."

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
        let shape = profile.questions.indices
            .map { "\"\(key(forQuestionAt: $0))\": ..." }
            .joined(separator: ", ")
        lines.append("Return: {\(shape)}")
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
    /// off-list are absent).
    public static func parse(_ reply: String, profile: AIProfile) -> [Int64: AIAnswerRecord] {
        guard let object = extractObject(from: reply) else { return [:] }
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
            }
        }
        return result
    }

    /// Keyword ids the parsed answers assign (answers without a keyword
    /// contribute nothing).
    public static func keywordIds(in parsed: [Int64: AIAnswerRecord]) -> Set<Int64> {
        Set(parsed.values.compactMap(\.keywordId))
    }

    static func match(_ text: String, in answers: [AIAnswerRecord]) -> AIAnswerRecord? {
        let needle = normalize(text)
        guard !needle.isEmpty else { return nil }
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

    /// The first {…} object in the reply, decoded as string values.
    static func extractObject(from reply: String) -> [String: Any]? {
        guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close else {
            return nil
        }
        let slice = String(reply[open ... close])
        guard let data = slice.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
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
