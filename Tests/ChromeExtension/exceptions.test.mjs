// Timed exceptions for a site or one page (#14), as the extension enforces
// them on its own clock. Run with scripts/test-extension.sh.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";

const require = createRequire(import.meta.url);
const P = require("../../Extensions/Chrome/policy.js");
const pages = JSON.parse(readFileSync(new URL("./fixtures/pages.json", import.meta.url)));

const at = (iso) => Date.parse(iso);
const now = at("2026-10-14T15:30:00Z");
const BLOCKED = "chrome-extension://id/blocked.html";

const site = (domain, expiresAt = "2026-10-14T15:40:00Z") => ({ scope: { kind: "site", domain }, expiresAt });
const page = (url, expiresAt = "2026-10-14T15:40:00Z") => ({ scope: { kind: "page", url }, expiresAt });
const app = (bundleID, expiresAt = "2026-10-14T15:40:00Z") => ({ scope: { kind: "app", bundleID }, expiresAt });

function policy(exceptions = [], overrides = {}) {
  return {
    schemaVersion: 1, revision: 41, checksum: "c", effectiveAt: "2026-10-14T15:00:00Z",
    always: { domains: ["instagram.com"], apps: [] },
    scheduled: [],
    session: { sessionID: "s", mode: "normal", end: "2026-10-14T15:50:00Z", targets: { domains: ["youtube.com"], apps: [] } },
    allowed: { domains: [], apps: [], tools: [] },
    exceptions,
    ...overrides,
  };
}

test("one page means what the app means by it", () => {
  for (const [typed, canonical] of pages.canonical) {
    assert.equal(P.canonicalPage(typed), canonical, typed);
  }
  for (const [exception, url, matches] of pages.matches) {
    assert.equal(P.pageMatches(exception, url), matches, `${exception} vs ${url}`);
  }
});

test("a site exception lifts the block on that site until it expires", () => {
  const p = policy([site("youtube.com")]);
  const d = P.decide(p, "https://www.youtube.com/watch?v=1", now);
  assert.equal(d.blocked, false);
  assert.equal(d.excepted.expiresAt, at("2026-10-14T15:40:00Z"));
  assert.equal(d.excepted.scope.kind, "site");
  assert.equal(d.domain, "youtube.com");
  assert.equal(P.decide(p, "https://www.youtube.com/watch?v=1", at("2026-10-14T15:40:00Z")).blocked, true, "blocked again at expiry");
  assert.equal(P.decide(p, "https://instagram.com/", now).blocked, true, "other sites stay blocked");
});

test("a page exception lifts only that page; navigating within the site is blocked", () => {
  const p = policy([page("https://youtube.com/watch?v=3kqW9M")]);
  assert.equal(P.decide(p, "https://www.youtube.com/watch?v=3kqW9M&t=10s", now).blocked, false);
  assert.equal(P.decide(p, "https://www.youtube.com/watch?v=next", now).blocked, true);
  assert.equal(P.decide(p, "https://www.youtube.com/", now).blocked, true);
});

test("an exception covers any rule kind, as app exceptions do", () => {
  const p = policy([site("instagram.com")]);
  assert.equal(P.decide(p, "https://instagram.com/", now).blocked, false);
});

test("app exceptions and expired ones change nothing for sites", () => {
  const p = policy([app("youtube.com"), site("youtube.com", "2026-10-14T15:00:00Z")]);
  assert.equal(P.decide(p, "https://youtube.com/", now).blocked, true);
});

test("of two exceptions covering a page the later expiry counts", () => {
  const p = policy([page("https://youtube.com/watch?v=a", "2026-10-14T15:35:00Z"), site("youtube.com", "2026-10-14T15:45:00Z")]);
  assert.equal(P.decide(p, "https://youtube.com/watch?v=a", now).excepted.expiresAt, at("2026-10-14T15:45:00Z"));
});

test("an exception's expiry is a boundary, so worker and page re-check then", () => {
  const p = policy([page("https://youtube.com/watch?v=a", "2026-10-14T15:35:00Z")]);
  assert.equal(P.nextBoundary(p, now), at("2026-10-14T15:35:00Z"));
  assert.equal(P.nextBoundary(p, at("2026-10-14T15:36:00Z")), at("2026-10-14T15:50:00Z"), "an expired one is no longer a boundary");
});

test("network rules leave excepted sites out and let excepted pages load", () => {
  const p = policy([site("instagram.com"), page("https://youtube.com/watch?v=3kqW9M")]);
  const rules = P.networkRules(p, now, BLOCKED);

  const redirect = rules.find((r) => r.id === 1);
  assert.deepEqual(redirect.condition.requestDomains, ["instagram.com", "youtube.com"]);
  assert.deepEqual(redirect.condition.excludedRequestDomains, ["instagram.com"]);
  assert.equal(redirect.action.redirect.regexSubstitution, BLOCKED + "#\\0");
  assert.deepEqual(rules.find((r) => r.id === 2).condition.excludedRequestDomains, ["instagram.com"]);

  const allow = rules.filter((r) => r.action.type === "allowAllRequests");
  assert.equal(allow.length, 1);
  assert.ok(allow[0].priority > redirect.priority);
  assert.deepEqual(allow[0].condition.resourceTypes, ["main_frame"]);
  const re = new RegExp(allow[0].condition.regexFilter);
  assert.ok(re.test("https://www.youtube.com/watch?v=3kqW9M"));
  assert.ok(re.test("https://youtube.com/watch?feature=share&v=3kqW9M&t=1#x"));
  assert.ok(!re.test("https://www.youtube.com/watch?v=3kqW9Mx"));
  assert.ok(!re.test("https://www.youtube.com/watch?v=other"));
  assert.ok(!re.test("https://evil.com/?u=https://youtube.com/watch?v=3kqW9M"));
});

test("a page without a query covers only itself, not every query on its path", () => {
  const p = policy([page("https://youtube.com/watch")]);
  assert.equal(P.decide(p, "https://www.youtube.com/watch?v=any", now).blocked, true);
  assert.equal(P.decide(p, "https://www.youtube.com/watch?t=4", now).blocked, false);
  const re = new RegExp(P.pageAllowRule(page("https://youtube.com/watch"), 10).condition.regexFilter);
  assert.ok(re.test("https://www.youtube.com/watch"));
  assert.ok(re.test("https://www.youtube.com/watch?t=4&pp=x#c"));
  assert.ok(!re.test("https://www.youtube.com/watch?v=any"));
  assert.ok(!re.test("https://www.youtube.com/watch?t=4&v=any"));
});

test("network rules ignore expired exceptions and need none without blocks", () => {
  const p = policy([site("youtube.com", "2026-10-14T15:00:00Z")]);
  const redirect = P.networkRules(p, now, BLOCKED).find((r) => r.id === 1);
  assert.equal(redirect.condition.excludedRequestDomains, undefined);
  assert.deepEqual(P.networkRules(policy([], { always: { domains: [], apps: [] }, session: null }), now, BLOCKED), []);
});

test("a page with several parameters needs exactly those, in any order, plus ignorable ones", () => {
  const rule = P.pageAllowRule(page("https://example.com/docs/page?a=1&b=2&c=3"), 10);
  const re = new RegExp(rule.condition.regexFilter);
  assert.ok(re.test("https://example.com/docs/page?c=3&a=1&b=2"));
  assert.ok(re.test("https://www.example.com/docs/page?b=2&utm_source=mail&a=1&c=3&fbclid=x"));
  assert.ok(!re.test("https://www.example.com/docs/page?b=2&x=9&a=1&c=3"), "an unknown extra parameter is another page");
  assert.ok(!re.test("https://example.com/docs/page?a=1&b=2"));
  assert.ok(!re.test("https://example.com/docs/pages?a=1&b=2&c=3"));
});

test("past three parameters the network rule allows the path and the page script judges the rest", () => {
  const rule = P.pageAllowRule(page("https://example.com/p?a=1&b=2&c=3&d=4"), 10);
  const re = new RegExp(rule.condition.regexFilter);
  assert.ok(re.test("https://example.com/p?a=1"));
  assert.equal(P.decide(policy([page("https://example.com/p?a=1&b=2&c=3&d=4")], { always: { domains: ["example.com"], apps: [] } }),
    "https://example.com/p?a=1", now).blocked, true);
});

test("page rules match letter case exactly, as video ids do", () => {
  const rule = P.pageAllowRule(page("https://youtube.com/watch?v=abc"), 10);
  assert.equal(rule.condition.isUrlFilterCaseSensitive, true);
});

test("a page Chrome cannot take as a regex falls back to its path, not to no carve-out", () => {
  const p = policy([page("https://youtube.com/watch?v=3kqW9M"), page("https://youtube.com/watch?v=other")]);
  assert.deepEqual(P.pageURLs(p, now), ["https://youtube.com/watch?v=3kqW9M", "https://youtube.com/watch?v=other"]);
  const rules = P.networkRules(p, now, BLOCKED, { pathOnly: new Set(["https://youtube.com/watch?v=other"]) });
  const [first, second] = rules.filter((r) => r.action.type === "allowAllRequests");
  assert.ok(first.condition.regexFilter.includes("v=3kqW9M"));
  assert.equal(second.condition.regexFilter, "^https?://(?:www\\.)?youtube\\.com/watch(?:[?#].*)?$");
});
