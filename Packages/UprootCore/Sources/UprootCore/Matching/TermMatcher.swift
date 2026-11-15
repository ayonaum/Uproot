import Foundation

/// How closely a file name matches a search term, weakest first.
public enum MatchKind: Int, Sendable, Comparable, Codable {
    /// The term sits inside a longer word: "terrain" in "terrainfx".
    case partial = 1
    /// The term is a whole word somewhere in the name: "Abstract Terrain Objects".
    case word = 2
    /// The name starts with the term: "Terrain Crack Install.log".
    case prefix = 3
    /// The term is a whole component of a reverse-DNS name: "com.vendor.terrain.plist".
    case identifier = 4
    /// The name is the term, ignoring the extension: "Terrain.vst3".
    case exact = 5

    public static func < (lhs: MatchKind, rhs: MatchKind) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Strong matches name the product itself rather than merely mentioning it.
    public var isStrong: Bool { self >= .prefix }
}

/// One thing the user is looking for, prepared for matching.
public struct SearchTerm: Sendable, Hashable {
    public enum Role: Sendable, Hashable {
        /// A program or plug-in name typed by the user.
        case product
        /// A company or developer name typed by the user.
        case vendor
        /// A bundle identifier read from a bundle the scan already found.
        case identifier
    }

    public let text: String
    public let role: Role
    let folded: [UInt8]
    let wordCount: Int

    /// Returns nil when the text has fewer than two letters or digits to match on.
    public init?(_ text: String, role: Role) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = NameFolding.fold(trimmed)
        guard folded.bytes.count >= 2 else { return nil }
        self.text = trimmed
        self.role = role
        self.folded = folded.bytes
        self.wordCount = folded.wordCount
    }

    /// Short terms only match whole words; "SEB" must not find "Sebastian".
    var isShort: Bool { folded.count <= 4 }

    /// Long or multi-word terms are unlikely to appear in unrelated names by chance.
    public var isDistinctive: Bool {
        role == .identifier || folded.count >= 9 || (wordCount >= 2 && folded.count >= 7)
    }
}

/// The best match of one term against one name.
public struct TermMatch: Sendable, Hashable {
    public var term: SearchTerm
    public var kind: MatchKind
    /// The term is the file's extension, as in "config.seb".
    public var isExtension: Bool
}

/// What a name matched: at most one product (or identifier) term and one vendor term.
struct NameEvaluation: Sendable {
    var product: TermMatch?
    var vendor: TermMatch?
    var isEmpty: Bool { product == nil && vendor == nil }
}

/// The full set of terms for one search.
struct TermSet: Sendable {
    var products: [SearchTerm]
    var vendors: [SearchTerm]

    var all: [SearchTerm] { products + vendors }

    /// Cheap test on a squashed ASCII name: can any term possibly match?
    @inline(__always)
    func mayMatch(_ squashed: [UInt8]) -> Bool {
        for term in products where TermMatcher.contains(squashed, term.folded) { return true }
        for term in vendors where TermMatcher.contains(squashed, term.folded) { return true }
        return false
    }

    func evaluate(_ name: FoldedName) -> NameEvaluation {
        NameEvaluation(product: TermMatcher.best(of: products, in: name),
                       vendor: TermMatcher.best(of: vendors, in: name))
    }
}

enum TermMatcher {
    /// The strongest match among `terms`; ties go to the longer term.
    static func best(of terms: [SearchTerm], in name: FoldedName) -> TermMatch? {
        var best: TermMatch?
        for term in terms {
            guard let candidate = match(term, in: name) else { continue }
            if let current = best {
                let stronger = candidate.kind > current.kind
                    || (candidate.kind == current.kind && term.folded.count > current.term.folded.count)
                if stronger { best = candidate }
            } else {
                best = candidate
            }
        }
        return best
    }

    static func match(_ term: SearchTerm, in name: FoldedName) -> TermMatch? {
        let needle = term.folded
        let haystack = name.bytes
        guard needle.count <= haystack.count else { return nil }

        if haystack.count == needle.count {
            return haystack == needle ? TermMatch(term: term, kind: .exact, isExtension: false) : nil
        }
        if name.stemLength == needle.count, haystack.starts(with: needle) {
            return TermMatch(term: term, kind: .exact, isExtension: false)
        }

        var best: TermMatch?
        var from = 0
        while let start = firstIndex(of: needle, in: haystack, from: from) {
            from = start + 1
            let end = start + needle.count
            let startBoundary = name.boundaries[start]
            let endBoundary = name.boundary(endingAt: end)
            let aligned = startBoundary != Boundary.none && endBoundary != Boundary.none

            if term.isShort {
                // A short term must be exactly one word of the name.
                guard aligned else { continue }
                let crossesWords = ((start + 1)..<end).contains { name.boundaries[$0] != Boundary.none }
                if crossesWords { continue }
            }

            var candidate = TermMatch(term: term, kind: .partial, isExtension: false)
            if aligned {
                if start == 0 {
                    // "Terrain v1.0.0" and "FL Studio 2025" are the product itself, not a sibling.
                    candidate.kind = restIsVersion(name, from: end) ? .exact : .prefix
                } else if name.isReverseDNS && startBoundary == Boundary.component && endBoundary == Boundary.component {
                    candidate.kind = .identifier
                } else {
                    candidate.kind = .word
                    candidate.isExtension = start == name.stemLength && end == haystack.count && !name.isReverseDNS
                }
            } else if needle.count < 5 {
                continue
            }

            if best == nil || candidate.kind > best!.kind { best = candidate }
        }
        return best
    }

    private static let versionWords: Set<String> = [
        "v", "ver", "version", "beta", "alpha", "rc", "trial", "demo", "x", "bit", "mac", "macos", "osx",
        "universal", "intel", "arm", "silicon", "copy", "final", "release", "build", "win", "setup", "installer",
    ]

    /// True when everything between `index` and the extension reads as a version or platform tag.
    private static func restIsVersion(_ name: FoldedName, from index: Int) -> Bool {
        guard index < name.stemLength else { return false }
        var word: [UInt8] = []
        func isVersionWord(_ word: [UInt8]) -> Bool {
            if word.allSatisfy({ (0x30...0x39).contains($0) }) { return true }
            return versionWords.contains(String(decoding: word, as: UTF8.self))
        }
        for position in index..<name.stemLength {
            if name.boundaries[position] != Boundary.none, !word.isEmpty {
                guard isVersionWord(word) else { return false }
                word.removeAll(keepingCapacity: true)
            }
            word.append(name.bytes[position])
        }
        return isVersionWord(word)
    }

    @inline(__always)
    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        firstIndex(of: needle, in: haystack, from: 0) != nil
    }

    static func firstIndex(of needle: [UInt8], in haystack: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, from >= 0, haystack.count - from >= needle.count else { return nil }
        return haystack.withUnsafeBufferPointer { hay -> Int? in
            needle.withUnsafeBufferPointer { ndl -> Int? in
                guard let base = hay.baseAddress, let needleBase = ndl.baseAddress else { return nil }
                guard let found = memmem(base + from, hay.count - from, needleBase, ndl.count) else { return nil }
                return base.distance(to: found.assumingMemoryBound(to: UInt8.self))
            }
        }
    }
}
