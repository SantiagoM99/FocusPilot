# Independent architecture critique

Reviewer: architecture_detractor. Date: 2026-10-13. Based on primary platform documentation and the owner's requirements; prototypes have not yet validated the complete system.

## Findings and dispositions

1. **Distribution shapes integration.** Recommend Developer ID signed/notarized direct distribution first. Apple supports direct distribution of Safari web extensions. The main app can avoid App Store sandbox constraints, but the extension sandbox and system permissions remain. Accepted as a provisional direction; verify signing and packaging in the first spike.
2. **Separate browser bridges.** Safari uses a sandboxed native extension and native messaging; shared App Group state/app-to-extension dispatch are candidates requiring validation. Chrome uses a registered native messaging host with absolute executable path and allowed extension origins. Accepted: separate transport adapters and one authoritative writer; no unauthenticated localhost service.
3. **Protection must be acknowledged.** Versioned policies and per-browser/profile acknowledgements are required before declaring full coverage. Accepted: protected/syncing/degraded/unknown states, permissions and last acknowledgement.
4. **Timed exceptions lack inherent rule expiry.** Browser code must remove allow rules; worker suspension, sleep and quit can delay this. DNR rules do not close an already loaded page or stop buffered video. Accepted: measured recovery/overrun tests; no exact tutorial-close guarantee.
5. **Application activation is not intention.** Correlate OS foreground state and timestamped browser window/tab observations. Stale context is unknown. Accepted: conservative check-ins only.
6. **Model has no arbitrary execution authority.** Typed proposals include task/session/policy revisions. Herdr output, page content and assignment documents are untrusted. Accepted: validation before execution and no autonomous approval answers.
7. **Caches need provenance and time validity.** Summaries include run/output/model/prompt identity; scrubbed input is hashed after scrubbing. Memory deletion invalidates derivatives. Deadline recommendations expire with time. Accepted in memory design.
8. **Operational constraints need spikes.** App relocation/update for Chrome host, extension disablement, bookmarks, Herdr endpoint identity and energy usage are not implementation details to defer. Accepted as release blockers.

## Refined component boundaries

SwiftUI/AppKit presentation; FocusCoordinator actor for session/policy/proposal validation; TaskRepository actor as SQLite writer; browser adapters; Herdr adapter with bounded reads; supervisor without arbitrary shell authority; memory service; workspace service with preview and path validation. Model credentials belong in Keychain.

## Acceptance gates

- AI offline does not disable focus, saved tasks, or launch actions.
- Both supported browser profiles acknowledge current policy before full protection is shown.
- Disabled extensions, missing permissions and stale observations are visible.
- Restart/wake does not silently extend an exception or duplicate prompts; any remaining overrun window is measured and documented.
- Agent turn completion never completes parent task.
- Old model response cannot change a newer task selection.
- Untrusted text cannot authorize execution or relax policy.
- Creation stays within selected roots and never overwrites an existing project.
- Deadlines retain timezone and stay distinct from work scheduling.
- Deleting a memory deletes its associated derived records.

## Sources

- [Safari extension distribution](https://developer.apple.com/documentation/safariservices/distributing-your-safari-web-extension)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Safari native messaging](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)
- [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
- [Safari blocking](https://developer.apple.com/documentation/safariservices/blocking-content-with-your-safari-web-extension)
- [Chrome worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)
- [Application activation](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)
- [Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
