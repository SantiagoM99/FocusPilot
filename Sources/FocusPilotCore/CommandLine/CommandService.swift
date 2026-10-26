import Foundation

/// A request over the command socket, one per connection: from the
/// focuspilot CLI, or an exception request the Chrome host relays from the
/// blocked page (#14).
public enum CommandRequest: Codable, Equatable, Sendable {
    case add(HerdrAddRequest)
    case tasks(HerdrCaller?)
    case exception(ExceptionCommand)
    /// The owner left a strict-session exception wait for this scope.
    case cancelException(ExceptionScope)
}

/// A timed exception as the blocked page asks for it.
public struct ExceptionCommand: Codable, Equatable, Sendable {
    public var scope: ExceptionScope
    public var duration: TimeInterval
    public var reason: String?
    public var confirmed: Bool

    public init(scope: ExceptionScope, duration: TimeInterval, reason: String?, confirmed: Bool) {
        self.scope = scope
        self.duration = duration
        self.reason = reason
        self.confirmed = confirmed
    }
}

public enum CommandResponse: Codable, Equatable, Sendable {
    case added(HerdrAddResult)
    case tasks(HerdrTaskScope)
    case exception(ExceptionOutcome)
    case exceptionCancelled
    /// Not done, with a message for the caller, e.g. the rate limit.
    case refused(String)
    case failed(String)
}

/// At most `limit` adds per pane in any `window`, so an agent stuck in a
/// loop cannot flood the owner's list. Only allowed adds count.
public struct AddRateLimit: Sendable {
    public static let limit = 20
    public static let window: TimeInterval = 60

    private var recent: [String: [Date]] = [:]

    public init() {}

    /// Records the add and returns true if it is within the limit. Panes
    /// with no add in the last window are forgotten, so closed panes do not
    /// pile up for as long as the app runs.
    public mutating func allow(_ pane: String, at now: Date) -> Bool {
        recent = recent.compactMapValues { times in
            let kept = times.filter { now.timeIntervalSince($0) < Self.window }
            return kept.isEmpty ? nil : kept
        }
        let kept = recent[pane] ?? []
        guard kept.count < Self.limit else { return false }
        recent[pane] = kept + [now]
        return true
    }

    var trackedPanes: Int { recent.count }

    /// The key adds are counted under; every add from outside Herdr shares one.
    public static func key(for caller: HerdrCaller?) -> String {
        caller?.paneID ?? "outside Herdr"
    }
}

/// Where exception requests go: the coordinator, which applies the
/// strict-session confirmation and wait.
public protocol ExceptionGate: Sendable {
    func requestException(_ scope: ExceptionScope, duration: TimeInterval, reason: String?, confirmed: Bool) async throws -> ExceptionOutcome
    func cancelException(for scope: ExceptionScope) async
}

extension FocusCoordinator: ExceptionGate {}

/// Answers command-socket requests inside the running app. CLI callers can
/// only append tasks and read; everything written goes through
/// `TaskRepository`. Exception requests are taken only from the Chrome host
/// bundled with the app, identified by its executable, and only while Chrome
/// started it, so an agent with the focuspilot command, or one that runs the
/// host from a shell, cannot grant itself one. That is a hurdle, not tamper
/// resistance (an agent could start its own Chrome); every grant from Chrome
/// is therefore also announced to the owner (see AppModel).
public actor CommandService {
    static let rateLimitMessage =
        "Refused: this pane has added \(AddRateLimit.limit) tasks in the last minute. Wait a minute and try again."
    static let exceptionCallerMessage = "Only the FocusPilot blocked page in Chrome can ask for a site exception."

    private let repository: TaskRepository
    private let exceptions: (any ExceptionGate)?
    /// The Chrome host's executable path; nil refuses every exception request.
    private let exceptionCaller: String?
    private let now: @Sendable () -> Date
    private var rateLimit = AddRateLimit()

    public init(repository: TaskRepository, exceptions: (any ExceptionGate)? = nil, exceptionCaller: String? = nil,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.repository = repository
        self.exceptions = exceptions
        self.exceptionCaller = exceptionCaller.map(Self.resolved)
        self.now = now
    }

    public func handle(_ request: CommandRequest, from peer: CommandPeer? = nil) async -> CommandResponse {
        switch request {
        case .exception(let command):
            guard let exceptions = gate(for: peer) else { return .refused(Self.exceptionCallerMessage) }
            do {
                return .exception(try await exceptions.requestException(command.scope, duration: command.duration,
                                                                        reason: command.reason, confirmed: command.confirmed))
            } catch let error as ExceptionError {
                return .refused(ExceptionErrorText.message(error))
            } catch {
                return .failed("FocusPilot could not allow it: \(error.localizedDescription)")
            }
        case .cancelException(let scope):
            guard let exceptions = gate(for: peer) else { return .refused(Self.exceptionCallerMessage) }
            await exceptions.cancelException(for: scope)
            return .exceptionCancelled
        case .add(let add):
            guard add.capture.task.isValid else { return .refused("Nothing to add: the task needs a title.") }
            guard rateLimit.allow(AddRateLimit.key(for: add.caller), at: now()) else {
                return .refused(Self.rateLimitMessage)
            }
            do {
                return .added(try await repository.addFromHerdr(add))
            } catch {
                return .failed("FocusPilot could not save the task: \(error.localizedDescription)")
            }
        case .tasks(let caller):
            do {
                return .tasks(try await repository.herdrScope(for: caller))
            } catch {
                return .failed("FocusPilot could not read the tasks: \(error.localizedDescription)")
            }
        }
    }

    private func gate(for peer: CommandPeer?) -> (any ExceptionGate)? {
        guard let exceptions, let exceptionCaller, let path = peer?.executablePath, Self.resolved(path) == exceptionCaller,
              let parent = peer?.parentExecutablePath, Self.isChrome(parent) else { return nil }
        return exceptions
    }

    /// Google Chrome and its Beta, Dev and Canary channels.
    static func isChrome(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard parts.count >= 4, parts[parts.count - 3] == "Contents", parts[parts.count - 2] == "MacOS" else { return false }
        let app = parts[parts.count - 4]
        return app.hasPrefix("Google Chrome") && app.hasSuffix(".app")
    }

    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}

/// What an exception refusal says, on the blocked page and in the app.
public enum ExceptionErrorText {
    public static func message(_ error: ExceptionError) -> String {
        switch error {
        case .unsupportedDuration: "Choose 5, 10 or 20 minutes."
        case .reasonRequired: "Say why you need it for the task."
        case .invalidSite: "That isn't a site address."
        case .invalidPage: "That isn't a web page address."
        case .notBlocked(let host): "\(host) isn't blocked by any rule."
        }
    }
}
