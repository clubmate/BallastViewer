import Testing
@testable import BallastCore

// MARK: - Search (spec §11.3 + U5: keywords AND filenames)

struct SearchFilterTests {
    @Test func foldedQueryAgreesWithPlainMatch() {
        let paths = ["PEOPLE > ANNA", "STRASSE", "MÜNCHEN"]
        let facts = PhotoQueryFacts(keywordPaths: paths, keywordGroupIds: [],
                                    foldedKeywordPaths: paths.map(CaseInsensitiveMatch.fold))
        let unfolded = PhotoQueryFacts(keywordPaths: paths)
        for query in ["ann", "PeOpLe", "straße", "münchen", "MÜN", "img_12", ".jpg", "bernd", "  "] {
            let expected = SearchFilter.matches(filename: "IMG_1234.JPG", keywordPaths: paths, query: query)
            let folded = SearchFilter.FoldedQuery(query)
            #expect((folded?.matches(filename: "IMG_1234.JPG", facts: facts) ?? true) == expected, Comment(rawValue: query))
            #expect((folded?.matches(filename: "IMG_1234.JPG", facts: unfolded) ?? true) == expected, Comment(rawValue: query))
        }
        #expect(SearchFilter.FoldedQuery("   ") == nil)
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(SearchFilter.matches(filename: "a.jpg", keywordPaths: [], query: ""))
        #expect(SearchFilter.matches(filename: "a.jpg", keywordPaths: [], query: "   "))
    }

    @Test func keywordSubstringCaseInsensitive() {
        let paths = ["PEOPLE > ANNA", "TRAVEL"]
        #expect(SearchFilter.matches(filename: "x.jpg", keywordPaths: paths, query: "ann"))
        #expect(SearchFilter.matches(filename: "x.jpg", keywordPaths: paths, query: "PeOpLe"))
        #expect(!SearchFilter.matches(filename: "x.jpg", keywordPaths: paths, query: "bernd"))
    }

    @Test func filenameSubstringCaseInsensitive() {
        #expect(SearchFilter.matches(filename: "IMG_1234.JPG", keywordPaths: [], query: "img_12"))
        #expect(SearchFilter.matches(filename: "IMG_1234.JPG", keywordPaths: [], query: ".jpg"))
        #expect(!SearchFilter.matches(filename: "IMG_1234.JPG", keywordPaths: [], query: "5678"))
    }

    @Test func pathSeparatorMatchesFullDerivedPath() {
        // The user sees "PEOPLE > ANNA" in chips; searching that string must hit.
        #expect(SearchFilter.matches(
            filename: "x.jpg", keywordPaths: ["PEOPLE > ANNA"], query: "people > an"
        ))
    }

    // MARK: U37: whitespace = OR terms, "> " glues path terms

    @Test func spaceSeparatedTermsCombineWithOr() {
        #expect(SearchFilter.matches(
            filename: "x.jpg", keywordPaths: ["TRAVEL > PARIS"], query: "PARIS ROME"
        ))
        #expect(SearchFilter.matches(
            filename: "x.jpg", keywordPaths: ["TRAVEL > ROME"], query: "PARIS ROME"
        ))
        #expect(!SearchFilter.matches(
            filename: "x.jpg", keywordPaths: ["TRAVEL > OSLO"], query: "PARIS ROME"
        ))
        // A term can also hit the filename.
        #expect(SearchFilter.matches(
            filename: "PARIS_001.jpg", keywordPaths: [], query: "PARIS ROME"
        ))
    }

    @Test func pathTermStaysOneTermNextToOrTerms() {
        // "LOCATION > ROME PARIS" = "LOCATION > ROME" OR "PARIS".
        let query = "LOCATION > ROME PARIS"
        #expect(SearchFilter.matches(
            filename: "x.jpg", keywordPaths: ["LOCATION > ROME"], query: query
        ))
        #expect(SearchFilter.matches(
            filename: "x.jpg", keywordPaths: ["TRAVEL > PARIS"], query: query
        ))
        // ROME under a DIFFERENT parent must NOT match the path term.
        #expect(!SearchFilter.matches(
            filename: "x.jpg", keywordPaths: ["TRAVEL > ROME"], query: query
        ))
        let folded = SearchFilter.FoldedQuery(query)
        #expect(folded?.terms == ["location > rome", "paris"])
    }

    @Test func strayPathSeparatorsDoNotMatchEverything() {
        // A lone ">" must not become a term that hits every nested path.
        #expect(SearchFilter.FoldedQuery(">") == nil)
        #expect(SearchFilter.FoldedQuery("> ROME")?.terms == ["rome"])
        // Trailing ">" waits for a right side that never comes — kept as-is.
        #expect(!SearchFilter.matches(
            filename: "x.jpg", keywordPaths: ["PEOPLE > ANNA"], query: "> OSLO"
        ))
        #expect(SearchFilter.FoldedQuery("A > B > C")?.terms == ["a > b > c"])
    }
}

// MARK: - Canonical hex colors (C8: #RRGGBBAA, alpha last, both directions)

struct HexColorTests {
    @Test func parsesSixAndEightDigits() {
        #expect(HexColor.parse("#1E1E1E") == HexColor(red: 0x1E, green: 0x1E, blue: 0x1E, alpha: 0xFF))
        #expect(HexColor.parse("#FF9500CC") == HexColor(red: 0xFF, green: 0x95, blue: 0x00, alpha: 0xCC))
        #expect(HexColor.parse("ff9500cc") == HexColor(red: 0xFF, green: 0x95, blue: 0x00, alpha: 0xCC))
    }

    @Test func rejectsMalformedInput() {
        #expect(HexColor.parse("") == nil)
        #expect(HexColor.parse("#FFF") == nil)
        #expect(HexColor.parse("#GGGGGG") == nil)
        #expect(HexColor.parse("#123456789") == nil)
    }

    @Test func formatsCanonicallyAndRoundTrips() {
        let color = HexColor(red: 0x12, green: 0xAB, blue: 0x00, alpha: 0x80)
        #expect(color.formatted == "#12AB0080")
        #expect(HexColor.parse(color.formatted) == color)
        // The C8 bug was #AARRGGBB in, #RRGGBBAA out — alpha must stay last.
        #expect(HexColor.parse("#11223344")?.formatted == "#11223344")
    }
}

// MARK: - Keyword shortcut normalization (C7)

struct KeywordShortcutNormalizationTests {
    private func tree() -> KeywordTree {
        KeywordTree(records: [
            KeywordRecord(id: 1, parentId: nil, groupId: nil, name: "PEOPLE"),
            KeywordRecord(id: 2, parentId: 1, groupId: nil, name: "ANNA"),
        ])
    }

    @Test func lowercaseNameResolvesToFullPath() {
        // Binding "anna" must store the same keyword the panel would assign.
        #expect(KeywordResolver.canonicalText("anna", tree: tree()) == "PEOPLE > ANNA")
    }

    @Test func unknownNameIsUppercased() {
        #expect(KeywordResolver.canonicalText("bernd", tree: tree()) == "BERND")
        #expect(KeywordResolver.canonicalText("new > path", tree: tree()) == "NEW > PATH")
    }

    @Test func emptyInputYieldsNil() {
        #expect(KeywordResolver.canonicalText("  ", tree: tree()) == nil)
    }
}
