import Foundation
import FocusPilotCore

let outcome = FocusPilotCommand(location: .applicationSupport(), environment: ProcessInfo.processInfo.environment,
                                now: .now, timeZone: .current)
    .run(Array(CommandLine.arguments.dropFirst()))
FileHandle.standardOutput.write(Data(outcome.output.utf8))
FileHandle.standardError.write(Data(outcome.error.utf8))
exit(outcome.status)
