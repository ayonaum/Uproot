import Foundation

/// Where the scan looks beyond the places it always covers.
public struct ScanOptions: Sendable, Equatable, Codable {
    /// Also look inside apps and plug-ins that do not match themselves. Slow and noisy; off by default.
    public var searchInsideBundles = false
    /// Walk external and network volumes as well as the startup disk.
    public var includeExternalVolumes = false

    public init(searchInsideBundles: Bool = false, includeExternalVolumes: Bool = false) {
        self.searchInsideBundles = searchInsideBundles
        self.includeExternalVolumes = includeExternalVolumes
    }
}

/// What kind of search the user wants.
public enum SearchTarget: String, Sendable, Codable, CaseIterable {
    /// A program or plug-in and everything it left on the machine. The scan judges what
    /// belongs to it, follows its identifiers and installer packages, and preselects what it is sure of.
    case program
    /// Any files and folders by name. Every match is listed and nothing is preselected.
    case files
}

/// What the user asked to find.
public struct SearchQuery: Sendable, Equatable, Codable {
    public var target: SearchTarget
    /// Names of the program or plug-in; in a file search, the file names.
    public var products: [String]
    /// Names of the company behind it.
    public var vendors: [String]
    /// Paths containing any of these are left out of the results.
    public var excludes: [String]
    public var options: ScanOptions

    public init(target: SearchTarget = .program, products: [String], vendors: [String] = [], excludes: [String] = [],
                options: ScanOptions = .init()) {
        self.target = target
        self.products = products
        self.vendors = target == .files ? [] : vendors
        self.excludes = excludes
        self.options = options
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Searches saved before file search existed have no target.
        target = try container.decodeIfPresent(SearchTarget.self, forKey: .target) ?? .program
        products = try container.decode([String].self, forKey: .products)
        vendors = try container.decodeIfPresent([String].self, forKey: .vendors) ?? []
        excludes = try container.decodeIfPresent([String].self, forKey: .excludes) ?? []
        options = try container.decodeIfPresent(ScanOptions.self, forKey: .options) ?? .init()
    }

    /// A one-line description for history and window titles.
    public var summary: String {
        let names = products.isEmpty ? vendors : products
        return names.joined(separator: ", ")
    }

    func termSet() -> TermSet {
        var products = unique(self.products.compactMap { SearchTerm($0, role: .product) })
        var vendors = unique(self.vendors.compactMap { SearchTerm($0, role: .vendor) })
        // With only a company given, everything of that company is what the user wants.
        if products.isEmpty {
            products = vendors.compactMap { SearchTerm($0.text, role: .product) }
            vendors = []
        }
        return TermSet(products: products, vendors: vendors)
    }

    /// Terms too short to search for, so the app can say why they were ignored.
    public var rejectedTerms: [String] {
        (products + vendors).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && SearchTerm($0, role: .product) == nil }
    }

    public var hasSearchableTerms: Bool { !termSet().products.isEmpty }

    private func unique(_ terms: [SearchTerm]) -> [SearchTerm] {
        var seen = Set<[UInt8]>()
        return terms.filter { seen.insert($0.folded).inserted }
    }
}

/// The machine being scanned. Tests point this at a fixture tree.
public struct ScanEnvironment: Sendable {
    /// Prepended to every system path; empty on a real machine.
    public var systemRoot: String
    public var home: String
    /// The per-user temporary folder under /var/folders.
    public var userTemp: String?
    /// The per-user cache folder under /var/folders.
    public var userCache: String?
    public var uid: uid_t

    public init(systemRoot: String = "", home: String, userTemp: String? = nil, userCache: String? = nil, uid: uid_t = getuid()) {
        self.systemRoot = systemRoot
        self.home = home
        self.userTemp = userTemp
        self.userCache = userCache
        self.uid = uid
    }

    public static var current: ScanEnvironment {
        ScanEnvironment(systemRoot: "",
                        home: NSHomeDirectory(),
                        userTemp: darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR),
                        userCache: darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR))
    }

    /// A system path on this environment: `sys("/Library")`.
    public func sys(_ path: String) -> String { systemRoot + path }

    /// Shortens a path for display: the home folder becomes "~", the fixture root is dropped.
    public func display(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        if !systemRoot.isEmpty, path.hasPrefix(systemRoot + "/") { return String(path.dropFirst(systemRoot.count)) }
        return path
    }

    private static func darwinUserDirectory(_ name: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(name, &buffer, buffer.count) > 0 else { return nil }
        var path = String(nullTerminated: buffer)
        // confstr answers with a trailing slash and the /var alias; scan paths use /private/var.
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path.hasPrefix("/var/") { path = "/private" + path }
        return path
    }
}
