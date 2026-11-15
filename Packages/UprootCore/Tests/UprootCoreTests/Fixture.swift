import Foundation
@testable import UprootCore

/// A throwaway directory tree laid out like a Mac, for scanning without touching the real one.
final class Fixture {
    let root: String
    let home: String

    var environment: ScanEnvironment {
        ScanEnvironment(systemRoot: root, home: home)
    }

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("uproot-fixture-" + UUID().uuidString)
        // Resolve /var to /private/var so paths compare equal to what the walker reports.
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base.resolvingSymlinksInPath().path
        home = root + "/Users/tester"
        for folder in ["/Applications", "/Library", "/Users/Shared", "/usr/local/bin", "/opt", "/private/etc",
                       "/private/var/db/receipts", "/private/var/log", "/private/var/tmp", "/private/tmp", "/Volumes"] {
            try directory(root + folder)
        }
        try directory(home + "/Library")
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }

    /// Path under the fixture's disk root.
    func sys(_ path: String) -> String { root + path }
    /// Path under the fixture's home folder.
    func user(_ path: String) -> String { home + "/" + path }

    func directory(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ path: String, _ contents: String = "x") throws -> String {
        try directory((path as NSString).deletingLastPathComponent)
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    /// Creates a bundle with an Info.plist carrying `identifier`.
    @discardableResult
    func bundle(_ path: String, identifier: String? = nil) throws -> String {
        try directory(path + "/Contents/MacOS")
        try file(path + "/Contents/MacOS/" + ((path as NSString).lastPathComponent as NSString).deletingPathExtension)
        if let identifier {
            let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": "1.0.0"]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: path + "/Contents/Info.plist"))
        }
        return path
    }

    func plist(_ path: String, _ contents: [String: Any]) throws {
        try directory((path as NSString).deletingLastPathComponent)
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Writes an installer receipt whose payload is `paths`, given relative to the disk root.
    func receipt(_ packageID: String, payload paths: [String]) throws {
        let receipts = sys("/private/var/db/receipts")
        try plist(receipts + "/\(packageID).plist", ["PackageIdentifier": packageID, "PackageVersion": "1.0", "InstallPrefixPath": "/"])
        // mkbom builds the bill of materials from a directory mirroring the payload.
        let staging = root + "/.staging-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: staging) }
        for path in paths {
            var isDirectory: ObjCBool = false
            let source = sys("/" + path)
            if FileManager.default.fileExists(atPath: source, isDirectory: &isDirectory), isDirectory.boolValue {
                try directory(staging + "/" + path)
            } else {
                try file(staging + "/" + path)
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mkbom")
        process.arguments = [staging, receipts + "/\(packageID).bom"]
        try process.run()
        process.waitUntilExit()
    }

    func scan(_ products: [String], vendors: [String] = [], excludes: [String] = [],
              options: ScanOptions = .init(), target: SearchTarget = .program) async -> ScanResult {
        await Scanner(environment: environment)
            .scan(SearchQuery(target: target, products: products, vendors: vendors, excludes: excludes, options: options))
    }
}

extension ScanResult {
    /// The item at a path, or nil when the scan did not list it.
    func item(_ path: String) -> FoundItem? { items.first { $0.path == path } }

    func relevance(_ path: String) -> Relevance? { item(path)?.relevance }
}
