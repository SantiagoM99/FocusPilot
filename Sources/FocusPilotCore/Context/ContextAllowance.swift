/// Which linked pages the session allows (decision 0004: the resources of
/// every task in scope are allowed). Until sessions can cover several
/// projects, the scope is the session task's project, or the task alone.
///
/// A page on a site a rule blocks is left out. Chrome does not unblock an
/// allowed domain, and the two lists must never contradict each other, so
/// linking a page never weakens blocking, strict sessions included.
enum ContextAllowance {
    static func entries(_ inputs: PolicyInputs, sessionTaskID: Int64?) -> [AllowedActivity] {
        guard let sessionTaskID else { return [] }
        let project = inputs.taskProjects[sessionTaskID]
        let blocked = inputs.rules.flatMap(\.targets)
        var taken = inputs.allowed.map(\.target)
        var entries: [AllowedActivity] = []
        for site in inputs.contextSites {
            let inScope = switch site.owner {
            case .task(let id): id == sessionTaskID || (project != nil && inputs.taskProjects[id] == project)
            case .project(let id): id == project
            }
            let target = ActivityTarget.site(domain: site.domain)
            guard inScope, !blocked.contains(where: target.overlaps), !taken.contains(where: target.overlaps) else { continue }
            taken.append(target)
            entries.append(AllowedActivity(name: site.domain, target: target))
        }
        return entries
    }
}
