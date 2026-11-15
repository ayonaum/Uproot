import Foundation
import os

/// A directory waiting to be read, with what the walk knows about how it got there.
struct WalkDirectory: Sendable {
    var path: String
    /// How many more levels may be opened below this one. Zero means: read the entries, open nothing.
    var remainingDepth: Int
    /// Some ancestor folder is named after the vendor.
    var underVendor = false
    /// The nearest enclosing app or plug-in that does not itself match the search.
    var foreignBundle: String?
    /// The volume the walk started on; directories on other volumes are not entered.
    var device: dev_t = 0
}

enum EntryType: Sendable {
    case file, directory, symlink, other
}

/// Reads directory trees on several threads at once.
///
/// For each entry the walker calls `visit`, which decides whether the entry is worth
/// recording and whether a directory should be opened in turn.
final class ParallelWalker: @unchecked Sendable {
    /// Returns the directory to open next, or nil to leave the entry alone.
    /// `scratch` is a buffer the visitor may reuse; each worker thread has its own.
    typealias Visit = @Sendable (_ parent: WalkDirectory, _ name: UnsafeBufferPointer<UInt8>,
                                 _ type: EntryType, _ scratch: inout [UInt8]) -> WalkDirectory?

    struct Snapshot: Sendable {
        var entriesVisited = 0
        var currentPath = ""
    }

    private let visit: Visit
    private let onUnreadable: @Sendable (_ path: String, _ errno: Int32) -> Void
    private let threadCount: Int

    private let condition = NSCondition()
    private var pending: [WalkDirectory] = []
    private var activeWorkers = 0
    private var cancelled = false

    private let progress = OSAllocatedUnfairLock(initialState: Snapshot())

    init(threadCount: Int? = nil,
         visit: @escaping Visit,
         onUnreadable: @escaping @Sendable (_ path: String, _ errno: Int32) -> Void) {
        self.visit = visit
        self.onUnreadable = onUnreadable
        self.threadCount = max(1, threadCount ?? min(ProcessInfo.processInfo.activeProcessorCount, 8))
    }

    var snapshot: Snapshot { progress.withLock { $0 } }

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    /// Walks every root to the end, or until `cancel()`. Blocks the calling thread.
    func run(roots: [WalkDirectory]) {
        condition.lock()
        pending = roots.reversed()
        condition.unlock()
        DispatchQueue.concurrentPerform(iterations: threadCount) { _ in
            self.workerLoop()
        }
    }

    private func workerLoop() {
        // Never pull iCloud placeholders down from the network just to read their names.
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)

        var scratch = [UInt8]()
        scratch.reserveCapacity(256)
        var discovered: [WalkDirectory] = []

        while true {
            condition.lock()
            while pending.isEmpty && activeWorkers > 0 && !cancelled {
                condition.wait()
            }
            if cancelled || pending.isEmpty {
                condition.broadcast()
                condition.unlock()
                return
            }
            let directory = pending.removeLast()
            activeWorkers += 1
            condition.unlock()

            discovered.removeAll(keepingCapacity: true)
            let count = read(directory, scratch: &scratch, discovered: &discovered)
            progress.withLock {
                $0.entriesVisited += count
                $0.currentPath = directory.path
            }

            condition.lock()
            pending.append(contentsOf: discovered)
            activeWorkers -= 1
            condition.broadcast()
            condition.unlock()
        }
    }

    private func read(_ directory: WalkDirectory, scratch: inout [UInt8], discovered: inout [WalkDirectory]) -> Int {
        guard let handle = opendir(directory.path) else {
            let code = errno
            if code != ENOENT && code != ENOTDIR { onUnreadable(directory.path, code) }
            return 0
        }
        defer { closedir(handle) }

        var directory = directory
        var info = stat()
        if fstat(dirfd(handle), &info) == 0 {
            if directory.device == 0 {
                directory.device = info.st_dev
            } else if directory.device != info.st_dev {
                return 0
            }
        }

        var count = 0
        while let entry = readdir(handle) {
            let length = Int(entry.pointee.d_namlen)
            // Skip "." and "..".
            let first = entry.pointee.d_name.0
            if first == 0x2E && (length == 1 || (length == 2 && entry.pointee.d_name.1 == 0x2E)) { continue }
            count += 1

            var type: EntryType
            switch Int32(entry.pointee.d_type) {
            case DT_DIR: type = .directory
            case DT_REG: type = .file
            case DT_LNK: type = .symlink
            case DT_UNKNOWN: type = .other
            default: type = .other
            }

            let next: WalkDirectory? = withUnsafePointer(to: &entry.pointee.d_name) { tuple in
                tuple.withMemoryRebound(to: UInt8.self, capacity: length) { bytes in
                    if entry.pointee.d_type == DT_UNKNOWN {
                        var entryInfo = stat()
                        if fstatat(dirfd(handle), UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self),
                                   &entryInfo, AT_SYMLINK_NOFOLLOW) == 0 {
                            switch entryInfo.st_mode & S_IFMT {
                            case S_IFDIR: type = .directory
                            case S_IFREG: type = .file
                            case S_IFLNK: type = .symlink
                            default: type = .other
                            }
                        }
                    }
                    return visit(directory, UnsafeBufferPointer(start: bytes, count: length), type, &scratch)
                }
            }
            if var next {
                next.device = directory.device
                discovered.append(next)
            }
        }
        return count
    }
}
