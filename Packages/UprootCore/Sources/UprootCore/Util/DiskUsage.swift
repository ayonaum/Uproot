import Foundation

/// Measures how much disk space files and folders take.
public enum DiskUsage {
    /// Space allocated to the item and everything inside it, in bytes. Stays on the item's volume
    /// and does not follow links.
    public static func allocatedSize(atPath path: String) -> Int64 {
        var info = stat()
        guard lstat(path, &info) == 0 else { return 0 }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { return Int64(info.st_blocks) * 512 }

        guard let cPath = strdup(path) else { return 0 }
        defer { free(cPath) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let stream = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return 0 }
        defer { fts_close(stream) }

        var total: Int64 = 0
        while let entry = fts_read(stream) {
            switch Int32(entry.pointee.fts_info) {
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT, FTS_D:
                if let status = entry.pointee.fts_statp {
                    total += Int64(status.pointee.st_blocks) * 512
                }
            default:
                break
            }
        }
        return total
    }

    /// Sizes of many items at once, measured in parallel. Items that are not on disk are left out.
    public static func sizes(of items: [FoundItem]) async -> [String: Int64] {
        let onDisk = items.filter(\.isOnDisk)
        return await withTaskGroup(of: (String, Int64).self) { group in
            var pending = onDisk.makeIterator()
            var running = 0
            var result: [String: Int64] = [:]
            let limit = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)

            func startNext() {
                guard let item = pending.next() else { return }
                running += 1
                group.addTask { (item.id, allocatedSize(atPath: item.path)) }
            }
            for _ in 0..<limit { startNext() }
            while running > 0, let (id, size) = await group.next() {
                running -= 1
                result[id] = size
                if Task.isCancelled { group.cancelAll(); break }
                startNext()
            }
            return result
        }
    }
}
