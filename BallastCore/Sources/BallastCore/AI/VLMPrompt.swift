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
///
/// U55 — a MULTIPLE question asks for a JSON list of every answer that
/// applies; the parser takes the list (or a comma-separated string), drops
/// the "none" exit whenever a real answer sits beside it, and treats a
/// literal copy of the shape's `"a|b|c"` placeholder as no answer.
public enum VLMPrompt {
    /// The default system prompt — editable in the AI window (the app stores
    /// the user's version; this is what Reset restores).
    public static let systemPrompt =
        "You are a photo cataloguing assistant. Look at the photo and answer every question by choosing from its allowed answers: exactly one, or every answer that applies where the question says so. Answer with a single JSON object and nothing else."

    /// Bumped whenever the rendered prompt TEMPLATE changes (wording around
    /// the questions, the return shape) so cached replies from the old
    /// template are not mistaken for answers to the new one.
    public static let promptVersion = 4

    /// The literal a gated question is answered with when its gate is not
    /// met — never an answer, never cached as one.
    public static let notApplicable = "n/a"

    /// The system prompt of a free question (AI ▸ Ask Model on Selection…):
    /// plain prose instead of JSON, and a nudge towards what is visible —
    /// the tool for finding out what the model can see before a question is
    /// put into a questionnaire.
    public static let askSystemPrompt =
        "You are a photo cataloguing assistant. Look at the photo and answer the question in plain English. Be brief and concrete, and describe only what is visible in the photo."

    /// Splits a reply into its `<think>…</think>` trace and the answer after
    /// it. A reply without a trace is all answer; a trace that never closed
    /// (token budget exhausted) is all thinking and the answer is empty.
    public static func splitThinking(_ reply: String) -> (thinking: String?, answer: String) {
        if let close = reply.range(of: "</think>", options: .backwards) {
            var trace = String(reply[..<close.lowerBound])
            if let open = trace.range(of: "<think>") { trace = String(trace[open.upperBound...]) }
            let answer = String(reply[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let thinking = trace.trimmingCharacters(in: .whitespacesAndNewlines)
            return (thinking.isEmpty ? nil : thinking, answer)
        }
        if let open = reply.range(of: "<think>") {
            let thinking = String(reply[open.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (thinking.isEmpty ? nil : thinking, "")
        }
        return (nil, reply.trimmingCharacters(in: .whitespacesAndNewlines))
    }

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
        questions(for: [profile], vocabulary: vocabulary)
    }

    /// U57: the questions of SEVERAL questionnaires as one text — the
    /// instructions of each, then every question numbered straight through
    /// (`q1`…`qN` across questionnaires), then one return shape. For a
    /// single questionnaire this is exactly `userPrompt(for:)`. The reply
    /// is cut back into per-questionnaire replies by
    /// `VLMAnswerParser.split(_:counts:)`, so the reply cache stays keyed
    /// per questionnaire.
    public static func questions(for profiles: [AIProfile], vocabulary: [Int64: [String]] = [:]) -> String {
        var lines: [String] = []
        for profile in profiles {
            let instructions = profile.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !instructions.isEmpty { lines.append(instructions) }
        }
        if !lines.isEmpty { lines.append("") }
        let flat = profiles.flatMap(\.flattened)
        // The list wording appears only when a question takes a list, so
        // a questionnaire without one renders (and caches) as before.
        let hasList = flat.contains { $0.question.kind == .multiple }
        lines.append(
            hasList
                ? "Questions (answer each with exactly one of its allowed values; a question that asks for every answer that applies takes a list):"
                : "Questions (answer each with exactly one of its allowed values):"
        )
        var shape: [String] = []
        // Gates name the parent's key: the parent sits in the same
        // questionnaire, so its key shifts by the same offset.
        var offset = 0
        var keyOffsets: [Int] = []
        for profile in profiles {
            keyOffsets.append(offset)
            offset += profile.flattened.count
        }
        var profileIndex = 0
        var indexWithinProfile = 0
        for (index, entry) in flat.enumerated() {
            while indexWithinProfile >= profiles[profileIndex].flattened.count {
                profileIndex += 1
                indexWithinProfile = 0
            }
            indexWithinProfile += 1
            let key = key(forQuestionAt: index)
            let question = entry.question
            var text = ""
            var gate: String?
            if let parent = entry.parentAnswer, let parentIndex = entry.parentIndex {
                let parentKey = self.key(forQuestionAt: parentIndex + keyOffsets[profileIndex])
                gate = "\(parentKey) is \"\(parent.value)\""
                text += "Only if \(gate!): "
            }
            text += question.text
            var values: [String]
            var isList = false
            switch question.kind {
            case .choice:
                values = question.answers.map(\.value)
                text += " One of: " + values.map { "\"\($0)\"" }.joined(separator: ", ")
            case .multiple:
                isList = true
                values = question.answers.map(\.value)
                text += " Every answer that applies, as a list, from: " + values.map { "\"\($0)\"" }.joined(separator: ", ")
                if let none = question.noneAnswer {
                    text += " (\"\(none.value)\" alone if nothing applies)"
                }
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
            let placeholder = "\"\(values.joined(separator: "|"))\""
            shape.append("\"\(key)\": " + (isList ? "[\(placeholder)]" : placeholder))
        }
        lines.append(
            (hasList ? "Return exactly this shape, one value per key, a list where the shape shows one: " : "Return exactly this shape, one value per key: ")
                + "{\(shape.joined(separator: ", "))}"
        )
        return lines.joined(separator: "\n")
    }

    /// U57: the user turn beside the photo when the questions travel in the
    /// system turn (so their KV cache can be reused across photos).
    public static let photoTurn = "Answer the questions for this photo."

    /// U57: the system turn of a prefix-cached run — the system prompt and
    /// the questions of every questionnaire being asked.
    public static func instructions(systemPrompt: String, questions: String) -> String {
        systemPrompt + "\n\n" + questions
    }

    /// Answer token budget for `questionCount` questions: a few tokens per
    /// key and value, with room for lists and long open answers.
    public static func answerBudget(questionCount: Int) -> Int {
        max(256, 40 * questionCount)
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

/// One parsed answer: which answer rows were chosen (or which words came
/// back). A choice question chooses one row, a multiple question (U55) any
/// number, an open question none (its words are `coined`).
public struct AIParsedAnswer: Hashable, Sendable {
    /// The chosen literal(s) — joined with ", " for a multiple question —
    /// or the model's words for an open question.
    public var value: String
    /// The answer rows chosen, in the question's order.
    public var chosen: [AIAnswerRecord]
    /// Open answer: the keyword these words become.
    public var coined: AICoinedKeyword?

    public init(value: String, chosen: [AIAnswerRecord] = [], coined: AICoinedKeyword? = nil) {
        self.value = value
        self.chosen = chosen
        self.coined = coined
    }

    init(_ answer: AIAnswerRecord) {
        self.init(value: answer.value, chosen: [answer])
    }

    init(chosen: [AIAnswerRecord]) {
        self.init(value: chosen.map(\.value).joined(separator: ", "), chosen: chosen)
    }

    /// The single answer row chosen (nil for an open answer or a multiple
    /// question — those carry `chosen`).
    public var answerId: Int64? { chosen.count == 1 ? chosen[0].id : nil }
    /// The keyword of the single chosen answer (see `answerId`).
    public var keywordId: Int64? { chosen.count == 1 ? chosen[0].keywordId : nil }
    /// Every keyword the chosen answers assign.
    public var keywordIds: [Int64] { chosen.compactMap(\.keywordId) }
    public var stopsProfile: Bool { chosen.contains { $0.stopsProfile } }
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
        // Answer ids chosen per question id — the gates of follow-ups.
        var chosen: [Int64: Set<Int64>] = [:]
        for (index, entry) in flat.enumerated() {
            let question = entry.question
            guard let questionId = question.id else { continue }
            if let gate = entry.parentAnswer {
                // The parent question's id is on the gate's record.
                guard let gateId = gate.id, chosen[gate.questionId]?.contains(gateId) == true else { continue }
            }
            let key = VLMPrompt.key(forQuestionAt: index)
            guard let raw = object[key] else { continue }
            let records = question.answers.map(\.record)
            if question.kind == .multiple {
                let picked = matchList(raw, in: records)
                guard !picked.isEmpty else { continue }
                result[questionId] = AIParsedAnswer(chosen: picked)
                chosen[questionId] = Set(picked.compactMap(\.id))
                if picked.contains(where: \.stopsProfile) { break }
                continue
            }
            guard let text = scalar(raw) else { continue }
            if isNotApplicable(text) { continue }
            if let answer = match(text, in: records) {
                result[questionId] = AIParsedAnswer(answer)
                if let answerId = answer.id { chosen[questionId] = [answerId] }
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

    /// U57: cuts the reply to a combined prompt (`VLMPrompt.questions(for:)`)
    /// into one reply per questionnaire, re-keyed `q1`…`qn` so it parses and
    /// caches exactly like a reply to that questionnaire alone. `counts` is
    /// the number of flattened questions per questionnaire, in prompt
    /// order. Nil when the reply carries no JSON object at all (a thinking
    /// trace that never closed, prose) — nothing to cache for anyone.
    public static func split(_ reply: String, counts: [Int]) -> [String]? {
        let total = counts.reduce(0, +)
        guard let object = extractObject(from: reply, keys: (0..<total).map(VLMPrompt.key)) else { return nil }
        var parts: [String] = []
        var offset = 0
        for count in counts {
            var part: [String: Any] = [:]
            for index in 0..<count {
                if let value = object[VLMPrompt.key(forQuestionAt: offset + index)] {
                    part[VLMPrompt.key(forQuestionAt: index)] = value
                }
            }
            offset += count
            let data = (try? JSONSerialization.data(withJSONObject: part, options: [.sortedKeys])) ?? Data("{}".utf8)
            parts.append(String(decoding: data, as: UTF8.self))
        }
        return parts
    }

    /// Keyword ids the parsed answers assign (answers without a keyword
    /// contribute nothing; coined keywords are resolved by the caller).
    public static func keywordIds(in parsed: [Int64: AIParsedAnswer]) -> Set<Int64> {
        Set(parsed.values.flatMap(\.keywordIds))
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

    /// A JSON value as answer text: a string, a number ("1"), or a
    /// one-element list (a choice question answered `["one"]`).
    static func scalar(_ raw: Any) -> String? {
        switch raw {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case let list as [Any]: return list.count == 1 ? scalar(list[0]) : nil
        default: return nil
        }
    }

    /// U55: the answer rows a multiple question's value names — a JSON list
    /// (`["sky", "trees"]`), or one string split at commas, semicolons or
    /// `|` ("sky, trees"). A literal copy of the shape placeholder (every
    /// value joined with `|`) is no answer, `n/a` never one. The exits — the
    /// keyword-less "none" and any answer that ends the questionnaire — are
    /// dropped when a real answer sits beside them: "none" and "sky" is
    /// "sky". Duplicates collapse; the order is the question's.
    static func matchList(_ raw: Any, in answers: [AIAnswerRecord]) -> [AIAnswerRecord] {
        var items: [String]
        switch raw {
        case let list as [Any]:
            items = list.compactMap(scalar)
        case let string as String:
            if normalize(string) == answers.map(\.value).joined(separator: "|").lowercased() { return [] }
            items = string.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" || $0.isNewline }).map(String.init)
        case let number as NSNumber:
            items = [number.stringValue]
        default:
            return []
        }
        items = items.filter { !isNotApplicable($0) }
        var picked = Set(items.compactMap { match($0, in: answers).flatMap(\.id) })
        let exits = answers.filter { $0.stopsProfile || ($0.value == AIAnswerRecord.noneValue && $0.keywordId == nil) }
        if picked.contains(where: { id in !exits.contains { $0.id == id } }) {
            for exit in exits { if let id = exit.id { picked.remove(id) } }
        }
        return answers.filter { $0.id.map(picked.contains) ?? false }
    }

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
