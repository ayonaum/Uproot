import SwiftUI
import UprootCore

/// What the window shows before the first search.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("Что удаляем?")
                        .font(.system(size: 26, weight: .semibold))
                    Text("Введите название программы, игры или плагина — Uproot найдёт всё, что от них лежит на диске, разложит по группам и удалит то, что вы отметите. Или переключитесь на «Файлы и папки» и ищите что угодно по имени.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 470)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Feature(symbol: "text.magnifyingglass", tint: .blue,
                            title: "Ищет не только по имени",
                            detail: "Ещё по идентификатору найденной программы, записям установщика, службам автозапуска и запущенным процессам.")
                    Feature(symbol: "checklist", tint: .green,
                            title: "Отмечает только то, в чём уверен",
                            detail: "Спорные совпадения остаются без галочки, а файлы других программ убираются в отдельный список.")
                    Feature(symbol: "arrow.uturn.backward.circle", tint: .orange,
                            title: "Удаляет в Корзину",
                            detail: "Пароль администратора спросит один раз, а после удаления проверит диск ещё раз.")
                }
                .frame(maxWidth: 470, alignment: .leading)

                if !model.recentQueries.isEmpty {
                    RecentSearches()
                        .frame(maxWidth: 520)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RecentSearches: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Недавние поиски")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Очистить", action: model.clearRecentQueries)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                let queries = Array(model.recentQueries.prefix(6))
                ForEach(Array(queries.enumerated()), id: \.offset) { index, query in
                    if index > 0 { Divider().padding(.leading, 34) }
                    RecentRow(query: query)
                }
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let query: SearchQuery
    @State private var isHovered = false

    var body: some View {
        Button {
            model.use(query)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(query.products.joined(separator: ", "))
                    .font(.system(size: 13))
                    .lineLimit(1)
                if query.target == .files {
                    Tag(text: "файлы", tint: .blue)
                }
                if !query.vendors.isEmpty {
                    Text(query.vendors.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.05) : .clear)
        .onHover { isHovered = $0 }
    }
}

/// Shown while a scan runs.
struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.progress
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 6) {
                Text("Ищу «\(model.query.summary)»")
                    .font(.system(size: 18, weight: .semibold))
                Text(progress.stage.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 28) {
                Counter(value: Texts.number(progress.entriesScanned), caption: "проверено")
                Counter(value: Texts.number(progress.hitsFound), caption: "совпадений")
            }

            Text(Texts.abbreviate(progress.currentPath))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520, minHeight: 14)

            VStack(spacing: 3) {
                ForEach(Array(progress.recentNames.suffix(4).enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: 420, minHeight: 70, alignment: .top)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Counter: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 110)
    }
}

/// A strip under the query when the app cannot read the whole disk.
struct AccessBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Нет полного доступа к диску")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Часть папок останется непроверенной, а macOS будет спрашивать разрешения по одной. Включите Uproot в списке «Полный доступ к диску» и перезапустите.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Открыть настройки", action: FullDiskAccess.openSettings)
            Button("Перезапустить", action: FullDiskAccess.relaunch)
        }
        .controlSize(.small)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.09))
    }
}
