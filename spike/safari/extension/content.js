// Throwaway spike for issue #1. declarativeNetRequest only stops the next navigation; it cannot
// end an already loaded single-page app or buffered media when an exception expires. This script
// evaluates the stored policy with its own timer and blanks the page itself.
(() => {
  const P = globalThis.FPPolicy;
  let timer = null;
  let timerDueAt = null;
  let blanked = false;

  // DOM calls rather than innerHTML: sites with a Trusted Types CSP (instagram.com) can reject
  // string HTML sinks, and a throw here used to leave the page up with nothing reported.
  function el(tag, text, style) {
    const e = document.createElement(tag);
    if (text != null) e.textContent = text;
    if (style) e.setAttribute("style", style);
    return e;
  }

  function blank(result) {
    for (const m of document.querySelectorAll("video, audio")) m.pause();
    window.stop();
    const head = el("head");
    head.append(el("title", "Blocked by FocusPilot spike"));
    const body = el("body", null, "font: 16px -apple-system, sans-serif; margin: 15vh auto; max-width: 32em;");
    body.append(
      el("h1", "Blocked by FocusPilot spike S1"),
      el("p", `${location.hostname} is blocked by policy revision ${result.revision}.`),
      ...(result.strictPastEnd ? [el("p", "Strict session past its end: FocusPilot must confirm it ended.")] : []),
      el("p", "Blanked in-page by the content script.")
    );
    document.documentElement.replaceChildren(head, body);
    blanked = true;
  }

  function report(event, details) {
    browser.runtime
      .sendMessage({ type: "page-event", event, visibility: document.visibilityState, ...details })
      .catch(() => {});
  }

  async function check(reason) {
    const { policy = null } = await browser.storage.local.get("policy");
    const now = Date.now();
    const result = P.evaluate(policy, now);
    const blocked = result.blockedDomains.some((d) => P.hostMatches(location.hostname, d));

    if (reason === "load") {
      // Proves the page itself loaded: a navigation DNR blocked never runs this script.
      browser.runtime
        .sendMessage({ type: "page-event", event: "content-load", blocked, revision: result.revision, href: location.href, visibility: document.visibilityState })
        .catch(() => {});
    }
    if (blocked && !blanked) {
      const overrunMs = reason === "timer" && timerDueAt != null ? now - timerDueAt : null;
      try {
        blank(result);
      } catch (e) {
        report("content-blank-failed", { reason, revision: result.revision, error: String(e?.message ?? e) });
        return;
      }
      browser.runtime
        .sendMessage({ type: "page-event", event: "content-blanked", reason, revision: result.revision, overrunMs, visibility: document.visibilityState })
        .catch(() => {});
    } else if (!blocked && blanked) {
      // The original page is gone; reloading is the only way to give it back.
      location.reload();
      return;
    }

    clearTimeout(timer);
    timerDueAt = result.nextTransitionAt;
    if (timerDueAt != null) {
      const delayMs = Math.max(0, timerDueAt - now) + 100;
      timer = setTimeout(() => {
        report("timer-fired", { dueAt: new Date(timerDueAt).toISOString(), lateMs: Date.now() - timerDueAt });
        safeCheck("timer");
      }, delayMs);
      report("timer-armed", { reason, delayMs, dueAt: new Date(timerDueAt).toISOString() });
    }
  }

  function safeCheck(reason) {
    check(reason).catch((e) => report("content-error", { reason, error: String(e?.message ?? e) }));
  }

  browser.storage.onChanged.addListener((changes) => {
    if (changes.policy) safeCheck("policy-changed");
  });
  // Timers do not run while the Mac sleeps; re-check as soon as the tab is visible again.
  document.addEventListener("visibilitychange", () => {
    browser.runtime.sendMessage({ type: "page-event", event: "visibility", visibility: document.visibilityState }).catch(() => {});
    if (!document.hidden) safeCheck("visible");
  });
  safeCheck("load");
})();
