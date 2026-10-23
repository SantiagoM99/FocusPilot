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

  // Why `url` is blocked now, if it is: the session first, since its page
  // shows the task; then a schedule; then always-on rules.
  function decide(policy, url, now) {
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
      if (domain) return { blocked: true, reason: "session", domain };
    }
    for (const block of policy?.scheduled ?? []) {
      const domain = match(block.targets.domains);
      if (domain && scheduleContains(block.schedule, now)) return { blocked: true, reason: "schedule", domain, schedule: block.schedule };
    }
    const domain = match(policy?.always?.domains ?? []);
    if (domain) return { blocked: true, reason: "always", domain };
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
    const future = times.filter((t) => t !== null && t > now);
    return future.length ? Math.min(...future) : null;
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
    isNewer, supports, returnURL,
  };
})();

if (typeof module === "object") module.exports = FocusPolicy;
