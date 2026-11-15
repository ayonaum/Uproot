import SwiftUI
import UprootCore

/// The journal of past removals.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<UUID> = []
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Журнал удалений")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !model.history.isEmpty {
                    Button("Очистить журнал", action: model.clearHistory)
                }
                Button("Закрыть") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            Divider()

            if model.history.isEmpty {
                ContentUnavailableView("Журнал пуст", systemImage: "clock",
                                       description: Text("Здесь появится всё, что вы удалите через Uproot."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.history) { entry in
                            EntryCard(entry: entry, isExpanded: expanded.contains(entry.id), message: $message) {
                                expanded.formSymmetricDifference([entry.id])
                            }
                        }
                    }
                    .padding(16)
                }
            }

            if let message {
                Divider()
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 620, height: 520)
    }
}

private struct EntryCard: View {
    @Environment(AppModel.self) private var model
    let entry: HistoryEntry
    let isExpanded: Bool
    @Binding var message: String?
    let toggle: () -> Void

    var body: some View {
        let report = entry.report
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.query.summary)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(Texts.date(report.date)) · \(report.mode == .trash ? "в Корзину" : "навсегда")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Texts.objects(report.succeeded.count))
                        .font(.system(size: 12, weight: .medium))
                    if !report.problems.isEmpty {
                        Text("не удалось: \(report.problems.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    } else if report.bytesRemoved > 0 {
                        Text(Texts.size(report.bytesRemoved))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(report.outcomes) { outcome in
                        OutcomeRow(outcome: outcome, entry: entry, message: $message)
                    }
                }
                .padding(12)
            }
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct OutcomeRow: View {
    @Environment(AppModel.self) private var model
    let outcome: RemovalOutcome
    let entry: HistoryEntry
    @Binding var message: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(outcome.succeeded ? Color.green : Color.orange)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 0) {
                Text(Texts.abbreviate(outcome.path))
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(outcome.status.text)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if case .trashed(let location?) = outcome.status {
                if TrashRestore.canPutBack(outcome) {
                    Button("Вернуть") {
                        message = model.putBack(outcome, in: entry).map { "Не удалось вернуть «\(outcome.name)»: \($0)" }
                    }
                    .help("Переместить из Корзины на прежнее место")
                }
                Button {
                    Finder.reveal(path: location)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Показать в Корзине")
            }
        }
        .controlSize(.small)
    }
}
