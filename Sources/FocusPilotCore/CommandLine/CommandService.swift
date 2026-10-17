import Foundation

/// A focuspilot CLI request, one per connection.
public enum CommandRequest: Codable, Equatable, Sendable {
    case add(HerdrAddRequest)
    case tasks(HerdrCaller?)
}

public enum CommandResponse: Codable, Equatable, Sendable {
    case added(HerdrAddResult)
    case tasks(HerdrTaskScope)
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

/// Answers CLI requests inside the running app. It can only append tasks and
/// read; everything it writes goes through `TaskRepository`.
public actor CommandService {
    static let rateLimitMessage =
        "Refused: this pane has added \(AddRateLimit.limit) tasks in the last minute. Wait a minute and try again."

    private let repository: TaskRepository
    private let now: @Sendable () -> Date
    private var rateLimit = AddRateLimit()

    public init(repository: TaskRepository, now: @escaping @Sendable () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    public func handle(_ request: CommandRequest) async -> CommandResponse {
        switch request {
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
}
