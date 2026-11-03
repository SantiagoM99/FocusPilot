// Pages linked to the session's projects on blocked sites (owner decision
// 0003, 2026-11-03): in a normal session that exact page opens, matched as
// #14 matches a page exception; other pages on the site stay blocked, and a
// strict session never lets one through. The fixture is what the app
// writes (ChromeContractTests). Run with scripts/test-extension.sh.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";

const require = createRequire(import.meta.url);
const P = require("../../Extensions/Chrome/policy.js");
globalThis.FocusPolicy = P;
const FocusBlockedView = require("../../Extensions/Chrome/blocked-view.js");
const delivery = JSON.parse(readFileSync(new URL("./fixtures/linked-pages.json", import.meta.url)));
const { policy } = delivery;
const at = (iso) => Date.parse(iso);
const during = at("2026-10-14T15:30:00Z");
const end = at("2026-10-14T15:50:00Z");
const BLOCKED = "chrome-extension://id/blocked.html";
const lecture = "https://www.youtube.com/watch?v=lecture7";

test("the app writes linked pages canonical, in the session", () => {
  assert.deepEqual(policy.session.allowedPages,
    ["https://reddit.com/r/MachineLearning/comments/abc", "https://youtube.com/watch?v=lecture7"]);
});

test("in a normal session the linked page opens, that page only", () => {
  const d = P.decide(policy, lecture + "&t=95s", during);
  assert.equal(d.blocked, false);
  assert.equal(d.linked, "https://youtube.com/watch?v=lecture7");
  assert.equal(d.excepted, undefined, "not a timed exception");
  assert.equal(P.decide(policy, "https://www.youtube.com/watch?v=next", during).blocked, true);
  assert.equal(P.decide(policy, "https://www.youtube.com/", during).blocked, true);
});

test("a linked page on an always-blocked site opens during the session and is blocked after it", () => {
  const thread = "https://www.reddit.com/r/MachineLearning/comments/abc";
  assert.equal(P.decide(policy, thread, during).blocked, false);
  assert.equal(P.decide(policy, "https://reddit.com/r/MachineLearning", during).blocked, true);
  assert.equal(P.decide(policy, thread, end).blocked, true, "blocked again at the planned end");
  assert.equal(P.nextBoundary(policy, during), end);
});

test("during a normal break the linked page on an always-blocked site still opens", () => {
  const onBreak = { ...policy, session: { ...policy.session, resumesAt: "2026-10-14T15:40:00Z" } };
  assert.equal(P.decide(onBreak, "https://reddit.com/r/MachineLearning/comments/abc", during).blocked, false);
});

test("a strict session never lets a linked page through", () => {
  const strict = { ...policy, session: { ...policy.session, mode: "strict" } };
  assert.equal(P.decide(strict, lecture, during).blocked, true);
  assert.equal(P.decide(strict, "https://reddit.com/r/MachineLearning/comments/abc", during).blocked, true);
  assert.deepEqual(P.pageURLs(strict, during), []);
});

test("without a session no linked page is allowed", () => {
  const none = { ...policy, session: null };
  assert.equal(P.decide(none, "https://reddit.com/r/MachineLearning/comments/abc", during).blocked, true);
});

test("the network rules let each linked page load past the redirect", () => {
  const rules = P.networkRules(policy, during, BLOCKED);
  const allows = rules.filter((r) => r.action.type === "allowAllRequests");
  assert.equal(allows.length, 2);
  const lectureRule = allows.find((r) => new RegExp(r.condition.regexFilter).test("https://www.youtube.com/watch?v=lecture7&t=95s"));
  assert.ok(lectureRule, "the lecture loads, position ignored");
  assert.equal(new RegExp(lectureRule.condition.regexFilter).test("https://www.youtube.com/watch?v=next"), false);
  assert.equal(P.networkRules(policy, end, BLOCKED).filter((r) => r.action.type === "allowAllRequests").length, 0,
    "gone after the planned end");
});

test("a linked page and a page exception for the same page get one rule", () => {
  const both = { ...policy, exceptions: [{ scope: { kind: "page", url: lecture }, expiresAt: "2026-10-14T15:40:00Z" }] };
  assert.deepEqual(P.pageURLs(both, during), policy.session.allowedPages);
});

test("the blocked page says a linked page is allowed in this session", () => {
  const m = FocusBlockedView.model({ delivery, url: lecture, now: during, appRunning: true, timeZone: "America/Bogota" });
  assert.equal(m.kind, "linked");
  assert.equal(m.status.text, "Linked to a task in this session");
  assert.equal(m.title, "This page is allowed in this session");
  assert.equal(m.subtitle, "It’s linked to a task in the session, so it opens until 10:50. Other pages on youtube.com stay blocked.");
  assert.equal(m.primary.label, "Go back to youtube.com");
});
