import Foundation
import GRDB

/// A block rule set as stored; targets and activation are JSON.
struct RuleSetRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "blockRuleSet"

    var id: Int64?
    var targets: String
    var activation: String
    var revision: Int

    init(_ rule: BlockRuleSet) throws {
        id = rule.id
        targets = try JSONCoding.string(rule.targets)
        activation = try JSONCoding.string(rule.activation)
        revision = rule.revision
    }

    func rule() throws -> BlockRuleSet {
        BlockRuleSet(id: id, targets: try JSONCoding.value(targets), activation: try JSONCoding.value(activation), revision: revision)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// An allowed app, site or tool as stored. `targetKey` is unique, so the
/// same site or app cannot be allowed twice.
struct AllowedRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "allowedActivity"

    var id: Int64?
    var name: String
    var target: String
    var targetKey: String
    var source: String

    init(_ entry: AllowedActivity) throws {
        id = entry.id
        name = entry.name
        target = try JSONCoding.string(entry.target)
        targetKey = entry.target.key
        source = entry.source.rawValue
    }

    func entry() throws -> AllowedActivity {
        AllowedActivity(id: id, name: name, target: try JSONCoding.value(target), source: AllowedActivity.Source(rawValue: source) ?? .owner)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

enum JSONCoding {
    static func string(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func value<T: Decodable>(_ text: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }
}

/// The tools allowed on a fresh install (EXPERIENCE: seeded allowed list).
/// Herdr runs inside a terminal, so it is a command, not an app.
enum SeededAllowedList {
    static let entries = [
        AllowedActivity(name: "Finder", target: .app(bundleID: "com.apple.finder", name: "Finder"), source: .seeded),
        AllowedActivity(name: "Terminal", target: .app(bundleID: "com.apple.Terminal", name: "Terminal"), source: .seeded),
        AllowedActivity(name: "System Settings", target: .app(bundleID: "com.apple.systempreferences", name: "System Settings"), source: .seeded),
        AllowedActivity(name: "Overleaf", target: .site(domain: "overleaf.com"), source: .seeded),
        AllowedActivity(name: "Herdr", target: .tool(command: "herdr"), source: .seeded),
    ]
}
