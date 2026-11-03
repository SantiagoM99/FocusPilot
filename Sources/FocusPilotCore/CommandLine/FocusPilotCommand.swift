import Foundation

/// The `focuspilot` command: adds a task, reads tasks, or sends the owner a
/// report from a Herdr pane.
///
/// It never writes the database itself. Adds and reports go to the running
/// app over the owner-only socket, or into the inbox when the app is closed.
/// There is no command that changes Now, the order, deadlines or an existing
/// task, and a report's proposed message is sent only if the owner accepts.
public struct FocusPilotCommand: Sendable {
    public struct Outcome: Equatable, Sendable {
        public var status: Int32
        public var output = ""
        public var error = ""
    }

    public static let usage = """
        Usage:
          focuspilot add [--json] [--] <text>
                                           Add a task to the end of Next, marked from Herdr.
                                           A trailing deadline is read like quick capture:
                                           focuspilot add "Re-run ablation by fri 23:59"
                                           Options go before the text; after -- everything is text.
          focuspilot tasks [--json]        Show the owner's Now and this workspace's project.
          focuspilot report [--json] --summary <text> [--project <name>] [--from <name>]
                            [--to <agent> --message <text>]
                                           Tell the owner what happened, in plain words. With
                                           --to and --message, propose the exact message to send
                                           to that Herdr agent (name or pane ID) if they accept.

        Tasks go to the project linked to this Herdr workspace, or to No project.
        focuspilot cannot change Now, the order, deadlines or existing tasks.

        """

    private let location: StorageLocation
    private let environment: [String: String]
    private let now: Date
    private let timeZone: TimeZone
    private let socketCreationDate: @Sendable (URL) -> Date?

    public init(location: StorageLocation, environment: [String: String], now: Date, timeZone: TimeZone,
                socketCreationDate: @escaping @Sendable (URL) -> Date? = {
                    try? FileManager.default.attributesOfItem(atPath: $0.path)[.creationDate] as? Date
                }) {
        self.location = location
        self.environment = environment
        self.now = now
        self.timeZone = timeZone
        self.socketCreationDate = socketCreationDate
    }

    public func run(_ arguments: [String]) -> Outcome {
        switch arguments.first {
        case "add":
            guard let (json, text) = Self.options(before: arguments.dropFirst()) else {
                return Outcome(status: 2, error: Self.usage)
            }
            return add(text.joined(separator: " "), json: json)
        case "report":
            guard let fields = Self.reportFields(arguments.dropFirst()) else { return Outcome(status: 2, error: Self.usage) }
            return report(fields)
        case "tasks":
            guard let (json, rest) = Self.options(before: arguments.dropFirst()), rest.isEmpty else {
                return Outcome(status: 2, error: Self.usage)
            }
            return tasks(json: json)
        case "help", "--help", "-h": return Outcome(status: 0, output: Self.usage)
        default: return Outcome(status: 2, error: Self.usage)
        }
    }

    /// Reads options up to the first word that is not one, or up to `--`;
    /// the rest is the task text, kept as typed even if it contains
    /// "--json". Nil for an unknown option.
    private static func options(before arguments: ArraySlice<String>) -> (json: Bool, rest: ArraySlice<String>)? {
        var json = false
        var rest = arguments
        while let word = rest.first, word.hasPrefix("-") {
            rest = rest.dropFirst()
            switch word {
            case "--": return (json, rest)
            case "--json": json = true
            default: return nil
            }
        }
        return (json, rest)
    }

    // MARK: add

    private func add(_ text: String, json: Bool) -> Outcome {
        let request = HerdrAddRequest(text: text, capturedAt: now, timeZone: timeZone, caller: caller)
        guard request.capture.task.isValid else {
            return Outcome(status: 2, error: "Nothing to add: the task needs a title.\n\n" + Self.usage)
        }
        do {
            switch try CommandSocketClient(path: location.commandSocketPath).send(.add(request)) {
            case .added(let result): return added(result, json: json)
            case .refused(let message), .failed(let message): return Outcome(status: 1, error: message + "\n")
            case .tasks, .exception, .exceptionCancelled, .reported: return Outcome(status: 1, error: "FocusPilot gave an unexpected answer.\n")
            }
        } catch .pathTooLong {
            return Outcome(status: 1, error: "The FocusPilot data folder path is too long for its socket.\n")
        } catch {
            // Not running, or no reply: queue it. If the app did save it, the
            // request ID keeps the import from adding it twice.
            return queue(request, json: json)
        }
    }

    private func added(_ result: HerdrAddResult, json: Bool) -> Outcome {
        if json {
            return Outcome(status: 0, output: Self.json([
                "status": result.wasAlreadyAdded ? "alreadyAdded" : "added", "title": result.title,
                "project": result.projectTitle ?? NSNull(), "deadline": result.deadlineDescription ?? NSNull(),
                "hints": result.hints,
            ]))
        }
        let place = result.projectTitle.map { "in \($0)" } ?? "under No project"
        var lines = [result.wasAlreadyAdded
            ? "Already added: “\(result.title)” is in Next \(place), marked from Herdr."
            : "Added “\(result.title)” to the end of Next \(place), marked from Herdr."]
        if let deadline = result.deadlineDescription { lines.append("Deadline: \(deadline)") }
        if result.workspaceHasNoProject { lines.append("This Herdr workspace has no linked project in FocusPilot.") }
        if caller == nil { lines.append("Not run from a Herdr pane, so no project was chosen.") }
        lines += result.hints.map { "Note: \($0)" }
        return Outcome(status: 0, output: lines.joined(separator: "\n") + "\n")
    }

    private func queue(_ request: HerdrAddRequest, json: Bool) -> Outcome {
        do {
            try location.inbox.enqueue(request)
        } catch TaskInbox.Refusal.rateLimited {
            return Outcome(status: 1, error: CommandService.rateLimitMessage + "\n")
        } catch {
            return Outcome(status: 1, error: "FocusPilot is not running and the task could not be queued: \(error.localizedDescription)\n")
        }
        let (task, hints) = request.capture
        if json {
            return Outcome(status: 0, output: Self.json(["status": "queued", "title": task.title, "hints": hints]))
        }
        let lines = ["FocusPilot is not running. Queued “\(task.title)”; it will be added when FocusPilot starts."]
            + hints.map { "Note: \($0)" }
        return Outcome(status: 0, output: lines.joined(separator: "\n") + "\n")
    }

    // MARK: report

    struct ReportFields {
        var json = false
        var values: [String: String] = [:]
    }

    /// `--summary` is required; every option but `--json` takes one value,
    /// given once. Nil for anything else, including loose words.
    static func reportFields(_ arguments: ArraySlice<String>) -> ReportFields? {
        let named: Set = ["--summary", "--project", "--from", "--to", "--message"]
        var fields = ReportFields()
        var rest = arguments
        while let word = rest.first {
            rest = rest.dropFirst()
            if word == "--json" { fields.json = true; continue }
            guard named.contains(word), let value = rest.first, fields.values[word] == nil else { return nil }
            fields.values[word] = value
            rest = rest.dropFirst()
        }
        return fields.values["--summary"] == nil ? nil : fields
    }

    private func report(_ fields: ReportFields) -> Outcome {
        let request = ReportRequest(summary: fields.values["--summary"]!, project: fields.values["--project"],
                                    to: fields.values["--to"], message: fields.values["--message"], from: fields.values["--from"],
                                    sentAt: now, caller: caller)
        if let problem = request.problem { return Outcome(status: 1, error: "Refused: \(problem)\n") }
        do {
            switch try CommandSocketClient(path: location.commandSocketPath).send(.report(request)) {
            case .reported(let receipt): return reported(receipt, request, json: fields.json)
            case .refused(let message), .failed(let message):
                return Outcome(status: 1, error: (message.hasPrefix("Refused") ? message : "Refused: " + message) + "\n")
            case .added, .tasks, .exception, .exceptionCancelled: return Outcome(status: 1, error: "FocusPilot gave an unexpected answer.\n")
            }
        } catch .pathTooLong {
            return Outcome(status: 1, error: "The FocusPilot data folder path is too long for its socket.\n")
        } catch {
            do {
                try location.inbox.enqueue(request)
            } catch TaskInbox.Refusal.rateLimited {
                return Outcome(status: 1, error: CommandService.reportRateLimitMessage + "\n")
            } catch {
                return Outcome(status: 1, error: "FocusPilot is not running and the report could not be queued: \(error.localizedDescription)\n")
            }
            if fields.json { return Outcome(status: 0, output: Self.json(["status": "queued"])) }
            return Outcome(status: 0, output: "FocusPilot is not running. The report is queued and reaches the owner when FocusPilot starts.\n")
        }
    }

    private func reported(_ receipt: ReportReceipt, _ request: ReportRequest, json: Bool) -> Outcome {
        if json {
            return Outcome(status: 0, output: Self.json([
                "status": receipt.wasAlreadyReceived ? "alreadyReported" : "reported", "project": receipt.projectTitle ?? NSNull(),
                "targetProblem": receipt.targetProblem ?? NSNull(), "notes": receipt.notes,
            ]))
        }
        let place = receipt.projectTitle.map { ", in \($0)" } ?? ", with no project"
        var lines = [receipt.wasAlreadyReceived ? "Already reported\(place)." : "Reported to FocusPilot\(place). The owner sees it in Needs you."]
        if let to = request.to {
            lines.append(receipt.targetProblem.map { "Note: \($0)" }
                ?? "If they accept, FocusPilot sends your message to \(to), exactly as written.")
        }
        lines += receipt.notes.map { "Note: \($0)" }
        return Outcome(status: 0, output: lines.joined(separator: "\n") + "\n")
    }

    // MARK: tasks

    private func tasks(json: Bool) -> Outcome {
        let scope: HerdrTaskScope
        do {
            switch try CommandSocketClient(path: location.commandSocketPath).send(.tasks(caller)) {
            case .tasks(let answer): scope = answer
            case .refused(let message), .failed(let message): return Outcome(status: 1, error: message + "\n")
            case .added, .exception, .exceptionCancelled, .reported: return Outcome(status: 1, error: "FocusPilot gave an unexpected answer.\n")
            }
        } catch .pathTooLong {
            return Outcome(status: 1, error: "The FocusPilot data folder path is too long for its socket.\n")
        } catch {
            return json ? Outcome(status: 3, output: Self.json(["running": false]))
                : Outcome(status: 3, error: "FocusPilot is not running, so tasks can’t be read.\n")
        }
        if json {
            return Outcome(status: 0, output: Self.json([
                "running": true, "now": scope.now.map(Self.dictionary) ?? NSNull(),
                "project": scope.projectTitle ?? NSNull(), "tasks": scope.tasks.map(Self.dictionary),
            ]))
        }
        var lines: [String] = []
        if let now = scope.now {
            lines.append("Now: \(now.title)")
            if let action = now.nextAction { lines.append("  Next action: \(action)") }
            if let deadline = now.deadline { lines.append("  Due \(deadline)") }
        } else {
            lines.append("Now: nothing pinned")
        }
        lines.append("")
        if let project = scope.projectTitle {
            lines.append("\(project) (this workspace’s project)")
            if scope.tasks.isEmpty { lines.append("  No open tasks") }
            for task in scope.tasks {
                let details = [task.deadline.map { "due \($0)" }, task.isFromHerdr ? "from Herdr" : nil].compactMap(\.self)
                let status = task.status.rawValue.capitalized.padding(toLength: 6, withPad: " ", startingAt: 0)
                lines.append("  \(status) " + ([task.title] + details).joined(separator: " · "))
            }
        } else if caller == nil {
            lines.append("Not run from a Herdr pane, so only Now is shown.")
        } else {
            lines.append("This Herdr workspace has no linked project in FocusPilot, so only Now is shown.")
        }
        return Outcome(status: 0, output: lines.joined(separator: "\n") + "\n")
    }

    // MARK: Helpers

    /// The pane this command runs in, from the variables Herdr exports into
    /// its panes. The server is identified like `HerdrCLI` does, by its
    /// socket's creation time.
    private var caller: HerdrCaller? {
        guard let workspace = environment["HERDR_WORKSPACE_ID"], !workspace.isEmpty else { return nil }
        let home = environment["HOME"] ?? NSHomeDirectory()
        let socket = environment["HERDR_SOCKET_PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config/herdr/herdr.sock"
        guard let startedAt = socketCreationDate(URL(fileURLWithPath: socket)) else { return nil }
        let server = HerdrServer(sessionName: environment["HERDR_SESSION"] ?? "default", socketPath: socket, startedAt: startedAt)
        return HerdrCaller(server: server, workspaceID: workspace, paneID: environment["HERDR_PANE_ID"])
    }

    private static func dictionary(_ task: HerdrScopedTask) -> [String: Any] {
        ["title": task.title, "status": task.status.rawValue, "nextAction": task.nextAction ?? NSNull(),
         "deadline": task.deadline ?? NSNull(), "fromHerdr": task.isFromHerdr]
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
