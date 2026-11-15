import Foundation
import Testing
@testable import UprootCore

/// Searches whose words are also names macOS uses itself. A tool that deletes what it finds
/// must not answer "Preferences" with the Preferences folder, or "Notes" with the user's notes.
@Suite struct SafetyTests {
    private func checked(_ result: ScanResult, in f: Fixture) -> [String] {
        ResultBoard(items: result.items).checked.map(f.environment.display).sorted()
    }

    @Test func standardFoldersAreNobodysLeftovers() async throws {
        let f = try Fixture()
        try f.bundle(f.sys("/Library/Audio/Plug-Ins/VST3/Audio Damage.vst3"))
        try f.file(f.user("Library/Preferences/com.example.app.plist"))
        // Looking inside Preferences must not trade the folder for the settings every app shares.
        try f.file(f.user("Library/Preferences/.GlobalPreferences.plist"))
        try f.file(f.user("Library/Keychains/login.keychain-db"))
        try f.file(f.user(".config/gh/hosts.yml"))
        try f.file(f.user("Documents/notes.txt"))
        try f.file(f.user("Library/Mail/V10/MailData/Envelope Index"))
        try f.file(f.sys("/Library/Application Support/Avid/Audio/Plug-Ins/Other.aaxplugin/Contents/x"))
        // A standard folder moved to another disk leaves a link in its place; the link is as standard.
        try FileManager.default.createSymbolicLink(atPath: f.user("Library/Caches"), withDestinationPath: f.sys("/Users/Shared"))

        let result = await f.scan(["Audio", "VST3", "Plug-Ins", "Preferences", "Keychains", "config", "Documents",
                                   "Library", "Mail", "Avid", "Caches"])
        let folders = [
            f.sys("/Library/Audio"), f.sys("/Library/Audio/Plug-Ins"), f.sys("/Library/Audio/Plug-Ins/VST3"),
            f.sys("/Library/Application Support/Avid"), f.sys("/Library/Application Support/Avid/Audio"),
            f.sys("/Library/Application Support/Avid/Audio/Plug-Ins"),
            f.user("Library"), f.user("Library/Preferences"), f.user("Library/Keychains"), f.user("Library/Mail"),
            f.user("Library/Caches"), f.user(".config"), f.user("Documents"),
        ]
        for folder in folders {
            #expect(result.item(folder) == nil, "\(f.environment.display(folder))")
        }
        // The folders are still looked into: what is inside is found by its own name.
        #expect(result.relevance(f.sys("/Library/Audio/Plug-Ins/VST3/Audio Damage.vst3")) == .medium)
        #expect(checked(result, in: f).isEmpty)
    }

    @Test func fileSearchListsAStandardFolderAndTheRemoverRefusesIt() async throws {
        let f = try Fixture()
        let kept = try f.file(f.user("Library/Preferences/com.example.app.plist"))

        let result = await f.scan(["Preferences"], target: .files)
        let folder = try #require(result.item(f.user("Library/Preferences")))
        let report = await Remover(environment: f.environment, settleDelay: .milliseconds(10)).remove([folder], mode: .permanent)
        #expect(report.outcomes.map(\.status) == [.failed(.protectedLocation)])
        #expect(Remover.exists(kept))
    }

    @Test func dataOfBuiltInAppsIsShownButNeverPreselected() async throws {
        let f = try Fixture()
        let paths = [
            f.user("Library/Group Containers/group.com.apple.notes"),
            f.user("Library/Containers/com.apple.Notes"),
            f.user("Library/Preferences/com.apple.Notes.plist"),
        ]
        try f.file(paths[0] + "/NoteStore.sqlite")
        try f.file(paths[1] + "/Data/Library/x")
        try f.file(paths[2])
        // Somebody else's program of the same name is still recognised.
        try f.file(f.user("Library/Preferences/com.example.notes.plist"))

        let result = await f.scan(["Notes"])
        for path in paths {
            let item = try #require(result.item(path), "\(f.environment.display(path))")
            #expect(item.relevance == .medium)
            #expect(item.reasons.contains(.partOfMacOS))
        }
        #expect(checked(result, in: f) == ["~/Library/Preferences/com.example.notes.plist"])
    }

    /// Xcode, Keynote and the like are Apple's too, but they are uninstalled like anyone else's.
    @Test func anAppleAppThatCanBeUninstalledKeepsItsLeftovers() async throws {
        let f = try Fixture()
        try f.bundle(f.sys("/Applications/Xcode.app"), identifier: "com.apple.dt.Xcode")
        try f.file(f.user("Library/Preferences/com.apple.dt.Xcode.plist"))
        try f.file(f.user("Library/Caches/com.apple.dt.Xcode/cache.db"))

        let result = await f.scan(["Xcode"])
        #expect(checked(result, in: f) == ["/Applications/Xcode.app", "~/Library/Caches/com.apple.dt.Xcode",
                                           "~/Library/Preferences/com.apple.dt.Xcode.plist"])
    }

    @Test func whatTheSystemForbidsRemovingIsRecognised() {
        var info = stat()
        #expect(!Assembler.isGuardedBySystem(info))
        info.st_flags = UInt32(UF_IMMUTABLE)   // the user's own lock is not the system's
        #expect(!Assembler.isGuardedBySystem(info))
        info.st_flags = UInt32(SF_NOUNLINK)
        #expect(Assembler.isGuardedBySystem(info))
        info.st_flags = UInt32(SF_RESTRICTED) | UInt32(UF_HIDDEN)
        #expect(Assembler.isGuardedBySystem(info))
    }

    @Test func systemFilesUnderEtcAndVarAreNotPreselectedByName() async throws {
        let f = try Fixture()
        try f.file(f.sys("/private/etc/hosts"))
        try f.file(f.sys("/private/etc/pam.d/sudo"))
        try f.file(f.sys("/private/var/vm/swapfile0"))
        try f.file(f.sys("/private/var/db/sudo/ts/x"))
        try f.file(f.sys("/private/etc/paths.d/Gadget"))

        let result = await f.scan(["hosts", "sudo", "vm", "Gadget"])
        // The one place here that exists for other software's files still counts.
        #expect(checked(result, in: f) == ["/private/etc/paths.d/Gadget"])
        #expect(result.item(f.sys("/private/var/vm")) == nil)
    }

    @Test func whatMacOSRunsIsNotALeftover() {
        func process(_ path: String, pid: pid_t = 500) -> RunningProcess {
            RunningProcess(pid: pid, executablePath: path, uid: 0)
        }
        #expect(Processes.isPartOfMacOS(process("/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer")))
        #expect(Processes.isPartOfMacOS(process("/usr/sbin/cfprefsd")))
        #expect(Processes.isPartOfMacOS(process("/sbin/launchd", pid: 1)))
        #expect(!Processes.isPartOfMacOS(process("/usr/local/bin/gadgetd")))
        #expect(!Processes.isPartOfMacOS(process("/Applications/Gadget.app/Contents/MacOS/Gadget")))
        #expect(!Processes.isPartOfMacOS(process("/Library/Application Support/Gadget/gadgetd")))
    }
}
