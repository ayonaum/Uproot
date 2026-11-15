import SwiftUI
import UprootCore

/// The interface language. Formatters use it so that sizes and dates match the labels.
let interfaceLocale = Locale(identifier: "ru_RU")

enum Texts {
    /// The machine whose paths are being shown; set once at launch, before any view exists.
    nonisolated(unsafe) static var environment = ScanEnvironment.current

    /// Picks the Russian plural form: 1 объект, 2 объекта, 5 объектов.
    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let lastTwo = abs(count) % 100, last = abs(count) % 10
        if (11...14).contains(lastTwo) { return many }
        if last == 1 { return one }
        if (2...4).contains(last) { return few }
        return many
    }

    static func objects(_ count: Int) -> String {
        "\(number(count)) \(plural(count, "объект", "объекта", "объектов"))"
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(interfaceLocale))
    }

    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(interfaceLocale))
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(interfaceLocale))
    }

    /// The last path component, for mentioning a file in a sentence.
    static func name(ofPath path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// The folder a path is in, with the home folder shortened to "~".
    static func folder(ofPath path: String) -> String {
        abbreviate((path as NSString).deletingLastPathComponent)
    }

    /// Shortens a path for display: the home folder becomes "~".
    static func abbreviate(_ path: String) -> String {
        environment.display(path)
    }
}

extension ItemCategory {
    var title: String {
        switch self {
        case .applications: "Программы"
        case .audioPlugins: "Аудиоплагины и пресеты"
        case .appData: "Данные программы"
        case .preferences: "Настройки"
        case .caches: "Кэш и состояние"
        case .logs: "Журналы"
        case .containers: "Контейнеры"
        case .launchItems: "Автозапуск и службы"
        case .extensions: "Расширения системы"
        case .receipts: "Записи установщика"
        case .processes: "Запущенные процессы"
        case .volumes: "Смонтированные тома"
        case .installers: "Загрузки и установщики"
        case .windows: "Windows-программы"
        case .hostData: "Базы плагинов в других программах"
        case .commandLine: "Командная строка и система"
        case .personalFiles: "Личные файлы"
        case .other: "Прочее"
        }
    }

    var symbol: String {
        switch self {
        case .applications: "macwindow"
        case .audioPlugins: "pianokeys"
        case .appData: "folder.fill"
        case .preferences: "gearshape.fill"
        case .caches: "clock.arrow.circlepath"
        case .logs: "doc.text.fill"
        case .containers: "shippingbox.fill"
        case .launchItems: "bolt.fill"
        case .extensions: "puzzlepiece.extension.fill"
        case .receipts: "list.bullet.clipboard.fill"
        case .processes: "cpu.fill"
        case .volumes: "externaldrive.fill"
        case .installers: "arrow.down.circle.fill"
        case .windows: "pc"
        case .hostData: "square.stack.3d.up.fill"
        case .commandLine: "terminal.fill"
        case .personalFiles: "person.fill"
        case .other: "questionmark.folder.fill"
        }
    }

    var tint: Color {
        switch self {
        case .applications: .blue
        case .audioPlugins: .purple
        case .appData: .teal
        case .preferences: .gray
        case .caches: .orange
        case .logs: .brown
        case .containers: .indigo
        case .launchItems: .yellow
        case .extensions: .green
        case .receipts: .mint
        case .processes: .red
        case .volumes: .cyan
        case .installers: .blue
        case .windows: .indigo
        case .hostData: .pink
        case .commandLine: .gray
        case .personalFiles: .orange
        case .other: .secondary
        }
    }
}

extension MatchReason {
    /// A few words for the second line of a result row.
    var text: String {
        switch self {
        case .exactName: "точное имя"
        case .nameStartsWith(let term): "начинается с «\(term)»"
        case .identifierComponent(let term): "идентификатор содержит «\(term)»"
        case .containsWord(let term): "содержит слово «\(term)»"
        case .containsText(let term): "содержит «\(term)»"
        case .fileExtension(let term): "тип файла .\(term.lowercased())"
        case .vendorName(let term): "название компании «\(term)»"
        case .insideVendorFolder: "в папке компании"
        case .bundleIdentifier(let id): "идентификатор \(id)"
        case .installedByPackage(let id): "установлено пакетом \(id)"
        case .launches(let path): "запускает \(Texts.name(ofPath: path))"
        case .linksTo(let path): "ссылка на \(Texts.name(ofPath: path))"
        case .runsFrom(let path): "запущено из \(Texts.name(ofPath: path))"
        case .volumeContains(let name): "на томе лежит \(name)"
        case .insideOtherBundle(let name): "внутри \(name)"
        case .personalLocation: "личная папка"
        case .insideOtherProgram(let owner): "в папке «\(owner)»"
        case .holdsOnlyFoundItems: "внутри только найденное"
        case .partOfMacOS: "относится к macOS или программе Apple"
        }
    }
}

extension FoundItem {
    /// Where the item is, for the second line of its row.
    var locationText: String {
        switch kind {
        case .receipt: "pkgutil"
        case .process:
            if case .process(let pid, _) = detail { "PID \(pid) · \(Texts.folder(ofPath: path))" } else { Texts.folder(ofPath: path) }
        case .volume:
            if case .volume(let image?) = detail { "образ \(Texts.abbreviate(image))" } else { Texts.abbreviate(path) }
        case .file, .folder, .bundle, .symlink: Texts.folder(ofPath: path)
        }
    }

    var reasonText: String {
        reasons.prefix(2).map(\.text).joined(separator: " · ")
    }

    var allReasonsText: String {
        reasons.map(\.text).joined(separator: "\n")
    }

    /// What removing this item does, in the infinitive: "переместить в Корзину".
    func actionText(mode: RemovalMode) -> String {
        switch kind {
        case .receipt: "забыть запись установщика"
        case .process: "завершить процесс"
        case .volume: "извлечь том"
        case .file, .folder, .bundle, .symlink: mode == .trash ? "переместить в Корзину" : "удалить навсегда"
        }
    }
}

extension RemovalOutcome.Status {
    var text: String {
        switch self {
        case .trashed: "в Корзине"
        case .deleted: "удалено"
        case .terminated: "процесс завершён"
        case .ejected: "том извлечён"
        case .forgotten: "запись удалена"
        case .alreadyGone: "уже отсутствовало"
        case .cancelled: "отменено: пароль не введён"
        case .reappeared: "появилось снова"
        case .failed(.accessDenied): "нет доступа — включите полный доступ к диску"
        case .failed(.adminUnavailable): "нужны права администратора"
        case .failed(.protectedLocation): "стандартная папка или объект macOS — Uproot такие не удаляет"
        case .failed(.message(let message)): message.isEmpty ? "не удалось удалить" : message
        }
    }
}

extension RemovalMode {
    var title: String {
        switch self {
        case .trash: "В Корзину"
        case .permanent: "Удалить навсегда"
        }
    }
}

extension Grouping {
    var title: String {
        switch self {
        case .category: "По типу"
        case .location: "По папкам"
        }
    }
}

extension ScanProgress.Stage {
    var title: String {
        switch self {
        case .files: "Просматриваю папки"
        case .identifiers: "Ищу по идентификаторам найденных программ"
        case .packages: "Проверяю записи установщика"
        case .services: "Проверяю службы, ссылки и процессы"
        case .finishing: "Собираю результаты"
        }
    }
}
