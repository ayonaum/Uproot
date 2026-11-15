import Foundation

extension String {
    /// Reads a C string out of a fixed buffer, stopping at the first zero byte.
    init(nullTerminated buffer: [CChar]) {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self.init(decoding: bytes, as: UTF8.self)
    }
}
