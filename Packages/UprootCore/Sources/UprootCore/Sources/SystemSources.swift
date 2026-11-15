import Foundation

// MARK: - launchd

/// A job launchd starts from a property list.
struct LaunchJob: Sendable {
    var plistPath: String
    var label: String
    /// Executables the job runs.
    var programs: [String]
    var associatedBundleIDs: [String]
    /// Daemons run as root in the system domain; agents run in the user's session.
    var isSystemDomain: Bool
}

enum LaunchJobs {
    static func all(environment env: ScanEnvironment) -> [LaunchJob] {
        let folders: [(path: String, system: Bool)] = [
            (env.home + "/Library/LaunchAgents", false),
            (env.sys("/Library/LaunchAgents"), false),
            (env.sys("/Library/LaunchDaemons"), true),
        ]
        var jobs: [LaunchJob] = []
        for folder in folders {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where name.hasSuffix(".plist") {
                let path = folder.path + "/" + name
                guard let plist = PropertyList.dictionary(atPath: path) else { continue }
                var programs: [String] = []
                if let program = plist["Program"] as? String { programs.append(program) }
                if let arguments = plist["ProgramArguments"] as? [String], let first = arguments.first { programs.append(first) }
                if let bundleProgram = plist["BundleProgram"] as? String { programs.append(bundleProgram) }
                var associated: [String] = []
                if let ids = plist["AssociatedBundleIdentifiers"] as? [String] { associated = ids }
                if let id = plist["AssociatedBundleIdentifiers"] as? String { associated = [id] }
                jobs.append(LaunchJob(plistPath: path,
                                      label: (plist["Label"] as? String) ?? String(name.dropLast(".plist".count)),
                                      programs: programs,
                                      associatedBundleIDs: associated,
                                      isSystemDomain: folder.system))
            }
        }
        return jobs
    }
}

// MARK: - Processes

struct RunningProcess: Sendable {
    var pid: pid_t
    var executablePath: String
    var uid: uid_t
    var name: String { (executablePath as NSString).lastPathComponent }
}

enum Processes {
    static func all() -> [RunningProcess] {
        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity + 64)
        let filled = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard filled > 0 else { return [] }

        let own = getpid()
        var result: [RunningProcess] = []
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(filled) where pid > 0 && pid != own {
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard length > 0 else { continue }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let uid: uid_t = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info.pbi_uid : UInt32.max
            result.append(RunningProcess(pid: pid, executablePath: String(nullTerminated: pathBuffer), uid: uid))
        }
        return result
    }

    static func isRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

// MARK: - Volumes

struct MountedVolume: Sendable {
    var mountPoint: String
    var name: String
    /// The disk image file behind the volume, when it is one.
    var imagePath: String?
    var isInternal: Bool
}

enum Volumes {
    /// Volumes mounted under /Volumes, leaving out the startup disk.
    static func mounted(environment env: ScanEnvironment) -> [MountedVolume] {
        let base = env.sys("/Volumes")
        guard env.systemRoot.isEmpty else {
            // A fixture has no real mounts; its folders under /Volumes stand in for them.
            let names = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
            return names.filter { !$0.hasPrefix(".") }.map {
                MountedVolume(mountPoint: base + "/" + $0, name: $0, imagePath: nil, isInternal: false)
            }
        }
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var volumes: [MountedVolume] = []
        for url in urls where url.path.hasPrefix(base + "/") {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.volumeIsRootFileSystem == true { continue }
            volumes.append(MountedVolume(mountPoint: url.path,
                                         name: values?.volumeName ?? url.lastPathComponent,
                                         imagePath: nil,
                                         isInternal: values?.volumeIsInternal ?? false))
        }
        return volumes
    }

    /// Mount point to disk image path, for the images attached right now.
    static func diskImages() -> [String: String] {
        guard let output = Shell.run("/usr/bin/hdiutil", ["info", "-plist"]), output.succeeded,
              let plist = (try? PropertyListSerialization.propertyList(from: Data(output.stdout.utf8), format: nil)) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for image in images {
            guard let path = image["image-path"] as? String,
                  let entities = image["system-entities"] as? [[String: Any]] else { continue }
            for entity in entities {
                if let mount = entity["mount-point"] as? String { result[mount] = path }
            }
        }
        return result
    }
}
