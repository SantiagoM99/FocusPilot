/// Where a task sits in the planning window. At most one task is `now`;
/// the database enforces it. `done` is reserved for completing tasks (#11)
/// and is never shown in Today.
public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case now, next, later, done
}
