import AppKit
import UprootCore

/// Full Disk Access, the privacy permission that lets the scan read every folder and
/// lets removal touch other apps' files without a string of separate prompts.
enum FullDiskAccess {
    /// macOS has no call for asking; reading the privacy database is the customary test,
    /// because only apps with Full Disk Access may open it.
    static var isGranted: Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The permission takes effect on the next launch, so offer to do that for the user.
    @MainActor static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            // Quit only once the new copy is up; otherwise a failed relaunch would just close the app.
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Finder icons for result rows.
@MainActor enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for item: FoundItem) -> NSImage {
        if let cached = cache.object(forKey: item.id as NSString) { return cached }
        let image: NSImage
        switch item.kind {
        case .receipt:
            image = symbol("shippingbox.fill")
        case .process:
            image = NSWorkspace.shared.icon(forFile: enclosingApp(of: item.path) ?? item.path)
        case .file, .folder, .bundle, .symlink, .volume:
            image = NSWorkspace.shared.icon(forFile: item.path)
        }
        cache.setObject(image, forKey: item.id as NSString)
        return image
    }

    private static func symbol(_ name: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            .applying(.init(hierarchicalColor: .secondaryLabelColor))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) ?? NSImage()
    }

    private static func enclosingApp(of path: String) -> String? {
        var current = path
        while current.count > 1 {
            if current.hasSuffix(".app") { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
}

@MainActor enum Finder {
    static func reveal(_ items: [FoundItem]) {
        let urls = items.filter { $0.kind != .receipt }.map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
