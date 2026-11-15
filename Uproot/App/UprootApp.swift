import SwiftUI
import UprootCore

/// The executable has two jobs. Started normally it is the app; started with the helper
/// flag it runs one privileged script for the app and exits (see `ElevationHelper`).
@main
enum Launcher {
    @MainActor static func main() {
        if CommandLine.arguments.contains(ElevationHelper.flag) {
            ElevationHelper.runAndExit()
        }
        if let problem = LaunchOptions().fixtureProblem {
            FileHandle.standardError.write(Data("Uproot: \(problem)\n".utf8))
            exit(2)
        }
        UprootApp.main()
    }
}

struct UprootApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Uproot", id: "main") {
            RootView()
                .environment(model)
                .environment(\.locale, interfaceLocale)
        }
        .defaultSize(width: 1040, height: 720)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Picker("Группировка", selection: $model.grouping) {
                    ForEach(Grouping.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Divider()
            }
            CommandMenu("Поиск") {
                Button("Найти", action: model.startScan)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isScanning || model.removal != nil)
                Button("Остановить", action: model.stopScan)
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.isScanning)
                Divider()
                Button("Удалить отмеченное…", action: model.requestRemoval)
                    .disabled(model.phase != .results || model.removal != nil || model.board.selection.isEmpty)
                Button("Снять все отметки", action: model.uncheckAll)
                    .disabled(model.board.checked.isEmpty)
                Divider()
                Button("Журнал удалений") { model.showsHistory = true }
                    .keyboardShortcut("y", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let size = LaunchOptions().windowSize else { return }
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
            var frame = window.frame
            frame.origin.y += frame.height - size.height
            frame.size = size
            window.setFrame(frame, display: true)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            QueryPanel()
            Divider()
            if !model.hasFullDiskAccess {
                AccessBanner()
                Divider()
            }
            Group {
                switch model.phase {
                case .welcome: WelcomeView()
                case .scanning: ScanningView()
                case .results: ResultsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showsHistory = true
                } label: {
                    Label("Журнал", systemImage: "clock.arrow.circlepath")
                }
                .help("Журнал удалений")
            }
        }
        .navigationSubtitle(model.isFixture ? "тестовый диск" : "")
        .sheet(item: $model.removal) { session in
            RemovalSheet(session: session)
                .environment(model)
                .environment(\.locale, interfaceLocale)
        }
        .sheet(isPresented: $model.showsHistory) {
            HistoryView()
                .environment(model)
                .environment(\.locale, interfaceLocale)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
        }
    }
}
