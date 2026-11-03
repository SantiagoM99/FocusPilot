/// Which linked pages a session lets through (decision 0004: the
/// resources of every project in scope are allowed; #60: the scope's
/// projects, every project when none were chosen, plus the Now task's
/// project when it sits outside them).
///
/// A page on a site no rule blocks joins the allowed list. A page on a
/// blocked site is allowed as that exact page, only while a normal session
/// runs (owner decision 0003, 2026-11-03): not during its break or pause,
/// when always-on rules still hold. In a strict session it stays blocked
/// and the owner asks for an exception, with the usual wait.
enum ContextAllowance {
    struct Result: Equatable {
        var allowed: [AllowedActivity] = []
        var pages: [String] = []
    }

    static func compute(_ inputs: PolicyInputs, session: FocusSession?) -> Result {
        guard let session else { return Result() }
        let blocked = inputs.rules.flatMap(\.targets)
        var taken = inputs.allowed.map(\.target)
        var result = Result()
        for site in inputs.contextSites where covers(session.scope, site.owner, inputs.taskProjects) {
            let target = ActivityTarget.site(domain: site.domain)
            if blocked.contains(where: target.overlaps) {
                if session.mode == .normal, session.phase == .running, let page = PageAddress.canonical(site.url) {
                    result.pages.append(page)
                }
            } else if !taken.contains(where: target.overlaps) {
                taken.append(target)
                result.allowed.append(AllowedActivity(name: site.domain, target: target))
            }
        }
        return result
    }

    private static func covers(_ scope: SessionScope, _ owner: ResourceOwner, _ taskProjects: [Int64: Int64]) -> Bool {
        let projectID: Int64? = switch owner {
        case .task(let id): taskProjects[id]
        case .project(let id): id
        }
        return scope.covers(projectID: projectID) || scope.alsoAllowed.contains { $0.id == projectID }
    }
}
