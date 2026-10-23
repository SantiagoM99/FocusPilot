import Foundation

/// Chrome native messaging framing: a 32-bit length in native byte order
/// (little-endian on Apple silicon and Intel Macs) followed by UTF-8 JSON.
/// https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
public enum NativeMessageFrame {
    public enum Failure: Error, Equatable {
        case tooLarge
    }

    /// Chrome refuses host messages over 1 MB.
    public static let maxOutgoing = 1024 * 1024
    /// Chrome sends at most 64 MiB; anything longer is a broken stream.
    public static let maxIncoming = 64 * 1024 * 1024

    public static func encode(_ body: Data) throws -> Data {
        guard body.count <= maxOutgoing else { throw Failure.tooLarge }
        return withUnsafeBytes(of: UInt32(body.count).littleEndian) { Data($0) } + body
    }
}

/// Splits Chrome's stdin into message bodies, however the bytes arrive.
public struct NativeMessageReader: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var messages: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            guard length <= NativeMessageFrame.maxIncoming else { throw NativeMessageFrame.Failure.tooLarge }
            guard buffer.count >= 4 + length else { break }
            messages.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(4 + length))
        }
        return messages
    }
}
