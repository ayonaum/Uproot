import Foundation

/// Where a path sits relative to the standard folders of macOS.
struct Placement: Sendable, Equatable {
    var category: ItemCategory
    /// The standard folder, shortened for display: "~/Library/Application Support".
    var locationTitle: String
    /// Levels below that folder; 1 is a direct child.
    var depth: Int
    /// The folder directly under the standard location when the item is deeper than that.
    var owner: String?
    /// The item is in a slot where software gets installed, such as a direct child of Preferences.
    var installSlot: Bool
    /// One level below an install slot, the usual "Vendor/Product" layout.
    var nearInstallSlot: Bool
    /// The item is among the user's own documents and downloads.
    var personal: Bool
}

/// Maps paths onto the standard layout of a Mac.
struct PlacementResolver: Sendable {
    private struct Rule: Sendable {
        var base: String
        var category: ItemCategory
        /// Items at this depth or above are in an install slot. Zero: never.
        var installDepth: Int
        /// Subfolders that do not count as a level, such as Preferences/ByHost.
        var transparent: Set<String> = []
        var personal = false
    }

    let environment: ScanEnvironment
    /// Rules by base path, so the longest matching base wins.
    private let rules: [String: Rule]
    private let hostDataBases: [String]

    init(environment env: ScanEnvironment) {
        self.environment = env
        var rules: [String: Rule] = [:]
        func add(_ base: String, _ category: ItemCategory, depth: Int, transparent: Set<String> = [], personal: Bool = false) {
            rules[base] = Rule(base: base, category: category, installDepth: depth, transparent: transparent, personal: personal)
        }

        let home = env.home
        for library in [home + "/Library", env.sys("/Library")] {
            add(library, .appData, depth: 1)
            add(library + "/Application Support", .appData, depth: 1)
            add(library + "/Application Support/CrashReporter", .logs, depth: 1)
            add(library + "/Application Support/Avid/Audio/Plug-Ins", .audioPlugins, depth: 2)
            add(library + "/Application Support/Avid/Audio/Plug-Ins (Unused)", .audioPlugins, depth: 2)
            add(library + "/Application Support/Digidesign/Plug-Ins", .audioPlugins, depth: 2)
            add(library + "/Audio", .audioPlugins, depth: 2)
            add(library + "/Audio/Plug-Ins", .audioPlugins, depth: 1)
            for format in ["Components", "VST", "VST3", "CLAP", "HAL", "MAS", "LV2", "AAX", "Driver"] {
                add(library + "/Audio/Plug-Ins/" + format, .audioPlugins, depth: 2)
            }
            for folder in ["Presets", "MIDI Drivers", "MIDI Devices", "MIDI Patch Names", "Sounds",
                           "Impulse Responses", "Apple Loops", "Sysex Librarian", "Plug-In Settings"] {
                add(library + "/Audio/" + folder, .audioPlugins, depth: 2)
            }
            add(library + "/Preferences", .preferences, depth: 1, transparent: ["ByHost"])
            for folder in ["Caches", "HTTPStorages", "WebKit", "Saved Application State", "Cookies", "Autosave Information"] {
                add(library + "/" + folder, .caches, depth: 1)
            }
            add(library + "/Logs", .logs, depth: 1, transparent: ["DiagnosticReports", "CrashReporter"])
            for folder in ["Containers", "Group Containers", "Application Scripts", "Daemon Containers"] {
                add(library + "/" + folder, .containers, depth: 1)
            }
            for folder in ["LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools", "StartupItems"] {
                add(library + "/" + folder, .launchItems, depth: 1)
            }
            for folder in ["Extensions", "SystemExtensions", "DriverExtensions", "PreferencePanes", "QuickLook",
                           "Spotlight", "Internet Plug-Ins", "Screen Savers", "Services", "Input Methods",
                           "Keyboard Layouts", "ColorPickers", "Components", "Contextual Menu Items", "Frameworks",
                           "Filesystems", "Scripts", "ScriptingAdditions", "Address Book Plug-Ins", "Workflows",
                           "Automator", "Fonts", "Sounds", "Printers", "Image Capture", "Plug-Ins", "Compositions",
                           "Video", "CoreMediaIO", "Graphics", "Java", "Widgets", "Speech", "Keychains"] {
                add(library + "/" + folder, .extensions, depth: 1)
            }
            add(library + "/Receipts", .receipts, depth: 1)
            add(library + "/Mobile Documents", .personalFiles, depth: 0, personal: true)
            add(library + "/CloudStorage", .personalFiles, depth: 0, personal: true)
        }

        for applications in [env.sys("/Applications"), home + "/Applications"] {
            add(applications, .applications, depth: 2)
        }
        add(home + "/Applications/CrossOver", .windows, depth: 1)
        add(env.sys("/Users/Shared"), .appData, depth: 1)

        add(home, .personalFiles, depth: 0, personal: true)
        for folder in ["Desktop", "Documents", "Movies", "Music", "Pictures", "Public"] {
            add(home + "/" + folder, .personalFiles, depth: 0, personal: true)
        }
        add(home + "/Downloads", .installers, depth: 0, personal: true)
        for folder in [".config", ".local/share", ".local/state", ".local/bin", ".cache", "bin"] {
            add(home + "/" + folder, .commandLine, depth: 1)
        }
        add(home + "/Music/Audio Music Apps/Plug-In Settings", .hostData, depth: 1)

        for prefix in [env.sys("/usr/local"), env.sys("/opt/homebrew")] {
            add(prefix, .commandLine, depth: 1)
            for folder in ["bin", "sbin", "lib", "libexec", "share", "include", "etc", "opt", "var", "Cellar", "Caskroom", "Frameworks"] {
                add(prefix + "/" + folder, .commandLine, depth: 1)
            }
        }
        add(env.sys("/opt"), .commandLine, depth: 1)
        add(env.sys("/private/etc"), .commandLine, depth: 1,
            transparent: ["sudoers.d", "paths.d", "manpaths.d", "newsyslog.d", "pam.d", "asl"])
        add(env.sys("/private/var"), .other, depth: 1)
        add(env.sys("/private/var/db"), .other, depth: 1)
        add(env.sys("/private/var/log"), .logs, depth: 1)
        add(env.sys("/private/var/tmp"), .caches, depth: 1)
        add(env.sys("/private/tmp"), .caches, depth: 1)
        if let temp = env.userTemp { add(temp, .caches, depth: 1) }
        if let cache = env.userCache { add(cache, .caches, depth: 1) }

        self.rules = rules
        // Plug-in databases that hosts keep per plug-in; a name there is the plug-in, however deep.
        self.hostDataBases = [
            home + "/Documents/Image-Line/FL Studio/Presets/Plugin database",
            home + "/Documents/Image-Line/FL Studio/Presets/Plugin presets",
        ]
    }

    /// True for the standard folders the rules are anchored on.
    func isRuleBase(_ path: String) -> Bool { rules[path] != nil }

    func resolve(path: String) -> Placement {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if let windows = windowsPlacement(path: path, components: components) { return windows }

        for base in hostDataBases where path.hasPrefix(base + "/") {
            let depth = path.dropFirst(base.count + 1).split(separator: "/").count
            return Placement(category: .hostData, locationTitle: environment.display(base), depth: depth,
                             owner: "FL Studio", installSlot: true, nearInstallSlot: false, personal: false)
        }

        // Longest base that is a proper ancestor of the path.
        var prefix = path
        while let slash = prefix.lastIndex(of: "/") {
            prefix = String(prefix[..<slash])
            guard !prefix.isEmpty, let rule = rules[prefix] else { continue }
            return placement(for: path, under: rule)
        }
        let parent = (path as NSString).deletingLastPathComponent
        return Placement(category: .other, locationTitle: environment.display(parent), depth: 1, owner: nil,
                         installSlot: false, nearInstallSlot: false, personal: false)
    }

    private func placement(for path: String, under rule: Rule) -> Placement {
        var relative = path.dropFirst(rule.base.count + 1).split(separator: "/").map(String.init)
        var title = environment.display(rule.base)
        while relative.count > 1, let first = relative.first, rule.transparent.contains(first) {
            title += "/" + first
            relative.removeFirst()
        }
        let depth = relative.count
        var owner = depth > 1 ? relative[0] : nil
        var category = rule.category
        var personal = rule.personal
        var installDepth = rule.installDepth

        if rule.base == environment.home, let first = relative.first {
            // Hidden folders in the home directory belong to command-line tools, not to the user's documents.
            if first.hasPrefix(".") {
                category = .commandLine
                personal = false
                installDepth = 1
            }
        }
        if personal, category == .personalFiles, let ext = Bundles.pathExtension(of: relative.last ?? ""),
           ScanLayout.installerExtensions.contains(ext) {
            category = .installers
        }
        if let game = steamGame(in: relative) { owner = game }

        return Placement(category: category, locationTitle: title, depth: depth, owner: owner,
                         installSlot: installDepth > 0 && depth <= installDepth,
                         nearInstallSlot: installDepth > 0 && depth == installDepth + 1,
                         personal: personal)
    }

    /// Wine-style prefixes (CrossOver, Whisky, plain Wine) mirror a Windows disk under "drive_c".
    private func windowsPlacement(path: String, components: [String]) -> Placement? {
        if let driveIndex = components.firstIndex(of: "drive_c"), driveIndex >= 1, driveIndex < components.count - 1 {
            let bottle = components[driveIndex - 1]
            let inside = Array(components[(driveIndex + 1)...])
            let lowered = inside.map { $0.lowercased() }
            var slotDepth: Int?   // number of leading components that form the install location

            if let first = lowered.first {
                if first == "program files" || first == "program files (x86)" || first == "programdata" {
                    slotDepth = 1
                } else if first == "users", lowered.count >= 3 {
                    if lowered.count >= 4, lowered[2] == "appdata", ["local", "locallow", "roaming"].contains(lowered[3]) {
                        slotDepth = 4
                        if let programs = lowered.firstIndex(of: "programs"), lowered.contains("start menu") {
                            slotDepth = programs + 1
                        } else if lowered.count >= 5, lowered[4] == "temp" {
                            slotDepth = 5
                        }
                    } else if ["desktop", "documents"].contains(lowered[2]) {
                        slotDepth = 3
                    }
                }
            }
            let depth = slotDepth.map { inside.count - $0 } ?? inside.count
            let slot = slotDepth != nil && depth == 1
            let near = slotDepth != nil && depth == 2
            let owner = steamGame(in: inside) ?? (slotDepth != nil && depth > 1 ? inside[slotDepth!] : nil)
            return Placement(category: .windows, locationTitle: "Windows · \(bottle)", depth: max(depth, 1),
                             owner: owner, installSlot: slot, nearInstallSlot: near, personal: false)
        }
        // CrossOver keeps menu entries for the bottle's programs next to drive_c.
        if let dataIndex = components.firstIndex(of: "desktopdata"), dataIndex >= 2,
           components[dataIndex - 2] == "Bottles", dataIndex < components.count - 1 {
            return Placement(category: .windows, locationTitle: "Windows · \(components[dataIndex - 1])",
                             depth: 1, owner: nil, installSlot: true, nearInstallSlot: false, personal: false)
        }
        return nil
    }

    private func steamGame(in components: [String]) -> String? {
        guard let common = components.firstIndex(of: "common"), common >= 1,
              components[common - 1].lowercased() == "steamapps", common + 2 < components.count else { return nil }
        return components[common + 1]
    }
}
