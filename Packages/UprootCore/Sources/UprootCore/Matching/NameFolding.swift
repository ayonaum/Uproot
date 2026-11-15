import Foundation

/// How a position in a folded name relates to the words of the original name.
enum Boundary {
    /// Inside a word.
    static let none: UInt8 = 0
    /// A camelCase hump or a switch between letters and digits.
    static let soft: UInt8 = 1
    /// Just after a separator such as a space, dash or underscore.
    static let hard: UInt8 = 2
    /// The start of the name, or just after a dot.
    static let component: UInt8 = 3
}

/// A file name reduced to what matters for matching: lowercase letters and digits,
/// plus a record of where each word of the original name began.
///
/// "Safe_Exam Browser-3.7.dmg" folds to "safeexambrowser37dmg", so one search term finds
/// every spelling of a product name, however an installer chose to separate the words.
struct FoldedName: Sendable, Equatable {
    /// Lowercased letters and digits as UTF-8.
    var bytes: [UInt8] = []
    /// One `Boundary` value per byte of `bytes`.
    var boundaries: [UInt8] = []
    /// Folded length of the name without its extension; equals `bytes.count` when there is none.
    var stemLength = 0
    /// True for names shaped like "com.vendor.product" or "TEAMID1234.group.name".
    var isReverseDNS = false

    /// The boundary just past `index`, treating the end of the name as a component boundary.
    func boundary(endingAt index: Int) -> UInt8 {
        index >= bytes.count ? Boundary.component : boundaries[index]
    }

    /// Number of words in the name.
    var wordCount: Int {
        boundaries.reduce(0) { $0 + ($1 == Boundary.none ? 0 : 1) }
    }
}

enum NameFolding {
    private static let reverseDNSPrefixes: Set<String> = [
        "com", "org", "net", "io", "app", "ai", "co", "us", "uk", "de", "fr", "ru", "jp", "me", "dev",
        "edu", "gov", "info", "tv", "fm", "ch", "se", "nl", "it", "es", "ca", "au", "eu", "cc", "at",
        "be", "pl", "cz", "no", "fi", "dk", "kr", "cn", "in", "br", "xyz", "tech", "software", "studio",
        "group", "systems", "digital", "audio", "tools", "ua",
    ]

    private enum CharClass { case lower, upper, digit, other }

    /// Folds a file name. Case, accents and separators are dropped; word starts are kept.
    static func fold(_ name: String) -> FoldedName {
        let scalars = Array(name.precomposedStringWithCanonicalMapping.unicodeScalars)
        var out = FoldedName()
        out.bytes.reserveCapacity(scalars.count)
        out.boundaries.reserveCapacity(scalars.count)

        var lastDot: (scalarIndex: Int, foldedCount: Int)?
        var previous: CharClass = .other
        var previousWasDot = false
        var emittedAny = false

        for (index, scalar) in scalars.enumerated() {
            let cls = classify(scalar)
            guard cls != .other else {
                if scalar == "." { lastDot = (index, out.bytes.count) }
                previousWasDot = scalar == "."
                previous = .other
                continue
            }

            let boundary: UInt8
            if !emittedAny || previousWasDot {
                boundary = Boundary.component
            } else if previous == .other {
                boundary = Boundary.hard
            } else if previous == .lower && cls == .upper {
                boundary = Boundary.soft
            } else if previous == .upper && cls == .upper && index + 1 < scalars.count
                        && classify(scalars[index + 1]) == .lower {
                // "SEBConfig": the last capital of a run starts the next word.
                boundary = Boundary.soft
            } else if (previous == .digit) != (cls == .digit) {
                boundary = Boundary.soft
            } else {
                boundary = Boundary.none
            }

            let before = out.bytes.count
            appendFolded(scalar, to: &out.bytes)
            for offset in 0..<(out.bytes.count - before) {
                out.boundaries.append(offset == 0 ? boundary : Boundary.none)
            }
            emittedAny = true
            previous = cls
            previousWasDot = false
        }

        out.stemLength = out.bytes.count
        if let lastDot, lastDot.scalarIndex > 0, isPlausibleExtension(scalars[(lastDot.scalarIndex + 1)...]) {
            out.stemLength = lastDot.foldedCount
        }
        out.isReverseDNS = looksLikeReverseDNS(name)
        return out
    }

    /// Lowercases ASCII letters and keeps digits, writing into `output`.
    /// Returns false when the name holds non-ASCII bytes and needs the full `fold`.
    @inline(__always)
    static func squashASCII(_ name: UnsafeBufferPointer<UInt8>, into output: inout [UInt8]) -> Bool {
        output.removeAll(keepingCapacity: true)
        for byte in name {
            switch byte {
            case 0x30...0x39, 0x61...0x7A: output.append(byte)
            case 0x41...0x5A: output.append(byte | 0x20)
            case 0x80...: return false
            default: break
            }
        }
        return true
    }

    private static func classify(_ scalar: Unicode.Scalar) -> CharClass {
        if scalar.isASCII {
            switch scalar.value {
            case 0x30...0x39: return .digit
            case 0x41...0x5A: return .upper
            case 0x61...0x7A: return .lower
            default: return .other
            }
        }
        let properties = scalar.properties
        if properties.numericType != nil { return .digit }
        if properties.isUppercase { return .upper }
        if properties.isAlphabetic { return .lower }
        return .other
    }

    private static func appendFolded(_ scalar: Unicode.Scalar, to bytes: inout [UInt8]) {
        if scalar.isASCII {
            let value = UInt8(scalar.value)
            bytes.append((0x41...0x5A).contains(value) ? value | 0x20 : value)
            return
        }
        let folded = String(scalar).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        bytes.append(contentsOf: folded.utf8)
    }

    private static func isPlausibleExtension(_ scalars: ArraySlice<Unicode.Scalar>) -> Bool {
        guard (1...12).contains(scalars.count) else { return false }
        var hasLetter = false
        for scalar in scalars {
            switch scalar.value {
            case 0x30...0x39: break
            case 0x41...0x5A, 0x61...0x7A: hasLetter = true
            default: return false
            }
        }
        return hasLetter
    }

    private static func looksLikeReverseDNS(_ name: String) -> Bool {
        guard !name.contains(" ") else { return false }
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3, let first = components.first, !first.isEmpty else { return false }
        if reverseDNSPrefixes.contains(first.lowercased()) { return true }
        // Team-prefixed identifiers: "UBF8T346G9.com.vendor.app".
        let isTeamID = first.count == 10 && first.allSatisfy { $0.isASCII && ($0.isNumber || $0.isUppercase) }
        return isTeamID
    }
}
