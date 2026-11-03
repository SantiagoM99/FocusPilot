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
        case .missing: "Not found"
        case .volumeUnavailable(let disk): "Disk “\(disk)” not connected"
        case .replaced: "A different folder is at this path now"
        case .inTrash: "In the Trash"
        case .outsideRoot(_, let root): "Moved out of \(path(root, home: home))"
        }
    }

    public static func moved(to newPath: String, home: String = NSHomeDirectory()) -> String {
        "Moved to \(path(newPath, home: home))"
    }

    /// When the page opens: a blocked site's page only in normal sessions
    /// (owner decision 0003, 2026-11-03).
    public static func sessionNote(for page: WebPageLink, rules: [BlockRuleSet]) -> String {
        blockingRule(page, rules) == nil ? "Allowed in this project’s sessions"
            : "This page opens in normal sessions · Blocked in strict sessions — ask for an exception"
    }

    /// The blocked site the page is on, as the rule names it.
    private static func blockingRule(_ page: WebPageLink, _ rules: [BlockRuleSet]) -> String? {
        rules.flatMap(\.targets).first(where: ActivityTarget.site(domain: page.domain).overlaps)?.displayName
    }

    /// What Open context did: items that need repair were never tried;
    /// items that were tried and did not open are named after them.
    public static func launchResult(opened: Int, needingRepair names: [String], failed: [String] = [],
                                    moved: [MovedFolder] = [], home: String = NSHomeDirectory()) -> String {
        let total = opened + names.count + failed.count
        if total == 0 { return "Nothing to open" }
        var text = total == opened ? "Opened \(opened) item\(opened == 1 ? "" : "s")." : "Opened \(opened) of \(total)."
        if !names.isEmpty { text += " \(list(names)) need\(names.count == 1 ? "s" : "") repair." }
        if !failed.isEmpty { text += " \(list(failed)) didn’t open." }
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
