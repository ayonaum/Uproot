import Foundation
import os

/// How far a running scan has got.
public struct ScanProgress: Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        /// Walking folders and matching names.
        case files
        /// Looking for the bundle identifiers of what was found.
        case identifiers
        /// Reading installer receipts.
        case packages
        /// Checking launch jobs, links, volumes and processes.
        case services
        case finishing
    }

    public var stage: Stage = .files
    public var entriesScanned = 0
    public var hitsFound = 0
    public var currentPath = ""
    /// Names of the latest matches, newest last.
    public var recentNames: [String] = []

    public init() {}
}

public struct ScanResult: Sendable {
    public var query: SearchQuery
    public var items: [FoundItem]
    /// Bundle identifiers read from the found programs and searched for as well.
    public var identifiers: [String]
    public var entriesScanned: Int
    public var duration: TimeInterval
    /// Folders the scan was not allowed to read, capped to a sample.
    public var unreadableSample: [String]
    public var unreadableCount: Int
    public var wasCancelled: Bool

    public static func empty(for query: SearchQuery) -> ScanResult {
        ScanResult(query: query, items: [], identifiers: [], entriesScanned: 0, duration: 0,
                   unreadableSample: [], unreadableCount: 0, wasCancelled: false)
    }
}

/// Finds everything on the machine that belongs to a program.
public struct Scanner: Sendable {
    public let environment: ScanEnvironment

    public init(environment: ScanEnvironment = .current) {
        self.environment = environment
    }

    /// Runs a scan off the calling task. Cancelling the task stops the scan and returns what was found so far.
    public func scan(_ query: SearchQuery, progress: (@Sendable (ScanProgress) -> Void)? = nil) async -> ScanResult {
        let run = ScanRun(query: query, environment: environment, progress: progress)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Thread.detachNewThread {
                    continuation.resume(returning: run.execute())
                }
            }
        } onCancel: {
            run.cancel()
        }
    }
}

/// One scan from start to finish.
final class ScanRun: @unchecked Sendable {
    private struct Shared {
        var walker: ParallelWalker?
        var collector: HitCollector?
        var cancelled = false
        var stage = ScanProgress.Stage.files
        var entries = 0
    }

    private let query: SearchQuery
    private let env: ScanEnvironment
    private let progress: (@Sendable (ScanProgress) -> Void)?
    private let shared = OSAllocatedUnfairLock(initialState: Shared())

    init(query: SearchQuery, environment: ScanEnvironment, progress: (@Sendable (ScanProgress) -> Void)?) {
        self.query = query
        self.env = environment
        self.progress = progress
    }

    func cancel() {
        let walker = shared.withLock { state -> ParallelWalker? in
            state.cancelled = true
            return state.walker
        }
        walker?.cancel()
    }

    private var isCancelled: Bool { shared.withLock { $0.cancelled } }

    func execute() -> ScanResult {
        let started = Date()
        let terms = query.termSet()
        guard !terms.products.isEmpty else { return .empty(for: query) }

        let volumes = Volumes.mounted(environment: env)
        let layout = ScanLayout(environment: env, options: query.options,
                                externalVolumes: volumes.map(\.mountPoint))
        let fileSearch = query.target == .files
        let resolver = PlacementResolver(environment: env)
        let collector = HitCollector(terms: terms, layout: layout, placement: resolver, options: query.options,
                                     excludes: query.excludes, listsInsideMatches: fileSearch)
        let walker = ParallelWalker(visit: collector.visit, onUnreadable: collector.noteUnreadable)
        shared.withLock {
            $0.walker = walker
            $0.collector = collector
        }

        let timer = startProgressTimer()
        defer { timer?.cancel() }

        // 1. Names on disk.
        if !isCancelled { walker.run(roots: layout.roots) }
        let entries = walker.snapshot.entriesVisited
        shared.withLock { $0.entries = entries }
        var hits = collector.hits
        var identifiers: [String] = []

        if fileSearch && !isCancelled {
            // Files by name: the walk is the whole search.
            setStage(.finishing)
            var assembler = Assembler(environment: env, resolver: resolver, terms: terms, fileSearch: true)
            assembler.add(hits: hits)
            let unreadable = collector.unreadable
            return ScanResult(query: query, items: assembler.finish(), identifiers: [], entriesScanned: entries,
                              duration: Date().timeIntervalSince(started), unreadableSample: unreadable.sample,
                              unreadableCount: unreadable.count, wasCancelled: false)
        }

        if !isCancelled {
            // 2. Bundle identifiers of the found programs, looked up where macOS files things by identifier.
            setStage(.identifiers)
            identifiers = BundleInspector.identifiers(of: Array(hits.values))
            let identifierTerms = identifiers.compactMap { SearchTerm($0, role: .identifier) }
            if !identifierTerms.isEmpty {
                lookUp(identifierTerms, collector: collector, into: &hits)
            }

            // 3. Installer receipts and what their packages put on disk.
            setStage(.packages)
            let allTerms = TermSet(products: terms.products + identifierTerms, vendors: terms.vendors)
            var assembler = Assembler(environment: env, resolver: resolver, terms: allTerms,
                                      removableAppleIdentifiers: BundleInspector.removableAppleIdentifiers(of: Array(hits.values)))
            let receiptItems = scanReceipts(terms: allTerms, resolver: resolver, collector: collector, hits: &hits)

            // 4. Items for everything matched by name, then what hangs off them.
            setStage(.services)
            assembler.add(hits: hits)
            assembler.add(items: receiptItems)
            addLaunchJobs(to: &assembler, identifiers: identifiers, collector: collector)
            addLinks(to: &assembler, collector: collector)
            addVolumes(volumes, terms: terms, to: &assembler, collector: collector)
            if env.systemRoot.isEmpty { addProcesses(terms: terms, to: &assembler) }

            setStage(.finishing)
            let items = assembler.finish()
            reportProgress()
            let unreadable = collector.unreadable
            return ScanResult(query: query, items: items, identifiers: identifiers, entriesScanned: entries,
                              duration: Date().timeIntervalSince(started), unreadableSample: unreadable.sample,
                              unreadableCount: unreadable.count, wasCancelled: false)
        }

        // Cancelled: hand back what the walk had found, judged by name only.
        var assembler = Assembler(environment: env, resolver: resolver, terms: terms, fileSearch: fileSearch)
        assembler.add(hits: hits)
        let unreadable = collector.unreadable
        return ScanResult(query: query, items: assembler.finish(), identifiers: [], entriesScanned: entries,
                          duration: Date().timeIntervalSince(started), unreadableSample: unreadable.sample,
                          unreadableCount: unreadable.count, wasCancelled: true)
    }

    // MARK: Progress

    private func setStage(_ stage: ScanProgress.Stage) {
        shared.withLock { $0.stage = stage }
        reportProgress()
    }

    private func reportProgress() {
        guard let progress else { return }
        let state = shared.withLock { $0 }
        var value = ScanProgress()
        value.stage = state.stage
        if let walker = state.walker {
            let snapshot = walker.snapshot
            value.entriesScanned = snapshot.entriesVisited
            value.currentPath = state.stage == .files ? snapshot.currentPath : ""
        }
        if let collector = state.collector {
            value.hitsFound = collector.hitCount
            value.recentNames = collector.recentNames
        }
        progress(value)
    }

    private func startProgressTimer() -> DispatchSourceTimer? {
        guard progress != nil else { return nil }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + .milliseconds(80), repeating: .milliseconds(120))
        timer.setEventHandler { [weak self] in self?.reportProgress() }
        timer.resume()
        return timer
    }

    // MARK: Identifiers

    /// Reads the folders macOS keys by bundle identifier and keeps entries named after a found bundle.
    private func lookUp(_ identifierTerms: [SearchTerm], collector: HitCollector, into hits: inout [String: RawHit]) {
        let terms = TermSet(products: identifierTerms, vendors: [])
        var folders: [String] = []
        for library in [env.home + "/Library", env.sys("/Library")] {
            for name in ["Preferences", "Preferences/ByHost", "Caches", "Application Support", "Saved Application State",
                         "HTTPStorages", "WebKit", "Containers", "Group Containers", "Application Scripts", "Cookies",
                         "Logs", "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools",
                         "Application Support/CrashReporter"] {
                folders.append(library + "/" + name)
            }
        }
        folders += [env.userTemp, env.userCache].compactMap { $0 }

        let fileManager = FileManager.default
        for folder in folders {
            guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { continue }
            for name in names {
                guard let match = terms.evaluate(NameFolding.fold(name)).product, match.kind >= .word else { continue }
                let path = folder + "/" + name
                if collector.isExcluded(path) { continue }
                if var existing = hits[path] {
                    // An identifier match says more than a name match; let it lead.
                    if existing.evaluation.product.map({ $0.kind < match.kind || !$0.kind.isStrong }) ?? true {
                        existing.evaluation.product = match
                        hits[path] = existing
                    }
                    continue
                }
                var info = stat()
                guard lstat(path, &info) == 0 else { continue }
                let type = Self.entryType(info)
                hits[path] = RawHit(path: path, type: type,
                                    isBundle: type == .directory && Bundles.isBundle(name: name),
                                    evaluation: NameEvaluation(product: match, vendor: nil))
            }
        }
    }

    // MARK: Receipts

    private func scanReceipts(terms: TermSet, resolver: PlacementResolver, collector: HitCollector,
                              hits: inout [String: RawHit]) -> [FoundItem] {
        let receipts = Receipts(environment: env, placement: resolver)
        let slot = Placement(category: .receipts, locationTitle: env.display(env.sys("/private/var/db/receipts")),
                             depth: 1, owner: nil, installSlot: true, nearInstallSlot: false, personal: false)
        var items: [FoundItem] = []

        for packageID in receipts.packageIDs() {
            let evaluation = terms.evaluate(NameFolding.fold(packageID))
            guard !evaluation.isEmpty else { continue }
            var verdict = RelevanceScorer.score(.init(product: evaluation.product, vendor: evaluation.vendor, placement: slot))
            // Apple's own packages are shown, never preselected, and their payload is the system's.
            if verdict.relevance == .high, Assembler.carriesAppleIdentifier(packageID) {
                verdict.relevance = .medium
                verdict.reasons.append(.partOfMacOS)
            }
            let record = receipts.record(for: packageID)
            if collector.isExcluded(record.plistPath) { continue }
            items.append(FoundItem(id: "receipt:" + packageID, kind: .receipt, path: record.plistPath, name: packageID,
                                   category: .receipts, relevance: verdict.relevance, reasons: verdict.reasons,
                                   locationTitle: slot.locationTitle, needsAdmin: true,
                                   detail: .receipt(packageID: packageID, version: record.version, installed: record.installed),
                                   modified: record.installed))

            // Files of a package that clearly belongs to the product are worth showing even when
            // their own names say nothing.
            guard verdict.relevance == .high, !isCancelled else { continue }
            for path in receipts.ownedRoots(payload: receipts.payload(of: record)) {
                if collector.isExcluded(path) || resolver.isProtected(path) { continue }
                if var existing = hits[path] {
                    existing.extraReasons.append(.installedByPackage(id: packageID))
                    hits[path] = existing
                    continue
                }
                var info = stat()
                guard lstat(path, &info) == 0 else { continue }
                let type = Self.entryType(info)
                let name = (path as NSString).lastPathComponent
                hits[path] = RawHit(path: path, type: type, isBundle: type == .directory && Bundles.isBundle(name: name),
                                    evaluation: NameEvaluation(), extraReasons: [.installedByPackage(id: packageID)],
                                    forcedRelevance: .medium)
            }
        }
        return items
    }

    // MARK: Derived items

    /// Launch jobs: mark the ones found by name, and add the ones that start something found.
    private func addLaunchJobs(to assembler: inout Assembler, identifiers: [String], collector: HitCollector) {
        let known = Set(identifiers.map { $0.lowercased() })
        for job in LaunchJobs.all(environment: env) {
            let detail = ItemDetail.launchJob(label: job.label, isSystemDomain: job.isSystemDomain)
            if assembler.setDetail(detail, forPath: job.plistPath) { continue }
            if collector.isExcluded(job.plistPath) { continue }

            var reason: MatchReason?
            if let program = job.programs.first(where: { assembler.trustedItem(containing: $0) != nil }) {
                reason = .launches(path: program)
            } else if let id = job.associatedBundleIDs.first(where: { known.contains($0.lowercased()) }) {
                reason = .bundleIdentifier(id: id)
            }
            guard let reason else { continue }
            assembler.add(hit: RawHit(path: job.plistPath, type: .file, isBundle: false, evaluation: NameEvaluation(),
                                      extraReasons: [reason], forcedRelevance: .high, detail: detail))
        }
    }

    /// Command-line links such as /usr/local/bin/code that point into a found program.
    private func addLinks(to assembler: inout Assembler, collector: HitCollector) {
        let folders = [env.sys("/usr/local/bin"), env.sys("/opt/homebrew/bin"), env.home + "/bin", env.home + "/.local/bin"]
        let fileManager = FileManager.default
        for folder in folders {
            guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { continue }
            for name in names {
                let path = folder + "/" + name
                guard !assembler.contains(path: path), !collector.isExcluded(path),
                      let destination = try? fileManager.destinationOfSymbolicLink(atPath: path) else { continue }
                let target = destination.hasPrefix("/") ? destination : (folder as NSString).appendingPathComponent(destination)
                let resolved = (target as NSString).standardizingPath
                guard let item = assembler.trustedItem(containing: resolved) else { continue }
                assembler.add(hit: RawHit(path: path, type: .symlink, isBundle: false, evaluation: NameEvaluation(),
                                          extraReasons: [.linksTo(path: item.path)], forcedRelevance: .high))
            }
        }
    }

    /// Disk images left mounted after an install.
    private func addVolumes(_ volumes: [MountedVolume], terms: TermSet, to assembler: inout Assembler, collector: HitCollector) {
        guard !volumes.isEmpty else { return }
        var images: [String: String]?
        for volume in volumes where !collector.isExcluded(volume.mountPoint) {
            var reasons: [MatchReason] = []
            var relevance = Relevance.low

            if let match = terms.evaluate(NameFolding.fold(volume.name)).product {
                reasons.append(RelevanceScorer.reason(for: match))
                relevance = match.kind.isStrong || match.term.isDistinctive ? .high : .medium
            }
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: volume.mountPoint)) ?? []
            if let inner = contents.first(where: { terms.evaluate(NameFolding.fold($0)).product?.kind == .exact }) {
                reasons.append(.volumeContains(name: inner))
                relevance = .high
            }
            guard !reasons.isEmpty else { continue }
            // Internal partitions are not installer leftovers; never offer to eject them by default.
            if volume.isInternal { relevance = min(relevance, .medium) }

            if images == nil, env.systemRoot.isEmpty { images = Volumes.diskImages() }
            assembler.add(item: FoundItem(id: "volume:" + volume.mountPoint, kind: .volume, path: volume.mountPoint,
                                          name: volume.name, category: .volumes, relevance: relevance, reasons: reasons,
                                          locationTitle: env.display(env.sys("/Volumes")),
                                          detail: .volume(imagePath: images?[volume.mountPoint])))
        }
    }

    /// Processes running out of something found, or named exactly like the product.
    private func addProcesses(terms: TermSet, to assembler: inout Assembler) {
        // What macOS itself runs is not a leftover, whatever it is called: stopping "WindowServer"
        // or "loginwindow" would end the session.
        for process in Processes.all() where !Processes.isPartOfMacOS(process) {
            var reason: MatchReason?
            if let item = assembler.trustedItem(containing: process.executablePath) {
                reason = .runsFrom(path: item.path)
            } else if let match = terms.evaluate(NameFolding.fold(process.name)).product, match.kind == .exact {
                reason = RelevanceScorer.reason(for: match)
            }
            guard let reason else { continue }
            assembler.add(item: FoundItem(id: "pid:\(process.pid)", kind: .process, path: process.executablePath,
                                          name: process.name, category: .processes, relevance: .high, reasons: [reason],
                                          locationTitle: env.display((process.executablePath as NSString).deletingLastPathComponent),
                                          needsAdmin: process.uid != env.uid,
                                          detail: .process(pid: process.pid, ownedByCurrentUser: process.uid == env.uid)))
        }
    }

    static func entryType(_ info: stat) -> EntryType {
        switch info.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .file
        case S_IFLNK: .symlink
        default: .other
        }
    }
}
