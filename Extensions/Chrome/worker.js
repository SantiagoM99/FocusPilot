// FocusPilot's service worker. It keeps a native port to the FocusPilot
// host, stores the newest policy, turns it into network rules and sends
// open tabs on blocked sites to the blocked page. Every wake (worker start,
// browser start, alarm, policy) reconciles against this worker's own clock,
// so blocking keeps working while FocusPilot is quit (decision 0003).
// Lifecycle: https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle

importScripts("policy.js", "outbox.js", "observe.js");

const HOST = "com.santiagom99.focuspilot";
// The content script stops media and redirects first; the worker redirects
// any tab still on a blocked page after this (spike S3: 1.5 s).
const BACKUP_MS = 1500;
// Wakes the worker to reconcile and reconnect when nothing else does, e.g.
// after the host failed and the worker stopped (alarms: 30 s minimum).
const SAFETY_ALARM_MINUTES = 1;
// How long the blocked page waits for FocusPilot to answer an exception request.
const EXCEPTION_TIMEOUT_MS = 10000;
const store = chrome.storage.local;

let port = null;
let backoffMs = 1000;
let reconnectTimer = null;

// Memoized: several first-wake paths ask at once, and unsynchronized
// get-then-set made two IDs on first install in spike S2.
let profileIdPromise = null;
function profileId() {
  return (profileIdPromise ??= (async () => {
    const { profileId } = await store.get("profileId");
    if (profileId) return profileId;
    const id = crypto.randomUUID();
    await store.set({ profileId: id });
    return id;
  })());
}

const outbox = FocusOutbox.create({ get: (keys) => store.get(keys), set: (values) => store.set(values) }, profileId);

function post(message) {
  try { port?.postMessage(message); } catch { /* the disconnect handler reconnects */ }
}

// Observations go out only through the sender, in order and after hello.
const sender = FocusOutbox.sender(outbox, post);

async function observe(kind, details = {}) {
  await outbox.add(kind, details);
  await sender.send();
}

// ---- Policy and network rules ----

const reconcileQueue = FocusOutbox.serial();

function reconcile(trigger) {
  return reconcileQueue(() => reconcileNow(trigger));
}

async function currentDelivery() {
  return (await store.get("delivery")).delivery ?? null;
}

async function reconcileNow(trigger) {
  const now = Date.now();
  const policy = (await currentDelivery())?.policy ?? null;
  await applyRules(policy, now);
  await chrome.alarms.clear("boundary");
  const next = FocusPolicy.nextBoundary(policy, now);
  if (next !== null) await chrome.alarms.create("boundary", { when: next });
  await sweepTabs(policy, now, trigger);
}

// FocusPolicy.networkRules: blocked sites redirect, frames are blocked,
// timed exceptions are carved out. A page regex Chrome would refuse (its
// regex memory is limited) allows the page's path instead; the content
// script, which checks every parameter, still blocks other pages there.
// Rewritten only when they change.
async function applyRules(policy, now) {
  const blockedPage = chrome.runtime.getURL("blocked.html");
  const urls = FocusPolicy.pageURLs(policy, now);
  const pathOnly = new Set();
  for (const rule of FocusPolicy.networkRules(policy, now, blockedPage)) {
    if (rule.action.type !== "allowAllRequests") continue;
    const check = await chrome.declarativeNetRequest.isRegexSupported({ regex: rule.condition.regexFilter, isCaseSensitive: true });
    if (!check.isSupported) pathOnly.add(urls[rule.id - 10]);
  }
  const rules = FocusPolicy.networkRules(policy, now, blockedPage, { pathOnly });
  const existing = await chrome.declarativeNetRequest.getDynamicRules();
  const key = JSON.stringify(rules);
  const { appliedRules } = await store.get("appliedRules");
  const ids = existing.map((r) => r.id).sort((a, b) => a - b).join();
  if (appliedRules === key && ids === rules.map((r) => r.id).sort((a, b) => a - b).join()) return;
  try {
    await chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: existing.map((r) => r.id), addRules: rules });
  } catch (error) {
    // Blocking must survive a refused rule: keep the blocks and site
    // carve-outs, and let every excepted page through by its path.
    const fallback = FocusPolicy.networkRules(policy, now, blockedPage, { pathOnly: true });
    await chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: existing.map((r) => r.id), addRules: fallback })
      .catch(() => chrome.declarativeNetRequest.updateDynamicRules({
        removeRuleIds: existing.map((r) => r.id), addRules: fallback.filter((r) => r.action.type !== "allowAllRequests"),
      }));
    await observe("rules-rejected", { error: String(error?.message ?? error) });
  }
  // Recorded either way, so a refused set is not retried on every wake.
  await store.set({ appliedRules: key });
}

function blockedPage(url, by) {
  return chrome.runtime.getURL("blocked.html") + "?" + new URLSearchParams({ from: url, by });
}

// Open tabs on blocked sites: the content script acts first (it can pause
// media at once); the worker redirects whatever is still there.
async function sweepTabs(policy, now, trigger) {
  const tabs = await chrome.tabs.query({ url: ["http://*/*", "https://*/*"] });
  for (const tab of tabs) {
    if (FocusPolicy.decide(policy, tab.url, now).blocked) enforceTab(tab.id, trigger);
  }
}

function enforceTab(tabId, trigger) {
  chrome.tabs.sendMessage(tabId, { type: "evaluate" }).catch(() => {});
  setTimeout(async () => {
    const tab = await chrome.tabs.get(tabId).catch(() => null);
    if (!tab?.url || !/^https?:/.test(tab.url)) return;
    const policy = (await currentDelivery())?.policy ?? null;
    if (!FocusPolicy.decide(policy, tab.url, Date.now()).blocked) return;
    await chrome.tabs.update(tabId, { url: blockedPage(tab.url, "worker") }).catch(() => {});
    await observe("tab-redirected", { trigger });
  }, BACKUP_MS);
}

// Single-page apps change the URL without a request (spike S3: YouTube).
chrome.tabs.onUpdated.addListener(async (tabId, change) => {
  if (!change.url || !/^https?:/.test(change.url)) return;
  const policy = (await currentDelivery())?.policy ?? null;
  if (FocusPolicy.decide(policy, change.url, Date.now()).blocked) enforceTab(tabId, "navigation");
});

// ---- Observe-only (#21) ----

// While the app's delivery says observe, the domain of the tab in front
// goes to the host on every change; null when Chrome is not in front.
const frontQueue = FocusOutbox.serial();
let lastFront;

function reportFront() {
  return frontQueue(async () => {
    if ((await currentDelivery())?.observe !== true) {
      lastFront = undefined;
      return;
    }
    const win = await chrome.windows.getLastFocused().catch(() => null);
    const [tab] = win?.focused ? await chrome.tabs.query({ active: true, windowId: win.id }) : [];
    const domain = FocusObserve.domainOf(tab);
    if (domain === lastFront) return;
    lastFront = domain;
    await observe("tab-front", { domain });
  });
}

chrome.tabs.onActivated.addListener(() => reportFront());
chrome.tabs.onUpdated.addListener((_id, change, tab) => { if (change.url && tab?.active) reportFront(); });
chrome.windows.onFocusChanged.addListener(() => reportFront());

// ---- Native host ----

const policyQueue = FocusOutbox.serial();

function handlePolicy(message) {
  return policyQueue(async () => {
    const incoming = {
      policy: message.policy, focus: message.focus ?? null, source: message.source ?? null, observe: message.observe === true,
    };
    if (!FocusPolicy.supports(incoming)) {
      await observe("policy-rejected-schema", { schemaVersion: incoming.policy?.schemaVersion ?? null });
      return;
    }
    const stored = await currentDelivery();
    if (!FocusPolicy.isNewer(incoming, stored)) {
      if (incoming.policy.revision < stored.policy.revision) {
        await observe("policy-rejected-stale", { revision: incoming.policy.revision, current: stored.policy.revision });
      }
      return;
    }
    // Rules first: the blocked page returns to a newly excepted page as
    // soon as it sees the policy, and must not meet the old redirect.
    await reconcileQueue(() => applyRules(incoming.policy, Date.now()));
    await store.set({ delivery: incoming });
    await reconcile("policy");
    await observe("policy-applied", { revision: incoming.policy.revision, checksum: incoming.policy.checksum, source: incoming.source });
    reportFront();
  });
}

function handleHost(message) {
  backoffMs = 1000;
  switch (message?.type) {
    case "policy": handlePolicy(message); break;
    case "status":
      store.set({ appRunning: message.appRunning });
      reloadIfUpdated(message.extensionBuild);
      break;
    case "ack": outbox.acknowledge(message.seq); break;
    case "exception-result": pendingExceptions.get(message.id)?.(message); break;
  }
}

// ---- Exception requests from the blocked page (#14) ----

// The app decides; the blocked page waits for its answer by request id.
const pendingExceptions = new Map();

function requestException(message, reply) {
  const scope = message.scope;
  if (!port) {
    reply({ outcome: "refused", message: "FocusPilot isn't reachable. Open FocusPilot and try again." });
    return;
  }
  const id = crypto.randomUUID();
  const done = (result) => {
    clearTimeout(timer);
    pendingExceptions.delete(id);
    observe("exception-answered", { scope: scope?.kind ?? null, outcome: result.outcome });
    reply(result);
  };
  const timer = setTimeout(() => done({ outcome: "refused", message: "FocusPilot is taking long to answer. If it allows it, this page will update." }), EXCEPTION_TIMEOUT_MS);
  pendingExceptions.set(id, done);
  post({
    type: "exception-request", id, scope, durationSeconds: message.durationSeconds,
    reason: message.reason ?? null, confirmed: message.confirmed === true,
  });
}

// An app update refreshed the extension folder: load the new build. Once
// per build, so an extension loaded from another folder never loops.
async function reloadIfUpdated(build) {
  if (!build || build === chrome.runtime.getManifest().version_name) return;
  const { reloadedFor } = await store.get("reloadedFor");
  if (reloadedFor === build) return;
  await store.set({ reloadedFor: build });
  await observe("extension-reloading", { build });
  chrome.runtime.reload();
}

async function hello(reason) {
  post({
    type: "hello", reason, profileId: await profileId(), extensionId: chrome.runtime.id,
    version: chrome.runtime.getManifest().version,
    incognitoAllowed: await chrome.extension.isAllowedIncognitoAccess(),
    allSitesAccess: await chrome.permissions.contains({ origins: ["<all_urls>"] }),
  });
}

function connect(reason) {
  if (port) return;
  clearTimeout(reconnectTimer);
  const opened = chrome.runtime.connectNative(HOST);
  port = opened;
  opened.onMessage.addListener(handleHost);
  opened.onDisconnect.addListener(() => {
    const error = chrome.runtime.lastError?.message ?? null;
    if (port !== opened) return;
    port = null;
    sender.close();
    for (const done of [...pendingExceptions.values()]) {
      done({ outcome: "refused", message: "FocusPilot isn't reachable. Open FocusPilot and try again." });
    }
    store.set({ appRunning: null, hostError: error });
    observe("host-disconnected", { error });
    reconnectTimer = setTimeout(() => connect("reconnect"), backoffMs);
    backoffMs = Math.min(backoffMs * 2, 60000);
  });
  store.set({ hostError: null });
  hello(reason).then(() => { if (port === opened) sender.open(); });
}

// ---- Pages ----

chrome.runtime.onMessage.addListener((message, _from, reply) => {
  switch (message?.type) {
    case "blocked-shown":
      observe("blocked-shown", { domain: message.domain, view: message.view, by: message.by });
      break;
    case "exception-opened":
      observe("exception-opened", { domain: message.domain });
      break;
    case "exception-request":
      requestException(message, reply);
      return true;
    case "exception-cancel":
      post({ type: "exception-cancel", scope: message.scope });
      break;
    case "open-app":
      post({ type: "open-app" });
      reply({ sent: port !== null });
      break;
  }
});

// ---- Wake paths ----

// Content scripts are not injected into tabs that were open before an
// install or update; inject them so open pages can stop media at once.
async function injectIntoOpenTabs() {
  for (const tab of await chrome.tabs.query({ url: ["http://*/*", "https://*/*"] })) {
    chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["policy.js", "content.js"] }).catch(() => {});
  }
}

chrome.runtime.onInstalled.addListener(async (details) => {
  await chrome.alarms.create("safety", { periodInMinutes: SAFETY_ALARM_MINUTES });
  await injectIntoOpenTabs();
  reconcile(`installed:${details.reason}`);
});
chrome.runtime.onStartup.addListener(() => {
  reconcile("browser-start");
  connect("browser-start");
});
chrome.alarms.onAlarm.addListener((alarm) => {
  reconcile(`alarm:${alarm.name}`);
  connect(`alarm:${alarm.name}`);
});

observe("worker-start");
reconcile("worker-start");
connect("worker-start");
