import FocusPilotCore
import SwiftUI

/// A helper agent's report in Needs you (#67): who sent it, its summary,
/// and any proposed message, shown exactly as it would be sent. Accept
/// sends that text to that agent, after FocusPilot checks the agent again;
/// Dismiss discards the report. Report text is plain text, never markup.
/// The floating panel shows only the headline: Accept needs the full text
/// on screen, so it lives in In flight.
struct ReportRow: View {
    let model: AppModel
    let item: AttentionItem
    let report: AgentReport
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.purple)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: [item.headline, report.projectTitle].compactMap(\.self).joined(separator: " · "))
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    WaitedText(item: item, now: model.attentionTime)
                }
                Spacer(minLength: 8)
                Button("Show") {
                    model.requestedPage = .inFlight
                    model.planningWindowRequests += 1
                }
                .help("Opens In flight, where you can read the report and accept or dismiss it")
            }
            .padding(.vertical, 4)
        } else {
            full
        }
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.purple)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.headline)
                        .fontWeight(.medium)
                    Text(verbatim: item.place)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let claimed = report.claimedName {
                        // Free text from the sender, never its identity.
                        Text(verbatim: "Calls itself “\(claimed)”")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    WaitedText(item: item, now: model.attentionTime)
                }
                Spacer(minLength: 8)
            }
            Text(verbatim: report.summary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 28)
            if let proposal = report.proposal {
                proposalView(proposal)
                    .padding(.leading, 28)
            }
            if report.outcomeUnknown {
                Label(AcceptRefusal.outcomeUnknownText(report.proposal?.target?.label ?? report.proposal?.targetAsGiven ?? "the agent"),
                      systemImage: "questionmark.diamond.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
            } else if let notice = model.reportNotices[report.id] {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
            }
            HStack {
                Spacer()
                Button("Dismiss") { Task { await model.dismissReport(report.id) } }
                    .help("Discards the report. Nothing is sent.")
                if let proposal = report.proposal, let target = proposal.target, !report.outcomeUnknown {
                    // The same values the box above renders, passed as they are.
                    let shownMessage = proposal.message, shownTarget = proposal.target
                    Button("Accept and Send") {
                        Task { await model.acceptReport(report.id, shownMessage: shownMessage, shownTarget: shownTarget) }
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Sends the message above to \(target.label) in Herdr, exactly as shown, after checking it’s still the same agent")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    private func proposalView(_ proposal: ReportProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: proposal.target.map { "Accept sends this message to \($0.label) in Herdr, exactly as written:" }
                 ?? "Proposed message for \(proposal.targetAsGiven):")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(verbatim: proposal.message)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
                .contrastBorder(cornerRadius: 6)
                .accessibilityLabel("Message: \(proposal.message)")
            if let problem = proposal.targetProblem {
                Label(problem + " It can’t be accepted; dismiss it or ask for a new report.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
