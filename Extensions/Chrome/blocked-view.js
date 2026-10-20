// What the blocked page says (design 05: A in a session, C outside one,
// D for a strict session without the app). Pure, so node can test it;
// blocked.js renders it.

var FocusBlockedView = (() => {
  const DAY_NAMES = { mon: "Mon", tue: "Tue", wed: "Wed", thu: "Thu", fri: "Fri", sat: "Sat", sun: "Sun" };
  const ORDER = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

  // "24:08", "1:00:05", as MenuBarStatus.format in the app.
  function countdown(seconds) {
    const total = Math.max(0, Math.floor(seconds));
    const h = Math.floor(total / 3600), m = Math.floor(total / 60) % 60, s = total % 60;
    const pad = (n) => String(n).padStart(2, "0");
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
  }

  // "in 45 min", "in 7 h 33 min", "in 1 d 2 h".
  function relative(seconds) {
    const minutes = Math.max(0, Math.floor(seconds / 60));
    const d = Math.floor(minutes / 1440), h = Math.floor(minutes / 60) % 24, m = minutes % 60;
    if (d > 0) return `in ${d} d ${h} h`;
    if (h > 0) return `in ${h} h ${m} min`;
    return `in ${m} min`;
  }

  // "Mon–Fri", "Sat, Sun", "Every day", as RuleText.summary in the app.
  function days(list) {
    if (list.length >= 7) return "Every day";
    const runs = [];
    ORDER.forEach((day, i) => {
      if (!list.includes(day)) return;
      const run = runs[runs.length - 1];
      if (run && run[run.length - 1] === i - 1) run.push(i); else runs.push([i]);
    });
    return runs.flatMap((run) => run.length >= 3
      ? [`${DAY_NAMES[ORDER[run[0]]]}–${DAY_NAMES[ORDER[run[run.length - 1]]]}`]
      : run.map((i) => DAY_NAMES[ORDER[i]])).join(", ");
  }

  // "today at 18:00", "tomorrow at 08:00", "Mon at 08:00", in the Mac's zone.
  function when(instant, now, timeZone) {
    const date = (t) => new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(t));
    const time = new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(instant));
    if (date(instant) === date(now)) return `today at ${time}`;
    if (date(instant) === date(now + 86400000)) return `tomorrow at ${time}`;
    const weekday = new Intl.DateTimeFormat("en-US", { timeZone, weekday: "short" }).format(new Date(instant));
    return `${weekday} at ${time}`;
  }

  const reasonText = {
    session: (d) => `${d} is blocked during focus sessions`,
    schedule: (d) => `${d} is blocked by a schedule`,
    always: (d) => `${d} is blocked at all times`,
  };

  function hostOf(url) {
    try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return url; }
  }

  function model({ delivery, url, now, appRunning, timeZone }) {
    const policy = delivery?.policy ?? null;
    const decision = FocusPolicy.decide(policy, url, now);
    const offline = appRunning === false;
    const openApp = { label: offline ? "Open FocusPilot" : "Return to task", action: "open-app" };

    if (!decision.blocked) {
      const host = hostOf(url);
      return {
        kind: "unblocked", status: { tone: "gray", text: "Not blocked" }, title: `${host} isn't blocked now`,
        subtitle: "The rule that blocked it no longer applies.", primary: { label: `Go back to ${host}`, action: "go-back" },
        exceptionLink: false, footer: ["", "FocusPilot"],
      };
    }

    const domain = decision.domain;
    if (offline && FocusPolicy.strictPastEnd(policy, now)) {
      return {
        kind: "strict-offline", domain, status: { tone: "orange", text: "FocusPilot isn't running" },
        title: "Still blocked · strict session",
        subtitle: `Your last policy keeps ${domain} blocked until FocusPilot is running again.`,
        primary: { label: "Open FocusPilot", action: "open-app" },
        hint: "Applications › FocusPilot, or Spotlight. Exceptions can only be requested while it runs.",
        exceptionLink: false,
        footer: [`Compiled policy rev. ${policy.revision} · cached in the extension · no planned end while strict`, "FocusPilot"],
      };
    }
    const offlineHint = offline ? "FocusPilot isn't running. Exceptions can only be requested while it runs." : null;

    const session = policy?.session;
    if (FocusPolicy.sessionApplies(session, now) && delivery.focus) {
      const left = Date.parse(session.end) - now;
      const status = left > 0 ? `Focus session · ${countdown(left / 1000)} left` : "Strict session · past its planned end";
      return {
        kind: "session", domain, status: { tone: "accent", text: status }, eyebrow: "You're working on",
        title: delivery.focus.title, subtitle: delivery.focus.nextAction ?? delivery.focus.projectTitle ?? null,
        primary: openApp, hint: offlineHint, exceptionLink: !offline,
        footer: [reasonText[decision.reason](domain), "FocusPilot · Chrome"],
      };
    }

    let subtitle = null, detail = "Always-on rule · no end time";
    if (decision.reason === "schedule") {
      const s = decision.schedule;
      subtitle = `${days(s.days)} ${s.start}–${s.end} · ${s.timeZone}`;
      const end = FocusPolicy.scheduleNextChange(s, now);
      detail = end ? `Schedule ends ${when(end, now, timeZone)} · ${relative((end - now) / 1000)}` : null;
    } else if (decision.reason === "session") {
      detail = "Blocked during focus sessions";
    }
    return {
      kind: "rule", domain, status: { tone: "gray", text: "No session running" },
      title: reasonText[decision.reason](domain), subtitle, detail,
      primary: { label: "Open FocusPilot", action: "open-app" }, hint: offlineHint, exceptionLink: !offline,
      footer: ["", "FocusPilot"],
    };
  }

  return { model, countdown, relative, days, when };
})();

if (typeof module === "object") module.exports = FocusBlockedView;
