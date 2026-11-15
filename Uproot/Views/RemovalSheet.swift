import SwiftUI
import UprootCore

/// The sheet a removal lives in: asks for confirmation, shows progress, then sums up.
struct RemovalSheet: View {
    @Environment(AppModel.self) private var model
    let session: RemovalSession

    var body: some View {
        VStack(spacing: 0) {
            switch session.stage {
            case .confirming: Confirmation(session: session)
            case .running: Running(session: session)
            case .finished: Summary(session: session)
            }
        }
        .frame(width: 540)
        .interactiveDismissDisabled(session.stage == .running)
    }
}

private struct Confirmation: View {
    @Environment(AppModel.self) private var model
    let session: RemovalSession

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: session.mode == .trash ? "trash.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 38))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(session.mode == .trash ? Color.accentColor : Color.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Удалить \(Texts.objects(session.items.count))?")
                        .font(.system(size: 17, weight: .semibold))
                    Text(explanation)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 40) }
                        HStack(spacing: 9) {
                            Image(nsImage: IconCache.icon(for: item))
                                .resizable()
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.name)
                                    .font(.system(size: 12.5))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(item.isOnDisk ? item.locationText : item.actionText(mode: session.mode))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            if item.needsAdmin {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                            if let size = item.size, size > 0 {
                                Text(Texts.size(size))
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                }
            }
            .frame(height: min(CGFloat(session.items.count) * 37 + 2, 260))
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                ForEach(notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Picker("Способ", selection: $session.mode) {
                    ForEach(RemovalMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Отмена", role: .cancel, action: model.closeRemoval)
                    .keyboardShortcut(.cancelAction)
                Button(session.mode == .trash ? "Переместить в Корзину" : "Удалить навсегда", role: .destructive,
                       action: model.performRemoval)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(20)
    }

    private var explanation: String {
        let size = session.totalSize > 0 ? " Всего \(Texts.size(session.totalSize))." : ""
        switch session.mode {
        case .trash: return "Файлы и папки переедут в Корзину, откуда их можно вернуть." + size
        case .permanent: return "Файлы и папки будут удалены сразу и без возможности вернуть." + size
        }
    }

    private var notes: [String] {
        var notes: [String] = []
        if session.adminCount > 0 {
            notes.append("Для \(Texts.objects(session.adminCount)) macOS один раз спросит пароль администратора.")
        }
        let processes = session.count(of: .process)
        if processes > 0 {
            notes.append("\(Texts.plural(processes, "Будет завершён", "Будут завершены", "Будет завершено")) \(processes) \(Texts.plural(processes, "процесс", "процесса", "процессов")).")
        }
        let receipts = session.count(of: .receipt)
        if receipts > 0 {
            notes.append("Записи установщика удаляются сразу: это учётные записи системы, а не файлы.")
        }
        let volumes = session.count(of: .volume)
        if volumes > 0 {
            notes.append("\(Texts.plural(volumes, "Том будет извлечён", "Тома будут извлечены", "Тома будут извлечены")), сами образы останутся на месте.")
        }
        return notes
    }
}

private struct Running: View {
    let session: RemovalSession

    var body: some View {
        let progress = session.progress
        VStack(spacing: 14) {
            if let progress, progress.phase == .removing, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .frame(width: 320)
            } else {
                ProgressView()
            }
            Text(title(progress))
                .font(.system(size: 14, weight: .medium))
            Text(progress?.phase == .removing ? progress?.currentName ?? "" : " ")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 420)
        }
        .padding(36)
        .frame(maxWidth: .infinity)
    }

    private func title(_ progress: RemovalProgress?) -> String {
        switch progress?.phase {
        case .waitingForAdministrator: "Жду пароль администратора…"
        case .verifying: "Проверяю, что всё удалилось…"
        case .removing, nil: "Удаляю…"
        }
    }
}

private struct Summary: View {
    @Environment(AppModel.self) private var model
    let session: RemovalSession

    var body: some View {
        let report = session.report
        let problems = report?.problems ?? []
        let done = report?.succeeded ?? []
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 38))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(problems.isEmpty ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(done: done.count, problems: problems.count))
                        .font(.system(size: 17, weight: .semibold))
                    Text(detail(report))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Не удалось")
                        .font(.system(size: 12, weight: .semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(problems) { outcome in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(outcome.name)
                                        .font(.system(size: 12.5))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(outcome.status.text)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .frame(maxHeight: 150)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if problems.contains(where: { $0.status == .reappeared }) {
                        Label("Если что-то появилось снова, программа или плагин ещё работают — например, загружены в DAW. Закройте их и повторите.",
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VerificationLine(verification: session.verification)

            HStack {
                Spacer()
                Button("Готово", action: model.closeRemoval)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(20)
    }

    private func headline(done: Int, problems: Int) -> String {
        if done == 0 { return "Ничего не удалено" }
        let verb = session.mode == .trash ? "В Корзине" : "Удалено"
        return problems == 0 ? "\(verb): \(Texts.objects(done))" : "\(verb): \(Texts.objects(done)), не удалось: \(problems)"
    }

    private func detail(_ report: RemovalReport?) -> String {
        guard let report, report.bytesRemoved > 0 else { return "Операция записана в журнал." }
        let size = Texts.size(report.bytesRemoved)
        return session.mode == .trash
            ? "\(size) освободится, когда вы очистите Корзину. Операция записана в журнал."
            : "Освобождено \(size). Операция записана в журнал."
    }
}

private struct VerificationLine: View {
    let verification: RemovalSession.Verification?

    var body: some View {
        HStack(spacing: 8) {
            switch verification {
            case .checking, nil:
                ProgressView().controlSize(.small)
                Text("Ищу ещё раз, не осталось ли следов…")
            case .done(let sure, let toReview):
                Image(systemName: sure == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(sure == 0 ? Color.green : Color.orange)
                Text(text(sure: sure, toReview: toReview))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .font(.system(size: 12.5))
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func text(sure: Int, toReview: Int) -> String {
        var text = sure == 0 ? "Повторный поиск: точных совпадений не осталось."
                             : "Повторный поиск: \(Texts.plural(sure, "остался", "осталось", "осталось")) \(Texts.objects(sure))."
        if toReview > 0 { text += " Ещё \(Texts.objects(toReview)) без отметки — на ваше усмотрение." }
        return text
    }
}
