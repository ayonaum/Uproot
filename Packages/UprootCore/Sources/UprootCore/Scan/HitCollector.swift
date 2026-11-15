import Foundation
import os

/// A name on disk that matched the search, before it is judged and turned into an item.
struct RawHit: Sendable {
    var path: String
    var type: EntryType
    var isBundle: Bool
    var evaluation: NameEvaluation
    var underVendor = false
    var foreignBundle: String?
    /// Reasons that do not come from the name, such as "installed by package".
    var extraReasons: [MatchReason] = []
    /// Set for hits found through something other than their name.
    var forcedRelevance: Relevance?
    var detail: ItemDetail = .none

    var hasProductMatch: Bool { evaluation.product != nil }
}

/// Receives every directory entry of the walk, keeps the ones that match and
/// tells the walker which directories to open.
final class HitCollector: @unchecked Sendable {
    private struct State {
        var hits: [String: RawHit] = [:]
        var recentNames: [String] = []
        var unreadable: [String] = []
        var unreadableCount = 0
    }

    private let terms: TermSet
    private let layout: ScanLayout
    private let options: ScanOptions
    private let excludes: [String]
    /// A file search lists matches inside matching folders too, as `find` would.
    private let listsInsideMatches: Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(terms: TermSet, layout: ScanLayout, options: ScanOptions, excludes: [String], listsInsideMatches: Bool = false) {
        self.terms = terms
        self.layout = layout
        self.options = options
        self.listsInsideMatches = listsInsideMatches
        self.excludes = excludes.map { $0.lowercased() }.filter { !$0.isEmpty }
    }

    var hits: [String: RawHit] { state.withLock { $0.hits } }
    var hitCount: Int { state.withLock { $0.hits.count } }
    var recentNames: [String] { state.withLock { $0.recentNames } }
    var unreadable: (sample: [String], count: Int) { state.withLock { ($0.unreadable, $0.unreadableCount) } }

    func noteUnreadable(path: String, code: Int32) {
        guard code == EACCES || code == EPERM else { return }
        state.withLock {
            $0.unreadableCount += 1
            if $0.unreadable.count < 200 { $0.unreadable.append(path) }
        }
    }

    func isExcluded(_ path: String) -> Bool {
        guard !excludes.isEmpty else { return false }
        let lowered = path.lowercased()
        return excludes.contains { lowered.contains($0) }
    }

    /// The walker's callback. Runs on many threads at once.
    func visit(parent: WalkDirectory, name bytes: UnsafeBufferPointer<UInt8>, type: EntryType,
               scratch: inout [UInt8]) -> WalkDirectory? {
        // Most names cannot match; settle those without building a String.
        let isASCII = NameFolding.squashASCII(bytes, into: &scratch)
        if isASCII && !terms.mayMatch(scratch) {
            return type == .directory ? descend(parent: parent, name: String(decoding: bytes, as: UTF8.self)) : nil
        }

        let name = String(decoding: bytes, as: UTF8.self)
        if name == ".DS_Store" || name == ".localized" { return nil }
        let evaluation = terms.evaluate(NameFolding.fold(name))
        if evaluation.isEmpty {
            return type == .directory ? descend(parent: parent, name: name) : nil
        }

        let path = Self.join(parent.path, name)
        if isExcluded(path) { return nil }
        if type == .directory && layout.skippedNames.contains(name) { return nil }

        let isBundle = type == .directory && Bundles.isBundle(name: name)
        // Inside a vendor folder the vendor's name on every file adds nothing; the folder stands for them.
        if evaluation.product == nil && parent.underVendor {
            return type == .directory && !isBundle ? descend(parent: parent, name: name) : nil
        }
        let hit = RawHit(path: path, type: type, isBundle: isBundle, evaluation: evaluation,
                         underVendor: parent.underVendor, foreignBundle: parent.foreignBundle)
        state.withLock {
            $0.hits[path] = hit
            $0.recentNames.append(name)
            if $0.recentNames.count > 6 { $0.recentNames.removeFirst() }
        }

        // A product match stands for everything inside it. A vendor folder is opened to
        // find the product within, since the vendor may have other products installed.
        guard evaluation.product == nil || listsInsideMatches, type == .directory, !isBundle else { return nil }
        guard var child = descend(parent: parent, name: name) else { return nil }
        if let vendor = evaluation.vendor, vendor.kind.isStrong || vendor.term.isDistinctive {
            child.underVendor = true
        }
        return child
    }

    private func descend(parent: WalkDirectory, name: String) -> WalkDirectory? {
        guard parent.remainingDepth > 0, !layout.skippedNames.contains(name) else { return nil }
        let path = Self.join(parent.path, name)
        guard !layout.skippedPaths.contains(path) else { return nil }

        let depthLeft = parent.remainingDepth == Int.max ? Int.max : parent.remainingDepth - 1
        var child = WalkDirectory(path: path, remainingDepth: depthLeft,
                                  underVendor: parent.underVendor, foreignBundle: parent.foreignBundle)
        if layout.shallowPaths.contains(path) { child.remainingDepth = 0 }
        if Bundles.isBundle(name: name) {
            guard options.searchInsideBundles else { return nil }
            if child.foreignBundle == nil { child.foreignBundle = name }
        }
        return child
    }

    static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }
}
