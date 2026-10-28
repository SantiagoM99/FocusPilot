// What the compiled policy blocks at an instant. Shared by the service
// worker (importScripts), the content script and the blocked page, and
// tested with node (module.exports at the end). Mirrors PolicyCompiler and
// WeeklySchedule in FocusPilotCore; the app is the only writer of policies.

var FocusPolicy = (() => {
  const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
  const formatters = new Map();

  function formatter(timeZone) {
    if (!formatters.has(timeZone)) {
      formatters.set(timeZone, new Intl.DateTimeFormat("en-US", {
        timeZone, weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
      }));
    }
    return formatters.get(timeZone);
  }

  // Weekday ("mon") and minutes since midnight in the time zone.
  function localParts(now, timeZone) {
    const parts = Object.fromEntries(formatter(timeZone).formatToParts(new Date(now)).map((p) => [p.type, p.value]));
    return { day: parts.weekday.toLowerCase().slice(0, 3), minutes: Number(parts.hour) * 60 + Number(parts.minute) };
  }

  const minutesOf = (hhmm) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));
  const previousDay = (day) => WEEKDAYS[(WEEKDAYS.indexOf(day) + 6) % 7];

  // A window whose end is earlier than its start runs past midnight and
  // belongs to the day it starts.
  function scheduleContains(schedule, now) {
    const { day, minutes } = localParts(now, schedule.timeZone);
    const start = minutesOf(schedule.start);
    const end = minutesOf(schedule.end);
    if (end < start) {
      return (schedule.days.includes(day) && minutes >= start) || (schedule.days.includes(previousDay(day)) && minutes < end);
    }
    return schedule.days.includes(day) && minutes >= start && minutes < end;
  }

  // Schedule edges fall on whole minutes in any time zone, so stepping by
  // minutes finds the next one exactly, DST included. At most 8 days.
  function scheduleNextChange(schedule, now) {
    const current = scheduleContains(schedule, now);
    let t = Math.floor(now / 60000) * 60000 + 60000;
    for (const limit = now + 8 * 86400000; t <= limit; t += 60000) {
      if (scheduleContains(schedule, t) !== current) return t;
    }
    return null;
  }

  // Session rules: lifted during a normal break; a normal session stops at
  // its planned end, a strict one keeps going until the app publishes a
  // policy without it (decision 0003, 2026-10-13).
  function sessionApplies(session, now) {
    if (!session) return false;
    if (session.resumesAt && now < Date.parse(session.resumesAt)) return false;
    return now < Date.parse(session.end) || session.mode === "strict";
  }

  function hostMatches(host, domain) {
    return host === domain || host.endsWith("." + domain);
  }

  // ---- One page (#14) ----
  // Mirrors PageAddress in FocusPilotCore; Tests/ChromeExtension/fixtures/pages.json
  // pins both. A page is its host (without "www."), path and query, minus
  // parameters that only track or position (a video's start time), so the
  // same lecture stays the same page however it was reached.
  const TRACKING = new Set(["fbclid", "gclid", "dclid", "msclkid", "igsh", "igshid", "si"]);
  const YOUTUBE_NOISE = new Set(["t", "pp", "feature", "ab_channel", "list", "index", "start_radio", "embeds_referring_euri"]);

  function pageParts(url) {
    let parsed;
    try { parsed = new URL(url); } catch { return null; }
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
    const host = parsed.hostname.toLowerCase().replace(/\.$/, "").replace(/^www\./, "");
    const youtube = hostMatches(host, "youtube.com") || hostMatches(host, "youtu.be");
    const params = parsed.search.slice(1).split("&").filter((pair) => {
      if (!pair) return false;
      const key = pair.split("=")[0];
      return !key.startsWith("utm_") && !TRACKING.has(key) && !(youtube && YOUTUBE_NOISE.has(key));
    }).sort();
    return { host, port: parsed.port, path: parsed.pathname || "/", params };
  }

  function canonicalPage(url) {
    const p = pageParts(url);
    if (!p) return null;
    return `https://${p.host}${p.port ? ":" + p.port : ""}${p.path}${p.params.length ? "?" + p.params.join("&") : ""}`;
  }

  // Same host, port, path and parameters (in any order), ignoring the
  // tracking and position ones: one page, not every query on its path.
  function pageMatches(exceptionURL, url) {
    const e = pageParts(exceptionURL), u = pageParts(url);
    return !!e && !!u && e.host === u.host && e.port === u.port && e.path === u.path && e.params.join("&") === u.params.join("&");
  }

  // A parameter canonicalPage drops, as a regex for the network rule.
  function ignorableParameter(host) {
    const youtube = hostMatches(host, "youtube.com") || hostMatches(host, "youtu.be");
    const keys = [...TRACKING, ...(youtube ? YOUTUBE_NOISE : [])].map(escapeRegex);
    return `(?:utm_[^=&#]*|${keys.join("|")})(?:=[^&#]*)?`;
  }

  function isSiteOrPage(exception) {
    return exception?.scope?.kind === "site" || exception?.scope?.kind === "page";
  }

  // Site and page exceptions that have not expired. Expiry is absolute, so
  // sleep, a quit app or a browser restart never extends one.
  function activeExceptions(policy, now) {
    return (policy?.exceptions ?? []).filter((e) => isSiteOrPage(e) && now < Date.parse(e.expiresAt));
  }

  // The exception that lets `url` load now, with the latest expiry.
  function exceptionFor(policy, url, host, now) {
    let found = null;
    for (const e of activeExceptions(policy, now)) {
      const covers = e.scope.kind === "site" ? hostMatches(host, e.scope.domain) : pageMatches(e.scope.url, url);
      const expiresAt = Date.parse(e.expiresAt);
      if (covers && (!found || expiresAt > found.expiresAt)) found = { scope: e.scope, expiresAt };
    }
    return found;
  }

  // Why `url` is blocked now, if it is, and whether a timed exception lifts it.
  function decide(policy, url, now) {
    const decision = ruleDecision(policy, url, now);
    if (!decision.blocked) return decision;
    const excepted = exceptionFor(policy, url, decision.host, now);
    const { host, ...result } = decision;
    return excepted ? { ...result, blocked: false, excepted } : result;
  }

  // The rule that blocks `url`: the session first, since its page shows
  // the task; then a schedule; then always-on rules.
  function ruleDecision(policy, url, now) {
    let host;
    try {
      const parsed = new URL(url);
      if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return { blocked: false };
      host = parsed.hostname.replace(/\.$/, "");
    } catch {
      return { blocked: false };
    }
    const match = (domains) => domains.find((d) => hostMatches(host, d));
    if (sessionApplies(policy?.session, now)) {
      const domain = match(policy.session.targets.domains);
      if (domain) return { blocked: true, reason: "session", domain, host };
    }
    for (const block of policy?.scheduled ?? []) {
      const domain = match(block.targets.domains);
      if (domain && scheduleContains(block.schedule, now)) return { blocked: true, reason: "schedule", domain, schedule: block.schedule, host };
    }
    const domain = match(policy?.always?.domains ?? []);
    if (domain) return { blocked: true, reason: "always", domain, host };
    return { blocked: false };
  }

  // Every domain blocked now, sorted, for the network rules.
  function blockedDomains(policy, now) {
    const domains = new Set(policy?.always?.domains ?? []);
    for (const block of policy?.scheduled ?? []) {
      if (scheduleContains(block.schedule, now)) block.targets.domains.forEach((d) => domains.add(d));
    }
    if (sessionApplies(policy?.session, now)) policy.session.targets.domains.forEach((d) => domains.add(d));
    return [...domains].sort();
  }

  // The next instant blocking can change without a new policy.
  function nextBoundary(policy, now) {
    const times = [];
    const s = policy?.session;
    if (s) {
      if (s.resumesAt) times.push(Date.parse(s.resumesAt));
      if (s.mode !== "strict") times.push(Date.parse(s.end));
    }
    for (const block of policy?.scheduled ?? []) times.push(scheduleNextChange(block.schedule, now));
    for (const e of activeExceptions(policy, now)) times.push(Date.parse(e.expiresAt));
    const future = times.filter((t) => t !== null && t > now);
    return future.length ? Math.min(...future) : null;
  }

  // ---- Network rules ----

  const escapeRegex = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

  function permutations(items) {
    if (items.length <= 1) return [items];
    return items.flatMap((item, i) => permutations([...items.slice(0, i), ...items.slice(i + 1)]).map((rest) => [item, ...rest]));
  }

  // Lets one excepted page load past the redirect, with everything it loads
  // (allowAllRequests): exactly its parameters, in any order, among
  // ignorable ones. RE2 has no lookahead, so orders are spelled out for up
  // to three parameters; with more, or `pathOnly` (a regex Chrome refused),
  // the rule allows the path and the content script, which compares the
  // parameters, blocks other pages. Case-sensitive: video ids differ by case.
  function pageAllowRule(exception, id, { pathOnly = false } = {}) {
    const p = pageParts(exception.scope.url);
    const prefix = `^https?://(?:www\\.)?${escapeRegex(p.host)}${p.port ? ":" + p.port : ""}${escapeRegex(p.path)}`;
    let query = "(?:[?#].*)?";
    if (!pathOnly && p.params.length <= 3) {
      const noise = ignorableParameter(p.host);
      if (p.params.length === 0) {
        query = `(?:\\?(?:${noise}(?:&${noise})*)?)?(?:#.*)?`;
      } else {
        const orders = permutations(p.params).map((order) =>
          `\\?(?:${noise}&)*` + order.map(escapeRegex).join(`(?:&${noise})*&(?:${noise}&)*`) + `(?:&${noise})*`);
        query = `(?:${orders.join("|")})(?:#.*)?`;
      }
    }
    return {
      id, priority: 2, action: { type: "allowAllRequests" },
      condition: { regexFilter: prefix + query + "$", isUrlFilterCaseSensitive: true, resourceTypes: ["main_frame"] },
    };
  }

  // Excepted pages, canonical, sorted: page rule 10 + i is for the i-th.
  function pageURLs(policy, now) {
    return [...new Set(activeExceptions(policy, now).filter((e) => e.scope.kind === "page")
      .map((e) => canonicalPage(e.scope.url)).filter(Boolean))].sort();
  }

  // The dynamic rules for `now`: new top-level loads of blocked sites go to
  // `blockedPage` with the URL in the fragment, frames are blocked, and
  // timed exceptions are carved out (spike S2/S3: rules persist across restarts).
  function networkRules(policy, now, blockedPage, { pathOnly = new Set() } = {}) {
    const domains = blockedDomains(policy, now);
    if (!domains.length) return [];
    const live = activeExceptions(policy, now);
    const excluded = [...new Set(live.filter((e) => e.scope.kind === "site").map((e) => e.scope.domain))].sort();
    const exclusion = excluded.length ? { excludedRequestDomains: excluded } : {};
    return [
      {
        id: 1, priority: 1,
        action: { type: "redirect", redirect: { regexSubstitution: blockedPage + "#\\0" } },
        condition: { regexFilter: "^.+$", requestDomains: domains, ...exclusion, resourceTypes: ["main_frame"] },
      },
      { id: 2, priority: 1, action: { type: "block" }, condition: { requestDomains: domains, ...exclusion, resourceTypes: ["sub_frame"] } },
      ...pageURLs(policy, now).map((url, i) => pageAllowRule({ scope: { kind: "page", url } }, 10 + i, { pathOnly: pathOnly === true || pathOnly.has?.(url) })),
    ];
  }

  // Deliveries, not policies: `source` names the FocusPilot data that
  // issued the revisions, which restart when the owner resets that data.
  function isNewer(incoming, current) {
    if (!current || incoming.source !== current.source) return true;
    return incoming.policy.revision > current.policy.revision;
  }

  // CompiledPolicy.currentSchemaVersion in the app. A policy in another
  // schema is refused and the last good one stays.
  const SCHEMA_VERSION = 1;

  function supports(delivery) {
    return delivery?.policy?.schemaVersion === SCHEMA_VERSION;
  }

  // Every domain any rule names, whether or not it blocks now.
  function namedDomains(policy) {
    return [
      ...(policy?.always?.domains ?? []),
      ...(policy?.scheduled ?? []).flatMap((block) => block.targets.domains),
      ...(policy?.session?.targets.domains ?? []),
    ];
  }

  // The http(s) page the blocked page may send the owner back to: only a
  // site the rules name, since anyone can link to blocked.html with any ?from=.
  function returnURL(policy, url) {
    try {
      const parsed = new URL(url);
      if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
      const host = parsed.hostname.replace(/\.$/, "");
      return namedDomains(policy).some((d) => hostMatches(host, d)) ? parsed.href : null;
    } catch {
      return null;
    }
  }

  return {
    localParts, scheduleContains, scheduleNextChange, sessionApplies, hostMatches, decide, blockedDomains, nextBoundary,
    isNewer, supports, returnURL, canonicalPage, pageMatches, activeExceptions, networkRules, pageAllowRule, pageURLs,
  };
})();

if (typeof module === "object") module.exports = FocusPolicy;
