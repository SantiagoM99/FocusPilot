// Throwaway spike for issue #1. A command-line stand-in for the appex: signed ad hoc with the
// same sandbox entitlements, so scripts/check.sh can test shared-store access without Safari.
import Foundation

let report = SharedStore.probeAll().map { $0.1.dictionary }
let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
let out: [String: Any] = ["sandboxed": sandboxed, "home": NSHomeDirectory(), "stores": report]
print(String(data: try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
