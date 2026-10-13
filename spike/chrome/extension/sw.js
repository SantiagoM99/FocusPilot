// Throwaway spike for issue #2. Every wake path calls reconcile() so the last acknowledged
// policy is enforced against this worker's own clock, with or without the native host.
// Lifecycle facts: https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle

const HOST = "com.focuspilot.spike";
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

async function profileId() {
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
    rules.push(blockRule(RULE_BASE.always + i, r.domain)));

  const s = policy?.session;
  if (s && !s.ended && now >= Date.parse(s.startsAt)) {
    const pastEnd = now >= Date.parse(s.endsAt);
    if (!pastEnd || s.mode === "strict") {
      notes.sessionActive = true;
      notes.strictPastEnd = pastEnd;
      s.domains.forEach((d, i) => rules.push(blockRule(RULE_BASE.session + i, d)));
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

function blockRule(id, domain) {
  return { id, priority: 1, action: { type: "block" }, condition: { urlFilter: `||${domain}`, resourceTypes: RESOURCE_TYPES } };
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
  return state;
}

function stripRule(r) {
  return { id: r.id, priority: r.priority, action: r.action, condition: { urlFilter: r.condition.urlFilter, resourceTypes: r.condition.resourceTypes } };
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
