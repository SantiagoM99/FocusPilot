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
  // A small margin so the alarm never fires a hair before the instant it is meant to apply.
  const when = at == null ? null : at + 250;
  // Safari fires an alarm no sooner than ~30 s after it is created, so recreating it on every
  // reconcile (at least once a minute) kept pushing transitions up to 30 s late. Keep it if it
  // already targets the same instant.
  const existing = await browser.alarms.get("transition");
  if (existing && when != null && Math.abs(existing.scheduledTime - when) < 1000) return;
  await browser.alarms.clear("transition");
  if (when != null) browser.alarms.create("transition", { when });
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
  const { known: knownTabs, reloaded } = await reloadBlockedTabs(result.blockedDomains);
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
    reloaded,
    knownTabs,
    tabs: await testTabs(),
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

// What each test-domain tab shows right now: Safari's error page after a DNR block, the content
// script's blank page, or the site. Host-permitted tabs only, so no "tabs" permission is needed.
async function testTabs() {
  try {
    // Safari's url filter matched nothing here, so list every tab Safari reveals: without the
    // "tabs" permission it hides url and title for hosts outside host_permissions.
    const all = await browser.tabs.query({});
    // Only tabs on hosts the extension may access come with a url (the test domain).
    const test = all.filter((t) => t.url);
    return {
      hostAccess: await browser.permissions.contains({ origins: ["*://*.instagram.com/*"] }),
      total: all.length,
      withoutUrl: all.filter((t) => !t.url).length,
      test: test.map((t) => ({ id: t.id, status: t.status, title: t.title ?? null, url: t.url, active: t.active })),
    };
  } catch (e) {
    return String(e?.message ?? e);
  }
}

// DNR cannot touch a page that is already loaded, and WebKit stops a page's timers while Safari is
// in the background, so the content script cannot be relied on to blank in time. The background
// keeps running, though: reload every known tab on a newly blocked domain so DNR blocks the load.
// Tabs are known from tabs.onUpdated; Safari hides their url from tabs.query.
async function reloadBlockedTabs(blockedDomains) {
  const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
  const out = [];
  for (const [id, info] of Object.entries(tabHosts)) {
    if (info.blockedPage || !blockedDomains.some((d) => P.hostMatches(info.host, d))) continue;
    try {
      await browser.tabs.reload(Number(id));
      out.push({ tabId: Number(id), host: info.host, ok: true });
    } catch (e) {
      out.push({ tabId: Number(id), host: info.host, ok: false, error: String(e?.message ?? e) });
      delete tabHosts[id];
    }
  }
  await browser.storage.local.set({ tabHosts });
  return { known: tabHosts, reloaded: out };
}

browser.tabs.onRemoved.addListener((tabId, removeInfo) => {
  queue(async () => {
    const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
    if (!(tabId in tabHosts)) return;
    delete tabHosts[tabId];
    await browser.storage.local.set({ tabHosts });
    await observe("tab-removed", { tabId, ...removeInfo });
  });
});

// Tab loads on the host-permitted test domain only (no "tabs" permission, so Safari exposes url and
// title only for hosts the extension may access). A DNR-blocked load shows here with Safari's
// error page while content-load never arrives.
browser.tabs.onUpdated.addListener((tabId, change, tab) => {
  let host = null;
  try {
    host = new URL(tab?.url ?? change.url ?? "").hostname;
  } catch {}
  if (!host || !P.hostMatches(host, "instagram.com")) return;
  if (!("status" in change) && !("title" in change) && !("url" in change)) return;
  queue(async () => {
    const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
    // Safari's own error page after a DNR block; reloading it again would only loop.
    const blockedPage = (tab?.title ?? change.title) === "Failed to open page";
    tabHosts[tabId] = { host, blockedPage, at: new Date().toISOString() };
    await browser.storage.local.set({ tabHosts });
    await observe("tab-updated", { tabId, ...change, tabUrl: tab?.url ?? null, tabTitle: tab?.title ?? null, tabStatus: tab?.status ?? null });
  });
});

browser.alarms.get("sync").then((a) => {
  if (!a) browser.alarms.create("sync", { periodInMinutes: SYNC_PERIOD_MINUTES });
});
openPort();
reconcile("worker-start");
