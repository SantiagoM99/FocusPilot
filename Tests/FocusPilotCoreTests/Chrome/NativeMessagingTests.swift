import Foundation
import Testing
@testable import FocusPilotCore

@Suite("Chrome native messaging frames")
struct NativeMessagingTests {
    @Test func framesAreALittleEndianLengthThenTheJSON() throws {
        let frame = try NativeMessageFrame.encode(Data(#"{"a":1}"#.utf8))

        #expect(Array(frame.prefix(4)) == [7, 0, 0, 0])
        #expect(frame.dropFirst(4) == Data(#"{"a":1}"#.utf8))
    }

    @Test func messagesOverOneMegabyteAreNotSent() {
        #expect(throws: NativeMessageFrame.Failure.tooLarge) {
            try NativeMessageFrame.encode(Data(count: NativeMessageFrame.maxOutgoing + 1))
        }
    }

    @Test func readerReassemblesSplitAndJoinedFrames() throws {
        var reader = NativeMessageReader()
        let joined = try NativeMessageFrame.encode(Data("one".utf8)) + NativeMessageFrame.encode(Data("two".utf8))

        #expect(try reader.append(joined.prefix(5)) == [])
        #expect(try reader.append(joined.dropFirst(5)) == [Data("one".utf8), Data("two".utf8)])
    }

    @Test func absurdLengthsAreRefused() {
        var reader = NativeMessageReader()

        #expect(throws: NativeMessageFrame.Failure.tooLarge) {
            try reader.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        }
    }
}
