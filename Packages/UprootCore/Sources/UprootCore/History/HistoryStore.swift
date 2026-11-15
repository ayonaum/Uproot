import Foundation

/// One finished removal, kept so the user can see later what was taken off the machine.
public struct HistoryEntry: Codable, Identifiable, Sendable {
    public var id: UUID
    public var query: SearchQuery
    public var report: RemovalReport

    public init(id: UUID = UUID(), query: SearchQuery, report: RemovalReport) {
        self.id = id
        self.query = query
        self.report = report
    }
}

/// Keeps the removal journal and the list of recent searches on disk.
public struct HistoryStore: Sendable {
    private let folder: URL
    private var journalURL: URL { folder.appendingPathComponent("history.json") }
    private var recentURL: URL { folder.appendingPathComponent("recent-searches.json") }

    public static let recentLimit = 12
    public static let journalLimit = 200

    public init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Uproot", isDirectory: true)
    }

    /// Past removals, newest first.
    public func entries() -> [HistoryEntry] {
        read(HistoryEntry.self, from: journalURL)
    }

    public func append(_ entry: HistoryEntry) {
        var all = entries()
        all.insert(entry, at: 0)
        write(Array(all.prefix(Self.journalLimit)), to: journalURL)
    }

    public func replace(_ entry: HistoryEntry) {
        var all = entries()
        guard let index = all.firstIndex(where: { $0.id == entry.id }) else { return }
        all[index] = entry
        write(all, to: journalURL)
    }

    public func clearEntries() {
        try? FileManager.default.removeItem(at: journalURL)
    }

    /// Recent searches, newest first.
    public func recentQueries() -> [SearchQuery] {
        read(SearchQuery.self, from: recentURL)
    }

    public func noteSearch(_ query: SearchQuery) {
        var all = recentQueries().filter { $0.products != query.products || $0.vendors != query.vendors }
        all.insert(query, at: 0)
        write(Array(all.prefix(Self.recentLimit)), to: recentURL)
    }

    public func clearRecentQueries() {
        try? FileManager.default.removeItem(at: recentURL)
    }

    /// Reads a list of records. Every caller goes on to write the list back with one record
    /// added, so whatever cannot be read here must not simply count as "nothing there".
    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> [T] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let list = try? decoder.decode(LossyList<T>.self, from: data) { return list.elements }
        // Not a list at all. Set the file aside rather than let the next write replace it.
        let aside = url.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        return []
    }

    /// A list that leaves out the records it cannot decode, such as one written by a newer
    /// build with a status this one does not know, instead of failing as a whole.
    private struct LossyList<Element: Decodable>: Decodable {
        private struct Skipped: Decodable {}
        var elements: [Element] = []

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            while !container.isAtEnd {
                if let element = try? container.decode(Element.self) {
                    elements.append(element)
                } else {
                    // A failed decode leaves the container where it was; step over the record.
                    _ = try container.decode(Skipped.self)
                }
            }
        }
    }

    private func write(_ value: some Encodable, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// Puts back things this app moved to the Trash.
public enum TrashRestore {
    /// True while the trashed copy is still in the Trash and its old place is free.
    public static func canPutBack(_ outcome: RemovalOutcome) -> Bool {
        guard case .trashed(let location?) = outcome.status else { return false }
        return Remover.exists(location) && !Remover.exists(outcome.path)
    }

    public static func putBack(_ outcome: RemovalOutcome) throws {
        guard case .trashed(let location?) = outcome.status else { return }
        let destination = URL(fileURLWithPath: outcome.path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: URL(fileURLWithPath: location), to: destination)
    }
}
