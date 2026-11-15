import Foundation

/// The one shell script that does everything needing administrator rights, so the user
/// is asked for a password once however many items are involved.
///
/// Every path and identifier enters the script as a single-quoted literal. The script
/// reports on each step with a line the app can parse, and decides success by looking
/// at the disk afterwards rather than trusting exit codes.
struct PrivilegedScript: Sendable {
    enum Step: Sendable, Equatable {
        case trash(key: Int, path: String, trashFolder: String)
        case delete(key: Int, path: String)
        case forgetReceipt(key: Int, packageID: String)
        case stopProcess(key: Int, pid: Int32)
        /// Unloads a daemon from the system domain before its plist goes.
        case bootout(label: String)
        /// Restarts the Audio Unit registrar so hosts stop listing removed components.
        case refreshAudioUnits
    }

    enum StepResult: Sendable, Equatable {
        case done(location: String?)
        case failed(message: String)
    }

    var steps: [Step]
    var uid: uid_t
    var gid: gid_t

    private static let marker = "@@UPROOT"

    func render() -> String {
        var lines = [
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH",
            // A file name may hold a line break or a tab; printed raw it could pass for a report line.
            "plain() { printf %s \"$1\" | tr '\\n\\r\\t' '   '; }",
            "ok() { printf '\(Self.marker)\\tOK\\t%s\\t%s\\n' \"$1\" \"$(plain \"$2\")\"; }",
            "fail() { printf '\(Self.marker)\\tFAIL\\t%s\\t%s\\n' \"$1\" \"$(plain \"$2\")\"; }",
            "gone() { [ ! -e \"$1\" ] && [ ! -L \"$1\" ]; }",
            "unlock() { chflags -R nouchg,noschg \"$1\" 2>/dev/null; }",
            "del() {",
            "  if gone \"$2\"; then ok \"$1\" ''; return; fi",
            "  unlock \"$2\"",
            "  err=$(rm -rf -- \"$2\" 2>&1 | tr '\\n\\t' '  ')",
            "  if gone \"$2\"; then ok \"$1\" ''; else fail \"$1\" \"$err\"; fi",
            "}",
            "trash() {",
            "  if gone \"$2\"; then ok \"$1\" ''; return; fi",
            // A Trash made here would be root's; hand it to the user, or the Finder cannot use it.
            "  [ -d \"$3\" ] || { mkdir -p \"$3\" 2>/dev/null && chown \(uid):\(gid) \"$3\" 2>/dev/null; }",
            "  dst=\"$3/$4$5\"; n=1",
            "  while ! gone \"$dst\"; do n=$((n+1)); dst=\"$3/$4 $n$5\"; done",
            "  unlock \"$2\"",
            "  err=$(mv -f -- \"$2\" \"$dst\" 2>&1 | tr '\\n\\t' '  ')",
            "  if gone \"$2\"; then chown -R \(uid):\(gid) \"$dst\" 2>/dev/null; ok \"$1\" \"$dst\"; else fail \"$1\" \"$err\"; fi",
            "}",
            "forget() {",
            "  if err=$(pkgutil --forget \"$2\" 2>&1); then ok \"$1\" ''; else fail \"$1\" \"$(printf %s \"$err\" | tr '\\n\\t' '  ')\"; fi",
            "}",
            "stop() {",
            "  kill -TERM \"$2\" 2>/dev/null; n=0",
            "  while kill -0 \"$2\" 2>/dev/null && [ $n -lt 20 ]; do sleep 0.1; n=$((n+1)); done",
            "  kill -KILL \"$2\" 2>/dev/null; ok \"$1\" ''",
            "}",
        ]
        for step in steps {
            switch step {
            case .trash(let key, let path, let trashFolder):
                let name = (path as NSString).lastPathComponent
                let ext = (name as NSString).pathExtension
                let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
                lines.append("trash \(key) \(Self.quote(path)) \(Self.quote(trashFolder)) \(Self.quote(stem)) \(Self.quote(ext.isEmpty ? "" : "." + ext))")
            case .delete(let key, let path):
                lines.append("del \(key) \(Self.quote(path))")
            case .forgetReceipt(let key, let packageID):
                lines.append("forget \(key) \(Self.quote(packageID))")
            case .stopProcess(let key, let pid):
                lines.append("stop \(key) \(pid)")
            case .bootout(let label):
                lines.append("launchctl bootout \(Self.quote("system/" + label)) 2>/dev/null")
            case .refreshAudioUnits:
                lines.append("killall -9 AudioComponentRegistrar 2>/dev/null")
            }
        }
        lines.append("exit 0")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Reads the script's report: one result per step key.
    static func parse(_ output: String) -> [Int: StepResult] {
        var results: [Int: StepResult] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, fields[0] == Substring(marker), let key = Int(fields[2]) else { continue }
            let text = fields.count > 3 ? fields[3...].joined(separator: " ").trimmingCharacters(in: .whitespaces) : ""
            results[key] = fields[1] == "OK" ? .done(location: text.isEmpty ? nil : text) : .failed(message: text)
        }
        return results
    }

    /// Wraps text in single quotes for sh; the only character needing care is the quote itself.
    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
