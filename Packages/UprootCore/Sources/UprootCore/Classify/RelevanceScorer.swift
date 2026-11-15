import Foundation

/// Decides how likely a matched name is to belong to the product, and says why.
///
/// The verdict rests on two things: how the name matches, and where the item sits.
/// A strong match in a place where software is installed is trusted. The same match deep
/// inside another program's files is shown but left for the user to judge, and nothing
/// among the user's own documents is ever preselected.
enum RelevanceScorer {
    struct Input {
        var product: TermMatch?
        var vendor: TermMatch?
        /// An ancestor folder carries the vendor's name.
        var underVendor = false
        /// The enclosing app or plug-in that does not match the search, if any.
        var foreignBundle: String?
        /// Something besides the name ties the item to the product: its own bundle identifier,
        /// or a matching installer package that put it there.
        var corroborated = false
        /// The user is looking for files by name, not for what belongs to a program.
        var fileSearch = false
        var placement: Placement
    }

    struct Verdict: Equatable {
        var relevance: Relevance
        var reasons: [MatchReason]
    }

    static func score(_ input: Input) -> Verdict {
        var reasons: [MatchReason] = []
        if let product = input.product { reasons.append(reason(for: product)) }
        if let vendor = input.vendor { reasons.append(.vendorName(term: vendor.term.text)) }
        if input.underVendor { reasons.append(.insideVendorFolder) }

        let relevance = relevance(for: input)
        if let bundle = input.foreignBundle {
            reasons.append(.insideOtherBundle(name: bundle))
        } else if input.fileSearch {
            // Where a file lies is plain from its path; nothing more needs explaining.
        } else if input.placement.personal {
            reasons.append(.personalLocation)
        } else if relevance < .high, let owner = input.placement.owner, !input.underVendor {
            reasons.append(.insideOtherProgram(owner: owner))
        }
        return Verdict(relevance: relevance, reasons: reasons)
    }

    private static func relevance(for input: Input) -> Relevance {
        let placement = input.placement
        let vendorContext = input.vendor != nil || input.underVendor

        // Never reach into another program's bundle on the strength of a name.
        if input.foreignBundle != nil { return .low }

        // In a file search every match is an answer, and choosing what to delete is left to the user.
        if input.fileSearch { return .medium }

        if placement.personal {
            if let product = input.product {
                // The product's own name, its vendor's, or "config.seb", a document only it opens.
                if product.kind == .exact || vendorContext || product.isExtension { return .medium }
                // "Terrain Crack.dmg" among downloads, yes; "terrain analysis.docx" among documents, no.
                if product.kind.isStrong && (product.term.isDistinctive || placement.category == .installers) {
                    return .medium
                }
                return .low
            }
            // A download named after the company may be its installer; other personal files are not software.
            if input.product == nil, let vendor = input.vendor, vendor.kind.isStrong, placement.category == .installers {
                return .medium
            }
            return .low
        }

        guard let product = input.product else {
            // Only the company's name matches: related, but possibly to another of its products.
            guard let vendor = input.vendor else { return .low }
            return placement.installSlot && (vendor.kind.isStrong || vendor.term.isDistinctive) ? .medium : .low
        }

        let kind = product.kind
        let distinctive = product.term.isDistinctive
        // Programs and plug-ins are preselected only when the name is the one asked for:
        // "Terrain FX.app" is not what "Terrain" means unless the user says so.
        let isProgramSlot = placement.category == .applications || placement.category == .audioPlugins
        let trustedKind = isProgramSlot
            ? (kind == .exact || product.term.role == .identifier || input.corroborated)
            : kind.isStrong

        if input.corroborated && (placement.installSlot || placement.nearInstallSlot) { return .high }

        if vendorContext && kind >= .word && (trustedKind || !isProgramSlot)
            && (placement.installSlot || placement.nearInstallSlot || input.underVendor) {
            return .high
        }
        if trustedKind && placement.installSlot { return .high }
        if trustedKind && placement.nearInstallSlot && distinctive { return .high }
        if kind == .word && distinctive && placement.installSlot && !isProgramSlot { return .high }

        // Deep inside another program's files a common word proves little: a game's "terrain"
        // folder has nothing to do with a plug-in called Terrain.
        if vendorContext { return .medium }
        if kind.isStrong && (distinctive || placement.installSlot || placement.nearInstallSlot) { return .medium }
        if kind == .word && (placement.installSlot || distinctive) { return .medium }
        if kind == .partial && placement.installSlot { return .medium }
        return .low
    }

    static func reason(for match: TermMatch) -> MatchReason {
        let text = match.term.text
        if match.term.role == .identifier { return .bundleIdentifier(id: text) }
        if match.isExtension { return .fileExtension(term: text) }
        switch match.kind {
        case .exact: return .exactName(term: text)
        case .identifier: return .identifierComponent(term: text)
        case .prefix: return .nameStartsWith(term: text)
        case .word: return .containsWord(term: text)
        case .partial: return .containsText(term: text)
        }
    }
}
