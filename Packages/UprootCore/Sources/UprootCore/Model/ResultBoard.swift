import Foundation

public enum CheckState: Sendable, Equatable {
    case off
    /// Some of what lies inside is checked.
    case mixed
    case on
}

/// How the result list is divided into sections.
public enum Grouping: String, Sendable, CaseIterable, Codable {
    /// By kind of thing: applications, plug-ins, preferences.
    case category
    /// By the folder things were found in.
    case location
}

public struct ResultRow: Identifiable, Sendable, Equatable {
    public var item: FoundItem
    /// Nesting level; 0 for items that are not inside another found item.
    public var depth: Int
    public var id: String { item.id }
}

public struct ResultSection: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Hashable {
        case category(ItemCategory)
        case location(String)
        /// Doubtful matches that sit inside the named program or folder.
        case doubtful(owner: String)
    }

    public var kind: Kind
    public var rows: [ResultRow]

    public var id: String {
        switch kind {
        case .category(let category): "category:" + category.rawValue
        case .location(let title): "location:" + title
        case .doubtful(let owner): "doubtful:" + owner
        }
    }

    public var itemIDs: [String] { rows.map(\.id) }

    /// Combined size of the section; nested rows are part of their parents and not counted twice.
    public var size: Int64 {
        rows.reduce(0) { $0 + ($1.depth == 0 ? $1.item.size ?? 0 : 0) }
    }
}

/// The results of a scan together with what the user has checked for removal.
///
/// Items can be nested: a vendor's folder with the product's folders inside. Checking a
/// folder means the whole folder goes, so its nested items show as checked too, and
/// unchecking one of them trades the folder for its other nested items.
public struct ResultBoard: Sendable {
    public private(set) var items: [FoundItem]
    private var indexByID: [String: Int] = [:]
    private var childIDs: [String: [String]] = [:]
    /// Checked items, never an item together with one of its ancestors.
    public private(set) var checked: Set<String> = []

    public init(items: [FoundItem] = []) {
        self.items = items
        rebuildIndex()
        // Start with what the scan is sure about.
        for item in items where item.relevance == .high && !hasCheckedAncestor(item.id) {
            setChecked(item.id, true)
        }
    }

    public var isEmpty: Bool { items.isEmpty }

    public func item(_ id: String) -> FoundItem? { indexByID[id].map { items[$0] } }

    // MARK: Checking

    public func state(of id: String) -> CheckState {
        if checked.contains(id) || hasCheckedAncestor(id) { return .on }
        return descendants(of: id).contains(where: checked.contains) ? .mixed : .off
    }

    /// The combined state of several items, as shown on a section header.
    public func state(of ids: some Sequence<String>) -> CheckState {
        var sawOn = false, sawOff = false
        for id in ids {
            switch state(of: id) {
            case .on: sawOn = true
            case .off: sawOff = true
            case .mixed: return .mixed
            }
            if sawOn && sawOff { return .mixed }
        }
        return sawOn ? .on : .off
    }

    public mutating func toggle(_ id: String) {
        setChecked(id, state(of: id) != .on)
    }

    public mutating func setChecked(_ ids: some Sequence<String>, _ on: Bool) {
        for id in ids { setChecked(id, on) }
    }

    public mutating func setChecked(_ id: String, _ on: Bool) {
        guard indexByID[id] != nil else { return }
        if on {
            guard !hasCheckedAncestor(id) else { return }
            for descendant in descendants(of: id) { checked.remove(descendant) }
            checked.insert(id)
            promoteCompleteParent(of: id)
        } else {
            // If a folder above is checked, keep everything in it except this item.
            if let ancestor = checkedAncestor(of: id) {
                checked.remove(ancestor)
                checkAll(under: ancestor, except: id)
            }
            checked.remove(id)
            for descendant in descendants(of: id) { checked.remove(descendant) }
        }
    }

    public mutating func uncheckAll() { checked.removeAll() }

    /// What to hand to the remover: every checked item, with nothing listed inside something else.
    public var selection: [FoundItem] {
        items.filter { checked.contains($0.id) }
    }

    /// Number of rows that show a check mark.
    public var checkedRowCount: Int {
        items.reduce(0) { $0 + (state(of: $1.id) == .on ? 1 : 0) }
    }

    public var selectionSize: Int64 {
        selection.reduce(0) { $0 + ($1.size ?? 0) }
    }

    public var selectionNeedsAdmin: Bool {
        selection.contains(where: \.needsAdmin)
    }

    // MARK: Updating

    public mutating func applySizes(_ sizes: [String: Int64]) {
        for (id, size) in sizes {
            if let index = indexByID[id] { items[index].size = size }
        }
    }

    /// Drops items that no longer exist, along with everything nested in them.
    public mutating func remove(ids: some Sequence<String>) {
        var gone = Set(ids)
        for id in ids { gone.formUnion(descendants(of: id)) }
        items.removeAll { gone.contains($0.id) }
        checked.subtract(gone)
        rebuildIndex()
    }

    // MARK: Sections

    /// The list as shown: sections of likely matches, then sections of doubtful ones.
    public func sections(grouping: Grouping, filter: String = "") -> (main: [ResultSection], doubtful: [ResultSection]) {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let visible: Set<String>? = needle.isEmpty ? nil : matching(needle)

        var main: [String: (kind: ResultSection.Kind, order: Int, rows: [ResultRow])] = [:]
        var doubtful: [String: [ResultRow]] = [:]

        for top in items where top.parentID == nil || indexByID[top.parentID!] == nil {
            let rows = rows(from: top, depth: 0, visible: visible)
            guard !rows.isEmpty else { continue }
            if rows.contains(where: { $0.item.relevance > .low }) {
                let kind: ResultSection.Kind = grouping == .category ? .category(top.category) : .location(top.locationTitle)
                let key = grouping == .category ? top.category.rawValue : top.locationTitle
                main[key, default: (kind, top.category.order, [])].rows += rows
            } else {
                doubtful[top.owner ?? top.locationTitle, default: []] += rows
            }
        }

        let mainSections = main.values
            .sorted { ($0.order, title(of: $0.kind)) < ($1.order, title(of: $1.kind)) }
            .map { ResultSection(kind: $0.kind, rows: $0.rows) }
        let doubtfulSections = doubtful
            .sorted { ($1.value.count, $0.key) < ($0.value.count, $1.key) }
            .map { ResultSection(kind: .doubtful(owner: $0.key), rows: $0.value) }
        return (mainSections, doubtfulSections)
    }

    private func title(of kind: ResultSection.Kind) -> String {
        switch kind {
        case .category(let category): category.rawValue
        case .location(let title): title
        case .doubtful(let owner): owner
        }
    }

    private func rows(from item: FoundItem, depth: Int, visible: Set<String>?) -> [ResultRow] {
        if let visible, !visible.contains(item.id) { return [] }
        var rows = [ResultRow(item: item, depth: depth)]
        for child in childIDs[item.id] ?? [] {
            if let index = indexByID[child] { rows += self.rows(from: items[index], depth: depth + 1, visible: visible) }
        }
        return rows
    }

    /// Items matching the filter text, plus the items they are nested in.
    private func matching(_ needle: String) -> Set<String> {
        var result = Set<String>()
        for item in items where item.name.lowercased().contains(needle) || item.path.lowercased().contains(needle) {
            var current: String? = item.id
            while let id = current, result.insert(id).inserted {
                current = self.item(id)?.parentID
            }
        }
        return result
    }

    // MARK: Tree

    private mutating func rebuildIndex() {
        indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
        childIDs = [:]
        for item in items {
            if let parent = item.parentID, indexByID[parent] != nil { childIDs[parent, default: []].append(item.id) }
        }
    }

    private func descendants(of id: String) -> [String] {
        var result: [String] = []
        var stack = childIDs[id] ?? []
        while let next = stack.popLast() {
            result.append(next)
            stack += childIDs[next] ?? []
        }
        return result
    }

    private func checkedAncestor(of id: String) -> String? {
        var current = item(id)?.parentID
        while let parent = current {
            if checked.contains(parent) { return parent }
            current = item(parent)?.parentID
        }
        return nil
    }

    private func hasCheckedAncestor(_ id: String) -> Bool { checkedAncestor(of: id) != nil }

    /// Checks everything under `root` individually, leaving `excluded` and the path down to it unchecked.
    private mutating func checkAll(under root: String, except excluded: String) {
        for child in childIDs[root] ?? [] where child != excluded {
            if descendants(of: child).contains(excluded) {
                checkAll(under: child, except: excluded)
            } else {
                checked.insert(child)
            }
        }
    }

    /// A folder that holds nothing but found items is as good as checked once all of them are.
    private mutating func promoteCompleteParent(of id: String) {
        guard let parentID = item(id)?.parentID, let parent = item(parentID),
              parent.reasons.contains(.holdsOnlyFoundItems), parent.unrelatedChildCount == 0 else { return }
        let siblings = childIDs[parentID] ?? []
        guard siblings.allSatisfy(checked.contains) else { return }
        for sibling in siblings { checked.remove(sibling) }
        checked.insert(parentID)
        promoteCompleteParent(of: parentID)
    }
}
