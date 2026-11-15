import Foundation

/// Turns raw hits into the final list of items: judges each one, nests items found
/// inside vendor folders, and decides whether such a folder can go as a whole.
struct Assembler {
    private let env: ScanEnvironment
    private let resolver: PlacementResolver
    private let terms: TermSet
    /// In a file search matched folders do not swallow the matches inside them, and no folder is promoted.
    private let fileSearch: Bool
    /// Lowercased identifiers of the Apple apps found that can be uninstalled; see `BundleInspector`.
    private let removableApple: [String]
    private var items: [String: FoundItem] = [:]
    /// Paths of items whose own name matched the product; whatever lies inside them is implied.
    private var owningPaths = Set<String>()
    /// Folders that hold found items without being one themselves: vendor folders, package folders.
    private var containerPaths = Set<String>()

    init(environment: ScanEnvironment, resolver: PlacementResolver, terms: TermSet, fileSearch: Bool = false,
         removableAppleIdentifiers: [String] = []) {
        self.env = environment
        self.resolver = resolver
        self.terms = terms
        self.fileSearch = fileSearch
        self.removableApple = removableAppleIdentifiers.map { $0.lowercased() }
    }

    func contains(path: String) -> Bool { items[path] != nil }

    /// The found item that `path` is, or lies inside, when the scan is sure about that item.
    func trustedItem(containing path: String) -> FoundItem? {
        var current = path
        while current.count > 1 {
            if let item = items[current], item.isOnDisk, item.relevance == .high { return item }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Returns false when nothing was found at `path`.
    mutating func setDetail(_ detail: ItemDetail, forPath path: String) -> Bool {
        guard items[path] != nil else { return false }
        items[path]?.detail = detail
        return true
    }

    mutating func add(items newItems: [FoundItem]) {
        for item in newItems { add(item: item) }
    }

    mutating func add(item: FoundItem) {
        items[item.id] = item
    }

    mutating func add(hits: [String: RawHit]) {
        // Shallow paths first, so an owning folder is known before what lies inside it.
        for hit in hits.values.sorted(by: { $0.path.utf8.count < $1.path.utf8.count }) {
            add(hit: hit)
        }
    }

    mutating func add(hit: RawHit) {
        guard !isInsideOwningItem(hit.path) else { return }
        var info = stat()
        guard lstat(hit.path, &info) == 0 else { return }

        let placement = resolver.resolve(path: hit.path)
        let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
        let kind: ItemKind = hit.isBundle ? .bundle : isDirectory ? .folder
            : (info.st_mode & S_IFMT) == S_IFLNK ? .symlink : .file

        var detail = hit.detail
        var extraReasons = hit.extraReasons
        var corroborated = extraReasons.contains { if case .installedByPackage = $0 { true } else { false } }
        if detail == .none, hit.isBundle, let ext = Bundles.pathExtension(of: hit.path), Bundles.identifiable.contains(ext),
           let bundle = BundleInspector.info(atPath: hit.path) {
            detail = .bundle(identifier: bundle.identifier, version: bundle.version)
            // "zoom.us.app" is Zoom when its identifier is "us.zoom.xos"; "Terrain FX.app" with
            // "com.vendor.terrainfx" is not what a search for "Terrain" asked for.
            if let identifier = bundle.identifier, hit.evaluation.product?.term.role == .product,
               let match = terms.evaluate(NameFolding.fold(identifier)).product, match.kind >= .identifier {
                corroborated = true
                extraReasons.append(.bundleIdentifier(id: identifier))
            }
        }

        let verdict = RelevanceScorer.score(.init(product: hit.evaluation.product, vendor: hit.evaluation.vendor,
                                                  underVendor: hit.underVendor, foreignBundle: hit.foreignBundle,
                                                  corroborated: corroborated && hit.hasProductMatch,
                                                  fileSearch: fileSearch, placement: placement))
        var relevance = hit.forcedRelevance ?? verdict.relevance
        var reasons = verdict.reasons + extraReasons

        let name = (hit.path as NSString).lastPathComponent
        // Apps built into macOS cannot be uninstalled, and what they keep is the user's own:
        // a search for "Notes" must not come back with the notes ticked for removal.
        if relevance == .high, belongsToMacOS(name: name, info: info) {
            relevance = .medium
            reasons.append(.partOfMacOS)
        }
        items[hit.path] = FoundItem(
            id: hit.path, kind: kind, path: hit.path, name: name, category: placement.category,
            relevance: relevance, reasons: reasons,
            locationTitle: placement.locationTitle, owner: placement.owner,
            needsAdmin: Self.needsAdmin(path: hit.path, info: info, uid: env.uid),
            detail: detail,
            modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)))

        if hit.hasProductMatch && !(fileSearch && isDirectory && !hit.isBundle) {
            owningPaths.insert(hit.path)
        } else if isDirectory && !hit.isBundle && !fileSearch && hit.forcedRelevance == nil {
            // A folder a package owns outright is not a vendor folder: nothing in it is "unrelated".
            containerPaths.insert(hit.path)
        }
    }

    /// Whether an item is macOS's own rather than what a program left behind: the system forbids
    /// removing it, or it carries the name of an Apple app other than the removable ones found.
    private func belongsToMacOS(name: String, info: stat) -> Bool {
        if Self.isGuardedBySystem(info) { return true }
        let lowered = name.lowercased()
        // ".GlobalPreferences.plist" holds the settings shared by every app.
        guard Self.carriesAppleIdentifier(lowered) || lowered.hasPrefix(".globalpreferences") else { return false }
        return !removableApple.contains { lowered.hasPrefix($0) || lowered.contains("." + $0) }
    }

    /// True for names such as "com.apple.Notes.plist" and "group.com.apple.notes".
    static func carriesAppleIdentifier(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("com.apple.") || lowered.contains(".com.apple.")
    }

    /// macOS marks what must stay: "restricted" for what system integrity protection covers,
    /// "sunlnk" for folders such as /Library/Preferences/SystemConfiguration. Not even root may
    /// remove these, and trying would still empty a folder before failing on the folder itself.
    static func isGuardedBySystem(_ info: stat) -> Bool {
        info.st_flags & UInt32(SF_RESTRICTED | SF_NOUNLINK) != 0
    }

    mutating func finish() -> [FoundItem] {
        // An item added before its owning ancestor was known is implied by that ancestor.
        for path in Array(items.keys) where items[path]?.isOnDisk == true && isInsideOwningItem(path) {
            items[path] = nil
            containerPaths.remove(path)
        }

        let parents = items.values.filter(\.isOnDisk).map { ($0.id, nearestItem(above: $0.path)) }
        for (id, parent) in parents {
            items[id]?.parentID = parent
        }

        // Deepest containers first: an inner folder may complete the outer one.
        for path in containerPaths.sorted(by: { $0.utf8.count > $1.utf8.count }) {
            guard var item = items[path] else { continue }
            let foundInside = items.values.contains { $0.relevance == .high && $0.isOnDisk && $0.path.hasPrefix(path + "/") }
            let coverage = coverage(of: path)
            if foundInside && coverage.complete {
                if item.relevance != .high {
                    item.relevance = .high
                    item.reasons.append(.holdsOnlyFoundItems)
                }
            } else {
                item.unrelatedChildCount = coverage.unrelated
            }
            items[path] = item
        }

        return items.values.sorted {
            if $0.category.order != $1.category.order { return $0.category.order < $1.category.order }
            if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    // MARK: Structure

    private func isInsideOwningItem(_ path: String) -> Bool {
        var current = (path as NSString).deletingLastPathComponent
        while current.count > 1 {
            if owningPaths.contains(current) { return true }
            current = (current as NSString).deletingLastPathComponent
        }
        return false
    }

    private func nearestItem(above path: String) -> String? {
        var current = (path as NSString).deletingLastPathComponent
        while current.count > 1 {
            if let item = items[current], item.isOnDisk { return item.id }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Whether everything in a folder is a found item the scan is sure of, and how many
    /// things directly inside are not part of the results at all.
    private func coverage(of folder: String) -> (complete: Bool, unrelated: Int) {
        guard let entries = Self.entries(of: folder) else { return (false, 0) }
        var unrelated = 0
        var complete = true
        for entry in entries {
            let path = folder + "/" + entry
            if let item = items[path] {
                if item.relevance != .high { complete = false }
            } else if Self.isPlainDirectory(path), isFullyCovered(path, depth: 1) {
                continue
            } else {
                complete = false
                let holdsItems = items.values.contains { $0.isOnDisk && $0.path.hasPrefix(path + "/") }
                if !holdsItems { unrelated += 1 }
            }
        }
        return (complete, unrelated)
    }

    private func isFullyCovered(_ folder: String, depth: Int) -> Bool {
        guard depth <= 6, let entries = Self.entries(of: folder), entries.count <= 500 else { return false }
        for entry in entries {
            let path = folder + "/" + entry
            if let item = items[path] {
                if item.relevance != .high { return false }
            } else if !(Self.isPlainDirectory(path) && isFullyCovered(path, depth: depth + 1)) {
                return false
            }
        }
        return true
    }

    /// What a folder holds, or nil when it cannot be read. A folder that cannot be read is not
    /// an empty one: what is in it is unknown, so nothing above it may be called fully covered.
    private static func entries(of folder: String) -> [String]? {
        (try? FileManager.default.contentsOfDirectory(atPath: folder))?.filter { !Receipts.ignorable.contains($0) }
    }

    private static func isPlainDirectory(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return false }
        return !Bundles.isBundle(name: (path as NSString).lastPathComponent)
    }

    /// Whether removing the item takes more rights than the current user has.
    static func needsAdmin(path: String, info: stat, uid: uid_t) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        if access(parent, W_OK) != 0 { return true }
        var parentInfo = stat()
        if stat(parent, &parentInfo) == 0, parentInfo.st_mode & S_ISVTX != 0,
           info.st_uid != uid, parentInfo.st_uid != uid {
            return true
        }
        // Moving or emptying a folder needs write access to the folder itself.
        if (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid != uid, access(path, W_OK) != 0 { return true }
        return false
    }
}
