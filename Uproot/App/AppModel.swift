import SwiftUI
import UprootCore

/// One line of the result list as drawn: the list is flat, sections are rows like any other.
enum DisplayRow: Identifiable, Equatable {
    case header(ResultSection)
    case item(ResultRow)
    /// The line that separates likely matches from doubtful ones.
    case doubtfulDivider(count: Int)

    var id: String {
        switch self {
        case .header(let section): "header:" + section.id
        case .item(let row): row.id
        case .doubtfulDivider: "doubtful-divider"
        }
    }
}

/// A removal from the moment the user asks for it until they close the summary.
@MainActor @Observable
final class RemovalSession: Identifiable {
    enum Stage: Equatable {
        case confirming
        case running
        case finished
    }

    /// What a fresh scan found after the removal.
    enum Verification: Equatable {
        case checking
        /// `sure`: items that clearly belong to the product; `toReview`: items left for the user to judge.
        case done(sure: Int, toReview: Int)
    }

    let id = UUID()
    private(set) var items: [FoundItem]
    var mode: RemovalMode
    var stage = Stage.confirming
    var progress: RemovalProgress?
    var report: RemovalReport?
    var verification: Verification?

    init(items: [FoundItem], mode: RemovalMode) {
        self.items = items
        self.mode = mode
    }

    /// Fills in sizes that had not been measured when the user asked for the removal.
    func measureMissingSizes() async {
        let unmeasured = items.filter { $0.isOnDisk && $0.size == nil }
        guard !unmeasured.isEmpty else { return }
        let sizes = await DiskUsage.sizes(of: unmeasured)
        for index in items.indices {
            if let size = sizes[items[index].id] { items[index].size = size }
        }
    }

    var totalSize: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }
    var adminCount: Int { items.filter(\.needsAdmin).count }
    func count(of kind: ItemKind) -> Int { items.filter { $0.kind == kind }.count }
}

/// Everything the window shows and does.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case welcome
        case scanning
        case results
    }

    // MARK: Query

    /// A program with everything it left behind, or plain files by name.
    var target = SearchTarget.program
    var products: [String] = []
    var vendors: [String] = []
    var excludes: [String] = []
    /// Text typed into a field but not yet turned into a token.
    var productDraft = ""
    var vendorDraft = ""
    var excludeDraft = ""
    var options = ScanOptions()
    /// A short message under the query fields, such as why a search did not start.
    var notice: String?

    // MARK: Results

    private(set) var phase = Phase.welcome
    private(set) var progress = ScanProgress()
    private(set) var result: ScanResult?
    private(set) var board = ResultBoard()
    private(set) var mainSections: [ResultSection] = []
    private(set) var doubtfulSections: [ResultSection] = []
    var grouping: Grouping {
        didSet {
            UserDefaults.standard.set(grouping.rawValue, forKey: "grouping")
            rebuildSections()
        }
    }
    var filter = "" {
        didSet { rebuildSections() }
    }
    var collapsedSections: Set<String> = []
    /// Doubtful sections start collapsed; these are the ones the user opened.
    var expandedDoubtfulSections: Set<String> = []
    var showsDoubtful = false
    /// Rows selected in the list, as opposed to rows checked for removal.
    var highlighted: Set<String> = []

    // MARK: Removal, access, history

    var removalMode: RemovalMode {
        didSet { UserDefaults.standard.set(removalMode.rawValue, forKey: "removalMode") }
    }
    var removal: RemovalSession?
    private(set) var hasFullDiskAccess = true
    private(set) var recentQueries: [SearchQuery] = []
    private(set) var history: [HistoryEntry] = []
    var showsHistory = false
    var showsOptions = false

    let environment: ScanEnvironment
    /// Running against a fixture tree instead of the real disk; see `LaunchOptions`.
    let isFixture: Bool
    private let store: HistoryStore
    private let launch: LaunchOptions
    private var scanTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var scanGeneration = 0

    init(launch: LaunchOptions = LaunchOptions()) {
        self.launch = launch
        // `Launcher` refuses to start with a fixture folder that fails the check, so the real
        // disk is only ever reached here when no fixture was asked for.
        if let root = launch.fixtureRoot, launch.fixtureProblem == nil {
            environment = ScanEnvironment(systemRoot: root, home: root + "/Users/tester")
            store = HistoryStore(folder: URL(fileURLWithPath: root + "/.uproot"))
            isFixture = true
        } else {
            environment = .current
            store = HistoryStore()
            isFixture = false
        }
        Texts.environment = environment
        grouping = Grouping(rawValue: UserDefaults.standard.string(forKey: "grouping") ?? "") ?? .category
        removalMode = RemovalMode(rawValue: UserDefaults.standard.string(forKey: "removalMode") ?? "") ?? .trash
        recentQueries = store.recentQueries()
        history = store.entries()
        refreshAccess()

        target = launch.target
        products = launch.products
        vendors = launch.vendors
        if launch.startScan { startScan() }
        if launch.show == "history" { showsHistory = true }
        if launch.show == "options" { showsOptions = true }
    }

    // MARK: Query

    var query: SearchQuery {
        SearchQuery(target: target, products: products, vendors: vendors, excludes: excludes, options: options)
    }

    var isScanning: Bool { phase == .scanning }

    /// Turns whatever is still being typed into tokens.
    func commitDrafts() {
        Self.commit(&productDraft, into: &products)
        Self.commit(&vendorDraft, into: &vendors)
        Self.commit(&excludeDraft, into: &excludes)
    }

    /// Splits typed text at commas and adds each new part to `tokens`.
    static func commit(_ draft: inout String, into tokens: inout [String]) {
        for part in draft.split(whereSeparator: { ",;\n".contains($0) }) {
            let token = part.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty, !tokens.contains(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) else { continue }
            tokens.append(token)
        }
        draft = ""
    }

    func use(_ query: SearchQuery) {
        target = query.target
        products = query.products
        vendors = query.vendors
        excludes = query.excludes
        options = query.options
        productDraft = ""
        vendorDraft = ""
        excludeDraft = ""
        startScan()
    }

    func clearRecentQueries() {
        store.clearRecentQueries()
        recentQueries = []
    }

    // MARK: Scanning

    func startScan() {
        // A removal works from the list on screen and ends with a search of its own.
        // A second search underneath it would leave the two fighting over the result.
        guard removal == nil else { return }
        commitDrafts()
        let query = query
        guard query.hasSearchableTerms else {
            notice = target == .files ? "Введите имя файла или его часть — не короче двух символов."
                                      : "Введите название программы или компании — не короче двух символов."
            return
        }
        let rejected = query.rejectedTerms
        notice = rejected.isEmpty ? nil : "Слишком короткие названия пропущены: \(rejected.joined(separator: ", "))"
        store.noteSearch(query)
        recentQueries = store.recentQueries()

        scanTask?.cancel()
        sizeTask?.cancel()
        scanGeneration += 1
        let generation = scanGeneration
        phase = .scanning
        progress = ScanProgress()
        scanTask = Task {
            let result = await scan(query, generation: generation)
            guard generation == scanGeneration else { return }
            apply(result)
            phase = .results
            if let filter = launch.filter { self.filter = filter }
            if launch.show == "doubtful" {
                showsDoubtful = true
                expandedDoubtfulSections = Set(doubtfulSections.map(\.id))
            }
            if launch.show == "confirm" { requestRemoval() }
            if launch.removeAfterScan, isFixture {
                requestRemoval()
                performRemoval()
            }
        }
    }

    /// Stops the scan; what was found so far is shown.
    func stopScan() {
        scanTask?.cancel()
    }

    private func scan(_ query: SearchQuery, generation: Int) async -> ScanResult {
        await Scanner(environment: environment).scan(query) { [weak self] progress in
            Task { @MainActor in
                guard let self, self.scanGeneration == generation else { return }
                self.progress = progress
            }
        }
    }

    private func apply(_ result: ScanResult) {
        self.result = result
        board = ResultBoard(items: result.items)
        collapsedSections = []
        expandedDoubtfulSections = []
        showsDoubtful = false
        highlighted = []
        filter = ""
        rebuildSections()
        measureSizes()
    }

    /// Sizes take longer than the scan; fill them in afterwards, surest items first.
    private func measureSizes() {
        sizeTask?.cancel()
        let items = board.items.filter(\.isOnDisk).sorted { $0.relevance > $1.relevance }
        // Each chunk redraws the whole list, so a long list gets bigger chunks, not more redraws.
        let chunkSize = max(40, items.count / 50)
        sizeTask = Task {
            var start = 0
            while start < items.count {
                let chunk = Array(items[start..<min(start + chunkSize, items.count)])
                start += chunk.count
                let sizes = await DiskUsage.sizes(of: chunk)
                guard !Task.isCancelled else { return }
                board.applySizes(sizes)
                rebuildSections()
            }
        }
    }

    // MARK: Result list

    private func rebuildSections() {
        let sections = board.sections(grouping: grouping, filter: filter)
        mainSections = sections.main
        doubtfulSections = sections.doubtful
    }

    var displayRows: [DisplayRow] {
        var rows: [DisplayRow] = []
        for section in mainSections {
            rows.append(.header(section))
            if !collapsedSections.contains(section.id) { rows += section.rows.map(DisplayRow.item) }
        }
        let doubtfulCount = doubtfulSections.reduce(0) { $0 + $1.rows.count }
        if doubtfulCount > 0 {
            rows.append(.doubtfulDivider(count: doubtfulCount))
            if showsDoubtful {
                for section in doubtfulSections {
                    rows.append(.header(section))
                    if expandedDoubtfulSections.contains(section.id) { rows += section.rows.map(DisplayRow.item) }
                }
            }
        }
        return rows
    }

    var likelyCount: Int { mainSections.reduce(0) { $0 + $1.rows.count } }
    var likelySize: Int64 { mainSections.reduce(0) { $0 + $1.size } }

    func isCollapsed(_ section: ResultSection) -> Bool {
        if case .doubtful = section.kind { return !expandedDoubtfulSections.contains(section.id) }
        return collapsedSections.contains(section.id)
    }

    func toggleCollapsed(_ section: ResultSection) {
        if case .doubtful = section.kind {
            expandedDoubtfulSections.formSymmetricDifference([section.id])
        } else {
            collapsedSections.formSymmetricDifference([section.id])
        }
    }

    func toggle(_ id: String) {
        board.toggle(id)
    }

    func setChecked(_ ids: Set<String>, _ on: Bool) {
        board.setChecked(ids, on)
    }

    /// Checks a whole section, or unchecks it when everything in it is already checked.
    func toggle(_ section: ResultSection) {
        let topLevel = section.rows.filter { $0.depth == 0 }.map(\.id)
        board.setChecked(topLevel, board.state(of: topLevel) != .on)
    }

    /// Space bar: flips the check marks of the selected rows together.
    func toggleHighlighted() {
        let ids = highlighted.filter { board.item($0) != nil }
        guard !ids.isEmpty else { return }
        board.setChecked(ids, board.state(of: ids) != .on)
    }

    func items(_ ids: Set<String>) -> [FoundItem] {
        board.items.filter { ids.contains($0.id) }
    }

    func uncheckAll() {
        board.uncheckAll()
    }

    /// Leaves an item out of this search's results without touching it on disk.
    func hide(_ ids: Set<String>) {
        board.hide(ids: ids)
        highlighted.subtract(ids)
        rebuildSections()
    }

    // MARK: Removal

    func requestRemoval() {
        // While a search runs, the list is the previous search's and about to be replaced.
        let selection = board.selection
        guard phase == .results, !selection.isEmpty, removal == nil else { return }
        removal = RemovalSession(items: selection, mode: removalMode)
    }

    func performRemoval() {
        guard let session = removal, session.stage == .confirming, let query = result?.query else { return }
        session.stage = .running
        sizeTask?.cancel()
        // A fixture never gets a way to become root.
        let remover = Remover(environment: environment, elevator: isFixture ? nil : ElevationHelper.Elevator())
        Task {
            await session.measureMissingSizes()
            let report = await remover.remove(session.items, mode: session.mode) { progress in
                Task { @MainActor in session.progress = progress }
            }
            session.report = report
            session.stage = .finished
            store.append(HistoryEntry(query: query, report: report))
            history = store.entries()

            // What went is not a result any more. The second look below takes a while, and the
            // list must not go on offering, checked, the things that were just removed.
            let gone = Set(report.succeeded.map(\.id))
            board.remove(ids: gone)
            highlighted.subtract(gone)
            rebuildSections()

            // Look again, the way one reruns `find` after `rm`, and show what is still there.
            session.verification = .checking
            scanGeneration += 1
            let generation = scanGeneration
            let fresh = await scan(query, generation: generation)
            guard generation == scanGeneration else { return }
            apply(fresh)
            phase = .results
            session.verification = .done(sure: fresh.items.filter { $0.relevance == .high }.count,
                                         toReview: fresh.items.filter { $0.relevance == .medium }.count)
        }
    }

    func closeRemoval() {
        removal = nil
    }

    // MARK: History and access

    func clearHistory() {
        store.clearEntries()
        history = []
    }

    /// Moves a trashed item back to where it was. Returns a message when that fails.
    func putBack(_ outcome: RemovalOutcome, in entry: HistoryEntry) -> String? {
        do {
            try TrashRestore.putBack(outcome)
        } catch {
            return error.localizedDescription
        }
        var entry = entry
        entry.report.outcomes.removeAll { $0.id == outcome.id }
        store.replace(entry)
        history = store.entries()
        return nil
    }

    func refreshAccess() {
        hasFullDiskAccess = isFixture || FullDiskAccess.isGranted
    }
}

/// Launch arguments, used for opening the app straight into a search and for testing.
///
///     --name <text>     a program or file name; may be repeated
///     --files           search for files by name instead of for a program
///     --vendor <text>   a company name; may be repeated
///     --scan            start searching at once
///     --fixture <path>  treat <path> as the disk root and <path>/Users/tester as the home folder
///     --show <what>     open "confirm", "history", "options" or "doubtful" once ready
///     --filter <text>   start with the result list filtered
///     --window <WxH>    open the window at this size, in points
///     --remove          with --fixture only: remove what the scan preselects, without asking
struct LaunchOptions {
    var target = SearchTarget.program
    var products: [String] = []
    var vendors: [String] = []
    var startScan = false
    var fixtureRoot: String?
    var show: String?
    var filter: String?
    var windowSize: CGSize?
    var removeAfterScan = false

    init(arguments: [String] = Array(CommandLine.arguments.dropFirst())) {
        var arguments = arguments
        func value() -> String? { arguments.isEmpty ? nil : arguments.removeFirst() }
        while let argument = value() {
            switch argument {
            case "--name": if let name = value() { products.append(name) }
            case "--vendor": if let name = value() { vendors.append(name) }
            case "--files": target = .files
            case "--scan": startScan = true
            case "--fixture":
                // No value at all still means "a fixture was asked for", so that it fails the check.
                let path = value() ?? ""
                // The real path: "/tmp/x" and "/private/tmp/x" must not look like two places.
                fixtureRoot = realpath(path, nil).map { resolved in
                    defer { free(resolved) }
                    return String(cString: resolved)
                } ?? path
            case "--show": show = value()
            case "--filter": filter = value()
            case "--window":
                let parts = (value() ?? "").split(separator: "x").compactMap { Double($0) }
                if parts.count == 2, parts.allSatisfy({ (200...10_000).contains($0) }) {
                    windowSize = CGSize(width: parts[0], height: parts[1])
                }
            case "--remove": removeAfterScan = true
            default: break
            }
        }
    }

    /// Why the `--fixture` folder cannot be used, or nil when it can or none was given.
    ///
    /// A fixture run may remove things without asking. An empty variable in a script, a typo or
    /// "/" must therefore stop the launch, never quietly turn it into a run on the real disk.
    var fixtureProblem: String? {
        guard let root = fixtureRoot else { return nil }
        guard root.hasPrefix("/"), root != "/" else {
            return "--fixture needs the full path of a fixture folder, not \"\(root)\""
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root + "/Users/tester", isDirectory: &isDirectory), isDirectory.boolValue else {
            return "\(root) is not a fixture: it has no Users/tester folder (build one with Tools/make-fixture.sh)"
        }
        return nil
    }
}
