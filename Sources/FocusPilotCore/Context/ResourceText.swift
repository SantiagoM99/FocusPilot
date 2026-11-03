import Foundation

/// What the Resources section and Open context say, in plain English.
public enum ResourceText {
    /// "~/Projects/nlp-report" for a path under the home folder.
    public static func path(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    public static func problem(_ problem: FolderProblem, home: String = NSHomeDirectory()) -> String {
        switch problem {
        case .missing: "Not found · deleted, or moved where FocusPilot can’t follow"
        case .volumeUnavailable(let disk): "On the disk “\(disk)”, which isn’t connected"
        case .replaced: "A different folder is at this path now"
        case .inTrash: "In the Trash"
        case .outsideRoot(_, let root): "Moved out of \(path(root, home: home))"
        }
    }

    public static func moved(to newPath: String, home: String = NSHomeDirectory()) -> String {
        "Moved to \(path(newPath, home: home))"
    }

    /// Whether the page's site is allowed in sessions, or stays blocked.
    public static func sessionNote(for page: WebPageLink, rules: [BlockRuleSet]) -> String {
        isBlocked(page, rules) ? "Blocked by your rules, also in this project’s sessions" : "Allowed in this project’s sessions"
    }

    /// Shown while linking a page a rule blocks.
    public static func blockedPageHelp(for page: WebPageLink, rules: [BlockRuleSet]) -> String? {
        isBlocked(page, rules)
            ? "Linking it doesn’t unblock it. When you need it during a session, ask for a timed exception on the blocked page."
            : nil
    }

    private static func isBlocked(_ page: WebPageLink, _ rules: [BlockRuleSet]) -> Bool {
        rules.flatMap(\.targets).contains(where: ActivityTarget.site(domain: page.domain).overlaps)
    }

    public static func launchResult(opened: Int, needingRepair names: [String], moved: [MovedFolder] = [],
                                    home: String = NSHomeDirectory()) -> String {
        let total = opened + names.count
        if total == 0 { return "Nothing to open. Choose what opens with this task in Resources." }
        var text = names.isEmpty
            ? "Opened \(opened) item\(opened == 1 ? "" : "s")."
            : "Opened \(opened) of \(total). \(list(names)) need\(names.count == 1 ? "s" : "") repair."
        for folder in moved {
            text += " “\(folder.name)” had moved; it opened from \(path(folder.path, home: home))."
        }
        return text
    }

    private static func list(_ names: [String]) -> String {
        let quoted = names.map { "“\($0)”" }
        return quoted.count <= 2 ? quoted.joined(separator: " and ")
            : quoted.dropLast().joined(separator: ", ") + " and " + quoted.last!
    }
}
