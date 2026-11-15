import Foundation

/// Reads what a bundle says about itself.
enum BundleInspector {
    struct Info: Sendable {
        var identifier: String?
        var version: String?
    }

    static func info(atPath path: String) -> Info? {
        let candidates = [
            path + "/Contents/Info.plist",
            path + "/Info.plist",
            path + "/Resources/Info.plist",
            path + "/Versions/Current/Resources/Info.plist",
        ]
        for candidate in candidates {
            guard let plist = PropertyList.dictionary(atPath: candidate) else { continue }
            return Info(identifier: plist["CFBundleIdentifier"] as? String,
                        version: (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String))
        }
        return nil
    }

    /// Bundle identifiers of the found programs and plug-ins, to search for by identifier next.
    ///
    /// Only bundles the name match is sure about count: an identifier taken from a doubtful
    /// match would drag that program's preferences and caches into the results.
    static func identifiers(of hits: [RawHit]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for hit in hits where hit.isBundle && hit.foreignBundle == nil {
            guard let product = hit.evaluation.product, product.kind == .exact,
                  let ext = Bundles.pathExtension(of: hit.path), Bundles.identifiable.contains(ext),
                  let identifier = info(atPath: hit.path)?.identifier else { continue }
            // Two components at least, and not one of Apple's own.
            guard identifier.split(separator: ".").count >= 2, !identifier.lowercased().hasPrefix("com.apple.") else { continue }
            if seen.insert(identifier.lowercased()).inserted { result.append(identifier) }
        }
        return result.sorted()
    }
}

enum PropertyList {
    static func dictionary(atPath path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
