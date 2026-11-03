import Darwin
import Foundation

/// A saved link to a folder the owner chose (spike S5, WORKSPACE_RULES
/// "Folder links"): a security-scoped bookmark, always, plus what the folder
/// was when linked, so a different folder at the same path is noticed.
public struct FolderBookmark: Codable, Equatable, Sendable {
    public var data: Data
    /// Where the folder was when linked or last followed.
    public var path: String
    /// A heuristic only: Apple says not to persist file identifiers, so a
    /// mismatch asks the owner and never acts alone.
    public var inode: UInt64
    public var volumeUUID: String?
    /// The root the folder must stay inside, if it was linked under one.
    public var root: String?

    public init(data: Data, path: String, inode: UInt64, volumeUUID: String?, root: String?) {
        self.data = data
        self.path = path
        self.inode = inode
        self.volumeUUID = volumeUUID
        self.root = root
    }

    /// The last folder name, for a link with no title of its own.
    public var name: String { (path as NSString).lastPathComponent }
}

/// Why a folder link cannot be used as it is.
public enum FolderProblem: Equatable, Sendable {
    /// Deleted, or the bookmark no longer resolves.
    case missing
    /// It was on a disk that is not connected.
    case volumeUnavailable(String)
    /// A different folder is at the path now (deleted and recreated).
    case replaced(path: String)
    case inTrash
    case outsideRoot(path: String, root: String)
}

/// What revalidating a folder link found.
public enum FolderCheck: Equatable, Sendable {
    case healthy(path: String)
    /// Renamed or moved within its root: the link followed it, and
    /// `refreshed` is the bookmark to save. The owner is shown the new path.
    case moved(path: String, refreshed: FolderBookmark)
    case needsRepair(FolderProblem)
}

public enum FolderLinkError: Error, Equatable {
    case notAFolder
    case outsideRoot
    case unreadable
}

/// Creates and revalidates folder links. Injected so coordinator tests can
/// fake folders that are deleted or moved.
public protocol FolderAccess: Sendable {
    func bookmark(_ url: URL, root: String?) throws -> FolderBookmark
    func check(_ bookmark: FolderBookmark) -> FolderCheck
}

/// The real folders, through Foundation bookmarks. Every check costs well
/// under a millisecond (S5), so links are revalidated whenever shown and
/// right before a launch.
public struct SystemFolderAccess: FolderAccess {
    public init() {}

    public func bookmark(_ url: URL, root: String?) throws -> FolderBookmark {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let identity = Self.identity(of: url), let path = FolderContainment.canonical(url.path) else {
            throw FolderLinkError.notAFolder
        }
        let root = root.map { FolderContainment.canonical($0) ?? $0 }
        if let root, !FolderContainment.contains(root: root, path: path) { throw FolderLinkError.outsideRoot }
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { throw FolderLinkError.unreadable }
        return FolderBookmark(data: data, path: path, inode: identity.inode, volumeUUID: identity.volumeUUID, root: root)
    }

    public func check(_ bookmark: FolderBookmark) -> FolderCheck {
        var isStale = false
        // Never mount a disk or show UI just to check a link.
        guard let url = try? URL(resolvingBookmarkData: bookmark.data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return .needsRepair(Self.missingVolume(for: bookmark.path).map(FolderProblem.volumeUnavailable) ?? .missing)
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let identity = Self.identity(of: url), let path = FolderContainment.canonical(url.path) else {
            return .needsRepair(.missing)
        }
        if identity.inode != bookmark.inode || identity.volumeUUID != bookmark.volumeUUID {
            return .needsRepair(.replaced(path: path))
        }
        if Self.isInTrash(path) { return .needsRepair(.inTrash) }
        if let root = bookmark.root, !FolderContainment.contains(root: root, path: path) {
            return .needsRepair(.outsideRoot(path: path, root: root))
        }
        guard isStale || path != bookmark.path else { return .healthy(path: path) }
        // Re-created while access is held (S5 rule 3).
        guard let refreshed = try? self.bookmark(url, root: bookmark.root) else { return .needsRepair(.missing) }
        return .moved(path: path, refreshed: refreshed)
    }

    /// The folder to open, resolved from its link. The caller starts and
    /// stops access around the open.
    public static func url(for bookmark: FolderBookmark) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark.data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                        relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    /// The disk name when `path` is on a volume under /Volumes that is not
    /// mounted now.
    static func missingVolume(for path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard components.count > 2, components[1] == "Volumes" else { return nil }
        return FileManager.default.fileExists(atPath: "/Volumes/" + components[2]) ? nil : components[2]
    }

    /// The home Trash (`.Trash`) and each volume's (`.Trashes`).
    static func isInTrash(_ path: String) -> Bool {
        (path as NSString).pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    private static func identity(of url: URL) -> (inode: UInt64, volumeUUID: String?)? {
        var info = stat()
        guard stat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        return (UInt64(info.st_ino), volume)
    }
}

/// Whether a path is inside a root, after resolving symlinks and `..` in
/// both (S5 rule 5, T8/T10). Components compare case-folded on a
/// case-insensitive volume, and always after Unicode normalization.
/// `URL.resolvingSymlinksInPath` is not used: it leaves some links unresolved.
public enum FolderContainment {
    public static func contains(root: String, path: String) -> Bool {
        guard let root = realPath(root), let path = realPath(path) else { return false }
        let caseSensitive = (try? URL(fileURLWithPath: root).resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? true
        func components(_ path: String) -> [String] {
            (path as NSString).pathComponents.map {
                let normal = $0.precomposedStringWithCanonicalMapping
                return caseSensitive ? normal : normal.lowercased()
            }
        }
        let rootParts = components(root), parts = components(path)
        return parts.count >= rootParts.count && Array(parts.prefix(rootParts.count)) == rootParts
    }

    /// The path with symlinks resolved (`/var` → `/private/var`), as
    /// stored and shown; nil if it does not exist.
    static func canonical(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// `realpath` of the deepest existing ancestor, with the rest appended
    /// as long as it holds no `.` or `..`.
    private static func realPath(_ path: String) -> String? {
        var existing = path, rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing) {
            let parent = (existing as NSString).deletingLastPathComponent
            guard parent != existing else { return nil }
            rest.insert((existing as NSString).lastPathComponent, at: 0)
            existing = parent
        }
        guard !rest.contains(where: { $0 == "." || $0 == ".." }), let resolved = realpath(existing, nil) else { return nil }
        defer { free(resolved) }
        return ([String(cString: resolved)] + rest).joined(separator: "/")
    }
}
