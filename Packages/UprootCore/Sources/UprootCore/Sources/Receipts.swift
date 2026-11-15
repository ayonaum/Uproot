import Foundation

/// A record macOS keeps for every installer package that has run.
struct ReceiptRecord: Sendable {
    var packageID: String
    var plistPath: String
    var bomPath: String
    var version: String?
    var installed: Date?
    /// Where the payload went, relative to the disk root.
    var installPrefix: String
}

/// Reads installer receipts and works out which files a package put on disk.
struct Receipts: Sendable {
    let environment: ScanEnvironment
    let placement: PlacementResolver

    private var directory: String { environment.sys("/private/var/db/receipts") }

    /// Package identifiers of every receipt on the machine.
    func packageIDs() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.filter { $0.hasSuffix(".plist") }.map { String($0.dropLast(".plist".count)) }.sorted()
    }

    func record(for packageID: String) -> ReceiptRecord {
        let plistPath = directory + "/" + packageID + ".plist"
        let plist = PropertyList.dictionary(atPath: plistPath) ?? [:]
        return ReceiptRecord(packageID: packageID,
                             plistPath: plistPath,
                             bomPath: directory + "/" + packageID + ".bom",
                             version: plist["PackageVersion"] as? String,
                             installed: plist["InstallDate"] as? Date,
                             installPrefix: (plist["InstallPrefixPath"] as? String) ?? "/")
    }

    /// Absolute paths of everything the package installed, folders included.
    func payload(of record: ReceiptRecord) -> [String] {
        guard FileManager.default.fileExists(atPath: record.bomPath),
              let output = Shell.run("/usr/bin/lsbom", ["-s", record.bomPath]), output.succeeded else { return [] }
        var prefix = record.installPrefix
        while prefix.hasPrefix("/") { prefix.removeFirst() }
        while prefix.hasSuffix("/") { prefix.removeLast() }

        var paths: [String] = []
        for line in output.stdout.split(separator: "\n") {
            var relative = Substring(line)
            if relative.hasPrefix("./") { relative = relative.dropFirst(2) } else if relative == "." { continue }
            guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else { continue }
            var full = prefix.isEmpty ? String(relative) : prefix + "/" + relative
            // Packages write through the "/etc", "/var" and "/tmp" links; the scan names the real folders.
            for alias in ["etc", "var", "tmp"] where full == alias || full.hasPrefix(alias + "/") {
                full = "private/" + full
            }
            paths.append(environment.sys("/") + full)
        }
        return paths
    }

    /// The top-most things on disk that came from this payload and from nothing else.
    ///
    /// A package lists every folder it touches, including shared ones such as /Library/Audio.
    /// Walking down from the top, a folder counts as the package's own only when it is not a
    /// standard folder and everything in it today is part of the payload; otherwise the walk
    /// continues into it. Files and bundles are always the package's own.
    func ownedRoots(payload: [String], limit: Int = 300) -> [String] {
        let all = Set(payload)
        var children: [String: [String]] = [:]
        var tops: [String] = []
        for path in payload {
            let parent = (path as NSString).deletingLastPathComponent
            if all.contains(parent) { children[parent, default: []].append(path) } else { tops.append(path) }
        }

        var roots: [String] = []
        var stack = tops
        let fileManager = FileManager.default
        while let path = stack.popLast(), roots.count < limit {
            var info = stat()
            guard lstat(path, &info) == 0 else { continue }
            let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
            let name = (path as NSString).lastPathComponent
            let payloadChildren = children[path] ?? []
            if (info.st_mode & S_IFMT) == S_IFLNK, !payloadChildren.isEmpty {
                // A folder to the package, a link on this disk: the package installed through it.
                // The link is not the package's to take; what it put behind the link may be.
                stack.append(contentsOf: payloadChildren)
                continue
            }
            guard isDirectory, !Bundles.isBundle(name: name) else {
                roots.append(path)
                continue
            }
            if placement.isStandardDirectory(path) {
                stack.append(contentsOf: payloadChildren)
                continue
            }
            let onDisk = ((try? fileManager.contentsOfDirectory(atPath: path)) ?? []).filter { !Self.ignorable.contains($0) }
            let listed = Set(payloadChildren.map { ($0 as NSString).lastPathComponent })
            if !onDisk.isEmpty && onDisk.allSatisfy(listed.contains) {
                roots.append(path)
            } else {
                stack.append(contentsOf: payloadChildren)
            }
        }
        return roots.sorted()
    }

    static let ignorable: Set<String> = [".DS_Store", ".localized", "Icon\r"]
}

extension PlacementResolver {
    /// Folders that belong to macOS or are shared by many programs, and so are never one package's own.
    func isStandardDirectory(_ path: String) -> Bool {
        if isRuleBase(path) || isProtected(path) { return true }
        let env = environment
        let system = env.sys("")
        let fixed: Set<String> = [
            system.isEmpty ? "/" : system,
            env.sys("/Applications/Utilities"), env.sys("/usr"), env.sys("/private"), env.sys("/Users"),
            env.sys("/Library/Application Support/Avid"), env.sys("/Library/Application Support/Avid/Audio"),
            env.sys("/Library/Application Support/Digidesign"), env.sys("/Library/Audio/Plug-Ins"),
            env.home, env.home + "/Library",
        ]
        if fixed.contains(path) { return true }
        if path.hasPrefix(env.sys("/System")) { return true }
        // The Unix tree under /usr/local and Homebrew is shared two levels down: share/man, lib/pkgconfig.
        for prefix in [env.sys("/usr/local"), env.sys("/opt/homebrew")] where path.hasPrefix(prefix + "/") {
            let depth = path.dropFirst(prefix.count + 1).split(separator: "/").count
            if depth <= 2 { return true }
            let name = (path as NSString).lastPathComponent
            if name.hasPrefix("man") && name.count <= 4 { return true }
        }
        return false
    }
}
