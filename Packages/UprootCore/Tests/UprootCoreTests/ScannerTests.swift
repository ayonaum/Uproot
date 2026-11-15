import Foundation
import Testing
@testable import UprootCore

/// End-to-end scans over fixture trees that mirror the two clean-ups in the terminal log
/// this app was written to replace.
@Suite struct ScannerTests {

    // MARK: Terrain, a plug-in with a sibling product and a vendor folder

    private func terrainFixture() throws -> Fixture {
        let f = try Fixture()
        try f.bundle(f.sys("/Applications/Terrain.app"), identifier: "com.wavescrate.terrain")
        try f.bundle(f.sys("/Applications/Terrain FX.app"), identifier: "com.wavescrate.terrainfx")
        try f.bundle(f.sys("/Library/Audio/Plug-Ins/VST3/Terrain.vst3"), identifier: "com.wavescrate.terrain.vst3")
        try f.bundle(f.sys("/Library/Audio/Plug-Ins/VST3/Terrain FX.vst3"))
        try f.bundle(f.sys("/Library/Audio/Plug-Ins/Components/Terrain.component"))
        try f.file(f.sys("/Library/Application Support/Waves Crate/Terrain/Content/a.bin"))
        try f.file(f.sys("/Library/Application Support/Waves Crate/Terrain FX/Content/b.bin"))
        try f.file(f.sys("/Library/Logs/Terrain Crack Install.log"))
        try f.file(f.user("Library/WavesCrate/Terrain/Banks/Macshooter/5AM.terrain"))
        try f.file(f.user("Library/WavesCrate/Terrain FX/InstrumentSettings.json"))
        try f.file(f.user("Library/Caches/Terrain/cache.db"))
        try f.file(f.user("Library/Preferences/com.wavescrate.terrain.plist"))
        try f.file(f.user("Library/Saved Application State/com.wavescrate.terrain.savedState/data.data"))
        try f.file(f.user("Documents/Image-Line/FL Studio/Presets/Plugin database/Generators/Terrain.fst"))
        try f.file(f.user("Documents/Image-Line/FL Studio/Presets/Plugin database/Installed/Effects/New/Terrain FX.nfo"))
        try f.file(f.user("Downloads/Telegram Desktop/Wavescrate - Terrain v1.0.0 [Mac]/Install.pkg"))
        // Things that only look related.
        try f.file(f.user("Library/Noizefield/Terrain/preset.fxp"))
        try f.file(f.user("Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/data/base/graphics/terrain/a.png"))
        try f.file(f.user("Library/Application Support/Steam/steamapps/common/SomeGame/data/terrain/tile.png"))
        try f.file(f.sys("/Applications/FL Studio 2025.app/Contents/Resources/FL/Plugins/Fruity/Effects/ZGameEditor Visualizer/Effects/Terrain/Terrain Lattice.zgeproj"))
        try f.file(f.user("Documents/school/terrain analysis.docx"))
        return f
    }

    @Test func terrainWithVendorSelectsWhatTheUserDeletedByHand() async throws {
        let f = try terrainFixture()
        let result = await f.scan(["Terrain", "Terrain FX"], vendors: ["Waves Crate"])

        let expectedHigh = [
            f.sys("/Applications/Terrain.app"),
            f.sys("/Applications/Terrain FX.app"),
            f.sys("/Library/Audio/Plug-Ins/VST3/Terrain.vst3"),
            f.sys("/Library/Audio/Plug-Ins/VST3/Terrain FX.vst3"),
            f.sys("/Library/Audio/Plug-Ins/Components/Terrain.component"),
            f.sys("/Library/Application Support/Waves Crate"),
            f.sys("/Library/Application Support/Waves Crate/Terrain"),
            f.sys("/Library/Logs/Terrain Crack Install.log"),
            f.user("Library/WavesCrate"),
            f.user("Library/WavesCrate/Terrain"),
            f.user("Library/WavesCrate/Terrain FX"),
            f.user("Library/Caches/Terrain"),
            f.user("Library/Preferences/com.wavescrate.terrain.plist"),
            f.user("Library/Saved Application State/com.wavescrate.terrain.savedState"),
            f.user("Documents/Image-Line/FL Studio/Presets/Plugin database/Generators/Terrain.fst"),
            f.user("Documents/Image-Line/FL Studio/Presets/Plugin database/Installed/Effects/New/Terrain FX.nfo"),
        ]
        for path in expectedHigh {
            #expect(result.relevance(path) == .high, "\(f.environment.display(path))")
        }

        // The vendor folder holds nothing but the product, so it can go as a whole, with its contents nested.
        let vendorFolder = try #require(result.item(f.user("Library/WavesCrate")))
        #expect(vendorFolder.reasons.contains(.holdsOnlyFoundItems))
        #expect(result.item(f.user("Library/WavesCrate/Terrain"))?.parentID == vendorFolder.id)

        // Another vendor's preset folder and a download are shown, never preselected.
        #expect(result.relevance(f.user("Library/Noizefield/Terrain")) == .medium)
        #expect(result.relevance(f.user("Downloads/Telegram Desktop/Wavescrate - Terrain v1.0.0 [Mac]")) == .medium)

        // A game's terrain folder and a school paper are doubtful at best.
        #expect(result.relevance(f.user("Library/Application Support/Steam/steamapps/common/SomeGame/data/terrain")) == .low)
        #expect(result.relevance(f.user("Documents/school/terrain analysis.docx")) == .low)

        // Other programs' bundles are not opened at all.
        #expect(!result.items.contains { $0.path.contains("factorio.app") || $0.path.contains("FL Studio 2025.app") })
        // Contents of a found folder are implied by the folder.
        #expect(!result.items.contains { $0.path.hasSuffix("5AM.terrain") })
        #expect(result.identifiers.contains("com.wavescrate.terrain"))
    }

    @Test func siblingProductIsNotPreselectedUnlessAskedFor() async throws {
        let f = try terrainFixture()
        let result = await f.scan(["Terrain"])

        #expect(result.relevance(f.sys("/Applications/Terrain.app")) == .high)
        // "Terrain FX" is a different program; its identifier says so.
        #expect(result.relevance(f.sys("/Applications/Terrain FX.app")) == .medium)
        #expect(result.relevance(f.sys("/Library/Audio/Plug-Ins/VST3/Terrain FX.vst3")) == .medium)
        // Without the vendor's name, a product folder inside the vendor's folder is still found by name.
        #expect(result.relevance(f.sys("/Library/Application Support/Waves Crate/Terrain")) == .medium)
    }

    @Test func searchingInsideBundlesMarksThoseHitsDoubtful() async throws {
        let f = try terrainFixture()
        let result = await f.scan(["Terrain"], options: ScanOptions(searchInsideBundles: true))
        let inside = try #require(result.items.first { $0.path.contains("factorio.app") })
        #expect(inside.relevance == .low)
        #expect(inside.reasons.contains(.insideOtherBundle(name: "factorio.app")))
    }

    @Test func excludedWordsDropResults() async throws {
        let f = try terrainFixture()
        let result = await f.scan(["Terrain"], excludes: ["noizefield", "steam"])
        #expect(!result.items.contains { $0.path.contains("Noizefield") || $0.path.contains("Steam") })
        #expect(result.relevance(f.sys("/Applications/Terrain.app")) == .high)
    }

    // MARK: Safe Exam Browser, a Windows program in a CrossOver bottle

    private func examBrowserFixture() throws -> Fixture {
        let f = try Fixture()
        let bottle = "Library/Application Support/CrossOver/Bottles/Steam"
        try f.file(f.user(bottle + "/drive_c/Program Files/SafeExamBrowser/Application/SafeExamBrowser.Core.dll"))
        try f.file(f.user(bottle + "/drive_c/Program Files/SafeExamBrowser/Application/seb_x64.dll"))
        try f.file(f.user(bottle + "/drive_c/users/crossover/AppData/Local/SafeExamBrowser/Logs/a.log"))
        try f.file(f.user(bottle + "/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Safe Exam Browser.lnk"))
        try f.file(f.user(bottle + "/drive_c/users/crossover/AppData/Local/Temp/Safe_Exam_Browser_2026.log"))
        try f.file(f.user(bottle + "/desktopdata/cxmenu/Shortcuts/CrossOver-363A1668.safeexambrowser"))
        try f.file(f.user("Applications/CrossOver/SafeExamBrowser/Safe Exam Browser.app/Contents/Info.plist"))
        try f.file(f.user("Library/Preferences/org.safeexambrowser.SafeExamBrowser.plist"))
        try f.file(f.user("Downloads/SafeExamBrowser-3.7.1.1.dmg"))
        try f.file(f.user("Downloads/config.seb"))
        try f.bundle(f.sys("/Volumes/SafeExamBrowser-3.7.1.1/Safe Exam Browser.app"))
        // The false positives that had to be filtered out by hand.
        try f.file(f.sys("/Applications/Waves/Data/Presets/CLA Epic/Artists/Sebastian Furrer/preset.xps"))
        try f.file(f.sys("/Library/Arturia/Shared/images/designers/Hugo Sebastian.jpg"))
        try f.file(f.sys("/Library/Arturia/Shared/images/designers/Seb Rochard.jpg"))
        try f.file(f.sys("/Library/Arturia/Samples/Rev SPRING-636/Kicks/TkSEb_SG_IRGibbsLastTank_1908.rev"))
        return f
    }

    @Test func examBrowserInAWindowsBottle() async throws {
        let f = try examBrowserFixture()
        let bottle = "Library/Application Support/CrossOver/Bottles/Steam"
        let result = await f.scan(["SafeExamBrowser", "Safe Exam Browser", "SEB"])

        let expectedHigh = [
            f.user(bottle + "/drive_c/Program Files/SafeExamBrowser"),
            f.user(bottle + "/drive_c/users/crossover/AppData/Local/SafeExamBrowser"),
            f.user(bottle + "/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Safe Exam Browser.lnk"),
            f.user(bottle + "/drive_c/users/crossover/AppData/Local/Temp/Safe_Exam_Browser_2026.log"),
            f.user(bottle + "/desktopdata/cxmenu/Shortcuts/CrossOver-363A1668.safeexambrowser"),
            f.user("Applications/CrossOver/SafeExamBrowser"),
            f.user("Library/Preferences/org.safeexambrowser.SafeExamBrowser.plist"),
        ]
        for path in expectedHigh {
            #expect(result.relevance(path) == .high, "\(f.environment.display(path))")
        }
        #expect(result.item(f.user(bottle + "/drive_c/Program Files/SafeExamBrowser"))?.category == .windows)

        // Downloads are the user's own; shown for review.
        #expect(result.relevance(f.user("Downloads/SafeExamBrowser-3.7.1.1.dmg")) == .medium)
        #expect(result.relevance(f.user("Downloads/config.seb")) == .medium)

        // The mounted installer image is offered for ejecting.
        let volume = try #require(result.items.first { $0.kind == .volume })
        #expect(volume.relevance == .high)
        #expect(volume.path == f.sys("/Volumes/SafeExamBrowser-3.7.1.1"))

        // Nobody called Sebastian is in the main results.
        #expect(!result.items.contains { $0.name.contains("Sebastian") || $0.name.hasPrefix("TkSEb") })
        #expect(result.relevance(f.sys("/Library/Arturia/Shared/images/designers/Seb Rochard.jpg")) == .low)
    }

    // MARK: Things found through something other than their name

    @Test func bundleIdentifierFindsDifferentlyNamedFiles() async throws {
        let f = try Fixture()
        try f.bundle(f.sys("/Applications/Visual Studio Code.app"), identifier: "com.microsoft.VSCode")
        try f.file(f.user("Library/Preferences/com.microsoft.VSCode.plist"))
        try f.file(f.user("Library/Caches/com.microsoft.VSCode.ShipIt/state.json"))
        try f.file(f.user("Library/Preferences/com.microsoft.Word.plist"))

        let result = await f.scan(["Visual Studio Code"])
        #expect(result.identifiers == ["com.microsoft.VSCode"])
        #expect(result.relevance(f.user("Library/Preferences/com.microsoft.VSCode.plist")) == .high)
        #expect(result.relevance(f.user("Library/Caches/com.microsoft.VSCode.ShipIt")) == .high)
        #expect(result.item(f.user("Library/Preferences/com.microsoft.Word.plist")) == nil)
    }

    @Test func launchJobAndCommandLineLinkFollowTheApp() async throws {
        let f = try Fixture()
        let app = try f.bundle(f.sys("/Applications/Gadget.app"), identifier: "dev.example.gadget")
        try f.file(app + "/Contents/Resources/bin/gdt")
        try f.plist(f.sys("/Library/LaunchDaemons/dev.example.helperd.plist"),
                    ["Label": "dev.example.helperd", "ProgramArguments": [app + "/Contents/MacOS/Gadget", "--daemon"]])
        try f.plist(f.sys("/Library/LaunchDaemons/org.other.daemon.plist"),
                    ["Label": "org.other.daemon", "Program": "/usr/libexec/other"])
        try FileManager.default.createSymbolicLink(atPath: f.sys("/usr/local/bin/gdt"),
                                                   withDestinationPath: app + "/Contents/Resources/bin/gdt")

        let result = await f.scan(["Gadget"])
        let job = try #require(result.item(f.sys("/Library/LaunchDaemons/dev.example.helperd.plist")))
        #expect(job.relevance == .high)
        #expect(job.detail == .launchJob(label: "dev.example.helperd", isSystemDomain: true))
        #expect(job.category == .launchItems)
        #expect(result.relevance(f.sys("/usr/local/bin/gdt")) == .high)
        #expect(result.item(f.sys("/Library/LaunchDaemons/org.other.daemon.plist")) == nil)
    }

    @Test func receiptPayloadBringsInFilesWithUnrelatedNames() async throws {
        let f = try Fixture()
        try f.bundle(f.sys("/Applications/zoom.us.app"), identifier: "us.zoom.xos")
        try f.file(f.sys("/Library/Application Support/VideoKit/engine.dylib"))
        try f.file(f.sys("/Library/Application Support/Shared Codecs/other-vendor.dylib"))
        try f.file(f.sys("/Library/Application Support/Shared Codecs/zm-codec.dylib"))
        try f.receipt("us.zoom.pkg.videomeeting", payload: [
            "Applications/zoom.us.app",
            "Library/Application Support/VideoKit/engine.dylib",
            "Library/Application Support/Shared Codecs/zm-codec.dylib",
        ])

        let result = await f.scan(["zoom"])
        let receipt = try #require(result.items.first { $0.kind == .receipt })
        #expect(receipt.relevance == .high)
        #expect(receipt.needsAdmin)

        // The app's name only starts with "zoom", but its identifier and the package agree it is Zoom.
        #expect(result.relevance(f.sys("/Applications/zoom.us.app")) == .high)
        // A folder holding only the package's files is offered whole; a shared folder is not, only the file in it.
        let owned = try #require(result.item(f.sys("/Library/Application Support/VideoKit")))
        #expect(owned.relevance == .medium)
        #expect(owned.reasons.contains(.installedByPackage(id: "us.zoom.pkg.videomeeting")))
        // Everything in it is the package's, so nothing in it is flagged as someone else's.
        #expect(owned.unrelatedChildCount == 0)
        #expect(result.item(f.sys("/Library/Application Support/Shared Codecs")) == nil)
        #expect(result.relevance(f.sys("/Library/Application Support/Shared Codecs/zm-codec.dylib")) == .medium)
        #expect(result.item(f.sys("/Library/Application Support/Shared Codecs/other-vendor.dylib")) == nil)
    }

    /// Packages install through the "/etc", "/var" and "/tmp" links. The link is not their file.
    @Test func receiptPayloadBehindASystemLinkDoesNotOfferTheLink() async throws {
        let f = try Fixture()
        try f.bundle(f.sys("/Applications/Gadget.app"), identifier: "dev.example.gadget")
        try f.file(f.sys("/private/etc/paths.d/Gadget"))
        try FileManager.default.createSymbolicLink(atPath: f.sys("/etc"), withDestinationPath: "private/etc")
        try f.receipt("dev.example.gadget.pkg", payload: ["etc/paths.d/Gadget"])

        let result = await f.scan(["Gadget"])
        #expect(result.item(f.sys("/etc")) == nil)
        #expect(!result.items.contains { $0.path.hasPrefix(f.sys("/etc/")) })
        // The file itself is found once, under its real path, and the package vouches for it.
        let file = try #require(result.item(f.sys("/private/etc/paths.d/Gadget")))
        #expect(file.relevance == .high)
        #expect(file.reasons.contains(.installedByPackage(id: "dev.example.gadget.pkg")))
    }

    /// A folder the scan cannot read is not an empty one.
    @Test func vendorFolderWithAnUnreadablePartIsNotTakenWhole() async throws {
        let f = try Fixture()
        try f.file(f.user("Library/Application Support/Acme Audio/Reverb One/settings.json"))
        try f.file(f.user("Library/Application Support/Acme Audio/Licences/another-product.lic"))
        chmod(f.user("Library/Application Support/Acme Audio/Licences"), 0)
        defer { chmod(f.user("Library/Application Support/Acme Audio/Licences"), 0o755) }

        let result = await f.scan(["Reverb One"], vendors: ["Acme Audio"])
        let folder = try #require(result.item(f.user("Library/Application Support/Acme Audio")))
        #expect(folder.relevance == .medium)
        #expect(!folder.reasons.contains(.holdsOnlyFoundItems))
        #expect(folder.unrelatedChildCount == 1)
        #expect(result.relevance(f.user("Library/Application Support/Acme Audio/Reverb One")) == .high)
    }

    @Test func vendorFolderWithOtherProductsStaysUnchecked() async throws {
        let f = try Fixture()
        try f.file(f.user("Library/Application Support/Acme Audio/Reverb One/settings.json"))
        try f.file(f.user("Library/Application Support/Acme Audio/Delay Two/settings.json"))

        let result = await f.scan(["Reverb One"], vendors: ["Acme Audio"])
        let folder = try #require(result.item(f.user("Library/Application Support/Acme Audio")))
        #expect(folder.relevance == .medium)
        #expect(folder.unrelatedChildCount == 1)
        #expect(result.relevance(f.user("Library/Application Support/Acme Audio/Reverb One")) == .high)
        #expect(result.item(f.user("Library/Application Support/Acme Audio/Delay Two")) == nil)
    }

    // MARK: Plain file search

    @Test func fileSearchListsEveryMatchAndPreselectsNothing() async throws {
        let f = try Fixture()
        try f.file(f.user("Documents/school/Invoice 2026-03.pdf"))
        try f.file(f.user("Documents/Invoices/invoice-old.pdf"))
        try f.file(f.user("Documents/Invoices/notes.txt"))
        try f.file(f.user("Desktop/my_invoice_draft.docx"))
        try f.bundle(f.sys("/Applications/Invoice Maker.app"), identifier: "com.example.invoicemaker")
        try f.file(f.user("Library/Preferences/com.example.invoicemaker.plist"))
        try f.file(f.sys("/Applications/Other.app/Contents/Resources/invoice-template.html"))

        let result = await f.scan(["invoice"], target: .files)

        // Personal documents are answers here, not doubtful leftovers.
        let expected = [
            f.user("Documents/school/Invoice 2026-03.pdf"),
            f.user("Documents/Invoices"),
            f.user("Documents/Invoices/invoice-old.pdf"),
            f.user("Desktop/my_invoice_draft.docx"),
            f.sys("/Applications/Invoice Maker.app"),
            f.user("Library/Preferences/com.example.invoicemaker.plist"),
        ]
        for path in expected {
            #expect(result.relevance(path) == .medium, "\(f.environment.display(path))")
        }
        // A match inside a matching folder is listed under it; a non-matching neighbour is not.
        #expect(result.item(f.user("Documents/Invoices/invoice-old.pdf"))?.parentID == f.user("Documents/Invoices"))
        #expect(result.item(f.user("Documents/Invoices/notes.txt")) == nil)
        // Nothing is checked for the user, and other programs' bundles stay closed.
        #expect(ResultBoard(items: result.items).checked.isEmpty)
        #expect(!result.items.contains { $0.path.contains("Other.app") })
        #expect(result.identifiers.isEmpty)
    }

    @Test func savedSearchesFromBeforeFileSearchStillLoad() throws {
        let old = Data(#"{"products":["Terrain"],"vendors":["Waves Crate"],"excludes":[],"options":{"searchInsideBundles":false,"includeExternalVolumes":false}}"#.utf8)
        let query = try JSONDecoder().decode(SearchQuery.self, from: old)
        #expect(query.target == .program)
        #expect(query.vendors == ["Waves Crate"])
    }

    @Test func emptyQueryFindsNothing() async throws {
        let f = try Fixture()
        let result = await f.scan(["a"])
        #expect(result.items.isEmpty)
    }
}
