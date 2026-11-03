/// Runs a launch plan after the owner's Open context click: each step is
/// handed to `open`, in order, and any that does not open is named in the
/// notice, so no item is skipped silently.
public enum LaunchRun {
    /// Runs on the caller's actor, so the app's main-actor opener needs no hop.
    public static func run(_ plan: LaunchPlan, isolation: isolated (any Actor)? = #isolation, names: (LaunchStep) -> String,
                           open: (LaunchStep) async -> Bool) async -> String {
        var opened = 0
        var failed: [String] = []
        for step in plan.steps {
            if await open(step) { opened += 1 } else { failed.append(names(step)) }
        }
        return ResourceText.launchResult(opened: opened, needingRepair: plan.needsRepair.map(\.resource.name), failed: failed,
                                         moved: plan.moved)
    }
}
