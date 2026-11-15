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

    /// Identifiers of the found apps that are Apple's and can be uninstalled like anyone else's:
    /// Xcode, Keynote, GarageBand. Files named after one of these are that program's leftovers.
    /// Files named after any other Apple app belong to something built into macOS.
    static func removableAppleIdentifiers(of hits: [RawHit]) -> [String] {
        var result = Set<String>()
        for hit in hits where hit.isBundle && hit.foreignBundle == nil && hit.evaluation.product?.kind == .exact {
            var status = stat()
            guard Bundles.pathExtension(of: hit.path) == "app", lstat(hit.path, &status) == 0,
                  !Assembler.isGuardedBySystem(status),
                  let identifier = info(atPath: hit.path)?.identifier?.lowercased(),
                  identifier.hasPrefix("com.apple."), identifier.split(separator: ".").count >= 3 else { continue }
            result.insert(identifier)
        }
        return result.sorted()
    }
}

enum PropertyList {
    /// Property lists are small. A file of gigabytes behind the name of one is not read into memory.
    static let sizeLimit: off_t = 16 << 20

    static func dictionary(atPath path: String) -> [String: Any]? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= sizeLimit,
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
