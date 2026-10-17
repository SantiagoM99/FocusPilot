// Spike-only probe, opened by URL from the terminal so tests need no clicks.
// It asks DNR which rules would match (testMatchOutcome is unpacked-only), loads the same URLs
// in iframes to see real blocking, reports to the host over its own native port, then closes.
const URLS = ["https://example.com/", "https://example.com/allowed", "https://example.org/", "https://example.net/"];
const label = new URLSearchParams(location.search).get("label") ?? "unlabelled";

function frameLoad(url) {
  return new Promise((resolve) => {
    const f = document.createElement("iframe");
    const started = performance.now();
    const timer = setTimeout(() => resolve({ url, event: "timeout" }), 8000);
    f.onload = () => {
      clearTimeout(timer);
      const entry = performance.getEntriesByName(url).at(-1);
      resolve({ url, event: "load", ms: Math.round(performance.now() - started), timingEntry: entry ? { duration: Math.round(entry.duration), transferSize: entry.transferSize, responseStatus: entry.responseStatus } : null });
    };
    f.src = url;
    document.getElementById("frames").append(f);
  });
}

(async () => {
  const outcomes = {};
  for (const url of URLS) {
    for (const type of ["main_frame", "sub_frame"]) {
      try {
        const r = await chrome.declarativeNetRequest.testMatchOutcome({ url, type });
        outcomes[`${type} ${url}`] = r.matchedRules.map((m) => m.ruleId);
      } catch (e) {
        outcomes[`${type} ${url}`] = `error: ${e.message}`;
      }
    }
  }
  const frames = await Promise.all(URLS.map(frameLoad));
  const report = {
    type: "probe",
    label,
    at: new Date().toISOString(),
    dynamicRuleIds: (await chrome.declarativeNetRequest.getDynamicRules()).map((r) => r.id),
    outcomes,
    frames,
    lastReconcile: (await chrome.storage.local.get("lastReconcile")).lastReconcile ?? null,
    connection: (await chrome.storage.local.get("connection")).connection ?? null,
  };
  document.getElementById("out").textContent = JSON.stringify(report, null, 2);
  const port = chrome.runtime.connectNative("com.focuspilot.spike");
  port.postMessage(report);
  setTimeout(async () => {
    port.disconnect();
    const tab = await chrome.tabs.getCurrent();
    if (tab && !label.includes("keep")) chrome.tabs.remove(tab.id);
  }, 500);
})();
