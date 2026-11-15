import Foundation

/// Runs command-line tools that ship with macOS.
enum Shell {
    struct Output: Sendable {
        var status: Int32
        var stdout: String
        var stderr: String
        var succeeded: Bool { status == 0 }
    }

    /// Runs a tool to completion. Returns nil when it cannot be launched.
    ///
    /// A tool still running after `timeout` seconds is killed, so that one stuck `hdiutil` or
    /// `diskutil` cannot hold a scan or a removal for ever; its status then says it did not succeed.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], input: Data? = nil, timeout: TimeInterval = 120) -> Output? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let stdin = input == nil ? nil : Pipe()
        process.standardInput = stdin ?? FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        let pid = process.processIdentifier
        let watchdog = DispatchWorkItem { kill(pid, SIGKILL) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }

        if let stdin, let input {
            // A tool that exits without reading must cost an error, not a signal or an exception.
            _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }

        // Drain both pipes while the tool runs, or a chatty tool blocks on a full pipe.
        let errData = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData.value = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return Output(status: process.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData.value, as: UTF8.self))
    }
}

/// Carries bytes out of the reader thread; the group's wait orders the two accesses.
private final class DataBox: @unchecked Sendable {
    var value = Data()
}
