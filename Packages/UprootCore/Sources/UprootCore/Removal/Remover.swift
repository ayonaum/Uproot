import Foundation

/// Removes found items: files go to the Trash or are deleted, processes are stopped,
/// volumes ejected and installer receipts forgotten.
///
/// Everything the current user may do is done directly. What is left over is gathered
/// into one script and run with administrator rights, so there is a single password prompt.
public struct Remover: Sendable {
    private let environment: ScanEnvironment
    private let elevator: (any PrivilegeElevator)?
    /// How long to wait before checking that removed items have stayed gone.
    private let settleDelay: Duration

    public init(environment: ScanEnvironment = .current, elevator: (any PrivilegeElevator)? = nil,
                settleDelay: Duration = .milliseconds(1200)) {
        self.environment = environment
        self.elevator = elevator
        self.settleDelay = settleDelay
    }

    /// Working on a fixture tree: nothing outside it may be changed, so system tools stay out of it.
    private var isFixture: Bool { !environment.systemRoot.isEmpty }

    public func remove(_ items: [FoundItem], mode: RemovalMode,
                       progress: (@Sendable (RemovalProgress) -> Void)? = nil) async -> RemovalReport {
        // Stop what is running first, so nothing rewrites its files while they are being removed.
        let ordered = items.sorted { Self.order($0.kind) < Self.order($1.kind) }
        var outcomes: [String: RemovalOutcome] = [:]
        var steps: [PrivilegedScript.Step] = []
        var keyed: [Int: FoundItem] = [:]
        var removedAudioUnit = false
        let placement = PlacementResolver(environment: environment)

        func record(_ item: FoundItem, _ status: RemovalOutcome.Status, admin: Bool = false) {
            outcomes[item.id] = RemovalOutcome(id: item.id, name: item.name, path: item.path, kind: item.kind,
                                               status: status, usedAdmin: admin, size: item.size)
        }
        func postpone(_ item: FoundItem, _ make: (Int) -> PrivilegedScript.Step) {
            let key = keyed.count
            keyed[key] = item
            steps.append(make(key))
        }

        for (index, item) in ordered.enumerated() {
            progress?(RemovalProgress(phase: .removing, completed: index, total: ordered.count, currentName: item.name))
            switch item.kind {
            case .process:
                guard case .process(let pid, _) = item.detail else { continue }
                // The scan may be minutes old and process numbers are reused: stop the process
                // only while it is still the program that was found.
                guard Processes.executablePath(of: pid) == item.path else {
                    record(item, .alreadyGone)
                    continue
                }
                switch Self.terminate(pid) {
                case .stopped: record(item, .terminated)
                case .notPermitted: postpone(item) { .stopProcess(key: $0, pid: pid) }
                }

            case .volume:
                record(item, isFixture ? Self.discardFixtureFiles([item.path], as: .ejected) : Self.eject(item.path))

            case .receipt:
                guard case .receipt(let packageID, _, _) = item.detail else { continue }
                if isFixture {
                    // A fixture's receipts are plain files; the real package database is never touched.
                    let bom = (item.path as NSString).deletingPathExtension + ".bom"
                    record(item, Self.discardFixtureFiles([item.path, bom], as: .forgotten))
                } else {
                    postpone(item) { .forgetReceipt(key: $0, packageID: packageID) }
                }

            case .file, .folder, .bundle, .symlink:
                // Whatever the list says, the folders macOS is built on stay where they are, and
                // so does everything outside the machine this remover was given and everything
                // the system itself has marked as not to be removed.
                guard !placement.isProtected(item.path), !Self.isGuardedBySystem(item.path) else {
                    record(item, .failed(.protectedLocation))
                    continue
                }
                if case .launchJob(let label, let isSystemDomain) = item.detail, !isFixture {
                    if isSystemDomain {
                        steps.append(.bootout(label: label))
                    } else {
                        Shell.run("/bin/launchctl", ["bootout", "gui/\(environment.uid)/\(label)"])
                    }
                }
                switch Self.removeDirectly(item.path, mode: mode, uid: environment.uid) {
                case .done(let status):
                    record(item, status)
                    if item.path.hasSuffix(".component") { removedAudioUnit = true }
                case .failed(let failure):
                    record(item, .failed(failure))
                case .needsAdmin:
                    if item.path.hasSuffix(".component") { removedAudioUnit = true }
                    switch mode {
                    case .permanent:
                        postpone(item) { .delete(key: $0, path: item.path) }
                    case .trash:
                        let trash = Self.trashFolder(for: item.path, home: environment.home)
                        postpone(item) { .trash(key: $0, path: item.path, trashFolder: trash) }
                    }
                }
            }
        }

        if !keyed.isEmpty {
            if removedAudioUnit && !isFixture { steps.append(.refreshAudioUnits) }
            progress?(RemovalProgress(phase: .waitingForAdministrator, completed: ordered.count - keyed.count,
                                      total: ordered.count, currentName: ""))
            let results = await runPrivileged(steps)
            for (key, item) in keyed {
                switch results {
                case .cancelled:
                    record(item, .cancelled)
                case .unavailable:
                    record(item, .failed(.adminUnavailable), admin: true)
                case .failed(let message):
                    record(item, .failed(.message(message)), admin: true)
                case .completed(let byKey):
                    record(item, Self.status(for: item, result: byKey[key], mode: mode), admin: true)
                }
            }
        }
        if removedAudioUnit && !isFixture {
            // The user's own registrar; launchd starts a fresh one that rescans the plug-in folders.
            Shell.run("/usr/bin/killall", ["-9", "AudioComponentRegistrar"])
        }

        // A program still loaded elsewhere, such as a plug-in inside a running host, may write
        // its files straight back. Catch that here instead of leaving the user to find out later.
        progress?(RemovalProgress(phase: .verifying, completed: ordered.count, total: ordered.count, currentName: ""))
        let removedFromDisk = outcomes.values.filter {
            switch $0.status {
            case .trashed, .deleted: true
            default: false
            }
        }
        if !removedFromDisk.isEmpty {
            try? await Task.sleep(for: settleDelay)
            for outcome in removedFromDisk where Self.exists(outcome.path) {
                outcomes[outcome.id]?.status = .reappeared
            }
        }

        return RemovalReport(mode: mode, date: Date(), outcomes: ordered.compactMap { outcomes[$0.id] })
    }

    // MARK: Direct removal

    private enum DirectResult {
        case done(RemovalOutcome.Status)
        case needsAdmin
        case failed(RemovalFailure)
    }

    private static func removeDirectly(_ path: String, mode: RemovalMode, uid: uid_t) -> DirectResult {
        guard exists(path) else { return .done(.alreadyGone) }
        var attempt = attemptRemoval(path, mode: mode)
        if case .needsAdmin = attempt, isOwned(path, by: uid) {
            // Locked or write-protected files of the user's own can be opened up without a password.
            Shell.run("/usr/bin/chflags", ["-R", "nouchg", path], timeout: 900)
            Shell.run("/bin/chmod", ["-R", "u+rwX", path], timeout: 900)
            attempt = attemptRemoval(path, mode: mode)
        }
        return attempt
    }

    private static func attemptRemoval(_ path: String, mode: RemovalMode) -> DirectResult {
        let url = URL(fileURLWithPath: path)
        do {
            switch mode {
            case .trash:
                var location: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &location)
                return .done(.trashed(location: location?.path))
            case .permanent:
                try FileManager.default.removeItem(at: url)
                return .done(.deleted)
            }
        } catch {
            if !exists(path) { return .done(mode == .trash ? .trashed(location: nil) : .deleted) }
            if isPermissionError(error as NSError) { return .needsAdmin }
            return .failed(.message(error.localizedDescription))
        }
    }

    private static func isPermissionError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError, NSFileWriteVolumeReadOnlyError].contains(error.code) {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, [Int(EPERM), Int(EACCES)].contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isPermissionError(underlying) }
        return false
    }

    private static func isOwned(_ path: String, by uid: uid_t) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_uid == uid
    }

    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    private static func isGuardedBySystem(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && Assembler.isGuardedBySystem(info)
    }

    /// The Trash that serves the volume `path` is on.
    private static func trashFolder(for path: String, home: String) -> String {
        let url = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                               appropriateFor: URL(fileURLWithPath: path), create: false)
        return url?.path ?? home + "/.Trash"
    }

    // MARK: Processes and volumes

    private enum TerminationResult { case stopped, notPermitted }

    private static func terminate(_ pid: pid_t) -> TerminationResult {
        if kill(pid, SIGTERM) != 0 {
            return errno == EPERM ? .notPermitted : .stopped
        }
        for _ in 0..<30 where Processes.isRunning(pid) {
            usleep(100_000)
        }
        if Processes.isRunning(pid) {
            kill(pid, SIGKILL)
            usleep(300_000)
        }
        return .stopped
    }

    private static func discardFixtureFiles(_ paths: [String], as status: RemovalOutcome.Status) -> RemovalOutcome.Status {
        for path in paths where exists(path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                return .failed(.message(error.localizedDescription))
            }
        }
        return status
    }

    private static func eject(_ mountPoint: String) -> RemovalOutcome.Status {
        guard exists(mountPoint) else { return .alreadyGone }
        guard let output = Shell.run("/usr/sbin/diskutil", ["eject", mountPoint]) else {
            return .failed(.message("diskutil"))
        }
        if output.succeeded || !exists(mountPoint) { return .ejected }
        let text = (output.stderr.isEmpty ? output.stdout : output.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(.message(text))
    }

    // MARK: Privileged work

    private enum PrivilegedResult {
        case completed([Int: PrivilegedScript.StepResult])
        case cancelled
        case unavailable
        case failed(String)
    }

    private func runPrivileged(_ steps: [PrivilegedScript.Step]) async -> PrivilegedResult {
        guard let elevator else { return .unavailable }
        let script = PrivilegedScript(steps: steps, uid: environment.uid, gid: getgid()).render()
        do {
            return .completed(PrivilegedScript.parse(try await elevator.runAsRoot(script: script)))
        } catch ElevationError.cancelled {
            return .cancelled
        } catch ElevationError.failed(let message) {
            return .failed(message)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func status(for item: FoundItem, result: PrivilegedScript.StepResult?, mode: RemovalMode) -> RemovalOutcome.Status {
        switch result {
        case .done(let location):
            switch item.kind {
            case .receipt: return .forgotten
            case .process: return .terminated
            case .volume: return .ejected
            case .file, .folder, .bundle, .symlink:
                return mode == .trash ? .trashed(location: location) : .deleted
            }
        case .failed(let message):
            let denied = message.localizedCaseInsensitiveContains("Operation not permitted")
            return .failed(denied ? .accessDenied : .message(message))
        case nil:
            return .failed(.message(""))
        }
    }

    private static func order(_ kind: ItemKind) -> Int {
        switch kind {
        case .process: 0
        case .volume: 1
        case .file, .folder, .bundle, .symlink: 2
        case .receipt: 3
        }
    }
}
