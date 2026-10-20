// Runs at document_start on every page and does nothing unless the page's
// site is in the policy. On a blocked page it stops media at once, then
// replaces the page with the blocked page (spike S3: about 60 ms). It also
// catches same-document URL changes and boundaries reached while open.
(() => {
  // A newer injection (after an extension update) takes over from this one.
  const instance = crypto.randomUUID();
  globalThis.__focusPilotContent = instance;
  const current = () => globalThis.__focusPilotContent === instance && !!chrome.runtime?.id;

  let delivery = null;
  let timer = null;
  let poll = null;
  let lastUrl = location.href;
  let leaving = false;

  function named(policy) {
    if (!policy) return [];
    return [policy.always.domains, ...policy.scheduled.map((b) => b.targets.domains), policy.session?.targets.domains ?? []].flat();
  }

  function concernsThisSite() {
    const host = location.hostname.replace(/\.$/, "");
    return named(delivery?.policy).some((d) => FocusPolicy.hostMatches(host, d));
  }

  function stopMedia() {
    for (const media of document.querySelectorAll("video, audio")) {
      try { media.pause(); media.muted = true; } catch { /* detached element */ }
    }
  }

  function evaluate(by) {
    if (!current() || leaving) return;
    clearTimeout(timer);
    if (!concernsThisSite()) return;
    const now = Date.now();
    const policy = delivery.policy;
    if (FocusPolicy.decide(policy, location.href, now).blocked) {
      leaving = true;
      stopMedia();
      location.replace(chrome.runtime.getURL("blocked.html") + "?" + new URLSearchParams({ from: location.href, by }));
      return;
    }
    const next = FocusPolicy.nextBoundary(policy, now);
    if (next !== null) timer = setTimeout(() => evaluate("boundary"), Math.min(next - now, 2 ** 31 - 1));
    poll ??= setInterval(urlChanged, 1000);
  }

  function urlChanged() {
    if (location.href === lastUrl) return;
    lastUrl = location.href;
    evaluate("navigation");
  }

  window.navigation?.addEventListener("currententrychange", urlChanged);
  window.addEventListener("popstate", urlChanged);
  // After sleep, page timers can fire late; check again when the tab shows.
  document.addEventListener("visibilitychange", () => evaluate("visible"));
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local" || !changes.delivery || !current()) return;
    delivery = changes.delivery.newValue ?? null;
    evaluate("policy");
  });
  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === "evaluate") evaluate("worker");
  });
  chrome.storage.local.get("delivery").then((stored) => {
    delivery = stored.delivery ?? null;
    evaluate("load");
  }).catch(() => {});
})();
