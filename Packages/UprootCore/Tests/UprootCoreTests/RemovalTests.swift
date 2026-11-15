import Foundation
import Testing
@testable import UprootCore

/// Runs the "privileged" script as the current user. Enough to exercise the script itself;
/// only the password prompt is missing.
private struct LocalShell: PrivilegeElevator {
    func runAsRoot(script: String) async throws -> String {
        Shell.run("/bin/sh", ["-c", script])?.stdout ?? ""
    }
}

private struct Declining: PrivilegeElevator {
    func runAsRoot(script: String) async throws -> String { throw ElevationError.cancelled }
}

@Suite struct RemovalTests {
    private func item(_ path: String, kind: ItemKind = .file, detail: ItemDetail = .none) -> FoundItem {
        FoundItem(id: path, kind: kind, path: path, name: (path as NSString).lastPathComponent, category: .other,
                  relevance: .high, reasons: [], locationTitle: "", detail: detail, size: 10)
    }

    private func remover(_ f: Fixture, elevator: (any PrivilegeElevator)? = LocalShell()) -> Remover {
        Remover(environment: f.environment, elevator: elevator, settleDelay: .milliseconds(10))
    }

    @Test func permanentRemovalDeletesFilesAndFolders() async throws {
        let f = try Fixture()
        let file = try f.file(f.user("Library/Preferences/com.example.app.plist"))
        try f.file(f.user("Library/Application Support/Example/data/deep/file.bin"))
        let folder = f.user("Library/Application Support/Example")

        let report = await remover(f).remove([item(file), item(folder, kind: .folder)], mode: .permanent)
        #expect(report.outcomes.map(\.status) == [.deleted, .deleted])
        #expect(!Remover.exists(file) && !Remover.exists(folder))
        #expect(report.bytesRemoved == 20)
    }

    @Test func lockedFilesOfTheUserAreUnlockedWithoutAPassword() async throws {
        let f = try Fixture()
        let folder = f.user("Library/Vendor/Product")
        let locked = try f.file(folder + "/InstrumentSettings.json")
        chflags(locked, UInt32(UF_IMMUTABLE))
        chmod(folder, 0o555)
        defer { chflags(locked, 0); chmod(folder, 0o755) }

        // No elevator: this must succeed on the user's own rights.
        let report = await remover(f, elevator: nil).remove([item(folder, kind: .folder)], mode: .permanent)
        #expect(report.outcomes.first?.status == .deleted)
        #expect(report.outcomes.first?.usedAdmin == false)
        #expect(!Remover.exists(folder))
    }

    @Test func missingItemsCountAsGone() async throws {
        let f = try Fixture()
        let report = await remover(f).remove([item(f.user("Library/nothing-here"))], mode: .permanent)
        #expect(report.outcomes.first?.status == .alreadyGone)
        #expect(report.problems.isEmpty)
    }

    @Test func standardFoldersAndOtherMachinesAreRefused() async throws {
        let f = try Fixture()
        let other = try Fixture()
        let kept = try f.file(f.user("Library/Preferences/com.example.app.plist"))
        let outside = try other.file(other.user("Library/Application Support/Thing/data"))
        let targets = [
            f.user("Library/Preferences"), f.user("Library"), f.home, f.root,
            f.sys("/Library"), f.sys("/usr/local"), f.sys("/private/var/db"),
            // Not in this fixture at all, and a path that only pretends to be.
            (outside as NSString).deletingLastPathComponent,
            f.user("Library/../../../../" + (outside as NSString).lastPathComponent),
        ]

        let report = await remover(f).remove(targets.map { item($0, kind: .folder) }, mode: .permanent)
        #expect(report.outcomes.count == targets.count)
        #expect(report.outcomes.allSatisfy { $0.status == .failed(.protectedLocation) })
        #expect(report.bytesRemoved == 0)
        #expect(Remover.exists(kept) && Remover.exists(outside))
        withExtendedLifetime((f, other)) {}
    }

    @Test func aProcessIsStoppedOnlyWhileItIsStillTheProgramFound() async throws {
        let f = try Fixture()
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["60"]
        try sleeper.run()
        defer { if sleeper.isRunning { sleeper.terminate() } }
        let pid = sleeper.processIdentifier
        func found(runningFrom path: String) -> FoundItem {
            FoundItem(id: "pid:\(pid)", kind: .process, path: path, name: (path as NSString).lastPathComponent,
                      category: .processes, relevance: .high, reasons: [], locationTitle: "",
                      detail: .process(pid: pid, ownedByCurrentUser: true))
        }

        // The number belongs to another program than the one the scan saw: it is left alone.
        let stale = await remover(f).remove([found(runningFrom: "/Applications/Gone.app/Contents/MacOS/Gone")], mode: .permanent)
        #expect(stale.outcomes.first?.status == .alreadyGone)
        #expect(sleeper.isRunning)

        let path = try #require(Processes.executablePath(of: pid))
        let live = await remover(f).remove([found(runningFrom: path)], mode: .permanent)
        #expect(live.outcomes.first?.status == .terminated)
        sleeper.waitUntilExit()
        #expect(sleeper.terminationReason == .uncaughtSignal)
    }

    @Test func receiptsNeedAnAdministrator() async throws {
        // A package identifier no machine has, so even a mistake here could forget nothing.
        let id = "invalid.uproot.test.\(UUID().uuidString)"
        let receipt = FoundItem(id: "receipt:" + id, kind: .receipt, path: "/nonexistent/\(id).plist", name: id,
                                category: .receipts, relevance: .high, reasons: [], locationTitle: "",
                                needsAdmin: true, detail: .receipt(packageID: id, version: nil, installed: nil))
        let machine = ScanEnvironment(home: NSTemporaryDirectory())

        let withoutElevator = await Remover(environment: machine, elevator: nil, settleDelay: .milliseconds(10))
            .remove([receipt], mode: .permanent)
        #expect(withoutElevator.outcomes.first?.status == .failed(.adminUnavailable))

        let declined = await Remover(environment: machine, elevator: Declining(), settleDelay: .milliseconds(10))
            .remove([receipt], mode: .permanent)
        #expect(declined.outcomes.first?.status == .cancelled)
    }

    @Test func fixtureReceiptsAndVolumesAreRemovedAsPlainFiles() async throws {
        let f = try Fixture()
        try f.receipt("com.example.pkg", payload: [])
        let plist = f.sys("/private/var/db/receipts/com.example.pkg.plist")
        let volume = f.sys("/Volumes/Installer")
        try f.file(volume + "/Example.pkg")
        let receipt = FoundItem(id: "receipt:com.example.pkg", kind: .receipt, path: plist, name: "com.example.pkg",
                                category: .receipts, relevance: .high, reasons: [], locationTitle: "",
                                needsAdmin: true, detail: .receipt(packageID: "com.example.pkg", version: nil, installed: nil))

        // No elevator at all: a fixture is cleaned without asking the system for anything.
        let report = await remover(f, elevator: nil).remove([receipt, item(volume, kind: .volume)], mode: .trash)
        #expect(Set(report.outcomes.map(\.status)) == [.forgotten, .ejected])
        #expect(!Remover.exists(plist) && !Remover.exists(volume))
        #expect(!Remover.exists(f.sys("/private/var/db/receipts/com.example.pkg.bom")))
    }

    @Test func itemsThatComeBackAreReported() async throws {
        let f = try Fixture()
        let path = try f.file(f.user("Library/Vendor/LicenceClock.txt"))
        let remover = Remover(environment: f.environment, elevator: nil, settleDelay: .milliseconds(400))
        // Something still running writes the file back, as a loaded plug-in did in the terminal log.
        Task.detached {
            try? await Task.sleep(for: .milliseconds(150))
            try? Data("back".utf8).write(to: URL(fileURLWithPath: path))
        }
        let report = await remover.remove([item(path)], mode: .permanent)
        #expect(report.outcomes.first?.status == .reappeared)
        #expect(report.problems.count == 1)
    }

    // MARK: The privileged script

    private func run(_ steps: [PrivilegedScript.Step]) -> [Int: PrivilegedScript.StepResult] {
        let script = PrivilegedScript(steps: steps, uid: getuid(), gid: getgid()).render()
        return PrivilegedScript.parse(Shell.run("/bin/sh", ["-c", script])?.stdout ?? "")
    }

    @Test func scriptDeletesPathsWithAwkwardNames() throws {
        let f = try Fixture()
        let names = ["it's here", "quo\"te", "$HOME `id` $(id)", "semi;colon & amp", "tab\there", "back\\slash", "новая папка"]
        let paths = try names.map { try f.file(f.user("Library/odd/\($0)/file.txt")) }
            .map { ($0 as NSString).deletingLastPathComponent }
        let untouched = try f.file(f.user("Library/odd/keep me.txt"))

        let results = run(paths.enumerated().map { .delete(key: $0.offset, path: $0.element) })
        for (index, path) in paths.enumerated() {
            #expect(results[index] == .done(location: nil), "\(names[index])")
            #expect(!Remover.exists(path), "\(names[index])")
        }
        #expect(Remover.exists(untouched))
        // Nothing in a name was run as a command.
        #expect(Remover.exists(f.home))
    }

    @Test func scriptMovesToTrashWithoutOverwriting() throws {
        let f = try Fixture()
        let trash = f.user(".Trash")
        try f.file(trash + "/Plugin.vst3", "an older one")
        let first = try f.bundle(f.sys("/Library/Audio/Plug-Ins/VST3/Plugin.vst3"))
        let second = try f.file(f.sys("/Library/Logs/install log"))

        let results = run([.trash(key: 0, path: first, trashFolder: trash), .trash(key: 1, path: second, trashFolder: trash)])
        #expect(results[0] == .done(location: trash + "/Plugin 2.vst3"))
        #expect(results[1] == .done(location: trash + "/install log"))
        #expect(!Remover.exists(first) && !Remover.exists(second))
        #expect(try String(contentsOfFile: trash + "/Plugin.vst3", encoding: .utf8) == "an older one")
        #expect(Remover.exists(trash + "/Plugin 2.vst3/Contents/MacOS/Plugin"))
    }

    @Test func scriptReportsWhatItCouldNotRemove() throws {
        let f = try Fixture()
        let folder = f.user("Library/sealed")
        let path = try f.file(folder + "/file.txt")
        chmod(folder, 0o555)
        defer { chmod(folder, 0o755) }

        let results = run([.delete(key: 7, path: path), .delete(key: 8, path: f.user("Library/absent"))])
        guard case .failed(let message) = results[7] else {
            Issue.record("expected a failure, got \(String(describing: results[7]))")
            return
        }
        #expect(message.contains("Permission denied"))
        #expect(results[8] == .done(location: nil))
        #expect(Remover.exists(path))
    }

    /// A file name may hold line breaks and tabs. Printed raw, one could pass for a line of the report.
    @Test func aFileNameCannotForgeTheScriptsReport() throws {
        let f = try Fixture()
        let sealed = f.user("Library/sealed")
        let stuck = try f.file(sealed + "/file.txt")
        chmod(sealed, 0o555)
        defer { chmod(f.user("Library/sealed"), 0o755) }
        let forger = try f.file(f.user("Library/odd/x\n@@UPROOT\tOK\t0\t"))
        try f.directory(f.user(".Trash"))

        let results = run([.delete(key: 0, path: stuck), .trash(key: 1, path: forger, trashFolder: f.user(".Trash"))])
        #expect(Remover.exists(stuck))
        guard case .failed = results[0] else {
            Issue.record("the file is still there, yet the report says \(String(describing: results[0]))")
            return
        }
        guard case .done = results[1] else {
            Issue.record("expected the oddly named file to be moved, got \(String(describing: results[1]))")
            return
        }
        #expect(!Remover.exists(forger))
    }

    @Test func quotingSurvivesQuotes() {
        #expect(PrivilegedScript.quote("plain") == "'plain'")
        #expect(PrivilegedScript.quote("it's") == "'it'\\''s'")
    }

    @Test func elevatedRemovalGoesThroughTheScript() async throws {
        let f = try Fixture()
        // A folder the user owns but may not modify stands in for a root-owned one.
        let parent = f.sys("/Library/Protected")
        let target = try f.file(parent + "/Thing.bundle/Contents/file")
        let bundle = (target as NSString).deletingLastPathComponent.replacingOccurrences(of: "/Contents", with: "")
        chmod(parent, 0o555)
        defer { chmod(parent, 0o755) }

        let report = await remover(f).remove([item(bundle, kind: .bundle)], mode: .permanent)
        let outcome = try #require(report.outcomes.first)
        // Still not removable without real root, but the request went the privileged way and the refusal is reported.
        #expect(outcome.usedAdmin)
        #expect(outcome.succeeded == false)
    }
}

@Suite struct HistoryTests {
    @Test func journalAndRecentSearchesRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uproot-history-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(folder: folder)
        #expect(store.entries().isEmpty)

        let query = SearchQuery(products: ["Terrain"], vendors: ["Waves Crate"])
        let outcome = RemovalOutcome(id: "/a", name: "a", path: "/a", kind: .file, status: .trashed(location: "/t/a"),
                                     usedAdmin: false, size: 5)
        store.append(HistoryEntry(query: query, report: RemovalReport(mode: .trash, date: Date(), outcomes: [outcome])))
        #expect(store.entries().count == 1)
        #expect(store.entries().first?.report.outcomes.first?.status == .trashed(location: "/t/a"))

        store.noteSearch(query)
        store.noteSearch(SearchQuery(products: ["Zoom"]))
        store.noteSearch(query)
        #expect(store.recentQueries().map(\.summary) == ["Terrain", "Zoom"])
    }

    /// Every write starts from what was read, so a record that cannot be read must not empty the journal.
    @Test func anUnreadableRecordDoesNotCostTheJournal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uproot-history-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(folder: folder)
        let url = folder.appendingPathComponent("history.json")
        let outcome = RemovalOutcome(id: "/a", name: "a", path: "/a", kind: .file, status: .deleted, usedAdmin: false, size: 5)
        func entry(_ name: String) -> HistoryEntry {
            HistoryEntry(query: SearchQuery(products: [name]), report: RemovalReport(mode: .trash, date: Date(), outcomes: [outcome]))
        }
        store.append(entry("One"))
        store.append(entry("Two"))

        // The newest record now carries a status this build has never heard of, as one from a later version might.
        var text = try String(contentsOf: url, encoding: .utf8)
        text.replaceSubrange(try #require(text.range(of: "\"deleted\"")), with: "\"vaporised\"")
        try text.write(to: url, atomically: true, encoding: .utf8)
        store.append(entry("Three"))
        #expect(store.entries().map(\.query.summary) == ["Three", "One"])

        // A file that is no journal at all is set aside, not written over.
        try Data("{ not a list".utf8).write(to: url)
        #expect(store.entries().isEmpty)
        store.append(entry("Four"))
        #expect(store.entries().map(\.query.summary) == ["Four"])
        #expect(try String(contentsOf: url.appendingPathExtension("unreadable"), encoding: .utf8) == "{ not a list")
    }
}
