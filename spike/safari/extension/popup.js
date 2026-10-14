// Throwaway spike for issue #1. Shows what the extension stored, evaluated and last heard from
// the native handler, so the owner can read state without Web Inspector.
async function render() {
  const s = await browser.storage.local.get(null);
  const view = {
    now: new Date().toISOString(),
    installId: s.installId,
    nextSeq: s.nextSeq,
    unsentObservations: (s.outbox ?? []).length,
    lastNative: s.lastNative,
    lastPortError: s.lastPortError,
    lastEval: s.lastEval && {
      at: new Date(s.lastEval.at).toISOString(),
      reason: s.lastEval.reason,
      revision: s.lastEval.revision,
      blockedDomains: s.lastEval.blockedDomains,
      sessionActive: s.lastEval.sessionActive,
      strictPastEnd: s.lastEval.strictPastEnd,
      activeExceptions: s.lastEval.activeExceptions,
      nextTransitionAt: s.lastEval.nextTransitionAt && new Date(s.lastEval.nextTransitionAt).toISOString(),
    },
    dynamicRules: await browser.declarativeNetRequest.getDynamicRules(),
    policy: s.policy,
  };
  document.getElementById("out").textContent = JSON.stringify(view, null, 2);
}

document.getElementById("sync").addEventListener("click", async () => {
  document.getElementById("out").textContent = "syncing…";
  try {
    await browser.runtime.sendMessage({ type: "sync-now" });
  } catch (e) {
    document.getElementById("out").textContent = "sync failed: " + e;
  }
  render();
});
render();
