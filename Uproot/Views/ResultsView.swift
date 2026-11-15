import QuickLook
import SwiftUI
import UprootCore

/// The found items, grouped, with the bar for removing what is checked.
struct ResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.board.isEmpty {
                NothingFound()
            } else {
                ResultsHeader()
                Divider()
                ResultsList()
                Divider()
                ActionBar()
            }
        }
    }
}

private struct ResultsHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(summary)
                    .font(.system(size: 13, weight: .semibold))
                if let footnote {
                    Text(footnote)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)

            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("Фильтр", text: $model.filter)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                if !model.filter.isEmpty {
                    Button {
                        model.filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Picker("Группировка", selection: $model.grouping) {
                ForEach(Grouping.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var summary: String {
        var text = "Найдено: \(Texts.objects(model.likelyCount))"
        if model.likelySize > 0 { text += " · \(Texts.size(model.likelySize))" }
        return text
    }

    private var footnote: String? {
        guard let result = model.result else { return nil }
        var parts: [String] = []
        if result.wasCancelled { parts.append("поиск остановлен, результаты неполные") }
        parts.append("проверено \(Texts.number(result.entriesScanned)) за \(String(format: "%.1f", result.duration)) с")
        if result.unreadableCount > 0 && !model.hasFullDiskAccess {
            parts.append("не удалось прочитать \(Texts.number(result.unreadableCount)) \(Texts.plural(result.unreadableCount, "папку", "папки", "папок"))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ResultsList: View {
    @Environment(AppModel.self) private var model
    @State private var quickLook: URL?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.highlighted) {
            ForEach(model.displayRows) { row in
                switch row {
                case .header(let section):
                    SectionHeaderView(section: section)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 2, trailing: 8))
                        .selectionDisabled()
                case .item(let row):
                    ResultRowView(row: row)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 8))
                        .tag(row.id)
                case .doubtfulDivider(let count):
                    DoubtfulDivider(count: count)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 4, bottom: 4, trailing: 8))
                        .selectionDisabled()
                }
            }
        }
        .listStyle(.inset)
        .environment(\.defaultMinListRowHeight, 26)
        .contextMenu(forSelectionType: String.self) { ids in
            menu(for: model.items(ids), ids: ids)
        } primaryAction: { ids in
            Finder.reveal(model.items(ids))
        }
        .onKeyPress(.space) {
            model.toggleHighlighted()
            return .handled
        }
        .quickLookPreview($quickLook)
    }

    @ViewBuilder
    private func menu(for items: [FoundItem], ids: Set<String>) -> some View {
        if !items.isEmpty {
            let onDisk = items.filter(\.isOnDisk)
            Button("Отметить для удаления") { model.setChecked(ids, true) }
            Button("Снять отметку") { model.setChecked(ids, false) }
            Divider()
            Button("Показать в Finder") { Finder.reveal(items) }
            if let first = onDisk.first, onDisk.count == 1 {
                Button("Быстрый просмотр") { quickLook = URL(fileURLWithPath: first.path) }
            }
            Button(items.count == 1 ? "Скопировать путь" : "Скопировать пути") {
                Finder.copy(items.map(\.path).joined(separator: "\n"))
            }
            Divider()
            Button("Убрать из результатов") { model.hide(ids) }
        }
    }
}

private struct SectionHeaderView: View {
    @Environment(AppModel.self) private var model
    let section: ResultSection

    var body: some View {
        let collapsed = model.isCollapsed(section)
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(collapsed ? 0 : 90))
                .frame(width: 12)
            CheckBox(state: model.board.state(of: section.rows.filter { $0.depth == 0 }.map(\.id))) {
                model.toggle(section)
            }
            IconTile(symbol: symbol, tint: tint)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(Texts.number(section.rows.count))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer(minLength: 8)
            if section.size > 0 {
                Text(Texts.size(section.size))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { model.toggleCollapsed(section) }
        .animation(.easeOut(duration: 0.12), value: collapsed)
    }

    private var title: String {
        switch section.kind {
        case .category(let category): category.title
        case .location(let title): title
        case .doubtful(let owner): owner
        }
    }

    private var symbol: String {
        switch section.kind {
        case .category(let category): category.symbol
        case .location: "folder.fill"
        case .doubtful: "questionmark"
        }
    }

    private var tint: Color {
        switch section.kind {
        case .category(let category): category.tint
        case .location: .blue
        case .doubtful: .gray
        }
    }
}

private struct ResultRowView: View {
    @Environment(AppModel.self) private var model
    let row: ResultRow
    @State private var isHovered = false

    var body: some View {
        let item = row.item
        HStack(spacing: 9) {
            CheckBox(state: model.board.state(of: item.id)) {
                model.toggle(item.id)
            }
            Image(nsImage: IconCache.icon(for: item))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // In a file search nothing is preselected, so there is no "sure" to contrast with.
                    if item.relevance == .medium, model.result?.query.target != .files {
                        Tag(text: "проверьте", tint: .orange)
                    }
                    if item.unrelatedChildCount > 0 {
                        Tag(text: "внутри ещё \(Texts.objects(item.unrelatedChildCount))", tint: .red)
                    }
                }
                Text(subtitle(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if isHovered, item.kind != .receipt {
                Button {
                    Finder.reveal([item])
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Показать в Finder")
            }
            if item.needsAdmin {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help("Для удаления потребуется пароль администратора")
            }
            Text(item.size.map { $0 > 0 ? Texts.size($0) : "—" } ?? (item.isOnDisk ? "…" : ""))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.leading, CGFloat(row.depth) * 24)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help("\(Texts.abbreviate(item.path))\n\(item.allReasonsText)")
    }

    private func subtitle(for item: FoundItem) -> String {
        let reason = item.reasonText
        return reason.isEmpty ? item.locationText : "\(item.locationText)  —  \(reason)"
    }
}

private struct DoubtfulDivider: View {
    @Environment(AppModel.self) private var model
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(model.showsDoubtful ? 90 : 0))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text("Сомнительные совпадения · \(Texts.number(count))")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Имя похоже, но это, скорее всего, части других программ или ваши документы. Не отмечены.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.12)) { model.showsDoubtful.toggle() }
        }
    }
}

private struct NothingFound: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Ничего не найдено", systemImage: "checkmark.seal")
        } description: {
            Text(model.target == .files
                 ? "Файлов и папок с именем «\(model.query.summary)» нет. Попробуйте часть имени или другое написание."
                 : "На диске нет ничего с названием «\(model.query.summary)». Попробуйте другое написание, короткое имя или название компании.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The bar at the bottom: what is checked, and the button that removes it.
private struct ActionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // Counted the way the confirmation lists them: a checked folder is one object, whatever is nested in it.
        let count = model.board.selection.count
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(count == 0 ? "Ничего не отмечено" : "Отмечено: \(Texts.objects(count)) · \(Texts.size(model.board.selectionSize))")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                if model.board.selectionNeedsAdmin {
                    Label("понадобится пароль администратора", systemImage: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if count > 0 {
                Button("Снять все", action: model.uncheckAll)
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            Spacer()

            Picker("Способ", selection: $model.removalMode) {
                ForEach(RemovalMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            Button(action: model.requestRemoval) {
                Label("Удалить…", systemImage: "trash")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(count == 0)
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Small parts

/// A check box with a third, partly-checked state.
struct CheckBox: View {
    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.palette)
                // White mark on an accent square, like the system's own check boxes.
                .foregroundStyle(state == .off ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.white),
                                 state == .off ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(state == .on ? "отмечено" : state == .mixed ? "отмечено частично" : "не отмечено")
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        case .off: "square"
        }
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct Tag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}
