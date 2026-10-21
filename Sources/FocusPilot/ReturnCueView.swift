import FocusPilotCore
import SwiftUI

/// The last wrap-up as the owner sees it on resuming (#20): the return cue
/// first, then what remains and, when there is room, what got done.
struct ReturnCueView: View {
    let wrapUp: TaskWrapUp
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cue = wrapUp.returnCue {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Start with", systemImage: "arrow.uturn.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(cue)
                        .font(isCompact ? .callout.weight(.medium) : .body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if let remaining = wrapUp.remainingWork {
                detail("Remains", remaining)
            }
            if !isCompact, let outcome = wrapUp.outcome {
                detail("Last time", outcome)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ title: String, _ text: String) -> some View {
        Text("\(Text(title + ": ").foregroundStyle(.secondary))\(text)")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
