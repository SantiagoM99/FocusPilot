// End to end: FocusPilot quits mid-session (#15). The frames are what the
// app's host sends in that story (pinned by SessionWithoutAppTests in Swift);
// the real service worker handles them on its own clock, and the blocked
// page is rendered from what it stored.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { startWorker } from "./support/fake-chrome.mjs";

const require = createRequire(import.meta.url);
globalThis.FocusPolicy = require("../../Extensions/Chrome/policy.js");
const FocusBlockedView = require("../../Extensions/Chrome/blocked-view.js");
const story = JSON.parse(readFileSync(new URL("./fixtures/quit-mid-session.json", import.meta.url)));

async function replay(mode) {
  const steps = Object.fromEntries(story[mode].map((s) => [s.step, s]));
  const worker = startWorker(steps["session-started"].at);
  await worker.settle();
  const page = (url) => FocusBlockedView.model({
    delivery: worker.stored("delivery"), appRunning: worker.stored("appRunning"), url, now: worker.now(), timeZone: "America/Bogota",
  });
  const at = async (name) => {
    await worker.advanceTo(steps[name].at);
    await worker.receive(steps[name].frames);
  };
  return { worker, page, at };
}

for (const mode of ["normal", "strict"]) {
  test(`${mode}: once the app quits, the blocked page says so and how to reopen it`, async () => {
    const { worker, page, at } = await replay(mode);
    await at("session-started");
    assert.deepEqual(worker.blockedDomains(), ["instagram.com", "youtube.com"]);

    await at("app-quit");

    const m = page("https://www.youtube.com/watch?v=1");
    assert.equal(m.status.text, "FocusPilot isn't running");
    assert.equal(m.primary.label, "Open FocusPilot");
    assert.match(m.hint, /Applications.*Spotlight/);
    assert.equal(m.exceptionLink, false);
    assert.equal(m.kind, mode === "strict" ? "strict-offline" : "normal-offline");
    assert.equal(m.title, mode === "strict" ? "Still blocked · strict session" : "Still blocked until 10:25");
    assert.match(page("https://instagram.com/").hint, /isn't running.*Applications.*Spotlight/);
  });
}

test("normal: the session's sites unblock at the planned end without the app; always-on rules stay", async () => {
  const { worker, page, at } = await replay("normal");
  await at("session-started");
  await at("app-quit");

  await at("past-planned-end");

  assert.deepEqual(worker.blockedDomains(), ["instagram.com"]);
  assert.equal(page("https://youtube.com/").kind, "unblocked");
  assert.equal(page("https://instagram.com/").title, "instagram.com is blocked at all times");
});

test("strict: the session's sites stay blocked past the planned end until the app confirms the end", async () => {
  const { worker, page, at } = await replay("strict");
  await at("session-started");
  await at("app-quit");

  await at("past-planned-end");

  assert.deepEqual(worker.blockedDomains(), ["instagram.com", "youtube.com"]);
  assert.equal(page("https://youtube.com/").kind, "strict-offline");

  await at("app-relaunched");

  assert.deepEqual(worker.blockedDomains(), ["instagram.com"]);
  assert.equal(page("https://youtube.com/").kind, "unblocked");
  assert.equal(page("https://instagram.com/").title, "instagram.com is blocked at all times");
});

test("the worker acknowledges each policy it applied while the app was away", async () => {
  const { worker, at } = await replay("strict");
  await at("session-started");
  await at("app-quit");
  await at("past-planned-end");
  await at("app-relaunched");

  const applied = worker.toHost.filter((m) => m.kind === "policy-applied").map((m) => m.revision);
  assert.deepEqual(applied, [3, 4]);
});
