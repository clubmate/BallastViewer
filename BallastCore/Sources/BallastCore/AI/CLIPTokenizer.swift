//
//  Vendored for U48 from apple/ml-mobileclip (ios_app/MobileCLIPExplore/Tokenizer/
//  CLIPTokenizer.swift, MIT), which in turn derives from
//  huggingface/swift-coreml-transformers:
//
//  Created by Matthew Waller on 1/31/23.
//  Copyright © 2023 Hugging Face. All rights reserved.
//  Modified by Hugues Thomas on 5/14/24.
//
//  Local changes: loads vocab/merges from Bundle.module instead of Bundle.main,
//  throws instead of force-unwrapping, Sendable, and `encodeFull` TRUNCATES
//  instead of crashing on prompts longer than the 77-token context window.
//

import Foundation

/// CLIP's byte-pair-encoding text tokenizer. Output of `encodeFull` is exactly
/// what the MobileCLIP text encoder expects: `[BOS, tokens…, EOS, 0-padding]`
/// with a fixed length of 77.
public final class CLIPTokenizer: Sendable {
    struct BytePair: Hashable {
        let a: String
        let b: String
    }

    public enum TokenizerError: Error {
        case resourceMissing(String)
        case malformedVocabulary
    }

    public let contextLength = 77
    private let bpeRanks: [BytePair: Int]
    private let encoder: [String: Int]
    private let startToken: Int
    private let endToken: Int

    /// Loads the vocabulary shipped as package resources (clip-vocab.json /
    /// clip-merges.txt from apple/ml-mobileclip).
    public convenience init() throws {
        guard let vocabURL = Bundle.module.url(forResource: "Resources/clip-vocab", withExtension: "json")
            ?? Bundle.module.url(forResource: "clip-vocab", withExtension: "json")
        else { throw TokenizerError.resourceMissing("clip-vocab.json") }
        guard let mergesURL = Bundle.module.url(forResource: "Resources/clip-merges", withExtension: "txt")
            ?? Bundle.module.url(forResource: "clip-merges", withExtension: "txt")
        else { throw TokenizerError.resourceMissing("clip-merges.txt") }
        try self.init(
            vocabData: Data(contentsOf: vocabURL),
            mergesText: String(contentsOf: mergesURL, encoding: .utf8)
        )
    }

    public init(vocabData: Data, mergesText: String) throws {
        let lines = mergesText.split(separator: "\n").map { String($0) }
        var bpeRanks: [BytePair: Int] = [:]
        // First line is the "#version:" header.
        for i in 1 ..< lines.count {
            let tuple = lines[i].split(separator: " ").map { String($0) }
            guard tuple.count == 2 else { continue }
            bpeRanks[BytePair(a: tuple[0], b: tuple[1])] = i - 1
        }
        self.bpeRanks = bpeRanks
        self.encoder = try JSONDecoder().decode([String: Int].self, from: vocabData)
        guard let start = encoder["<|startoftext|>"], let end = encoder["<|endoftext|>"] else {
            throw TokenizerError.malformedVocabulary
        }
        self.startToken = start
        self.endToken = end
    }

    private func byteEncode(text: String) -> [String] {
        let pattern =
            "<\\|startoftext\\|>|<\\|endoftext\\|>|'s|'t|'re|'ve|'m|'ll|'d|[\\p{L}]+|[\\p{N}]|[^\\s\\p{L}\\p{N}]+"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(
            in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        let tokens = matches.map { match -> String in
            let range = Range(match.range, in: text)!
            return String(text[range])
        }
        return tokens.map { token -> String in
            Array(token.utf8).compactMap { CLIPByteCoder.byteEncoder[$0] }.joined()
        }
    }

    private func getPairs(word: [String]) -> Set<BytePair> {
        var s = Set<BytePair>()
        for i in 0 ..< word.count - 1 {
            s.insert(BytePair(a: word[i], b: word[i + 1]))
        }
        return s
    }

    func bpe(token: String) -> String {
        if token.count <= 1 {
            return token + "</w>"
        }

        var word = Array(token).map { String($0) }
        let last = (word.last ?? "") + "</w>"
        word.removeLast()
        word.append(last)
        var pairs = Array(getPairs(word: word))
        if pairs.isEmpty {
            return token + "</w>"
        }

        while true {
            let bigrams = pairs.filter { bpeRanks[$0] != nil }
            if bigrams.isEmpty {
                break
            }
            let bigram = bigrams.min { bpeRanks[$0]! < bpeRanks[$1]! }!
            let first = bigram.a
            let second = bigram.b
            var newWord: [String] = []
            var i = 0
            while i < word.count {
                if let j = word[i ..< word.count].firstIndex(of: first) {
                    newWord.append(contentsOf: word[i ..< j])
                    i = j
                } else {
                    newWord.append(contentsOf: word[i ..< word.count])
                    break
                }

                if word[i] == first && i < word.count - 1 && word[i + 1] == second {
                    newWord.append(first + second)
                    i += 2
                } else {
                    newWord.append(word[i])
                    i += 1
                }
            }
            word = newWord
            if word.count == 1 {
                break
            } else {
                pairs = Array(getPairs(word: word))
            }
        }
        return word.joined(separator: " ")
    }

    func tokenize(text: String) -> [String] {
        var tokens: [String] = []
        for token in byteEncode(text: text.lowercased()) {
            tokens.append(contentsOf: bpe(token: token).split(separator: " ").map { String($0) })
        }
        return tokens
    }

    /// Raw token ids, unpadded, without BOS/EOS.
    public func encode(text: String) -> [Int] {
        tokenize(text: text).compactMap { encoder[$0] }
    }

    /// `[BOS, tokens…, EOS]` zero-padded to `contextLength`, truncated so
    /// BOS/EOS always fit (Apple's original crashed past 75 tokens).
    public func encodeFull(text: String) -> [Int32] {
        let tokens = encode(text: text).prefix(contextLength - 2)
        var full = Array(repeating: Int32(0), count: contextLength)
        full[0] = Int32(startToken)
        for (index, token) in tokens.enumerated() {
            full[index + 1] = Int32(token)
        }
        full[tokens.count + 1] = Int32(endToken)
        return full
    }
}
