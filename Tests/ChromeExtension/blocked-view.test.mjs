import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
globalThis.FocusPolicy = require("../../Extensions/Chrome/policy.js");
const FocusBlockedView = require("../../Extensions/Chrome/blocked-view.js");

const at = (iso) => Date.parse(iso);
const weekdays = { days: ["mon", "tue", "wed", "thu", "fri"], start: "08:00", end: "18:00", timeZone: "America/Bogota" };
// Wednesday 2026-10-14, 10:26:52 in Bogotá.
const now = at("2026-10-14T15:26:52Z");

function delivery({ session = null, focus = null } = {}) {
  return {
    policy: {
      schemaVersion: 1, revision: 41, checksum: "c", effectiveAt: "2026-10-14T15:00:00Z",
      always: { domains: ["facebook.com"], apps: [] },
      scheduled: [{ schedule: weekdays, targets: { domains: ["instagram.com"], apps: [] } }],
      session, allowed: { domains: [], apps: [], tools: [] },
    },
    focus,
  };
}

const session = (mode = "normal") => ({ sessionID: "s", mode, end: "2026-10-14T15:51:00Z", targets: { domains: ["youtube.com"], apps: [] } });
const focus = { title: "Explain baseline results", nextAction: "Open Overleaf §4.2 and write the baseline paragraph using Table 3.", projectTitle: "NLP report" };
const view = (d, url, extra = {}) => FocusBlockedView.model({ delivery: d, url, now, appRunning: true, timeZone: "America/Bogota", ...extra });

test("during a session the page shows the task and the way back", () => {
  const m = view(delivery({ session: session(), focus }), "https://www.youtube.com/watch?v=3kqW9M");

  assert.equal(m.kind, "session");
  assert.equal(m.status.text, "Focus session · 24:08 left");
  assert.equal(m.eyebrow, "You're working on");
  assert.equal(m.title, "Explain baseline results");
  assert.equal(m.subtitle, focus.nextAction);
  assert.deepEqual(m.primary, { label: "Return to task", action: "open-app" });
  assert.equal(m.exceptionLink, true);
  assert.deepEqual(m.footer, ["youtube.com is blocked during focus sessions", "FocusPilot · Chrome"]);
});

test("a site blocked by a schedule during a session still shows the task", () => {
  const m = view(delivery({ session: session(), focus }), "https://instagram.com/");

  assert.equal(m.kind, "session");
  assert.equal(m.footer[0], "instagram.com is blocked by a schedule");
});

test("outside a session a schedule says when it ends", () => {
  const m = view(delivery(), "https://instagram.com/");

  assert.equal(m.kind, "rule");
  assert.equal(m.status.text, "No session running");
  assert.equal(m.title, "instagram.com is blocked by a schedule");
  assert.equal(m.subtitle, "Mon–Fri 08:00–18:00 · America/Bogota");
  assert.equal(m.detail, "Schedule ends today at 18:00 · in 7 h 33 min");
  assert.deepEqual(m.primary, { label: "Open FocusPilot", action: "open-app" });
});

test("always-on rules have no end", () => {
  const m = view(delivery(), "https://facebook.com/");

  assert.equal(m.title, "facebook.com is blocked at all times");
  assert.equal(m.detail, "Always-on rule · no end time");
});

test("a strict session past its end without the app says how to reopen it", () => {
  const m = view(delivery({ session: session("strict"), focus }), "https://youtube.com/", { now: at("2026-10-14T16:30:00Z"), appRunning: false });

  assert.equal(m.kind, "strict-offline");
  assert.equal(m.status.text, "FocusPilot isn't running");
  assert.equal(m.title, "Still blocked · strict session");
  assert.equal(m.subtitle, "Your last policy keeps youtube.com blocked until FocusPilot is running again.");
  assert.equal(m.hint, "Applications › FocusPilot, or Spotlight. Exceptions can only be requested while it runs.");
  assert.equal(m.exceptionLink, false);
  assert.deepEqual(m.footer, ["Compiled policy rev. 41 · cached in the extension · no planned end while strict", "FocusPilot"]);
});

// Design 05 D applies to the whole strict session, not only past its end.
test("a strict session before its end without the app is variant D", () => {
  const m = view(delivery({ session: session("strict"), focus }), "https://youtube.com/", { appRunning: false });

  assert.equal(m.kind, "strict-offline");
  assert.equal(m.title, "Still blocked · strict session");
});

test("a normal session without the app says when the rule lifts (05 D2)", () => {
  const m = view(delivery({ session: session(), focus }), "https://youtube.com/", { appRunning: false });

  assert.equal(m.kind, "normal-offline");
  assert.deepEqual(m.status, { tone: "orange", text: "FocusPilot isn't running" });
  assert.equal(m.title, "Still blocked until 10:51");
  assert.equal(m.subtitle, "This normal session keeps youtube.com blocked until its planned end, then the rule lifts even if FocusPilot stays closed.");
  assert.deepEqual(m.primary, { label: "Open FocusPilot", action: "open-app" });
  assert.equal(m.hint, "Reopen it to pause, complete, or request an exception.");
  assert.equal(m.exceptionLink, false);
  assert.deepEqual(m.footer, ["Compiled policy rev. 41 · session end 10:51 cached in the extension", "FocusPilot"]);
});

// The offline session variants speak about the session, so a site blocked
// only by another rule keeps naming that rule.
test("without the app, a site blocked only by an always-on rule still says so", () => {
  const strictPast = { now: at("2026-10-14T16:30:00Z"), appRunning: false };
  for (const extra of [strictPast, { appRunning: false }]) {
    const m = view(delivery({ session: session("strict"), focus }), "https://facebook.com/", extra);

    assert.equal(m.kind, "session");
    assert.equal(m.footer[0], "facebook.com is blocked at all times");
    assert.deepEqual(m.primary, { label: "Open FocusPilot", action: "open-app" });
    assert.equal(m.exceptionLink, false);
    assert.equal(m.hint, "FocusPilot isn't running. Exceptions can only be requested while it runs.");
  }
});

test("a page that is no longer blocked offers to go back", () => {
  const m = view(delivery({ session: session(), focus }), "https://youtube.com/watch?v=1", { now: at("2026-10-14T16:00:00Z") });

  assert.equal(m.kind, "unblocked");
  assert.equal(m.title, "youtube.com isn't blocked now");
  assert.deepEqual(m.primary, { label: "Go back to youtube.com", action: "go-back" });
});

test("durations read like the rest of FocusPilot", () => {
  assert.equal(FocusBlockedView.countdown(24 * 60 + 8), "24:08");
  assert.equal(FocusBlockedView.countdown(3600 + 5), "1:00:05");
  assert.equal(FocusBlockedView.relative(45 * 60), "in 45 min");
  assert.equal(FocusBlockedView.relative(26 * 3600 + 60), "in 1 d 2 h");
});
