import Foundation

/// U49: the text side of a profile run — pure functions, pinned by tests.
/// The model sees ONE prompt per photo and profile: the profile's
/// instructions, then every question with its allowed answers, then the
/// exact JSON shape to return. Answers come back keyed "q1", "q2", … in
/// question order; the parser maps them back to answer records.
///
/// U50 — one pass, whatever the tree looks like: a follow-up question is
/// listed right after the question it depends on, marked "Only if q2 is
/// "female"", with "n/a" as its extra allowed value; the PARSER drops its
/// answer when the gate was not chosen, so consistency never depends on the
/// model honouring the condition. An open question asks for one or two
/// words; the words become a keyword.
public enum VLMPrompt {
    /// The default system prompt — editable in the AI window (the app stores
    /// the user's version; this is what Reset restores).
    public static let systemPrompt =
        "You are a photo cataloguing assistant. Look at the photo and answer every question by choosing exactly one of the allowed answers. Answer with a single JSON object and nothing else."

    /// Bumped whenever the rendered prompt TEMPLATE changes (wording around
    /// the questions, the return shape) so cached replies from the old
    /// template are not mistaken for answers to the new one.
    public static let promptVersion = 3

    /// The literal a gated question is answered with when its gate is not
    /// met — never an answer, never cached as one.
    public static let notApplicable = "n/a"

    /// Placeholder for the free-text slot in the return shape.
    static let openPlaceholder = "<one or two words>"

    /// At most this many vocabulary words are offered per open question.
    static let vocabularyLimit = 40

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
    /// `vocabulary` — existing keyword names per parent keyword id, offered
    /// to open questions as the preferred wording (NOT part of the cache
    /// key: it only nudges spelling, an older reply stays a valid answer).
    public static func userPrompt(for profile: AIProfile, vocabulary: [Int64: [String]] = [:]) -> String {
        var lines: [String] = []
        let instructions = profile.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            lines.append(instructions)
            lines.append("")
        }
        let flat = profile.flattened
        lines.append("Questions (answer each with exactly one of its allowed values):")
        var shape: [String] = []
        for (index, entry) in flat.enumerated() {
            let key = key(forQuestionAt: index)
            let question = entry.question
            var text = ""
            var gate: String?
            if let parent = entry.parentAnswer, let parentKey = entry.parentKey {
                gate = "\(parentKey) is \"\(parent.value)\""
                text += "Only if \(gate!): "
            }
            text += question.text
            var values: [String]
            switch question.kind {
            case .choice:
                values = question.answers.map(\.value)
                text += " One of: " + values.map { "\"\($0)\"" }.joined(separator: ", ")
            case .open:
                text += " Answer in one or two English words"
                let words = question.parentKeywordId.flatMap { vocabulary[$0] }?.prefix(vocabularyLimit) ?? []
                if !words.isEmpty {
                    text += " (prefer one of: " + words.map { "\"\($0.lowercased())\"" }.joined(separator: ", ") + ")"
                }
                values = [openPlaceholder]
                // The exits ("none") are the only fixed answers of an open question.
                for answer in question.answers {
                    text += ", or \"\(answer.value)\" if that does not apply"
                    values.append(answer.value)
                }
            }
            if let gate {
                text += ", or \"\(notApplicable)\" unless \(gate)"
                values.append(notApplicable)
            }
            lines.append("\(index + 1). \"\(key)\": \(text)")
            // The allowed values repeat INSIDE the return shape: small models
            // copy the shape literally, which keeps answers on the list.
            shape.append("\"\(key)\": \"\(values.joined(separator: "|"))\"")
        }
        lines.append("Return exactly this shape, one value per key: {\(shape.joined(separator: ", "))}")
        return lines.joined(separator: "\n")
    }

    /// Fingerprint of everything that changes what the model is ASKED — the
    /// cache key of a raw answer. Keyword mappings (and the vocabulary hint
    /// of open questions) are deliberately left out: re-mapping an answer to
    /// another keyword must reuse cached answers.
    public static func questionnaireHash(for profile: AIProfile) -> String {
        var parts: [String] = [profile.instructions]
        for entry in profile.flattened {
            parts.append((entry.parentKey ?? "") + "=" + (entry.parentAnswer?.value ?? ""))
            parts.append(entry.question.kind.rawValue)
            parts.append(entry.question.text)
            parts.append(entry.question.answers.map(\.value).joined(separator: "\u{1F}"))
        }
        let joined = parts.joined(separator: "\u{1E}")
        return FNV1a.hex(joined)
    }
}

/// A keyword an open question's answer would create (or reuse): the model's
/// words as a keyword name (UPPERCASE) and the parent it goes under.
public struct AICoinedKeyword: Hashable, Sendable {
    public var name: String
    public var parentKeywordId: Int64?

    public init(name: String, parentKeywordId: Int64?) {
        self.name = name
        self.parentKeywordId = parentKeywordId
    }
}

/// One parsed answer: which answer was chosen (or which words came back).
public struct AIParsedAnswer: Hashable, Sendable {
    /// The chosen literal, or the model's words for an open question.
    public var value: String
    /// The answer row chosen (nil for an open answer in the model's words).
    public var answerId: Int64?
    /// The keyword the chosen answer maps to.
    public var keywordId: Int64?
    public var stopsProfile: Bool
    /// Open answer: the keyword these words become.
    public var coined: AICoinedKeyword?

    public init(value: String, answerId: Int64? = nil, keywordId: Int64? = nil, stopsProfile: Bool = false, coined: AICoinedKeyword? = nil) {
        self.value = value
        self.answerId = answerId
        self.keywordId = keywordId
        self.stopsProfile = stopsProfile
        self.coined = coined
    }

    init(_ answer: AIAnswerRecord) {
        self.init(value: answer.value, answerId: answer.id, keywordId: answer.keywordId, stopsProfile: answer.stopsProfile)
    }
}

/// Parses the model's reply. Lenient on purpose — small models wrap JSON in
/// fences or prose, change case or add a trailing period — but strict on
/// the values: an answer that is not one of the allowed values counts as
/// "no answer" for that question, never as a guess.
public enum VLMAnswerParser {
    /// Chosen answer per question id (questions the model skipped, answered
    /// off-list or with "n/a" are absent). A follow-up whose gate answer was
    /// not chosen is dropped whatever the model said; a chosen answer with
    /// `stopsProfile` ends the questionnaire: later questions are dropped
    /// even if answered.
    public static func parse(_ reply: String, profile: AIProfile) -> [Int64: AIParsedAnswer] {
        let flat = profile.flattened
        guard let object = extractObject(from: reply, keys: flat.indices.map(VLMPrompt.key)) else {
            return [:]
        }
        var result: [Int64: AIParsedAnswer] = [:]
        // Answer id chosen per question id — the gates of follow-ups.
        var chosen: [Int64: Int64] = [:]
        for (index, entry) in flat.enumerated() {
            let question = entry.question
            guard let questionId = question.id else { continue }
            if let gate = entry.parentAnswer {
                // The parent question's id is on the gate's record.
                guard let gateId = gate.id, chosen[gate.questionId] == gateId else { continue }
            }
            let key = VLMPrompt.key(forQuestionAt: index)
            guard let raw = object[key] else { continue }
            let text: String
            switch raw {
            case let string as String: text = string
            case let number as NSNumber: text = number.stringValue
            default: continue
            }
            if isNotApplicable(text) { continue }
            let records = question.answers.map(\.record)
            if let answer = match(text, in: records) {
                result[questionId] = AIParsedAnswer(answer)
                if let answerId = answer.id { chosen[questionId] = answerId }
                if answer.stopsProfile { break }
            } else if question.kind == .open, let name = keywordName(from: text) {
                result[questionId] = AIParsedAnswer(
                    value: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    coined: AICoinedKeyword(name: name, parentKeywordId: question.parentKeywordId)
                )
            }
        }
        return result
    }

    /// Keyword ids the parsed answers assign (answers without a keyword
    /// contribute nothing; coined keywords are resolved by the caller).
    public static func keywordIds(in parsed: [Int64: AIParsedAnswer]) -> Set<Int64> {
        Set(parsed.values.compactMap(\.keywordId))
    }

    /// The keywords the open answers would create or reuse.
    public static func coinedKeywords(in parsed: [Int64: AIParsedAnswer]) -> [AICoinedKeyword] {
        parsed.values.compactMap(\.coined)
    }

    /// The model's words as a keyword name: trimmed, UPPERCASE, inner
    /// whitespace collapsed. Nil for anything that is not a usable name —
    /// the copied placeholder, a sentence, path or list characters.
    public static func keywordName(from text: String) -> String? {
        var cleaned = normalize(text)
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        guard !cleaned.isEmpty, !cleaned.contains("<"), !cleaned.contains(">"),
              !cleaned.contains("|"), !cleaned.contains("{"), !cleaned.contains("}"),
              !cleaned.contains("\n"), !cleaned.contains(":")
        else { return nil }
        let words = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard (1...4).contains(words.count) else { return nil }
        let joined = words.joined(separator: " ")
        guard joined.count <= 40, !placeholders.contains(joined) else { return nil }
        return KeywordDAO.normalize(joined)
    }

    /// Replies that copied the shape's placeholder instead of answering, or
    /// that are a "no answer" in the model's own words — an open question
    /// without a `none` exit must not coin UNKNOWN / NOT VISIBLE as keywords
    /// (review finding 2026-09-05).
    static let placeholders: Set<String> = [
        "one or two words", "words", "word", "answer", "value", "n/a", "na", "none", "null", "nil",
        "unknown", "not visible", "nothing", "no", "not sure", "unsure", "unclear", "cannot tell",
        "can't tell", "cant tell", "not applicable", "none visible", "not shown", "no answer",
        "unspecified", "undetermined", "indeterminate", "not available", "not present", "absent",
        "n.a", "-", "—", "?",
    ]

    static func isNotApplicable(_ text: String) -> Bool {
        let needle = normalize(text)
        return needle == "n/a" || needle == "na" || needle == "not applicable" || needle == "n.a"
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
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
