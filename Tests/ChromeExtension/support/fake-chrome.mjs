// Runs the real service worker (worker.js, with policy.js and outbox.js) in
// a node vm against a stand-in for the Chrome APIs it uses, on a clock the
// test moves. Only what the worker touches is modelled: storage, network
// rules, alarms and the native port; there are no tabs.
import vm from "node:vm";
import { readFileSync } from "node:fs";

const extension = new URL("../../../Extensions/Chrome/", import.meta.url);

function event() {
  const listeners = [];
  return { addListener: (fn) => listeners.push(fn), fire: (...args) => listeners.forEach((fn) => fn(...args)) };
}

export function startWorker(startAt) {
  let now = Date.parse(startAt);
  const data = {};
  let rules = [];
  const alarms = new Map();
  const toHost = [];
  const port = { onMessage: event(), onDisconnect: event(), postMessage: (m) => toHost.push(structuredClone(m)) };
  const onAlarm = event();

  class FakeDate extends Date {
    constructor(...args) { super(...(args.length ? args : [now])); }
    static now() { return now; }
  }

  const chrome = {
    storage: {
      local: {
        get: async (keys) => {
          const list = typeof keys === "string" ? [keys] : keys;
          return Object.fromEntries(list.filter((k) => k in data).map((k) => [k, structuredClone(data[k])]));
        },
        set: async (values) => { Object.assign(data, structuredClone(values)); },
      },
    },
    runtime: {
      id: "chmamkccdgghcchjaedemhkkiebdfabd",
      lastError: null,
      getURL: (path) => `chrome-extension://chmamkccdgghcchjaedemhkkiebdfabd/${path}`,
      getManifest: () => ({ version: "1.0.0", version_name: "1.0.0 (development)" }),
      connectNative: () => port,
      reload: () => {},
      onMessage: event(), onInstalled: event(), onStartup: event(),
    },
    extension: { isAllowedIncognitoAccess: async () => false },
    permissions: { contains: async () => true },
    declarativeNetRequest: {
      getDynamicRules: async () => structuredClone(rules),
      updateDynamicRules: async ({ removeRuleIds, addRules }) => {
        rules = rules.filter((r) => !removeRuleIds.includes(r.id)).concat(structuredClone(addRules));
      },
    },
    alarms: {
      create: async (name, info) => { alarms.set(name, info.when ?? now + info.periodInMinutes * 60000); },
      clear: async (name) => alarms.delete(name),
      onAlarm,
    },
    tabs: { query: async () => [], onUpdated: event(), sendMessage: async () => {}, get: async () => null, update: async () => {} },
    scripting: { executeScript: async () => {} },
  };

  const context = vm.createContext({
    chrome, Date: FakeDate, Intl, URL, URLSearchParams, Promise, console, structuredClone,
    crypto: { randomUUID: () => "4f5ce721-0000-4000-8000-000000000001" },
    // The worker only times reconnects and tab redirects; neither happens here.
    setTimeout: () => 0, clearTimeout: () => {},
  });
  context.importScripts = (...files) => files.forEach((f) => vm.runInContext(readFileSync(new URL(f, extension), "utf8"), context));
  vm.runInContext(readFileSync(new URL("worker.js", extension), "utf8"), context);

  // Lets the worker's promise chains run to the end.
  const settle = async () => { for (let i = 0; i < 50; i++) await new Promise((r) => setImmediate(r)); };

  return {
    settle,
    toHost,
    stored: (key) => structuredClone(data[key]),
    blockedDomains: () => rules.find((r) => r.id === 1)?.condition.requestDomains ?? [],
    // Frames from the native host, as Chrome hands them to the port.
    async receive(frames) {
      frames.forEach((f) => port.onMessage.fire(structuredClone(f)));
      await settle();
    },
    // Moves the clock and fires the alarms that came due, as Chrome does.
    async advanceTo(iso) {
      now = Date.parse(iso);
      for (const [name, when] of [...alarms]) {
        if (when <= now) { alarms.delete(name); onAlarm.fire({ name }); }
      }
      await settle();
    },
    now: () => now,
  };
}
