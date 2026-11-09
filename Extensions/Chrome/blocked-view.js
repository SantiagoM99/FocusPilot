// What the blocked page says (redesign Blocked.dc.html): controls, labels and
// real status only (decision 0003, 2026-11-03). Pure, so node can test it;
// blocked.js renders it.

var FocusBlockedView = (() => {
  // "24:08", "1:00:05", as MenuBarStatus.format in the app.
  function countdown(seconds) {
    const total = Math.max(0, Math.floor(seconds));
    const h = Math.floor(total / 3600), m = Math.floor(total / 60) % 60, s = total % 60;
    const pad = (n) => String(n).padStart(2, "0");
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
  }

  // "25 min", rounded up, for Reduce Motion: it changes once a minute, as
  // SessionText.minutesLeft in the app.
  function minutes(seconds) {
    return `${Math.ceil(Math.max(0, seconds) / 60)} min`;
  }

  // "in 45 min", "in 7 h 33 min", "in 1 d 2 h".
  function relative(seconds) {
    const minutes = Math.max(0, Math.floor(seconds / 60));
    const d = Math.floor(minutes / 1440), h = Math.floor(minutes / 60) % 24, m = minutes % 60;
    if (d > 0) return `in ${d} d ${h} h`;
    if (h > 0) return `in ${h} h ${m} min`;
    return `in ${m} min`;
  }

  // "today at 18:00", "tomorrow at 08:00", "Mon at 08:00", in the Mac's zone.
  function clock(instant, timeZone) {
    return new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(instant));
  }

  function when(instant, now, timeZone) {
    const date = (t) => new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(t));
    const time = clock(instant, timeZone);
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

  const reasonNote = { session: "Blocked during focus", schedule: "Blocked by a schedule", always: "Always blocked" };

  // "NLP report · Next: write the comparison table".
  function taskLine({ projectTitle, nextAction }) {
    const parts = [projectTitle, nextAction && `Next: ${nextAction}`].filter(Boolean);
    return parts.length ? parts.join(" · ") : null;
  }

  // The task's web page, unless a rule would only bounce the owner back here.
  function workPage(focus, policy, now) {
    const { resourceName: name, resourceURL: url } = focus;
    if (!name || !/^https?:/i.test(url ?? "") || FocusPolicy.decide(policy, url, now).blocked) return null;
    return { label: `Back to ${name}`, action: "open-url", url };
  }

  function hostOf(url) {
    try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return url; }
  }

  function model({ delivery, url, now, appRunning, timeZone, reduceMotion = false }) {
    const left = (seconds) => reduceMotion ? minutes(seconds) : countdown(seconds);
    const policy = delivery?.policy ?? null;
    const decision = FocusPolicy.decide(policy, url, now);
    const offline = appRunning === false;
    const openApp = { label: offline ? "Open FocusPilot" : "Back to FocusPilot", action: "open-app" };

    if (decision.excepted) {
      const host = hostOf(url);
      const { scope, expiresAt } = decision.excepted;
      const what = scope.kind === "site" ? "Whole site" : "This page";
      return {
        kind: "excepted", domain: decision.domain,
        status: { tone: "green", text: `Timed exception · ${left((expiresAt - now) / 1000)} left` },
        title: `${host} is allowed for now`,
        subtitle: `${what} · until ${clock(expiresAt, timeZone)}`,
        primary: { label: `Go back to ${host}`, action: "go-back" }, backURL: FocusPolicy.returnURL(policy, url),
        exceptionLink: false,
      };
    }

    if (decision.linked) {
      const host = hostOf(url);
      return {
        kind: "linked", domain: decision.domain,
        status: { tone: "green", text: "Linked to a task in this session" },
        title: "This page is allowed in this session",
        subtitle: `Until ${clock(Date.parse(policy.session.end), timeZone)}`,
        primary: { label: `Go back to ${host}`, action: "go-back" }, backURL: FocusPolicy.returnURL(policy, url),
        exceptionLink: false,
      };
    }

    if (!decision.blocked) {
      const host = hostOf(url);
      const backURL = FocusPolicy.returnURL(policy, url);
      return {
        kind: "unblocked", status: { tone: "gray", text: "Not blocked" }, title: `${host} isn't blocked now`,
        primary: { label: backURL ? `Go back to ${host}` : "Open a new tab", action: "go-back" }, backURL,
        exceptionLink: false,
      };
    }

    const domain = decision.domain;
    const session = policy?.session;
    const offlineSession = offline && decision.reason === "session";
    if (offlineSession && session.mode === "strict") {
      return {
        kind: "strict-offline", domain, status: { tone: "orange", text: "FocusPilot isn't running" },
        title: "Still blocked · strict session",
        primary: { label: "Open FocusPilot", action: "open-app" },
        exceptionLink: false,
      };
    }
    if (offlineSession) {
      const end = clock(Date.parse(session.end), timeZone);
      return {
        kind: "normal-offline", domain, status: { tone: "orange", text: "FocusPilot isn't running" },
        title: `Still blocked until ${end}`,
        primary: { label: "Open FocusPilot", action: "open-app" },
        exceptionLink: false,
      };
    }
    const offlineHint = offline ? "FocusPilot isn't running" : null;

    if (FocusPolicy.sessionApplies(session, now) && delivery.focus) {
      const remaining = Date.parse(session.end) - now;
      const status = remaining > 0 ? `Focusing · ${left(remaining / 1000)} left` : "Strict session · past its planned end";
      // With nothing in Now the app sends what the session covers instead (#56).
      const focus = delivery.focus, nothingInNow = focus.covers != null;
      return {
        kind: "session", domain, status: { tone: "green", text: status },
        title: focus.title, subtitle: nothingInNow ? focus.covers : taskLine(focus),
        primary: nothingInNow ? { label: "Open FocusPilot", action: "open-app" } : workPage(focus, policy, now) ?? openApp,
        hint: offlineHint, exceptionLink: !offline,
        note: `${domain} · ${reasonNote[decision.reason]}`,
      };
    }

    let subtitle = null;
    if (decision.reason === "schedule") {
      const end = FocusPolicy.scheduleNextChange(decision.schedule, now);
      subtitle = end ? `Ends ${when(end, now, timeZone)} · ${relative((end - now) / 1000)}` : null;
    }
    return {
      kind: "rule", domain, status: { tone: "gray", text: "No session running" },
      title: reasonText[decision.reason](domain), subtitle,
      primary: { label: "Open FocusPilot", action: "open-app" }, hint: offlineHint, exceptionLink: !offline,
    };
  }

  const DURATIONS = [600, 1200, 2700];

  // An exact-page exception on a video is what the owner came for, so it says so.
  function pageChoice(url) {
    try {
      const u = new URL(url), host = u.hostname.replace(/^(www|m)\./, "");
      const video = (host === "youtube.com" && /^\/(watch|shorts\/)/.test(u.pathname)) || host === "youtu.be";
      return video ? "This video only" : "This page only";
    } catch { return "This page only"; }
  }

  // The exception sheet. `state` is the page's: the
  // chosen duration and scope, the reason, and the phase of the request:
  // editing, confirming (strict: asked to confirm), waiting (strict: the
  // wait until `availableAt`), or sending.
  function exceptionForm({ delivery, url, now, state }) {
    const policy = delivery?.policy ?? null;
    const decision = FocusPolicy.decide(policy, url, now);
    const domain = decision.domain ?? hostOf(url);
    const strict = policy?.session?.mode === "strict" && FocusPolicy.sessionApplies(policy.session, now);
    const minutes = (seconds) => `${seconds / 60} min`;
    const waiting = state.phase === "waiting";
    const remaining = waiting ? Math.max(0, state.availableAt - now) : 0;

    let allow;
    if (state.phase === "sending") allow = { label: "Allowing…", disabled: true };
    else if (state.phase === "confirming") allow = { label: "Start the wait", disabled: false };
    else if (waiting) allow = remaining > 0 ? { label: `Allow in ${countdown(remaining / 1000)}`, disabled: true } : { label: "Allow now", disabled: false };
    else allow = { label: `Allow ${minutes(state.duration)}`, disabled: strict && !state.reason.trim() };

    const reason = state.reason.trim();
    return {
      title: `Allow ${domain}`, strict,
      durations: DURATIONS.map((seconds) => ({ seconds, label: minutes(seconds), selected: seconds === state.duration })),
      scopes: [
        { id: "page", label: pageChoice(url), selected: state.scope === "page" },
        { id: "site", label: "Whole site", selected: state.scope === "site" },
      ],
      reason: strict ? {} : null,
      locked: waiting || state.phase === "sending",
      allow, error: state.error ?? null,
      request: {
        scope: state.scope === "site" ? { kind: "site", domain } : { kind: "page", url },
        durationSeconds: state.duration, reason: strict && reason ? reason : null,
        confirmed: state.phase === "confirming",
      },
    };
  }

  // Where an arrow, Home or End key moves the choice in a radio group of
  // `count`, wrapping around; null for any other key.
  function nextChoice(index, count, key) {
    switch (key) {
      case "ArrowRight": case "ArrowDown": return (index + 1) % count;
      case "ArrowLeft": case "ArrowUp": return (index - 1 + count) % count;
      case "Home": return 0;
      case "End": return count - 1;
      default: return null;
    }
  }

  return { model, exceptionForm, countdown, relative, when, nextChoice };
})();

if (typeof module === "object") module.exports = FocusBlockedView;
