// Observe-only mode (#21): the worker reports the domain of the tab in
// front, and only while the app's delivery says observe. Never a URL.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { startWorker } from "./support/fake-chrome.mjs";

const delivery = JSON.parse(readFileSync(new URL("./fixtures/delivery.json", import.meta.url)));
const policyFrame = (revision, observe) => ({
  type: "policy", policy: { ...delivery.policy, revision }, focus: null, source: "observe-test",
  ...(observe ? { observe: true } : {}),
});

async function started({ observe }) {
  const worker = startWorker("2026-10-14T15:00:00Z");
  worker.tabs.set([
    { id: 1, windowId: 10, url: "https://www.github.com/owner/repo?q=secret", active: true, incognito: false },
    { id: 2, windowId: 10, url: "https://youtube.com/watch?v=1", active: false, incognito: false },
    { id: 3, windowId: 20, url: "https://private.example.com/", active: true, incognito: true },
  ]);
  worker.tabs.focusWindow(10);
  await worker.receive([policyFrame(5, observe)]);
  return worker;
}

const fronts = (worker) => worker.toHost.filter((m) => m.kind === "tab-front");

test("while observing, the front tab's domain is reported, without www or the path", async () => {
  const worker = await started({ observe: true });

  assert.deepEqual(fronts(worker).map((m) => m.domain), ["github.com"]);
  const sent = JSON.stringify(fronts(worker));
  assert.ok(!sent.includes("repo") && !sent.includes("secret"), "no path or query");
  assert.equal(fronts(worker)[0].url, undefined);
});

test("switching tabs reports the new domain, once per change", async () => {
  const worker = await started({ observe: true });

  await worker.tabs.activate(2);
  await worker.tabs.activate(2);

  assert.deepEqual(fronts(worker).map((m) => m.domain), ["github.com", "youtube.com"]);
});

test("a navigation in the front tab reports its new domain", async () => {
  const worker = await started({ observe: true });

  await worker.tabs.navigate(1, "https://news.ycombinator.com/");

  assert.deepEqual(fronts(worker).map((m) => m.domain), ["github.com", "news.ycombinator.com"]);
});

test("Chrome losing focus reports no domain; incognito and browser pages are never named", async () => {
  const worker = await started({ observe: true });

  await worker.tabs.focusWindow(-1);
  await worker.tabs.focusWindow(20);
  await worker.tabs.focusWindow(10);
  await worker.tabs.navigate(1, "chrome://settings/");

  assert.deepEqual(fronts(worker).map((m) => m.domain), ["github.com", null, "github.com", null]);
});

test("without observe mode nothing is reported", async () => {
  const worker = await started({ observe: false });

  await worker.tabs.activate(2);
  await worker.tabs.focusWindow(-1);

  assert.deepEqual(fronts(worker), []);
});

test("turning observe off stops the reports", async () => {
  const worker = await started({ observe: true });

  await worker.receive([policyFrame(6, false)]);
  await worker.tabs.activate(2);

  assert.deepEqual(fronts(worker).map((m) => m.domain), ["github.com"]);
});
