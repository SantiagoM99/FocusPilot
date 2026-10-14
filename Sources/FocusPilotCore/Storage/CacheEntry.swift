import Foundation
import GRDB

/// A derived value stored in the cache database under a caller-chosen key.
struct CacheEntry: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cacheEntry"

    var key: String
    var value: Data
}
