import Foundation

/// Which directories the Finder presents as single files.
enum Bundles {
    static let extensions: Set<String> = [
        "app", "vst", "vst3", "component", "aaxplugin", "clap", "lv2", "bundle", "framework", "plugin",
        "kext", "dext", "appex", "xpc", "prefpane", "qlgenerator", "mdimporter", "saver", "wdgt",
        "service", "action", "workflow", "driver", "systemextension", "colorpicker", "osax",
        "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band",
        "xcodeproj", "xcworkspace", "playground", "xcarchive", "dsym", "docset", "pkg", "mpkg",
        "sparsebundle", "rtfd", "key", "numbers", "pages", "scptd", "download", "lproj", "nib",
        "aplibrary", "photolibrary", "theater", "dvdproj", "ccip", "mlpackage", "scnassets", "xcassets",
    ]

    /// Extensions whose bundles carry an Info.plist worth reading for an identifier.
    static let identifiable: Set<String> = [
        "app", "vst", "vst3", "component", "aaxplugin", "clap", "bundle", "framework", "plugin",
        "kext", "dext", "appex", "xpc", "prefpane", "qlgenerator", "mdimporter", "saver", "systemextension",
    ]

    static func isBundle(name: String) -> Bool {
        guard let ext = pathExtension(of: name) else { return false }
        return extensions.contains(ext)
    }

    static func pathExtension(of name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = name[name.index(after: dot)...]
        return ext.isEmpty ? nil : ext.lowercased()
    }
}

/// Where a scan starts and which parts of the tree it leaves alone.
struct ScanLayout: Sendable {
    var roots: [WalkDirectory]
    /// Directory names never entered, wherever they appear.
    var skippedNames: Set<String>
    /// Directories never entered.
    var skippedPaths: Set<String>
    /// Directories whose entries are read but whose subdirectories are not opened.
    var shallowPaths: Set<String>

    static let skippedNames: Set<String> = [
        ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
        ".TemporaryItems", ".MobileBackups", ".vol", "node_modules", ".git", ".svn", ".hg", "__pycache__",
    ]

    /// Where macOS and its built-in apps keep the user's mail, messages, bookmarks and the like.
    /// The scan stays out of these folders, and they are never offered for removal.
    static func systemData(environment env: ScanEnvironment) -> [String] {
        let library = env.home + "/Library"
        return [
            env.home + "/.Trash",
            library + "/Mail",
            library + "/Messages",
            library + "/Safari",
            library + "/Calendars",
            library + "/Accounts",
            library + "/Metadata",
            library + "/Biome",
            library + "/Application Support/MobileSync",
            library + "/Application Support/AddressBook",
            library + "/Application Support/CloudDocs",
            env.sys("/Library/Apple"),
            env.sys("/Library/Updates"),
            env.sys("/Library/OSAnalytics"),
            env.sys("/Library/Managed Preferences"),
            // Network, audio device and directory settings of the machine itself.
            env.sys("/Library/Preferences/SystemConfiguration"),
            env.sys("/Library/Preferences/OpenDirectory"),
            env.sys("/Library/Preferences/Audio"),
        ]
    }

    /// File types that are downloads of software rather than the user's own work.
    static let installerExtensions: Set<String> = [
        "dmg", "pkg", "mpkg", "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "xz", "iso", "exe", "msi",
        "app", "torrent", "sparseimage", "cdr",
    ]

    init(environment env: ScanEnvironment, options: ScanOptions, externalVolumes: [String] = []) {
        let home = env.home
        let library = home + "/Library"
        let unlimited = Int.max

        var roots: [WalkDirectory] = [
            WalkDirectory(path: home, remainingDepth: unlimited),
            WalkDirectory(path: env.sys("/Applications"), remainingDepth: unlimited),
            WalkDirectory(path: env.sys("/Library"), remainingDepth: unlimited),
            WalkDirectory(path: env.sys("/Users/Shared"), remainingDepth: unlimited),
            WalkDirectory(path: env.sys("/usr/local"), remainingDepth: unlimited),
            WalkDirectory(path: env.sys("/opt"), remainingDepth: unlimited),
            WalkDirectory(path: env.sys("/private/etc"), remainingDepth: 2),
            WalkDirectory(path: env.sys("/private/var"), remainingDepth: 0),
            WalkDirectory(path: env.sys("/private/var/db"), remainingDepth: 0),
            WalkDirectory(path: env.sys("/private/var/log"), remainingDepth: 3),
            WalkDirectory(path: env.sys("/private/var/tmp"), remainingDepth: 2),
            WalkDirectory(path: env.sys("/private/tmp"), remainingDepth: 2),
        ]
        if let temp = env.userTemp { roots.append(WalkDirectory(path: temp, remainingDepth: 2)) }
        if let cache = env.userCache { roots.append(WalkDirectory(path: cache, remainingDepth: 2)) }
        if options.includeExternalVolumes {
            roots += externalVolumes.map { WalkDirectory(path: $0, remainingDepth: unlimited) }
        }
        self.roots = roots
        self.skippedNames = Self.skippedNames

        self.skippedPaths = Set(Self.systemData(environment: env)).union([
            library + "/Developer/CoreSimulator",
            library + "/Developer/Xcode/DerivedData",
            library + "/Developer/Xcode/iOS DeviceSupport",
            library + "/Developer/Xcode/Archives",
            env.sys("/Library/Developer"),
        ])

        // Other apps' private data: reading names is enough, and going deeper trips privacy prompts.
        self.shallowPaths = [
            library + "/Mobile Documents",
            library + "/CloudStorage",
            library + "/Containers",
            library + "/Group Containers",
            library + "/Daemon Containers",
        ]
    }
}
