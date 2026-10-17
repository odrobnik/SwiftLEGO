import Foundation

/// Text normalization shared by the inventory searches.
enum SearchText {
    /// The case- and diacritic-insensitive form all searches compare.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    /// The normalized runs of letters and digits in `text`.
    static func tokens(from text: String) -> [String] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { normalized(String($0)) }
    }

    /// Whether every query token is the prefix of a word in `name`.
    static func matches(nameTokens queryTokens: [String], in name: String) -> Bool {
        guard !queryTokens.isEmpty else { return false }
        let nameTokens = tokens(from: name)
        return queryTokens.allSatisfy { token in
            nameTokens.contains(where: { $0.hasPrefix(token) })
        }
    }

    /// A set number without its variant suffix, "75060" for "75060-1".
    static func strippedSetNumber(_ number: String) -> String {
        number.split(separator: "-").first.map(String.init) ?? number
    }
}

/// A parsed part search. A leading part number narrows the results by the numeric prefix
/// of the part ID, "2 x 4"-style dimensions match the part's text, and otherwise every
/// word of the query has to match the part's ID, colour or name.
struct PartSearchQuery {
    private let rawQuery: String
    private let primaryToken: String
    private let tokens: [String]
    private let numericPrefixToken: String
    private let dimensionPrefixQuery: String?
    private let primaryTokenIsNumeric: Bool
    private let primaryTokenIsDimensionQuery: Bool
    private let shouldEnforceNumericPrefix: Bool
    private let shouldMatchPartIDPrefix: Bool

    /// Returns `nil` for a query without any searchable text.
    init?(_ query: String) {
        let rawQuery = SearchText.normalized(query)
        guard !rawQuery.isEmpty else { return nil }

        let startsWithNumber = rawQuery.first?.isNumber == true
        let primaryToken = rawQuery.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? rawQuery
        let primaryTokenIsShortLength = Self.isShortLengthToken(primaryToken)
        let primaryTokenIsNumericOnly = primaryToken.allSatisfy(\.isNumber)
        let primaryTokenIsDimensionQuery = Self.normalizedDimensionQuery(for: primaryToken) != nil
        let numericPrefixToken = String(primaryToken.prefix(while: \.isNumber))
        let dimensionPrefixQuery = Self.normalizedDimensionPrefix(in: rawQuery)

        self.rawQuery = rawQuery
        self.primaryToken = primaryToken
        self.tokens = SearchText.tokens(from: rawQuery)
        self.numericPrefixToken = numericPrefixToken
        self.dimensionPrefixQuery = dimensionPrefixQuery
        self.primaryTokenIsNumeric = primaryTokenIsNumericOnly && !primaryTokenIsShortLength
        self.primaryTokenIsDimensionQuery = primaryTokenIsDimensionQuery
        self.shouldEnforceNumericPrefix = !numericPrefixToken.isEmpty && dimensionPrefixQuery == nil && !primaryTokenIsShortLength
        self.shouldMatchPartIDPrefix = startsWithNumber && !primaryTokenIsNumericOnly && !primaryTokenIsDimensionQuery && !primaryTokenIsShortLength
    }

    func matches(partID: String, colorName: String, name: String) -> Bool {
        let combined = "\(partID) \(colorName) \(name)"
        let searchableText = SearchText.normalized(combined)
            .replacingOccurrences(of: "×", with: "x")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let partTokens = Array(Set(SearchText.tokens(from: combined)))

        func matchesAll(_ tokens: some Sequence<String>) -> Bool {
            tokens.allSatisfy { token in
                Self.matches(token, partID: partID, partTokens: partTokens, searchableText: searchableText)
            }
        }

        if shouldEnforceNumericPrefix, !Self.matchesNumericPartID(partID, numericQuery: numericPrefixToken) {
            return false
        }

        if let dimensionPrefixQuery, !searchableText.contains(dimensionPrefixQuery) {
            return false
        }

        let secondaryTokens = tokens.dropFirst()

        if dimensionPrefixQuery != nil {
            return tokens.count <= 1 || matchesAll(secondaryTokens)
        }

        if primaryTokenIsNumeric {
            return matchesAll(secondaryTokens)
        }

        if primaryTokenIsDimensionQuery {
            return matchesAll([primaryToken]) && matchesAll(secondaryTokens)
        }

        if shouldMatchPartIDPrefix {
            return SearchText.normalized(partID).hasPrefix(primaryToken) && matchesAll(secondaryTokens)
        }

        if SearchText.normalized(colorName).contains(rawQuery) || SearchText.normalized(name).contains(rawQuery) {
            return true
        }

        return matchesAll(tokens)
    }

    private static func matches(
        _ token: String,
        partID: String,
        partTokens: [String],
        searchableText: String
    ) -> Bool {
        if token.allSatisfy(\.isNumber) && !isShortLengthToken(token) {
            if matchesNumericPartID(partID, numericQuery: token) {
                return true
            }

            return partTokens.contains(token)
        }

        if let dimensionQuery = normalizedDimensionQuery(for: token),
           searchableText.contains(dimensionQuery) {
            return true
        }

        return partTokens.contains { $0.contains(token) }
    }

    /// A one- or two-digit number, optionally followed by "L": a length such as "4" or
    /// "12L", which is too short to act as a part number.
    private static func isShortLengthToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var normalizedToken = trimmed.lowercased()
        if normalizedToken.hasSuffix("l") {
            normalizedToken.removeLast()
        }

        guard (1...2).contains(normalizedToken.count) else { return false }
        return normalizedToken.allSatisfy(\.isNumber)
    }

    private static func matchesNumericPartID(_ partID: String, numericQuery: String) -> Bool {
        let normalizedQuery = SearchText.normalized(numericQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedQuery.isEmpty else { return false }

        let numericPrefix = SearchText.normalized(partID.trimmingCharacters(in: .whitespacesAndNewlines))
            .prefix(while: \.isNumber)

        guard !numericPrefix.isEmpty else { return false }
        return numericPrefix == normalizedQuery
    }

    private static func normalizedDimensionPrefix(in query: String) -> String? {
        let prefix = query.prefix { character in
            character.isNumber || character.isWhitespace || character == "x" || character == "X" || character == "×"
        }
        guard !prefix.isEmpty else { return nil }
        return normalizedDimensionQuery(for: String(prefix))
    }

    /// "2x4", "2 × 4" and "2 x 4" all become "2 x 4"; anything else is `nil`.
    private static func normalizedDimensionQuery(for token: String) -> String? {
        let compact = SearchText.normalized(token)
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: " ", with: "")

        guard compact.contains("x") else { return nil }

        let components = compact.split(separator: "x", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        return components.joined(separator: " x ")
    }
}
