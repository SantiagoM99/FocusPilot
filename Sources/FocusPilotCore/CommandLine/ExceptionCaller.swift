import Darwin
import Foundation
import Security

/// Who may ask for a site exception over the command socket (#14).
///
/// What `chromeHost(at:)` guarantees:
/// - The process on the other end of the connection runs exactly the
///   `focuspilot-chrome-host` code in this app bundle. It is looked up by the
///   connection's audit token (`LOCAL_PEERTOKEN`), which also pins the pid's
///   version, and checked against that binary's designated requirement (its
///   cdhash), so a copy, an edited binary or a reused pid fails.
/// - That process's parent is Google Chrome: code signed by Google's
///   Developer ID (Team ID EQHXZ8M8AV) with a Chrome channel identifier, as
///   Chrome's own designated requirement says.
///
/// The limits:
/// - The parent is found by pid, because nothing gives the app the parent's
///   audit token: Chrome talks to its host over plain pipes. The pid is read
///   only after the host itself is authenticated, and the parent's start time
///   must be the same before and after its signature is checked, so a
///   parent that exits and is replaced by another process is refused.
/// - It proves Chrome started the host, not that a person clicked: a process
///   of the owner's can start its own Chrome, load the extension and drive
///   it. Every new grant from Chrome is announced for that reason
///   (`FocusNotice.exceptionGrantedFromChrome`). Not tamper resistance.
public struct ExceptionCallerCheck: Sendable {
    public let allows: @Sendable (CommandPeer?) -> Bool

    public init(allows: @escaping @Sendable (CommandPeer?) -> Bool) {
        self.allows = allows
    }

    /// Google Chrome in any channel, as its designated requirement says.
    static let chromeRequirementText = """
        (identifier "com.google.Chrome" or identifier "com.google.Chrome.beta" or identifier "com.google.Chrome.dev" \
        or identifier "com.google.Chrome.canary") and anchor apple generic \
        and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] \
        and certificate leaf[subject.OU] = "EQHXZ8M8AV"
        """

    static func chromeRequirement() -> SecRequirement? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(chromeRequirementText as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// The bundled host at `host`, started by Google Chrome.
    public static func chromeHost(at host: URL) -> ExceptionCallerCheck {
        let hostRequirement = designatedRequirement(of: host).map(Unchecked.init)
        let chrome = chromeRequirement().map(Unchecked.init)
        return ExceptionCallerCheck { peer in
            guard let token = peer?.auditToken, let hostRequirement, let chrome,
                  let hostCode = code(for: token), SecCodeCheckValidity(hostCode, [], hostRequirement.value) == errSecSuccess,
                  let before = parent(of: CommandPeer.processID(of: token)), before.processID > 1,
                  let parentCode = code(forProcess: before.processID),
                  SecCodeCheckValidity(parentCode, [], chrome.value) == errSecSuccess
            else { return false }
            return parent(of: CommandPeer.processID(of: token)) == before
        }
    }

    /// The running code an audit token names.
    static func code(for token: [UInt32]) -> SecCode? {
        let data = token.withUnsafeBytes { Data($0) }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: data] as CFDictionary
        return SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess ? code : nil
    }

    private static func code(forProcess pid: pid_t) -> SecCode? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        return SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess ? code : nil
    }

    private static func designatedRequirement(of url: URL) -> SecRequirement? {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// A process's parent and when that parent started.
    private struct Parent: Equatable {
        var processID: pid_t
        var startSeconds: UInt64
        var startMicroseconds: UInt64
    }

    private static func parent(of pid: pid_t) -> Parent? {
        guard let child = bsdInfo(pid), let parent = bsdInfo(pid_t(child.pbi_ppid)) else { return nil }
        return Parent(processID: pid_t(child.pbi_ppid), startSeconds: parent.pbi_start_tvsec, startMicroseconds: parent.pbi_start_tvusec)
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    /// Security objects are thread-safe but not marked Sendable.
    private struct Unchecked<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }
}
