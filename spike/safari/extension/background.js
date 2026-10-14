// Throwaway spike for issue #1. Every wake path calls reconcile(), which fetches the latest
// snapshot through the native handler when it can, and otherwise enforces the last stored policy
// against this worker's own clock. The app never has to be running.
// policy.js is listed before this file in manifest background.scripts and defines FPPolicy.
// Classic scripts, not "type": "module": the Safari converter reports "type" as unsupported.

const P = globalThis.FPPolicy;
// Safari ignores the application identifier and routes to the containing app's handler.
const NATIVE_APP = "com.focuspilot.spike.s1";
const SYNC_PERIOD_MINUTES = 1;
const RULE_BASE = 1000;
const RESOURCE_TYPES = ["main_frame", "sub_frame"];

const workerInstance = crypto.randomUUID();
const workerStartedAt = Date.now();
let port = null;

// Wake events can arrive together (worker start + onStartup + alarm); serialise the
// read-modify-write sections so sequence numbers and rule sets never interleave.
function serial() {
  let tail = Promise.resolve();
  return (fn) => (tail = tail.then(fn, fn));
}
const queue = serial();

async function installId() {
  const { installId } = await browser.storage.local.get("installId");
  if (installId) return installId;
  const id = crypto.randomUUID();
  await browser.storage.local.set({ installId: id, installCreatedAt: new Date().toISOString() });
  return id;
}

async function observe(kind, details = {}) {
  const { nextSeq = 1, outbox = [] } = await browser.storage.local.get(["nextSeq", "outbox"]);
  outbox.push({
    type: "observation",
    kind,
    seq: nextSeq,
    observedAt: new Date().toISOString(),
    installId: await installId(),
    workerInstance,
    workerAgeMs: Date.now() - workerStartedAt,
    ...details,
  });
  await browser.storage.local.set({ nextSeq: nextSeq + 1, outbox });
}

// One native round trip: hands the handler every unsent observation and gets the current policy
// snapshot back. Observations stay in storage until the handler confirms it appended them, so
// nothing is lost when the handler or shared store is unavailable; the app dedupes by
// (installId, seq).
async function exchange(reason) {
  const { outbox = [] } = await browser.storage.local.get("outbox");
  const sentSeqs = new Set(outbox.map((o) => o.seq));
  const startedAt = Date.now();
  try {
    const resp = await browser.runtime.sendNativeMessage(NATIVE_APP, {
      type: "sync",
      reason,
      installId: await installId(),
      workerInstance,
      records: outbox,
    });
    const nativeResult = {
      ok: !!resp?.ok,
      at: new Date().toISOString(),
      roundTripMs: Date.now() - startedAt,
      transport: resp?.transport ?? null,
      handlerPid: resp?.handlerPid ?? null,
      appended: resp?.appended ?? 0,
      stores: resp?.stores ?? null,
      error: resp?.error ?? null,
    };
    if (resp?.ok && resp.appended === outbox.length) {
      const { outbox: current = [] } = await browser.storage.local.get("outbox");
      await browser.storage.local.set({ outbox: current.filter((o) => !sentSeqs.has(o.seq)) });
    }
    await browser.storage.local.set({ lastNative: nativeResult });
    return { policy: resp?.policy ?? null, nativeResult };
  } catch (e) {
    const nativeResult = { ok: false, at: new Date().toISOString(), error: String(e?.message ?? e) };
    await browser.storage.local.set({ lastNative: nativeResult });
    return { policy: null, nativeResult };
  }
}

async function applyRules(domains) {
  const existing = await browser.declarativeNetRequest.getDynamicRules();
  const addRules = domains.map((d, i) => ({
    id: RULE_BASE + i,
    priority: 1,
    action: { type: "block" },
    condition: { urlFilter: `||${d}/`, resourceTypes: RESOURCE_TYPES },
  }));
  await browser.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: existing.map((r) => r.id),
    addRules,
  });
  return addRules.map((r) => r.id);
}

async function scheduleTransition(at) {
  await browser.alarms.clear("transition");
  // A small margin so the alarm never fires a hair before the instant it is meant to apply.
  if (at != null) browser.alarms.create("transition", { when: at + 250 });
}

function reconcile(reason) {
  return queue(() => reconcileNow(reason));
}

async function reconcileNow(reason) {
  const { policy: stored = null, lastEval = null } = await browser.storage.local.get(["policy", "lastEval"]);
  const { policy: fetched, nativeResult } = await exchange(reason);

  let policy = stored;
  if (fetched && (!stored || fetched.revision > stored.revision)) policy = fetched;
  if (fetched && stored && fetched.revision < stored.revision) {
    await observe("rejected-older-revision", { offered: fetched.revision, kept: stored.revision });
  }

  const now = Date.now();
  const result = P.evaluate(policy, now);
  const ruleIds = await applyRules(result.blockedDomains);
  const appliedAt = Date.now();
  await scheduleTransition(result.nextTransitionAt);

  const samePolicy = lastEval && policy && lastEval.revision === policy.revision;
  const overruns = samePolicy
    ? P.passedTransitions(policy, lastEval.at, now).map((t) => ({
        kind: t.kind,
        domain: t.domain,
        scheduledAt: new Date(t.at).toISOString(),
        overrunMs: appliedAt - t.at,
      }))
    : [];

  await browser.storage.local.set({
    policy,
    lastEval: { at: now, appliedAt, revision: policy?.revision ?? null, reason, ...result },
  });

  await observe(policy && (!lastEval || lastEval.revision !== policy.revision) ? "ack" : "reconcile", {
    reason,
    revision: policy?.revision ?? null,
    sessionId: policy?.session?.sessionId ?? null,
    blockedDomains: result.blockedDomains,
    ruleIds,
    sessionActive: result.sessionActive,
    strictPastEnd: result.strictPastEnd,
    activeExceptions: result.activeExceptions,
    nextTransitionAt: result.nextTransitionAt && new Date(result.nextTransitionAt).toISOString(),
    overruns,
    nativeOk: nativeResult.ok,
    nativeError: nativeResult.error,
    nativeTransport: nativeResult.transport ?? null,
    portOpen: !!port,
  });
  // Second round trip so the ack lands in the inbox now rather than on the next wake.
  await exchange(reason + ":ack");
}

// The app can push a nudge with SFSafariApplication.dispatchMessage, which Safari delivers on a
// connectNative port. Pushes only shorten latency; the periodic alarm is the source of truth.
function openPort() {
  try {
    port = browser.runtime.connectNative(NATIVE_APP);
    port.onMessage.addListener((msg) => reconcile("app-push:" + (msg?.name ?? "message")));
    port.onDisconnect.addListener(() => {
      port = null;
    });
  } catch (e) {
    port = null;
    browser.storage.local.set({ lastPortError: String(e?.message ?? e) });
  }
}

browser.runtime.onStartup.addListener(() => reconcile("onStartup"));
browser.runtime.onInstalled.addListener((d) => reconcile("onInstalled:" + d.reason));
browser.alarms.onAlarm.addListener((a) => reconcile("alarm:" + a.name));
browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type === "sync-now") {
    reconcile("popup").then(() => sendResponse({ ok: true }));
    return true;
  }
  if (msg?.type === "page-event") {
    const { type, ...details } = msg;
    queue(() => observe("page-event", { ...details, tabUrlHost: sender?.url ? new URL(sender.url).hostname : null }))
      .then(() => reconcile("page-event"));
    return false;
  }
  return false;
});

browser.alarms.get("sync").then((a) => {
  if (!a) browser.alarms.create("sync", { periodInMinutes: SYNC_PERIOD_MINUTES });
});
openPort();
reconcile("worker-start");
