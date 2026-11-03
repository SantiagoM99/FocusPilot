import Foundation
import GRDB

/// A linked folder or web page as stored. Exactly one of `taskId` and
/// `projectId` is set, and the columns of its kind (CHECKs in `OwnerSchema`).
struct ResourceRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "resource"

    var id: Int64?
    var taskId: Int64?
    var projectId: Int64?
    var kind: String
    var url: String?
    var bookmark: Data?
    var path: String?
    var inode: Int64?
    var volumeUUID: String?
    var root: String?
    var launchOrder: Int?
    var createdAt: Date

    init(owner: ResourceOwner, target: ResourceTarget, createdAt: Date) {
        switch owner {
        case .task(let id): taskId = id
        case .project(let id): projectId = id
        }
        kind = ""
        self.createdAt = createdAt
        set(target)
    }

    mutating func set(_ target: ResourceTarget) {
        switch target {
        case .folder(let folder):
            kind = "folder"
            bookmark = folder.data
            path = folder.path
            inode = Int64(bitPattern: folder.inode)
            volumeUUID = folder.volumeUUID
            root = folder.root
        case .webPage(let page):
            kind = "webPage"
            url = page.url
        }
    }

    var resource: ContextResource {
        let target: ResourceTarget = if kind == "folder" {
            .folder(FolderBookmark(data: bookmark ?? Data(), path: path ?? "", inode: UInt64(bitPattern: inode ?? 0),
                                   volumeUUID: volumeUUID, root: root))
        } else {
            .webPage(WebPageLink(stored: url ?? ""))
        }
        return ContextResource(id: id!, owner: taskId.map(ResourceOwner.task) ?? .project(projectId!), target: target,
                               launchOrder: launchOrder, createdAt: createdAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension WebPageLink {
    /// A URL validated when it was linked.
    init(stored url: String) {
        self.url = url
    }
}
