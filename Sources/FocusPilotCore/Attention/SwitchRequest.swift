import Foundation

/// A Switch the owner clicked, waiting for its "Where did you leave off?"
/// line (decision 0004). Nothing happens until the owner confirms it.
public struct SwitchRequest: Hashable, Sendable, Identifiable {
    public let id = UUID()
    public var taskID: Int64
    public var taskTitle: String
    /// The agent to open after Now changes.
    public var linkID: Int64?
    public var agentLabel: String?
    /// The attention item it came from, if any.
    public var item: AttentionItem.ID?

    public init(taskID: Int64, taskTitle: String, linkID: Int64?, agentLabel: String?, item: AttentionItem.ID?) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.linkID = linkID
        self.agentLabel = agentLabel
        self.item = item
    }

    public init(_ item: AttentionItem) {
        self.init(taskID: item.taskID, taskTitle: item.taskTitle, linkID: item.linkID, agentLabel: item.agentLabel, item: item.id)
    }

    public init(_ thread: InFlightThread) {
        self.init(taskID: thread.taskID, taskTitle: thread.taskTitle, linkID: thread.linkID,
                  agentLabel: thread.linkID == nil ? nil : thread.label, item: nil)
    }

    /// What confirming does, under the sheet's title.
    public var opens: String {
        guard linkID != nil, let agentLabel else { return "Makes it Now." }
        return "Makes it Now and opens \(agentLabel) in Herdr."
    }
}
