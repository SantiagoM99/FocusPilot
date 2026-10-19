// Throwaway spike for issues #1 and #3. Every wake path calls reconcile(), which fetches the latest
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
  // S3: Safari's storage.local quota was hit (every later set threw), so cap the unsent outbox.
  if (outbox.length > 200) outbox.splice(0, outbox.length - 200);
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
  try {
    await browser.storage.local.set({ nextSeq: nextSeq + 1, outbox });
  } catch (e) {
    await browser.storage.local.set({ nextSeq: nextSeq + 1, outbox: outbox.slice(-20), lastStorageError: String(e?.message ?? e) });
  }
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
    // Storage writes must not lose the response (S3: Safari threw "Exceeded storage quota" here).
    try {
      if (resp?.ok && resp.appended === outbox.length) {
        const { outbox: current = [] } = await browser.storage.local.get("outbox");
        await browser.storage.local.set({ outbox: current.filter((o) => !sentSeqs.has(o.seq)) });
      }
      await browser.storage.local.set({ lastNative: nativeResult });
    } catch (e) {
      nativeResult.storageError = String(e?.message ?? e);
      await browser.storage.local.remove("outbox").catch(() => {});
    }
    return { policy: resp?.policy ?? null, command: resp?.command ?? null, nativeResult };
  } catch (e) {
    const nativeResult = { ok: false, at: new Date().toISOString(), error: String(e?.message ?? e) };
    await browser.storage.local.set({ lastNative: nativeResult });
    return { policy: null, nativeResult };
  }
}

// S3: blocked loads go to the extension's own blocked page (DNR redirect to extensionPath) instead
// of Safari's "Failed to open page"; if Safari refuses the redirect rule, plain block is the
// fallback. URL-scoped exceptions are higher-priority allow rules for that one page.
const BLOCKED_PAGE = "blocked.html";
async function applyRules(result) {
  const existing = await browser.declarativeNetRequest.getDynamicRules();
  const rules = (type) => [
    ...result.blockedDomains.map((d, i) => ({
      id: RULE_BASE + i,
      priority: 1,
      action: type === "redirect" ? { type, redirect: { extensionPath: "/" + BLOCKED_PAGE } } : { type },
      condition: { urlFilter: `||${d}/`, resourceTypes: ["main_frame"] },
    })),
    ...result.blockedDomains.map((d, i) => ({
      id: RULE_BASE + 100 + i,
      priority: 1,
      action: { type: "block" },
      condition: { urlFilter: `||${d}/`, resourceTypes: ["sub_frame"] },
    })),
    ...result.allowedUrls.map((a, i) => ({
      id: RULE_BASE + 200 + i,
      priority: 2,
      action: { type: "allow" },
      condition: { urlFilter: "||" + a.key, resourceTypes: RESOURCE_TYPES },
    })),
  ];
  const { dnrMode = "redirect" } = await browser.storage.local.get("dnrMode");
  let action = dnrMode;
  try {
    await browser.declarativeNetRequest.updateDynamicRules({ removeRuleIds: existing.map((r) => r.id), addRules: rules(dnrMode) });
  } catch (e) {
    action = "block";
    await observe("dnr-redirect-refused", { error: String(e?.message ?? e) });
    await browser.declarativeNetRequest.updateDynamicRules({ removeRuleIds: existing.map((r) => r.id), addRules: rules("block") });
  }
  return { action, ids: (await browser.declarativeNetRequest.getDynamicRules()).map((r) => r.id) };
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
  const { policy: fetched, command, nativeResult } = await exchange(reason);
  // Commands first: closing probe tabs must not wait on anything that can fail below.
  const commandResult = await runCommand(command);

  let policy = stored;
  if (fetched && (!stored || fetched.revision > stored.revision)) policy = fetched;
  if (fetched && stored && fetched.revision < stored.revision) {
    await observe("rejected-older-revision", { offered: fetched.revision, kept: stored.revision });
  }

  const now = Date.now();
  const result = P.evaluate(policy, now);
  const { action: dnrAction, ids: ruleIds } = await applyRules(result);
  const appliedAt = Date.now();
  const { known: knownTabs, redirected, ownerTabsSkipped } = await enforceOpenTabs(result, reason);
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
    dnrAction,
    allowedUrls: result.allowedUrls,
    sessionActive: result.sessionActive,
    strictPastEnd: result.strictPastEnd,
    activeExceptions: result.activeExceptions,
    nextTransitionAt: result.nextTransitionAt && new Date(result.nextTransitionAt).toISOString(),
    overruns,
    nativeOk: nativeResult.ok,
    nativeError: nativeResult.error,
    storageError: nativeResult.storageError ?? null,
    nativeTransport: nativeResult.transport ?? null,
    portOpen: !!port,
    redirected,
    ownerTabsSkipped,
    commandResult,
    knownTabCount: Object.keys(knownTabs).length,
    hostAccess: await hostAccess(),
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
    const tabId = sender?.tab?.id ?? null;
    queue(async () => {
      if ((await releasedProbes()).includes(details.probe)) return;
      if (details.probe && tabId != null) await trackTab(tabId, sender.url, { probe: details.probe });
      await observe("page-event", { ...details, tabId, receivedAtMs: Date.now() });
    });
    return false;
  }
  // The content script found its page blocked (expiry, SPA navigation, new policy) and has
  // already stopped media; the browser performs the navigation, which page timers cannot block.
  if (msg?.type === "hello") {
    releasedProbes().then((r) => sendResponse({ released: r.includes(msg.probe) }));
    return true;
  }
  if (msg?.type === "enforce-me") {
    const tabId = sender?.tab?.id;
    queue(async () => {
      if ((await releasedProbes()).includes(msg.probe)) return { ok: false, released: true };
      const r = await redirectTab(tabId, sender.url, "content:" + msg.reason);
      await observe("enforce-me", { tabId, reason: msg.reason, href: msg.href, ...r });
      return r;
    }).then(sendResponse);
    return true;
  }
  if (msg?.type === "blocked-page-load") {
    const tabId = sender?.tab?.id ?? null;
    queue(async () => {
      const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
      if (tabId != null && tabHosts[tabId]) {
        tabHosts[tabId] = { ...tabHosts[tabId], onBlockedPage: true, at: new Date().toISOString() };
        await browser.storage.local.set({ tabHosts });
      }
      await observe("blocked-page-load", { tabId, loadedAtMs: msg.loadedAtMs, params: msg.params, probe: tabHosts[tabId]?.probe ?? null });
    });
    return false;
  }
  return false;
});

async function hostAccess() {
  const out = {};
  for (const d of ["instagram.com", "youtube.com"]) {
    try {
      out[d] = await browser.permissions.contains({ origins: [`*://*.${d}/*`] });
    } catch (e) {
      out[d] = String(e?.message ?? e);
    }
  }
  return out;
}

// Tabs are known from tabs.onUpdated and content-script messages; Safari hides their url from
// tabs.query (S1 finding 3). The spike only ever navigates or closes probe tabs: tabs it opened
// itself with #fp-probe=NAME. The owner's own tabs on these domains are counted and left alone.
const WATCHED = ["instagram.com", "youtube.com"];
async function trackTab(tabId, url, extra = {}) {
  const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
  const prev = tabHosts[tabId] ?? {};
  let host = null;
  try {
    host = new URL(url).hostname;
  } catch {}
  const probe = extra.probe ?? prev.probe ?? (url?.match(/[#&]fp-probe=([\w-]+)/)?.[1] || null);
  tabHosts[tabId] = { ...prev, host, url: probe ? url : null, probe, onBlockedPage: false, at: new Date().toISOString() };
  await browser.storage.local.set({ tabHosts });
  return tabHosts[tabId];
}

function blockedPageUrl(params) {
  return browser.runtime.getURL(BLOCKED_PAGE) + "?" + new URLSearchParams(params);
}

async function redirectTab(tabId, fromUrl, why) {
  const at = Date.now();
  try {
    await browser.tabs.update(tabId, { url: blockedPageUrl({ why, at, from: fromUrl ?? "" }) });
    return { ok: true, redirectCalledAtMs: at, updateMs: Date.now() - at };
  } catch (e) {
    return { ok: false, redirectCalledAtMs: at, error: String(e?.message ?? e) };
  }
}

// DNR cannot touch a page that is already loaded, so on every policy evaluation each known probe
// tab whose page is now blocked is sent to the blocked page. This is the "redirect matching open
// tabs on activation" path, and the backstop when a page's own timer is late or suspended.
async function enforceOpenTabs(result, reason) {
  const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
  const redirected = [];
  let ownerTabsSkipped = 0;
  for (const [id, info] of Object.entries(tabHosts)) {
    if (info.onBlockedPage || !info.host || !result.blockedDomains.some((d) => P.hostMatches(info.host, d))) continue;
    if (!info.probe) {
      ownerTabsSkipped++;
      continue;
    }
    if (!P.isBlocked(result, info.url)) continue;
    const r = await redirectTab(Number(id), info.url, "background:" + reason);
    redirected.push({ tabId: Number(id), probe: info.probe, url: info.url, ...r });
    if (r.ok) tabHosts[id] = { ...info, onBlockedPage: true };
    else delete tabHosts[id];
  }
  // Tab ids change when the extension reloads (S3), so tracked ids go stale and tabs opened before
  // the reload are unknown. Sweep tabs.query too: Safari returns url for host-permitted tabs.
  let swept = 0;
  try {
    for (const t of await browser.tabs.query({})) {
      if (!t.url || redirected.some((r) => r.tabId === t.id)) continue;
      const probe = t.url.match(/[#&]fp-probe=([\w-]+)/)?.[1];
      if (!P.isBlocked(result, t.url)) continue;
      if (!probe || (await releasedProbes()).includes(probe)) {
        ownerTabsSkipped++;
        continue;
      }
      swept++;
      const r = await redirectTab(t.id, t.url, "background-sweep:" + reason);
      redirected.push({ tabId: t.id, probe, url: t.url, via: "query", ...r });
    }
  } catch (e) {
    redirected.push({ via: "query", ok: false, error: String(e?.message ?? e) });
  }
  await browser.storage.local.set({ tabHosts });
  return { known: tabHosts, redirected, ownerTabsSkipped, swept };
}

// A probe tab the owner starts using becomes theirs: "release-probes" makes the spike forget it.
async function releasedProbes() {
  // s1ig: the owner took over that Instagram probe tab on 2026-10-19.
  const { releasedProbes = [] } = await browser.storage.local.get("releasedProbes");
  return [...new Set(["s1ig", ...releasedProbes])];
}

async function runCommand(command) {
  if (!command?.id) return null;
  const { lastCommandId = null } = await browser.storage.local.get("lastCommandId");
  if (command.id === lastCommandId) return null;
  await browser.storage.local.set({ lastCommandId: command.id }).catch(() => {});
  if (command.action === "release-probes") {
    const names = command.probes ?? [];
    const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
    for (const [id, info] of Object.entries(tabHosts)) if (names.includes(info.probe)) delete tabHosts[id];
    await browser.storage.local.set({ tabHosts, releasedProbes: [...new Set([...(await releasedProbes()), ...names])] });
    return { id: command.id, released: names };
  }
  // Spike tabs are marked #fp-probe=NAME, or ?fp=dnr for unmarked DNR-only checks.
  const mine = (t) => /[#&?]fp(-probe)?=/.test(t.url ?? "") || (t.url ?? "").startsWith(browser.runtime.getURL(BLOCKED_PAGE));
  if (command.action === "dnr-mode") {
    await browser.storage.local.set({ dnrMode: command.mode });
    return { id: command.id, dnrMode: command.mode };
  }
  if (command.action === "inspect-tabs") {
    const all = await browser.tabs.query({});
    return { id: command.id, tabs: all.filter(mine).map((t) => ({ id: t.id, url: t.url, title: t.title, status: t.status })), total: all.length };
  }
  if (command.action !== "close-probe-tabs") return { id: command.id, error: "unknown action" };
  const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
  const closed = [];
  for (const [id, info] of Object.entries(tabHosts)) {
    if (!info.probe) continue;
    try {
      await browser.tabs.remove(Number(id));
      closed.push({ tabId: Number(id), probe: info.probe, ok: true });
    } catch (e) {
      closed.push({ tabId: Number(id), probe: info.probe, ok: false, error: String(e?.message ?? e) });
    }
    delete tabHosts[id];
  }
  // Tab ids did not survive an extension reload (S3), so also find probe tabs by their URL marker.
  let queried = null;
  try {
    const all = await browser.tabs.query({});
    queried = { total: all.length, withUrl: all.filter((t) => t.url).length };
    for (const t of all.filter(mine)) {
      try {
        await browser.tabs.remove(t.id);
        closed.push({ tabId: t.id, url: t.url, ok: true, via: "query" });
      } catch (e) {
        closed.push({ tabId: t.id, url: t.url, ok: false, via: "query", error: String(e?.message ?? e) });
      }
    }
  } catch (e) {
    queried = String(e?.message ?? e);
  }
  await browser.storage.local.set({ tabHosts }).catch(() => {});
  return { id: command.id, closed, queried };
}

browser.tabs.onRemoved.addListener((tabId, removeInfo) => {
  queue(async () => {
    const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
    if (!(tabId in tabHosts)) return;
    const probe = tabHosts[tabId].probe;
    delete tabHosts[tabId];
    await browser.storage.local.set({ tabHosts });
    await observe("tab-removed", { tabId, probe, ...removeInfo });
  });
});

// Safari exposes url and title here only for host-permitted pages and the extension's own pages.
// A url change on a probe tab with no load (status) is a single-page-app navigation; the
// background checks it as well as the content script, whichever is first.
browser.tabs.onUpdated.addListener((tabId, change, tab) => {
  const url = tab?.url ?? change.url ?? "";
  const atMs = Date.now();
  if (url.startsWith(browser.runtime.getURL(BLOCKED_PAGE))) return;
  let host = null;
  try {
    host = new URL(url).hostname;
  } catch {}
  if (!host || !WATCHED.some((d) => P.hostMatches(host, d))) return;
  if (!("status" in change) && !("title" in change) && !("url" in change)) return;
  queue(async () => {
    const info = await trackTab(tabId, url);
    if (!info.probe) return;
    if ((await releasedProbes()).includes(info.probe)) {
      const { tabHosts = {} } = await browser.storage.local.get("tabHosts");
      delete tabHosts[tabId];
      await browser.storage.local.set({ tabHosts });
      return;
    }
    await observe("tab-updated", { tabId, probe: info.probe, ...change, tabUrl: url, tabTitle: tab?.title ?? null, tabStatus: tab?.status ?? null, atMs });
    if (!change.url) return;
    const { policy = null } = await browser.storage.local.get("policy");
    const result = P.evaluate(policy, Date.now());
    if (P.isBlocked(result, url)) {
      const r = await redirectTab(tabId, url, "background:tab-url-changed");
      await observe("tab-url-blocked", { tabId, probe: info.probe, url, sinceUpdateMs: Date.now() - atMs, ...r });
    }
  });
});

// S3: storage.local filled up (quota errors on every set). Report what holds the space straight to
// the native handler (storage itself cannot take a write), then drop the unsent outbox.
async function storageCheck() {
  const all = await browser.storage.local.get(null);
  const sizes = Object.fromEntries(Object.entries(all).map(([k, v]) => [k, JSON.stringify(v ?? null).length]));
  const total = Object.values(sizes).reduce((a, b) => a + b, 0);
  let dropped = false;
  if (total > 1_000_000) {
    await browser.storage.local.remove(["outbox"]);
    dropped = true;
  }
  try {
    await browser.runtime.sendNativeMessage(NATIVE_APP, {
      type: "sync",
      reason: "storage-check",
      installId: all.installId ?? "unknown",
      workerInstance,
      records: [{ type: "observation", kind: "storage-check", seq: -1, observedAt: new Date().toISOString(), sizes, total, dropped, outboxLength: all.outbox?.length ?? 0 }],
    });
  } catch {}
}

browser.alarms.get("sync").then((a) => {
  if (!a) browser.alarms.create("sync", { periodInMinutes: SYNC_PERIOD_MINUTES });
});
openPort();
queue(storageCheck);
reconcile("worker-start");
