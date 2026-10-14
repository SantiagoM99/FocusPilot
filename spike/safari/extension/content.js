// Throwaway spike for issue #1. declarativeNetRequest only stops the next navigation; it cannot
// end an already loaded single-page app or buffered media when an exception expires. This script
// evaluates the stored policy with its own timer and blanks the page itself.
(() => {
  const P = globalThis.FPPolicy;
  let timer = null;
  let timerDueAt = null;
  let blanked = false;

  function blank(result) {
    for (const m of document.querySelectorAll("video, audio")) m.pause();
    window.stop();
    document.documentElement.innerHTML =
      "<head><title>Blocked by FocusPilot spike</title></head>" +
      '<body style="font: 16px -apple-system, sans-serif; margin: 15vh auto; max-width: 32em;">' +
      "<h1>Blocked by FocusPilot spike S1</h1>" +
      `<p>${location.hostname} is blocked by policy revision ${result.revision}.</p>` +
      (result.strictPastEnd ? "<p>Strict session past its end: FocusPilot must confirm it ended.</p>" : "") +
      "<p>Blanked in-page by the content script.</p></body>";
    blanked = true;
  }

  async function check(reason) {
    const { policy = null } = await browser.storage.local.get("policy");
    const now = Date.now();
    const result = P.evaluate(policy, now);
    const blocked = result.blockedDomains.some((d) => P.hostMatches(location.hostname, d));

    if (blocked && !blanked) {
      const overrunMs = reason === "timer" && timerDueAt != null ? now - timerDueAt : null;
      blank(result);
      browser.runtime
        .sendMessage({ type: "page-event", event: "content-blanked", reason, revision: result.revision, overrunMs })
        .catch(() => {});
    } else if (!blocked && blanked) {
      // The original page is gone; reloading is the only way to give it back.
      location.reload();
      return;
    }

    clearTimeout(timer);
    timerDueAt = result.nextTransitionAt;
    if (timerDueAt != null) timer = setTimeout(() => check("timer"), Math.max(0, timerDueAt - now) + 100);
  }

  browser.storage.onChanged.addListener((changes) => {
    if (changes.policy) check("policy-changed");
  });
  // Timers do not run while the Mac sleeps; re-check as soon as the tab is visible again.
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) check("visible");
  });
  check("load");
})();
