// Shared by the service worker (importScripts) and the content script (manifest order).
// Implements only the DNR urlFilter forms the spike writes: "||domain[/path]" and "|prefix".
function urlFilterMatches(filter, url) {
  if (filter.startsWith("||")) {
    const u = new URL(url);
    const rest = filter.slice(2);
    const slash = rest.indexOf("/");
    const domain = slash < 0 ? rest : rest.slice(0, slash);
    const path = slash < 0 ? "" : rest.slice(slash);
    return hostMatches(u.hostname, domain) && (u.pathname + u.search).startsWith(path);
  }
  if (filter.startsWith("|")) return url.startsWith(filter.slice(1));
  return url.includes(filter);
}

function hostMatches(hostname, domain) {
  return hostname === domain || hostname.endsWith("." + domain);
}

function sessionActive(policy, now) {
  const s = policy?.session;
  if (!s || s.ended || now < Date.parse(s.startsAt)) return false;
  return now < Date.parse(s.endsAt) || s.mode === "strict";
}

// Same decision the DNR rules encode, evaluated for one URL so pages that are already
// loaded (or change URL without a network request) can be judged without the network layer.
function decide(policy, url, now) {
  let host;
  try { host = new URL(url).hostname; } catch { return { blocked: false, reason: "not-a-url" }; }
  if ((policy?.alwaysOn ?? []).some((r) => hostMatches(host, r.domain))) return { blocked: true, reason: "always-on" };
  if (!sessionActive(policy, now)) return { blocked: false, reason: "no-session" };
  const s = policy.session;
  if (!s.domains.some((d) => hostMatches(host, d))) return { blocked: false, reason: "not-listed" };
  const live = s.exceptions.filter((e) => now < Date.parse(e.expiresAt) && urlFilterMatches(e.urlFilter, url));
  if (live.length) return { blocked: false, reason: "exception", exceptionExpiresAt: Math.max(...live.map((e) => Date.parse(e.expiresAt))) };
  return { blocked: true, reason: "session" };
}
