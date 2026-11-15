import SwiftUI
import UprootCore

/// The top of the window: what to look for, and the button that starts looking.
struct QueryPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Что ищем", selection: $model.target) {
                    Text("Программа и её следы").tag(SearchTarget.program)
                    Text("Файлы и папки").tag(SearchTarget.files)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(model.isScanning)
                Text(model.target == .program
                     ? "Приложение, игра или плагин со всеми настройками, кэшем и службами"
                     : "Любые файлы и папки по имени или его части")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 14) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                    if model.target == .program {
                        GridRow {
                            FieldLabel("Программа", symbol: "app.dashed")
                            TokenField(placeholder: "Название программы, игры или плагина; через запятую — несколько",
                                       tokens: $model.products, draft: $model.productDraft, onSubmit: model.startScan)
                        }
                        GridRow {
                            FieldLabel("Компания", symbol: "building.2")
                            TokenField(placeholder: "Разработчик или издатель — необязательно",
                                       tokens: $model.vendors, draft: $model.vendorDraft, onSubmit: model.startScan)
                        }
                    } else {
                        GridRow {
                            FieldLabel("Имя", symbol: "doc.text.magnifyingglass")
                            TokenField(placeholder: "Имя файла или папки, часть имени или расширение; через запятую — несколько",
                                       tokens: $model.products, draft: $model.productDraft, onSubmit: model.startScan)
                        }
                    }
                }

                VStack(spacing: 8) {
                    if model.isScanning {
                        Button(action: model.stopScan) {
                            Label("Остановить", systemImage: "stop.fill")
                                .frame(width: 108)
                        }
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                    } else {
                        Button(action: model.startScan) {
                            Label("Найти", systemImage: "magnifyingglass")
                                .frame(width: 108)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    }

                    Button {
                        model.showsOptions.toggle()
                    } label: {
                        Label(optionsTitle, systemImage: "slider.horizontal.3")
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(hasCustomOptions ? Color.accentColor : Color.secondary)
                    .popover(isPresented: $model.showsOptions, arrowEdge: .bottom) {
                        ScanOptionsView()
                    }
                }
                .padding(.top, 1)
            }

            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var hasCustomOptions: Bool {
        model.options != ScanOptions() || !model.excludes.isEmpty
    }

    private var optionsTitle: String {
        hasCustomOptions ? "Параметры изменены" : "Параметры"
    }
}

private struct FieldLabel: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: 32)
            .gridColumnAlignment(.leading)
    }
}

/// The less common knobs, kept out of the way in a popover.
struct ScanOptionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            Text("Параметры поиска")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Не показывать пути, содержащие")
                    .font(.system(size: 12, weight: .medium))
                TokenField(placeholder: "Например: Steam, Sebastian", tokens: $model.excludes, draft: $model.excludeDraft)
            }

            OptionToggle(isOn: $model.options.searchInsideBundles,
                         title: "Искать внутри чужих программ и плагинов",
                         detail: "Заглядывать в пакеты .app, .vst3 и подобные, которые сами не совпали. Дольше, и почти всё найденное окажется частью других программ.")

            OptionToggle(isOn: $model.options.includeExternalVolumes,
                         title: "Просматривать внешние диски",
                         detail: "Обычно проверяется только системный диск; смонтированные образы установщиков находятся и без этого.")
        }
        .padding(16)
        .frame(width: 380)
    }
}

private struct OptionToggle: View {
    @Binding var isOn: Bool
    let title: String
    let detail: String

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }
}
