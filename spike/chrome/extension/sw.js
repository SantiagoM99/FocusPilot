// Throwaway spike for issue #2. Every wake path calls reconcile() so the last acknowledged
// policy is enforced against this worker's own clock, with or without the native host.
// Lifecycle facts: https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle

importScripts("match.js");

const HOST = "com.focuspilot.spike";
const BACKUP_GRACE_MS = 1500; // S3: content script acts first; the worker redirects only if the page is still there after this
const SAFETY_ALARM_MINUTES = 15; // long on purpose: a short period would mask whether the port alone keeps the worker alive
const RULE_BASE = { always: 1000, session: 2000, exception: 3000 };
const RESOURCE_TYPES = ["main_frame", "sub_frame"];

const swInstance = crypto.randomUUID();
const swStartedAt = Date.now();
let port = null;
let backoffMs = 1000;
let reconnectTimer = null;

// Several wake events can fire together (worker start + onStartup + alarm); serialise the
// read-modify-write sections so rule IDs and observation sequence numbers never collide.
function serial() {
  let tail = Promise.resolve();
  return (fn) => (tail = tail.then(fn, fn));
}
const observeQueue = serial();
const reconcileQueue = serial();

// Memoised: the first wake calls this from several paths at once, and unsynchronised
// get-then-set created two IDs on first install (hello and observations disagreed).
let profileIdPromise = null;
function profileId() {
  return (profileIdPromise ??= loadOrCreateProfileId());
}

async function loadOrCreateProfileId() {
  const { profileId } = await chrome.storage.local.get("profileId");
  if (profileId) return profileId;
  const id = crypto.randomUUID();
  await chrome.storage.local.set({ profileId: id, profileCreatedAt: new Date().toISOString() });
  return id;
}

function observe(kind, details = {}) {
  return observeQueue(() => observeNow(kind, details));
}

async function observeNow(kind, details) {
  const { nextSeq = 1, outbox = [] } = await chrome.storage.local.get(["nextSeq", "outbox"]);
  const observation = {
    type: "observation",
    kind,
    seq: nextSeq,
    observedAt: new Date().toISOString(),
    profileId: await profileId(),
    swInstance,
    ...details,
  };
  outbox.push(observation);
  await chrome.storage.local.set({ nextSeq: nextSeq + 1, outbox });
  await flush();
}

// Observations are kept in storage until the host is connected, so nothing seen while the
// host was missing is lost; the app side deduplicates by (profileId, seq).
async function flush() {
  if (!port) return;
  const { outbox = [] } = await chrome.storage.local.get("outbox");
  if (!outbox.length) return;
  try {
    for (const o of outbox) port.postMessage(o);
    await chrome.storage.local.set({ outbox: [] });
  } catch (e) {
    console.warn("flush failed", e);
  }
}

function desiredRules(policy, now) {
  const rules = [];
  const notes = { sessionActive: false, strictPastEnd: false, activeExceptions: [] };
  (policy?.alwaysOn ?? []).forEach((r, i) =>
    rules.push(...blockRules(RULE_BASE.always + 2 * i, r.domain)));

  const s = policy?.session;
  if (s && !s.ended && now >= Date.parse(s.startsAt)) {
    const pastEnd = now >= Date.parse(s.endsAt);
    if (!pastEnd || s.mode === "strict") {
      notes.sessionActive = true;
      notes.strictPastEnd = pastEnd;
      s.domains.forEach((d, i) => rules.push(...blockRules(RULE_BASE.session + 2 * i, d)));
      s.exceptions.filter((e) => now < Date.parse(e.expiresAt)).forEach((e, i) => {
        notes.activeExceptions.push(e.id);
        rules.push({
          id: RULE_BASE.exception + i,
          priority: 2,
          action: { type: "allow" },
          condition: { urlFilter: e.urlFilter, resourceTypes: RESOURCE_TYPES },
        });
      });
    }
  }
  return { rules, notes };
}

// S3: top-level loads go to the blocked page (redirect needs host permission for the domain);
// frames are plainly blocked.
function blockRules(id, domain) {
  return [
    { id, priority: 1, action: { type: "redirect", redirect: { extensionPath: "/blocked.html?reason=dnr" } }, condition: { urlFilter: `||${domain}`, resourceTypes: ["main_frame"] } },
    { id: id + 1, priority: 1, action: { type: "block" }, condition: { urlFilter: `||${domain}`, resourceTypes: ["sub_frame"] } },
  ];
}

// Positive values are how late the worker removed a rule relative to the instant it should
// have stopped applying; this is the measured expiry overrun the architecture asks for.
function overruns(policy, before, after, now) {
  const result = {};
  const s = policy?.session;
  if (!s) return result;
  const had = (base) => before.some((r) => r.id >= base && r.id < base + 1000);
  const has = (base) => after.some((r) => r.id >= base && r.id < base + 1000);
  if (had(RULE_BASE.session) && !has(RULE_BASE.session) && !s.ended) result.sessionEndOverrunMs = now - Date.parse(s.endsAt);
  if (had(RULE_BASE.exception) && !has(RULE_BASE.exception)) {
    const expired = s.exceptions.map((e) => Date.parse(e.expiresAt)).filter((t) => t <= now);
    if (expired.length) result.exceptionExpiryOverrunMs = now - Math.max(...expired);
  }
  return result;
}

function reconcile(trigger) {
  return reconcileQueue(() => reconcileNow(trigger));
}

async function reconcileNow(trigger) {
  const now = Date.now();
  const { policyRecord } = await chrome.storage.local.get("policyRecord");
  const policy = policyRecord?.policy;
  const { rules, notes } = desiredRules(policy, now);
  const before = (await chrome.declarativeNetRequest.getDynamicRules()).sort((a, b) => a.id - b.id);
  const changed = JSON.stringify(before.map(stripRule)) !== JSON.stringify(rules.map(stripRule));
  if (changed) {
    await chrome.declarativeNetRequest.updateDynamicRules({
      removeRuleIds: before.map((r) => r.id),
      addRules: rules,
    });
  }
  await scheduleNextBoundary(policy, now);
  const state = { trigger, at: new Date(now).toISOString(), revision: policy?.revision ?? null, ruleIds: rules.map((r) => r.id), ...notes };
  await chrome.storage.local.set({ lastReconcile: state });
  await observe("reconcile", { ...state, changed, ...overruns(policy, before, rules, now) });
  await enforceOpenTabs(trigger, policy);
  return state;
}

function stripRule(r) {
  return { id: r.id, priority: r.priority, action: { type: r.action.type, extensionPath: r.action.redirect?.extensionPath }, condition: { urlFilter: r.condition.urlFilter, resourceTypes: r.condition.resourceTypes } };
}

async function scheduleNextBoundary(policy, now) {
  const s = policy?.session;
  const times = s && !s.ended
    ? [s.startsAt, s.endsAt, ...s.exceptions.map((e) => e.expiresAt)].map(Date.parse).filter((t) => t > now)
    : [];
  await chrome.alarms.clear("boundary");
  if (times.length) await chrome.alarms.create("boundary", { when: Math.min(...times) });
}

async function handlePolicy(msg) {
  const { policyRecord } = await chrome.storage.local.get("policyRecord");
  const incoming = msg.policy;
  if (policyRecord && incoming.revision < policyRecord.policy.revision) {
    await observe("policy-rejected-stale", { revision: incoming.revision, current: policyRecord.policy.revision });
    return;
  }
  if (policyRecord?.checksum === msg.checksum) {
    port?.postMessage({ type: "ack", revision: incoming.revision, checksum: msg.checksum, duplicate: true, profileId: await profileId() });
    return;
  }
  await chrome.storage.local.set({ policyRecord: { policy: incoming, checksum: msg.checksum, receivedAt: new Date().toISOString() } });
  const state = await reconcile("policy-message");
  port?.postMessage({ type: "ack", revision: incoming.revision, checksum: msg.checksum, profileId: await profileId(), appliedAt: state.at, ruleIds: state.ruleIds, sessionActive: state.sessionActive, strictPastEnd: state.strictPastEnd });
}

async function connect(reason) {
  if (port) return;
  clearTimeout(reconnectTimer);
  port = chrome.runtime.connectNative(HOST);
  port.onMessage.addListener((msg) => {
    backoffMs = 1000;
    if (msg.type === "policy") handlePolicy(msg);
  });
  port.onDisconnect.addListener(async () => {
    const error = chrome.runtime.lastError?.message ?? null;
    port = null;
    const { disconnects = 0 } = await chrome.storage.local.get("disconnects");
    await chrome.storage.local.set({ disconnects: disconnects + 1, connection: { state: "disconnected", error, at: new Date().toISOString() } });
    await observe("native-disconnect", { error, retryInMs: backoffMs });
    reconnectTimer = setTimeout(() => connect("reconnect"), backoffMs);
    backoffMs = Math.min(backoffMs * 2, 60000);
  });
  const { disconnects = 0, connection } = await chrome.storage.local.get(["disconnects", "connection"]);
  port.postMessage({
    type: "hello",
    reason,
    profileId: await profileId(),
    extensionId: chrome.runtime.id,
    incognitoAllowed: await chrome.extension.isAllowedIncognitoAccess(),
    swInstance,
    swStartedAt: new Date(swStartedAt).toISOString(),
    userAgent: navigator.userAgent,
    disconnects,
    previousConnection: connection ?? null,
  });
  await chrome.storage.local.set({ connection: { state: "connected", at: new Date().toISOString(), swInstance } });
  await observeQueue(flush);
}

// ---- S3: pages that are already loaded -------------------------------------------------
// Tab URLs are visible through host permissions alone (no "tabs" permission). Only tabs the
// spike opened (registered by the content script from the ?fpspike marker) are acted on;
// matching owner tabs are only counted.

const tabsQueue = serial();

function isExtensionUrl(url) {
  return url.startsWith(chrome.runtime.getURL(""));
}

async function currentPolicy() {
  return (await chrome.storage.local.get("policyRecord")).policyRecord?.policy ?? null;
}

async function spikeTabs() {
  return (await chrome.storage.local.get("spikeTabs")).spikeTabs ?? {};
}

async function redirectTab(tabId, from, reason, decidedAt) {
  const q = new URLSearchParams({ from, reason, decidedAt: String(decidedAt) });
  await chrome.tabs.update(tabId, { url: chrome.runtime.getURL("blocked.html") + "?" + q });
  await observe("sw-redirect", { tabId, from, reason, decidedAt, redirectIssuedAt: Date.now() });
}

async function backup(tabId, trigger, decidedAt) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab?.url || isExtensionUrl(tab.url)) return;
  if (decide(await currentPolicy(), tab.url, Date.now()).blocked) await redirectTab(tabId, tab.url, `sw-backup:${trigger}`, decidedAt);
}

async function enforceOpenTabs(trigger, policy) {
  const now = Date.now();
  const mine = await spikeTabs();
  let ownerTabsMatching = 0;
  for (const tab of await chrome.tabs.query({})) {
    if (!tab.url || isExtensionUrl(tab.url)) continue;
    const d = decide(policy, tab.url, now);
    const spike = mine[tab.id];
    if (!spike) { if (d.blocked) ownerTabsMatching++; continue; }
    if (spike.csInstance && !spike.passive) {
      chrome.tabs.sendMessage(tab.id, { type: "policy", policy, trigger }).catch(() => {});
      if (d.blocked) setTimeout(() => backup(tab.id, trigger, now), BACKUP_GRACE_MS);
    } else if (d.blocked) {
      await redirectTab(tab.id, tab.url, `sw:${trigger}`, now);
    }
  }
  if (ownerTabsMatching) await observe("owner-tabs-not-touched", { trigger, count: ownerTabsMatching });
}

chrome.tabs.onRemoved.addListener(async (tabId, info) => {
  if ((await spikeTabs())[tabId]) observe("spike-tab-removed", { tabId, windowClosing: info.isWindowClosing, at: Date.now() });
});
chrome.tabs.onReplaced.addListener((added, removed) => {
  tabsQueue(async () => {
    const mine = await spikeTabs();
    if (!mine[removed]) return;
    mine[added] = mine[removed];
    delete mine[removed];
    await chrome.storage.local.set({ spikeTabs: mine });
    await observe("spike-tab-replaced", { removed, added, at: Date.now() });
  });
});

chrome.tabs.onUpdated.addListener(async (tabId, change) => {
  if (!change.url || isExtensionUrl(change.url)) return;
  const spike = (await spikeTabs())[tabId];
  if (!spike) return;
  const now = Date.now();
  const d = decide(await currentPolicy(), change.url, now);
  if (!d.blocked) return;
  await observe("sw-saw-blocked-url", { tabId, url: change.url, seenAt: now });
  if (spike.passive) await redirectTab(tabId, change.url, "sw:tabs.onUpdated", now);
  else setTimeout(() => backup(tabId, "tabs.onUpdated", now), BACKUP_GRACE_MS);
});

chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  const tabId = sender.tab?.id;
  if (msg.type === "cs-hello") {
    tabsQueue(async () => {
      const mine = await spikeTabs();
      if (msg.marker) mine[tabId] = { marker: msg.marker, passive: msg.marker.includes("passive"), registeredAt: Date.now() };
      if (mine[tabId]) mine[tabId].csInstance = msg.csInstance;
      await chrome.storage.local.set({ spikeTabs: mine });
      const enforce = !!mine[tabId];
      await observe("cs-hello", { tabId, enforce, marker: msg.marker, host: new URL(msg.url).hostname, url: enforce ? msg.url : undefined, loadedAt: msg.loadedAt, visibility: msg.visibility, prerendering: msg.prerendering });
      reply({ policy: await currentPolicy(), enforce });
    });
    return true;
  }
  if (msg.type === "cs-report") {
    const { type, kind, ...details } = msg;
    observe(kind, { tabId, ...details });
  }
  if (msg.type === "blocked-shown") {
    observe("blocked-shown", { tabId, ...msg.params, shownAt: msg.shownAt, navigationStart: msg.navigationStart });
  }
});

chrome.runtime.onStartup.addListener(() => { reconcile("onStartup"); connect("onStartup"); });
chrome.runtime.onInstalled.addListener((d) => {
  chrome.alarms.create("safety", { periodInMinutes: SAFETY_ALARM_MINUTES });
  reconcile(`onInstalled:${d.reason}`);
});
chrome.alarms.onAlarm.addListener((a) => { reconcile(`alarm:${a.name}`); connect(`alarm:${a.name}`); });
chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (msg === "status") {
    (async () => reply({
      swInstance, swStartedAt: new Date(swStartedAt).toISOString(), connected: !!port,
      incognitoAllowed: await chrome.extension.isAllowedIncognitoAccess(),
      rules: await chrome.declarativeNetRequest.getDynamicRules(),
      alarms: await chrome.alarms.getAll(),
      ...(await chrome.storage.local.get(["profileId", "profileCreatedAt", "connection", "disconnects", "lastReconcile", "policyRecord", "nextSeq"])),
    }))();
    return true;
  }
});

observe("worker-start");
reconcile("worker-start");
connect("worker-start");
