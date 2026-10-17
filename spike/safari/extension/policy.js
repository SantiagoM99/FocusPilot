// Throwaway spike for issue #1. Pure evaluation of a policy snapshot against a caller-supplied
// clock. Loaded as a classic script by the content script and as a side-effect module import by
// the background worker, so it publishes onto globalThis instead of using `export`.
(() => {
  const ms = (iso) => (iso == null ? null : Date.parse(iso));

  function hostMatches(host, domain) {
    return host === domain || host.endsWith("." + domain);
  }

  // Every time in the policy is absolute, so this needs nothing from the app: a normal session
  // stops at endsAt, a strict one keeps blocking until the app writes ended=true, and exceptions
  // expire at expiresAt in both modes (Architecture, Enforcement ownership).
  function evaluate(policy, now) {
    const out = {
      revision: policy?.revision ?? null,
      blockedDomains: [],
      sessionActive: false,
      strictPastEnd: false,
      activeExceptions: [],
      // S3: active URL-scoped exceptions. Their domain stays blocked except for these pages.
      allowedUrls: [],
      transitions: [],
      nextTransitionAt: null,
    };
    if (!policy) return out;

    const blocked = new Set((policy.alwaysOn ?? []).map((r) => r.domain));
    const s = policy.session;
    if (s && !s.ended) {
      const start = ms(s.startsAt);
      const end = ms(s.endsAt);
      const pastEnd = now >= end;
      out.sessionActive = now >= start && (!pastEnd || s.mode === "strict");
      out.strictPastEnd = out.sessionActive && pastEnd;
      out.transitions.push({ kind: "session-start", at: start });
      if (s.mode !== "strict") out.transitions.push({ kind: "session-end", at: end });
      for (const e of s.exceptions ?? []) {
        out.transitions.push({ kind: "exception-expiry", id: e.id, domain: e.domain, at: ms(e.expiresAt) });
      }
      if (out.sessionActive) {
        const live = (s.exceptions ?? []).filter((e) => now < ms(e.expiresAt));
        for (const e of live.filter((e) => e.url)) out.allowedUrls.push({ id: e.id, domain: e.domain, url: e.url, key: pageKey(e.url), expiresAt: e.expiresAt });
        for (const d of s.domains ?? []) {
          const exc = live.find((e) => !e.url && hostMatches(d, e.domain));
          if (exc) out.activeExceptions.push({ id: exc.id, domain: d, expiresAt: exc.expiresAt });
          else blocked.add(d);
        }
      }
    }
    out.blockedDomains = [...blocked];
    const future = out.transitions.map((t) => t.at).filter((t) => t > now);
    out.nextTransitionAt = future.length ? Math.min(...future) : null;
    return out;
  }

  // Transitions that fell due after `since` and by `now`: their lateness is the overrun the spike
  // must measure (sleep/wake, browser restart, worker suspension).
  function passedTransitions(policy, since, now) {
    if (since == null) return [];
    return evaluate(policy, now).transitions.filter((t) => t.at > since && t.at <= now);
  }

  // What a URL-scoped exception means by "this exact page": host without www, path, and for
  // YouTube the video id only (t=, list= and tracking parameters do not make it a new page).
  function pageKey(href) {
    try {
      const u = new URL(href);
      const host = u.hostname.replace(/^www\.|^m\./, "");
      const v = hostMatches(host, "youtube.com") && u.pathname === "/watch" ? u.searchParams.get("v") : null;
      return host + u.pathname + (v ? "?v=" + v : "");
    } catch {
      return null;
    }
  }

  // Whether a page is blocked under an evaluate() result: on a blocked domain and not an
  // exception's exact page.
  function isBlocked(result, href) {
    let host;
    try {
      host = new URL(href).hostname;
    } catch {
      return false;
    }
    if (!result.blockedDomains.some((d) => hostMatches(host, d))) return false;
    const key = pageKey(href);
    return !result.allowedUrls.some((a) => a.key === key);
  }

  globalThis.FPPolicy = { evaluate, hostMatches, passedTransitions, pageKey, isBlocked };
})();
