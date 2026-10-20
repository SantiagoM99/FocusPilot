// Run with scripts/test-extension.sh (node --test, no packages).
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const P = require("../../Extensions/Chrome/policy.js");

const at = (iso) => Date.parse(iso);
const weekdays = { days: ["mon", "tue", "wed", "thu", "fri"], start: "08:00", end: "18:00", timeZone: "America/Bogota" };
const evenings = { days: ["fri"], start: "22:00", end: "02:00", timeZone: "America/Bogota" };

function policy(overrides = {}) {
  return {
    schemaVersion: 1, revision: 41, checksum: "c", effectiveAt: "2026-10-14T15:00:00Z",
    always: { domains: ["instagram.com"], apps: [] },
    scheduled: [{ schedule: weekdays, targets: { domains: ["reddit.com"], apps: [] } }],
    session: null,
    allowed: { domains: ["overleaf.com"], apps: [], tools: [] },
    ...overrides,
  };
}

const session = (mode, end = "2026-10-14T15:50:00Z", extra = {}) => ({
  sessionID: "00000000-0000-0000-0000-000000000001", mode, end, targets: { domains: ["youtube.com"], apps: [] }, ...extra,
});

// Wednesday 2026-10-14 10:00 in Bogotá (UTC-5).
const wednesdayMorning = at("2026-10-14T15:00:00Z");

test("always-on domains block with no session, subdomains included", () => {
  const p = policy();
  assert.deepEqual(P.decide(p, "https://www.instagram.com/reel/1", wednesdayMorning), { blocked: true, reason: "always", domain: "instagram.com" });
  assert.equal(P.decide(p, "https://notinstagram.com/", wednesdayMorning).blocked, false);
  assert.equal(P.decide(p, "chrome://extensions", wednesdayMorning).blocked, false);
});

test("schedules are evaluated in their own time zone", () => {
  const p = policy();
  assert.equal(P.decide(p, "https://reddit.com/", wednesdayMorning).reason, "schedule");
  // 18:30 in Bogotá is 23:30 UTC: outside the window.
  assert.equal(P.decide(p, "https://reddit.com/", at("2026-10-14T23:30:00Z")).blocked, false);
  // Saturday.
  assert.equal(P.decide(p, "https://reddit.com/", at("2026-10-17T15:00:00Z")).blocked, false);
});

test("an overnight window belongs to the day it starts", () => {
  assert.equal(P.scheduleContains(evenings, at("2026-10-17T03:00:00Z")), true); // Fri 22:00 Bogotá
  assert.equal(P.scheduleContains(evenings, at("2026-10-17T06:30:00Z")), true); // Sat 01:30
  assert.equal(P.scheduleContains(evenings, at("2026-10-17T07:00:00Z")), false); // Sat 02:00
  assert.equal(P.scheduleContains(evenings, at("2026-10-16T06:30:00Z")), false); // Fri 01:30, Thursday not listed
});

test("session rules apply until a normal session's planned end", () => {
  const p = policy({ session: session("normal") });
  assert.equal(P.decide(p, "https://youtube.com/watch?v=1", wednesdayMorning).reason, "session");
  assert.equal(P.decide(p, "https://youtube.com/", at("2026-10-14T15:50:00Z")).blocked, false);
});

test("a strict session keeps blocking past its end until the app says it ended", () => {
  const p = policy({ session: session("strict") });
  assert.equal(P.decide(p, "https://youtube.com/", at("2026-10-14T18:00:00Z")).blocked, true);
  assert.equal(P.strictPastEnd(p, at("2026-10-14T18:00:00Z")), true);
});

test("a normal break lifts session rules until it ends", () => {
  const p = policy({ session: session("normal", "2026-10-14T15:50:00Z", { resumesAt: "2026-10-14T15:10:00Z" }) });
  assert.equal(P.decide(p, "https://youtube.com/", wednesdayMorning).blocked, false);
  assert.equal(P.decide(p, "https://youtube.com/", at("2026-10-14T15:10:00Z")).blocked, true);
});

test("a session explains a page even when another rule also blocks it", () => {
  const p = policy({ session: session("normal", "2026-10-14T15:50:00Z", { targets: { domains: ["youtube.com", "instagram.com"], apps: [] } }) });
  assert.equal(P.decide(p, "https://instagram.com/", wednesdayMorning).reason, "session");
});

test("blocked domains are what the network rules need right now", () => {
  const p = policy({ session: session("normal") });
  assert.deepEqual(P.blockedDomains(p, wednesdayMorning), ["instagram.com", "reddit.com", "youtube.com"]);
  assert.deepEqual(P.blockedDomains(null, wednesdayMorning), []);
});

test("the next boundary is the earliest change: session end, break end or schedule edge", () => {
  assert.equal(P.nextBoundary(policy({ session: session("normal") }), wednesdayMorning), at("2026-10-14T15:50:00Z"));
  const onBreak = policy({ session: session("normal", "2026-10-14T15:50:00Z", { resumesAt: "2026-10-14T15:10:00Z" }) });
  assert.equal(P.nextBoundary(onBreak, wednesdayMorning), at("2026-10-14T15:10:00Z"));
  // No session: the weekday schedule ends at 18:00 Bogotá.
  assert.equal(P.nextBoundary(policy(), wednesdayMorning), at("2026-10-14T23:00:00Z"));
  // Strict past its end: nothing changes until the app publishes.
  assert.equal(P.nextBoundary(policy({ scheduled: [], session: session("strict") }), at("2026-10-14T18:00:00Z")), null);
});

test("a schedule's next change can be days away", () => {
  // Friday 18:00 Bogotá ends; next start is Monday 08:00.
  assert.equal(P.scheduleNextChange(weekdays, at("2026-10-16T23:00:00Z")), at("2026-10-19T13:00:00Z"));
});

test("only newer revisions replace the stored policy", () => {
  assert.equal(P.isNewer({ revision: 42 }, { revision: 41 }), true);
  assert.equal(P.isNewer({ revision: 41 }, { revision: 41 }), false);
  assert.equal(P.isNewer({ revision: 3 }, null), true);
});
