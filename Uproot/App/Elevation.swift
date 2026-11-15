import Foundation
import UprootCore

/// Administrator rights by way of the standard macOS password prompt.
///
/// The app starts a second copy of itself in helper mode. That copy runs one line of
/// AppleScript, `do shell script … with administrator privileges`, which is what puts up
/// the prompt, and hands the script's output back. Doing this in a separate process keeps
/// the window responsive while the prompt is open and while root is at work.
enum ElevationHelper {
    /// Launch argument that puts the executable in helper mode.
    static let flag = "--uproot-run-privileged"

    private static let cancelledExitCode: Int32 = 3
    /// The shell script travels inside a command line, which macOS caps at about a megabyte.
    private static let scriptLimit = 400_000

    /// Body of the helper process: read the script from standard input, run it as root, print what it printed.
    static func runAndExit() -> Never {
        // The helper works for the app that started it and for nothing else. Without this check
        // any program on the machine could feed it a script of its own and have macOS ask for
        // the administrator's password in Uproot's name.
        guard let own = executablePath(of: getpid()), own == executablePath(of: getppid()) else {
            FileHandle.standardError.write(Data("Режим помощника запускает только само приложение Uproot.".utf8))
            exit(1)
        }
        let script = FileHandle.standardInput.readDataToEndOfFile()
        var error: NSDictionary?
        let result = NSAppleScript(source: appleScript(running: script))?.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -128: the user pressed Cancel in the password prompt.
            if number == -128 { exit(cancelledExitCode) }
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(number)"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
        FileHandle.standardOutput.write(Data((result?.stringValue ?? "").utf8))
        exit(0)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// AppleScript that feeds `script` to a root shell. The script is base64-encoded, so no
    /// file name in it can break out of the AppleScript or shell quoting.
    static func appleScript(running script: Data) -> String {
        let prompt = "Uproot нужны права администратора, чтобы удалить выбранные объекты."
        let command = "/bin/echo \(script.base64EncodedString()) | /usr/bin/base64 -D | /bin/sh"
        return "do shell script \"\(command)\" with prompt \"\(prompt)\" with administrator privileges without altering line endings"
    }

    /// The elevator the app hands to the remover.
    struct Elevator: PrivilegeElevator {
        func runAsRoot(script: String) async throws -> String {
            guard let executable = Bundle.main.executableURL else {
                throw ElevationError.failed("Не удалось найти исполняемый файл приложения.")
            }
            guard script.utf8.count < scriptLimit else {
                throw ElevationError.failed("Слишком много объектов для одной операции. Удалите их в два приёма.")
            }
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = [flag]
                    let input = Pipe(), output = Pipe(), errors = Pipe()
                    process.standardInput = input
                    process.standardOutput = output
                    process.standardError = errors
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: ElevationError.failed(error.localizedDescription))
                        return
                    }
                    // Should the helper die before it reads, the write must fail quietly: by default
                    // it would raise SIGPIPE or an Objective-C exception and take the app down.
                    _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                    try? input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
                    try? input.fileHandleForWriting.close()
                    let printed = output.fileHandleForReading.readDataToEndOfFile()
                    let complaint = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    // A helper killed by signal 3 is not a helper that exited with code 3.
                    switch (process.terminationReason, process.terminationStatus) {
                    case (.exit, 0):
                        continuation.resume(returning: String(decoding: printed, as: UTF8.self))
                    case (.exit, cancelledExitCode):
                        continuation.resume(throwing: ElevationError.cancelled)
                    default:
                        continuation.resume(throwing: ElevationError.failed(String(decoding: complaint, as: UTF8.self)))
                    }
                }
            }
        }
    }
}
