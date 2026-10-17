// Terminal-driven control: open chrome-extension://<id>/control.html?cmd=... with `open -a`.
// Extension pages are served from disk without a reload, so this works even before the
// extension has been reloaded, and `reload` is how new manifest/service-worker code is loaded.
const cmd = new URLSearchParams(location.search).get("cmd");

async function send(report) {
  document.getElementById("out").textContent = JSON.stringify(report, null, 2);
  const port = chrome.runtime.connectNative("com.focuspilot.spike");
  port.postMessage({ type: "control", cmd, at: new Date().toISOString(), ...report });
  await new Promise((r) => setTimeout(r, 500));
  port.disconnect();
}

async function closeSelf() {
  const tab = await chrome.tabs.getCurrent();
  if (tab) chrome.tabs.remove(tab.id);
}

(async () => {
  if (cmd === "reload") {
    await send({ manifestVersionBefore: chrome.runtime.getManifest().version });
    chrome.runtime.reload();
    return;
  }
  if (cmd === "status") {
    await send({ manifestVersion: chrome.runtime.getManifest().version, permissions: await chrome.permissions.getAll() });
    return closeSelf();
  }
  if (cmd === "spike-tabs") {
    const { spikeTabs = {} } = await chrome.storage.local.get("spikeTabs");
    const tabs = {};
    for (const id of Object.keys(spikeTabs)) {
      const t = await chrome.tabs.get(Number(id)).catch((e) => ({ error: e.message }));
      tabs[id] = { ...spikeTabs[id], url: t.url, status: t.status, active: t.active, audible: t.audible, discarded: t.discarded, frozen: t.frozen, windowId: t.windowId, error: t.error };
    }
    await send({ tabs });
    return closeSelf();
  }
  if (cmd === "close-spike-tabs") {
    const { spikeTabs = {} } = await chrome.storage.local.get("spikeTabs");
    const results = {};
    for (const id of Object.keys(spikeTabs)) {
      try { await chrome.tabs.remove(Number(id)); results[id] = "closed"; } catch (e) { results[id] = e.message; }
    }
    await chrome.storage.local.set({ spikeTabs: {} });
    await send({ results });
    return closeSelf();
  }
  await send({ error: "unknown cmd" });
  closeSelf();
})();
