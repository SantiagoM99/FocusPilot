// The fixture is what the app writes (pinned by ChromeContractTests in
// Swift); these checks run the extension's logic on it as delivered.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";

const require = createRequire(import.meta.url);
const P = require("../../Extensions/Chrome/policy.js");
globalThis.FocusPolicy = P;
const FocusBlockedView = require("../../Extensions/Chrome/blocked-view.js");
const delivery = JSON.parse(readFileSync(new URL("./fixtures/delivery.json", import.meta.url)));
const at = (iso) => Date.parse(iso);

test("the app's policy blocks what its rules say, when they say", () => {
  const { policy } = delivery;
  const during = at("2026-10-14T15:30:00Z");

  assert.equal(P.decide(policy, "https://www.youtube.com/watch?v=1", during).reason, "session");
  assert.equal(P.decide(policy, "https://youtube.com/", at("2026-10-14T18:00:00Z")).blocked, true, "strict keeps blocking");
  assert.equal(P.decide(policy, "https://instagram.com/", during).reason, "always");
  assert.equal(P.decide(policy, "https://tiktok.com/", at("2026-10-13T01:00:00Z")).reason, "schedule", "Mon 20:00 in Bogotá");
  assert.equal(P.decide(policy, "https://tiktok.com/", during).blocked, false);
  assert.deepEqual(P.blockedDomains(policy, during), ["instagram.com", "youtube.com"]);
});

test("the extension reads the schema the app writes", () => {
  assert.equal(P.supports(delivery), true);
});

test("the app's delivery carries what the blocked page and the worker need", () => {
  const m = FocusBlockedView.model({ delivery, url: "https://youtube.com/", now: at("2026-10-14T15:30:00Z"), appRunning: true, timeZone: "America/Bogota" });

  assert.equal(m.title, "Explain baseline results");
  assert.equal(m.subtitle, "Write §4.2");
  assert.equal(P.isNewer({ ...delivery, source: "another data folder", policy: { ...delivery.policy, revision: 1 } }, delivery), true);
});
