// Not in the host's allowed_origins; Chrome should refuse this connection.
async function tryConnect(trigger) {
  const port = chrome.runtime.connectNative("com.focuspilot.spike");
  port.onDisconnect.addListener(async () => {
    const result = { trigger, at: new Date().toISOString(), extensionId: chrome.runtime.id, error: chrome.runtime.lastError?.message ?? null };
    console.log("intruder result", result);
    await chrome.storage.local.set({ result });
  });
}
chrome.runtime.onInstalled.addListener(() => tryConnect("onInstalled"));
chrome.runtime.onMessage.addListener((msg, _s, reply) => {
  if (msg !== "try") return;
  tryConnect("popup");
  setTimeout(async () => reply(await chrome.storage.local.get("result")), 1000);
  return true;
});
