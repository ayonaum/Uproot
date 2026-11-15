import Testing
@testable import UprootCore

@Suite struct MatchingTests {
    private func kind(_ term: String, _ name: String, role: SearchTerm.Role = .product) -> MatchKind? {
        guard let term = SearchTerm(term, role: role) else { return nil }
        return TermMatcher.match(term, in: NameFolding.fold(name))?.kind
    }

    @Test func foldingDropsSeparatorsAndCase() {
        #expect(String(decoding: NameFolding.fold("Safe_Exam Browser-3.7.dmg").bytes, as: UTF8.self) == "safeexambrowser37dmg")
        #expect(NameFolding.fold("Safe Exam Browser.app").stemLength == "safeexambrowser".count)
    }

    @Test func everySpellingOfANameMatchesExactly() {
        for name in ["SafeExamBrowser", "Safe Exam Browser.app", "safe-exam-browser", "Safe_Exam_Browser.lnk", "Safe+Exam+Browser.lnk"] {
            #expect(kind("Safe Exam Browser", name) == .exact, "\(name)")
        }
    }

    @Test func versionSuffixStillCountsAsTheProduct() {
        #expect(kind("SafeExamBrowser", "SafeExamBrowser-3.7.1.1.dmg") == .exact)
        #expect(kind("FL Studio", "FL Studio 2025.app") == .exact)
        #expect(kind("Terrain", "Terrain v1.0.0 [Mac]") == .exact)
    }

    @Test func siblingProductIsOnlyAPrefix() {
        #expect(kind("Terrain", "Terrain FX.app") == .prefix)
        #expect(kind("Terrain", "TerrainFX.vst3") == .prefix)
        #expect(kind("Terrain", "Terrain Crack Install.log") == .prefix)
    }

    @Test func reverseDNSComponentsAreIdentifierMatches() {
        #expect(kind("Terrain", "com.wavescrate.terrain.plist") == .identifier)
        #expect(kind("SafeExamBrowser", "org.safeexambrowser.SafeExamBrowser.plist") == .identifier)
        #expect(kind("zoom", "us.zoom.xos.plist") == .identifier)
        #expect(kind("com.tw93.MoleApp", "com.tw93.MoleApp.systemhelper.plist", role: .identifier) == .prefix)
        #expect(kind("com.wavescrate.terrain", "com.wavescrate.terrain.savedState", role: .identifier) == .exact)
    }

    @Test func wordsAndPartialsAreWeaker() {
        #expect(kind("Terrain", "Abstract Terrain Objects Circle.zla") == .word)
        #expect(kind("Terrain", "UnityEngine.TerrainModule.dll") == .word)
        #expect(kind("Terrain", "com.wavescrate.terrainfx.au") == .partial)
        #expect(kind("Terrain", "subterraineous") == .partial)
    }

    /// The false positives from the terminal log: a search for "SEB" kept finding people called Sebastian.
    @Test func shortTermsMatchWholeWordsOnly() {
        #expect(kind("SEB", "Sebastian Furrer") == nil)
        #expect(kind("SEB", "Hugo Sebastian.jpg") == nil)
        #expect(kind("SEB", "TkSEb_SG_IRGibbsLastTank_1908_Cut_PP.rev") == nil)
        #expect(kind("SEB", "Belle & Sebastien") == nil)
        #expect(kind("SEB", "SEBConfigTool.exe") == .prefix)
        // "x64" is a platform tag, so this is SEB itself.
        #expect(kind("SEB", "seb_x64.dll") == .exact)
        #expect(kind("zoom", "zoomus.plist") == nil)
        #expect(kind("zoom", "ZoomOpener.app") == .prefix)
    }

    /// Plug-in names are full of these: a short name with a digit or a separator of its own.
    @Test func shortTermsKeepTheirOwnWordBreaks() {
        #expect(kind("Pro-Q", "Pro-Q 3.vst3") == .exact)
        #expect(kind("RX 10", "RX 10 Audio Editor.app") == .prefix)
        #expect(kind("DX7", "DX7 Presets") == .prefix)
        #expect(kind("C1", "Waves C1 comp.vst3") == .word)
        #expect(kind("VST3", "Serum.vst3") == .word)
        // Still one whole word of the name, nothing longer.
        #expect(kind("S1", "S1000 Samples") == nil)
        #expect(kind("DX7", "PDX70.bin") == nil)
    }

    @Test func extensionMatchIsFlagged() throws {
        let term = try #require(SearchTerm("SEB", role: .product))
        let match = try #require(TermMatcher.match(term, in: NameFolding.fold("config.seb")))
        #expect(match.kind == .word)
        #expect(match.isExtension)
    }

    @Test func nonLatinNamesFoldToo() {
        #expect(kind("Программа", "ПРОГРАММА установка.pkg") == .prefix)
        #expect(kind("Séb", "seb.app") == .exact)
    }

    @Test func termsNeedTwoCharacters() {
        #expect(SearchTerm("a", role: .product) == nil)
        #expect(SearchTerm(" - ", role: .product) == nil)
        #expect(SearchTerm("ab", role: .product) != nil)
    }

    @Test func distinctiveness() throws {
        #expect(try #require(SearchTerm("SafeExamBrowser", role: .product)).isDistinctive)
        #expect(try #require(SearchTerm("Terrain FX", role: .product)).isDistinctive)
        #expect(try #require(SearchTerm("Terrain", role: .product)).isDistinctive == false)
        #expect(try #require(SearchTerm("zoom", role: .product)).isDistinctive == false)
    }

    @Test func vendorOnlyQueryIsTreatedAsProduct() {
        let terms = SearchQuery(products: [], vendors: ["Waves Crate"]).termSet()
        #expect(terms.products.count == 1)
        #expect(terms.vendors.isEmpty)
    }

    @Test func prefilterAgreesWithFullFold() {
        let terms = SearchQuery(products: ["Safe Exam Browser"]).termSet()
        var scratch: [UInt8] = []
        let name = Array("Safe_Exam_Browser_2026.log".utf8)
        let isASCII = name.withUnsafeBufferPointer { NameFolding.squashASCII($0, into: &scratch) }
        #expect(isASCII)
        #expect(terms.mayMatch(scratch))
        #expect(scratch == NameFolding.fold("Safe_Exam_Browser_2026.log").bytes)
    }
}
