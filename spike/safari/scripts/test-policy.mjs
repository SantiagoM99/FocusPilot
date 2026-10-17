// Checks extension/policy.js against the enforcement rules in the Architecture
// (Enforcement ownership). Run: node spike/safari/scripts/test-policy.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const ctx = { globalThis: {}, URL };
vm.runInNewContext(readFileSync(new URL("../extension/policy.js", import.meta.url), "utf8"), ctx);
const P = ctx.globalThis.FPPolicy;

const t0 = Date.parse("2026-10-14T10:00:00Z");
const at = (min) => new Date(t0 + min * 60_000).toISOString();
const policy = (mode, endMin, exceptions = [], ended = false) => ({
  revision: 1, alwaysOn: [],
  session: { sessionId: "s", mode, startsAt: at(0), endsAt: at(endMin), ended, domains: ["instagram.com"], exceptions },
});
const blockedAt = (p, min) => P.evaluate(p, t0 + min * 60_000).blockedDomains;

const normal = policy("normal", 10);
assert.deepEqual([...blockedAt(normal, 5)], ["instagram.com"], "blocks during a normal session");
assert.deepEqual([...blockedAt(normal, 10)], [], "normal session stops at its end without the app");
assert.equal(P.evaluate(normal, t0 + 5 * 60_000).nextTransitionAt, t0 + 10 * 60_000);

const strict = policy("strict", 10);
assert.deepEqual([...blockedAt(strict, 30)], ["instagram.com"], "strict keeps blocking past its end");
assert.equal(P.evaluate(strict, t0 + 30 * 60_000).strictPastEnd, true);
assert.deepEqual([...blockedAt(policy("strict", 10, [], true), 30)], [], "strict stops once the app writes ended");

const withExc = policy("normal", 10, [{ id: "e", domain: "instagram.com", expiresAt: at(3) }]);
assert.deepEqual([...blockedAt(withExc, 2)], [], "exception allows the site");
assert.deepEqual([...blockedAt(withExc, 3)], ["instagram.com"], "exception expires at its instant");
assert.equal(P.evaluate(withExc, t0 + 2 * 60_000).nextTransitionAt, t0 + 3 * 60_000);
const strictExc = policy("strict", 10, [{ id: "e", domain: "instagram.com", expiresAt: at(3) }]);
assert.deepEqual([...blockedAt(strictExc, 4)], ["instagram.com"], "exceptions expire in strict mode too");

// A wake 7 minutes after the exception expiry and 1 minute after the end reports both overruns.
const passed = [...P.passedTransitions(withExc, t0 + 2 * 60_000, t0 + 11 * 60_000).map((t) => t.kind)].sort();
assert.deepEqual(passed, ["exception-expiry", "session-end"]);
assert.deepEqual([...P.passedTransitions(withExc, null, t0)], [], "no previous evaluation, no overrun");

assert.equal(P.hostMatches("www.instagram.com", "instagram.com"), true);
assert.equal(P.hostMatches("notinstagram.com", "instagram.com"), false);
assert.deepEqual([...P.evaluate(null, t0).blockedDomains], [], "no policy blocks nothing");
console.log("policy.js: all checks passed");

// S3: a URL-scoped exception allows one YouTube video and nothing else on the domain.
const yt = { revision: 2, alwaysOn: [], session: { sessionId: "y", mode: "normal", startsAt: at(0), endsAt: at(10), ended: false,
  domains: ["instagram.com", "youtube.com"], exceptions: [{ id: "u", domain: "youtube.com", url: "https://www.youtube.com/watch?v=AAA", expiresAt: at(3) }] } };
const r2 = P.evaluate(yt, t0 + 2 * 60_000);
assert.equal(P.isBlocked(r2, "https://www.youtube.com/watch?v=AAA&t=30s"), false, "the excepted video plays");
assert.equal(P.isBlocked(r2, "https://www.youtube.com/watch?v=BBB"), true, "another video is blocked");
assert.equal(P.isBlocked(r2, "https://www.youtube.com/"), true, "the home page is blocked");
assert.equal(P.isBlocked(P.evaluate(yt, t0 + 3 * 60_000), "https://www.youtube.com/watch?v=AAA"), true, "the video is blocked at expiry");
assert.equal(P.evaluate(yt, t0 + 2 * 60_000).nextTransitionAt, t0 + 3 * 60_000);
