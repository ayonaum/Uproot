import Foundation

/// What a found item is, which decides how it gets removed.
public enum ItemKind: String, Sendable, Codable {
    case file
    case folder
    /// A directory the Finder shows as a single file: an app, a plug-in, a framework.
    case bundle
    case symlink
    /// An installer receipt; removed with `pkgutil --forget`.
    case receipt
    /// A running process; removed by terminating it.
    case process
    /// A mounted volume, usually a disk image; removed by ejecting it.
    case volume
}

/// The kind of place an item lives in. Sections of the result list follow this order.
public enum ItemCategory: String, Sendable, Codable, CaseIterable {
    case applications
    case audioPlugins
    case appData
    case preferences
    case caches
    case logs
    case containers
    case launchItems
    case extensions
    case receipts
    case processes
    case volumes
    case installers
    case windows
    case hostData
    case commandLine
    case personalFiles
    case other

    public var order: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }
}

/// How sure the scan is that an item belongs to what the user searched for.
public enum Relevance: Int, Sendable, Codable, Comparable {
    /// Mentions the term, but most likely belongs to something else.
    case low = 0
    /// Plausible; the user should look before deleting.
    case medium = 1
    /// Belongs to the product. Selected for removal by default.
    case high = 2

    public static func < (lhs: Relevance, rhs: Relevance) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Why an item is in the results. The app turns these into text.
public enum MatchReason: Sendable, Hashable, Codable {
    case exactName(term: String)
    case nameStartsWith(term: String)
    case identifierComponent(term: String)
    case containsWord(term: String)
    case containsText(term: String)
    case fileExtension(term: String)
    case vendorName(term: String)
    case insideVendorFolder
    /// Matches a bundle identifier read from a found app or plug-in.
    case bundleIdentifier(id: String)
    case installedByPackage(id: String)
    /// A launchd job whose program lives inside a found item.
    case launches(path: String)
    case linksTo(path: String)
    case runsFrom(path: String)
    case volumeContains(name: String)
    case insideOtherBundle(name: String)
    case personalLocation
    case insideOtherProgram(owner: String)
    /// A vendor folder with nothing in it but found items.
    case holdsOnlyFoundItems
}

/// Extra facts that only some kinds of item have.
public enum ItemDetail: Sendable, Hashable, Codable {
    case none
    case bundle(identifier: String?, version: String?)
    case receipt(packageID: String, version: String?, installed: Date?)
    case process(pid: Int32, ownedByCurrentUser: Bool)
    case volume(imagePath: String?)
    case launchJob(label: String, isSystemDomain: Bool)
}

/// One thing the scan found and offers to remove.
public struct FoundItem: Identifiable, Sendable, Hashable, Codable {
    /// The path for anything on disk; a prefixed key for receipts, processes and volumes.
    public var id: String
    public var kind: ItemKind
    /// Where the item is: its own path, a receipt's plist, a process's executable, a volume's mount point.
    public var path: String
    public var name: String
    public var category: ItemCategory
    public var relevance: Relevance
    public var reasons: [MatchReason]
    /// The standard folder the item sits in, shortened for display: "~/Library/Caches".
    public var locationTitle: String
    /// The other program or vendor folder the item is inside, if any.
    public var owner: String?
    /// The found item this one is nested in.
    public var parentID: String?
    /// Removing it takes administrator rights.
    public var needsAdmin: Bool
    /// For a vendor folder: how many things directly inside are not part of the results.
    public var unrelatedChildCount: Int
    public var detail: ItemDetail
    public var size: Int64?
    public var modified: Date?

    public init(id: String, kind: ItemKind, path: String, name: String, category: ItemCategory,
                relevance: Relevance, reasons: [MatchReason], locationTitle: String, owner: String? = nil,
                parentID: String? = nil, needsAdmin: Bool = false, unrelatedChildCount: Int = 0,
                detail: ItemDetail = .none, size: Int64? = nil, modified: Date? = nil) {
        self.id = id
        self.kind = kind
        self.path = path
        self.name = name
        self.category = category
        self.relevance = relevance
        self.reasons = reasons
        self.locationTitle = locationTitle
        self.owner = owner
        self.parentID = parentID
        self.needsAdmin = needsAdmin
        self.unrelatedChildCount = unrelatedChildCount
        self.detail = detail
        self.size = size
        self.modified = modified
    }

    /// True for items that are files or folders on disk.
    public var isOnDisk: Bool {
        switch kind {
        case .file, .folder, .bundle, .symlink: true
        case .receipt, .process, .volume: false
        }
    }

    public var isDirectoryLike: Bool { kind == .folder || kind == .bundle }
}
