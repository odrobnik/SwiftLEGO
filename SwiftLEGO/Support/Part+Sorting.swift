import Foundation
#if canImport(BrickCore)
import BrickCore

extension Part {
    var subpartsSorted: [Part] {
        subparts.sorted { lhs, rhs in
            Part.subpartSortComparator(lhs, rhs, parentPartID: partID)
        }
    }

    static func subpartSortComparator(_ lhs: Part, _ rhs: Part, parentPartID: String? = nil) -> Bool {
        let colorComparison = lhs.colorName.localizedCaseInsensitiveCompare(rhs.colorName)
        if colorComparison != .orderedSame {
            return colorComparison == .orderedAscending
        }

        let expectedPrefix = parentPartID ?? lhs.parentPart?.partID
        if let prefix = expectedPrefix {
            let lhsMatches = lhs.partID.hasPrefix(prefix)
            let rhsMatches = rhs.partID.hasPrefix(prefix)

            if lhsMatches != rhsMatches {
                return lhsMatches && !rhsMatches
            }

            if lhsMatches && rhsMatches {
                switch comparePartIDSuffix(lhs.partID, rhs.partID, parentID: prefix) {
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                case .orderedSame:
                    break
                }
            }
        }

        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        switch comparePartID(lhs.partID, rhs.partID) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            break
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func comparePartID(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsKey = partIDSortKey(for: lhs)
        let rhsKey = partIDSortKey(for: rhs)

        if let lhsNumeric = lhsKey.numeric, let rhsNumeric = rhsKey.numeric {
            if lhsNumeric != rhsNumeric {
                return lhsNumeric < rhsNumeric ? .orderedAscending : .orderedDescending
            }
        } else if lhsKey.numericString != rhsKey.numericString {
            return lhsKey.numericString.localizedStandardCompare(rhsKey.numericString)
        }

        let suffixComparison = lhsKey.suffix.localizedCaseInsensitiveCompare(rhsKey.suffix)
        if suffixComparison != .orderedSame {
            return suffixComparison
        }

        return lhsKey.raw.localizedCaseInsensitiveCompare(rhsKey.raw)
    }

    private static func comparePartIDSuffix(_ lhs: String, _ rhs: String, parentID: String) -> ComparisonResult {
        let lhsSuffix = String(lhs.dropFirst(parentID.count))
        let rhsSuffix = String(rhs.dropFirst(parentID.count))

        if lhsSuffix.isEmpty && rhsSuffix.isEmpty {
            return .orderedSame
        }

        if lhsSuffix.isEmpty {
            return .orderedAscending
        }

        if rhsSuffix.isEmpty {
            return .orderedDescending
        }

        return lhsSuffix.localizedCaseInsensitiveCompare(rhsSuffix)
    }

    private static func partIDSortKey(for partID: String) -> (numeric: Int?, numericString: String, suffix: String, raw: String) {
        let trimmed = partID.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.lowercased()
        let digitsPrefix = raw.prefix { $0.isNumber }
        let suffixStartIndex = digitsPrefix.endIndex
        let suffix = String(raw[suffixStartIndex...])
        let numericString = String(digitsPrefix)
        let numericValue = Int(numericString)
        return (numericValue, numericString, suffix, raw)
    }
}
#endif
