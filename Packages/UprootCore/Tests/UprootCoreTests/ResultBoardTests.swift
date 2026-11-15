import Testing
@testable import UprootCore

@Suite struct ResultBoardTests {
    private func item(_ id: String, parent: String? = nil, relevance: Relevance = .high, category: ItemCategory = .appData,
                      location: String = "~/Library", owner: String? = nil, size: Int64 = 100,
                      reasons: [MatchReason] = [], unrelated: Int = 0) -> FoundItem {
        FoundItem(id: id, kind: .folder, path: id, name: id, category: category, relevance: relevance, reasons: reasons,
                  locationTitle: location, owner: owner, parentID: parent, unrelatedChildCount: unrelated, size: size)
    }

    /// A vendor folder that holds only found items, a loose file, and a doubtful match.
    private func board() -> ResultBoard {
        ResultBoard(items: [
            item("/vendor", size: 300, reasons: [.holdsOnlyFoundItems]),
            item("/vendor/a", parent: "/vendor", size: 100),
            item("/vendor/b", parent: "/vendor", size: 200),
            item("/prefs.plist", category: .preferences, location: "~/Library/Preferences", size: 5),
            item("/maybe", relevance: .medium, category: .applications, location: "/Applications", size: 50),
            item("/game/terrain", relevance: .low, owner: "SomeGame", size: 1),
        ])
    }

    @Test func sureItemsStartChecked() {
        let board = board()
        #expect(board.checked == ["/vendor", "/prefs.plist"])
        #expect(board.state(of: "/vendor/a") == .on)
        #expect(board.state(of: "/maybe") == .off)
        #expect(board.checkedRowCount == 4)
        // The folder's size already includes what is inside it.
        #expect(board.selectionSize == 305)
        #expect(board.selection.map(\.id) == ["/vendor", "/prefs.plist"])
    }

    @Test func uncheckingANestedItemKeepsItsSiblings() {
        var board = board()
        board.toggle("/vendor/a")
        #expect(board.state(of: "/vendor") == .mixed)
        #expect(board.state(of: "/vendor/a") == .off)
        #expect(board.state(of: "/vendor/b") == .on)
        #expect(board.selection.map(\.id) == ["/vendor/b", "/prefs.plist"])

        // Checking it again completes the folder, which then goes as a whole.
        board.toggle("/vendor/a")
        #expect(board.checked.contains("/vendor"))
        #expect(!board.checked.contains("/vendor/a"))
    }

    @Test func folderWithOtherContentIsNotCompletedByItsItems() {
        var board = ResultBoard(items: [
            item("/vendor", relevance: .medium, unrelated: 2),
            item("/vendor/a", parent: "/vendor"),
        ])
        #expect(board.checked == ["/vendor/a"])
        #expect(board.state(of: "/vendor") == .mixed)
        // Checking the folder itself is a separate, deliberate choice.
        board.toggle("/vendor")
        #expect(board.selection.map(\.id) == ["/vendor"])
        board.toggle("/vendor")
        #expect(board.selection.isEmpty)
    }

    @Test func sectionStateAndBulkChecking() {
        var board = board()
        let ids = ["/prefs.plist", "/maybe"]
        #expect(board.state(of: ids) == .mixed)
        board.setChecked(ids, true)
        #expect(board.state(of: ids) == .on)
        board.setChecked(ids, false)
        #expect(board.state(of: ids) == .off)
    }

    @Test func sectionsByCategoryKeepDoubtfulApart() {
        let sections = board().sections(grouping: .category)
        #expect(sections.main.map(\.id) == ["category:applications", "category:appData", "category:preferences"])
        #expect(sections.main[1].rows.map(\.depth) == [0, 1, 1])
        #expect(sections.main[1].size == 300)
        #expect(sections.doubtful.map(\.id) == ["doubtful:SomeGame"])
    }

    @Test func sectionsByLocation() {
        let sections = board().sections(grouping: .location)
        #expect(Set(sections.main.map(\.id)) == ["location:/Applications", "location:~/Library", "location:~/Library/Preferences"])
    }

    @Test func filterKeepsParentsOfMatches() {
        let sections = board().sections(grouping: .category, filter: "vendor/b")
        #expect(sections.main.count == 1)
        #expect(sections.main[0].rows.map(\.id) == ["/vendor", "/vendor/b"])
        #expect(sections.doubtful.isEmpty)
    }

    @Test func hidingANestedItemKeepsItOutOfTheRemoval() {
        var board = board()
        #expect(board.selection.map(\.id) == ["/vendor", "/prefs.plist"])
        board.hide(ids: ["/vendor/a"])
        // The checked folder would have taken the hidden item along; only its other content stays checked.
        #expect(board.selection.map(\.id) == ["/vendor/b", "/prefs.plist"])
        #expect(board.item("/vendor")?.unrelatedChildCount == 1)
        // Checking what is left does not bring the folder back by itself.
        board.setChecked("/vendor/b", false)
        board.setChecked("/vendor/b", true)
        #expect(board.selection.map(\.id) == ["/vendor/b", "/prefs.plist"])
    }

    @Test func removingAnItemTakesNestedOnesAlong() {
        var board = board()
        board.remove(ids: ["/vendor"])
        #expect(board.items.map(\.id) == ["/prefs.plist", "/maybe", "/game/terrain"])
        #expect(board.checked == ["/prefs.plist"])
    }
}
