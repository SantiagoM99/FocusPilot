/// The one sheet the planning window shows.
///
/// A window presents a single sheet at a time, and separate `.sheet`
/// modifiers asking at once can drop one of them. So the window shows the
/// first wanted sheet in this order, and the next appears when it closes:
/// quick capture (the owner is typing in it and its text lives only in the
/// sheet), then a waiting wrap-up, then Start focus. Pressing Start focus
/// while a wrap-up waits therefore shows the wrap-up first and Start focus
/// right after it is saved or skipped.
public enum PlanningSheet: Hashable, Sendable, Identifiable {
    case capture
    case wrapUp(WrapUpPrompt.ID)
    case startFocus

    public var id: Self {
        self
    }

    public static func showing(isCapturing: Bool, wrapUp: PendingWrapUp?, isStartingFocus: Bool) -> PlanningSheet? {
        if isCapturing { return .capture }
        if let wrapUp { return .wrapUp(wrapUp.id) }
        return isStartingFocus ? .startFocus : nil
    }
}
