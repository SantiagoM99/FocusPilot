// Spike S3 content script for already-loaded pages. It holds the exception expiry in a page
// timer (independent of service-worker suspension), watches same-document (SPA) URL changes,
// and on a block pauses media before replacing the page with blocked.html.
// Only tabs the spike opened (URL carried ?fpspike=... at load) are acted on; on any other
// tab the script only reports that it would have blocked, without the URL.

const csInstance = crypto.randomUUID();
const loadedAt = Date.now();
const marker = new URLSearchParams(location.search).get("fpspike") ?? "";
const flags = new Set(marker.split(",").filter(Boolean));
let policy = null;
let enforce = false;
let expiryTimer = null;
let lastUrl = location.href;
let lastNavigateEventAt = null;
let blocked = false;

function media() {
  return [...document.querySelectorAll("video, audio")].map((m) => ({
    tag: m.tagName.toLowerCase(), paused: m.paused, muted: m.muted, readyState: m.readyState,
    currentTime: Math.round(m.currentTime * 1000) / 1000,
  }));
}

function report(kind, details = {}) {
  chrome.runtime.sendMessage({ type: "cs-report", kind, csInstance, enforce, url: enforce ? location.href : undefined, host: location.hostname, at: Date.now(), ...details }).catch(() => {});
}

function evaluate(trigger) {
  if (blocked || !policy) return;
  const now = Date.now();
  const d = decide(policy, location.href, now);
  clearTimeout(expiryTimer);
  if (d.blocked) return block(trigger, d, now);
  if (d.exceptionExpiresAt) {
    const due = d.exceptionExpiresAt;
    expiryTimer = setTimeout(() => evaluate(`expiry-timer(due=${due})`), Math.max(0, due - now));
  }
}

function block(trigger, decision, now) {
  const before = media();
  const due = Number(/due=(\d+)/.exec(trigger)?.[1]) || null;
  const details = {
    trigger, reason: decision.reason, decidedAt: now, timerLateMs: due ? now - due : null,
    navigateEventAt: lastNavigateEventAt, mediaBefore: before, passive: flags.has("passive"),
  };
  if (!enforce || flags.has("passive")) return report("cs-would-block", details);
  blocked = true;
  for (const m of document.querySelectorAll("video, audio")) m.pause();
  const pausedAt = Date.now();
  report("cs-block", { ...details, pausedAt, mediaAfterPause: media() });
  const q = new URLSearchParams({ from: location.href, reason: `cs:${trigger}`, decidedAt: String(now), pausedAt: String(pausedAt), due: String(due ?? "") });
  location.replace(chrome.runtime.getURL("blocked.html") + "?" + q);
}

function urlChanged(via) {
  if (location.href === lastUrl) return;
  const from = lastUrl;
  lastUrl = location.href;
  report("cs-url-change", { via, from: enforce ? from : undefined, sameDocument: true, msSinceLoad: Date.now() - loadedAt, navigateEventAt: lastNavigateEventAt });
  evaluate(`spa:${via}`);
}

// Three independent detectors; the report says which one saw the change first.
if (window.navigation) {
  navigation.addEventListener("navigate", () => { lastNavigateEventAt = Date.now(); });
  navigation.addEventListener("currententrychange", () => urlChanged("navigation-api"));
}
document.addEventListener("yt-navigate-finish", () => urlChanged("yt-navigate-finish"));
setInterval(() => urlChanged("poll-250ms"), 250);

for (const type of ["visibilitychange", "freeze", "resume", "pagehide"]) {
  document.addEventListener(type, () => { if (enforce) report("cs-lifecycle", { event: type, visibility: document.visibilityState }); }, { capture: true });
}
window.addEventListener("pagehide", (e) => { if (enforce) report("cs-lifecycle", { event: "window-pagehide", persisted: e.persisted }); });

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type !== "policy") return;
  policy = msg.policy;
  evaluate(`policy-push:${msg.trigger}`);
});

// Spike tabs must not make sound in the owner's browser: mute every media element at its
// first play event (capture phase, so before the page's own handlers). Installed at
// document_start from the URL marker alone, before the service worker answers.
if (flags.has("mute")) {
  document.addEventListener("play", (e) => {
    if (!e.target.muted) { e.target.muted = true; report("cs-muted", { at: Date.now(), currentTime: e.target.currentTime }); }
  }, true);
  document.addEventListener("volumechange", (e) => { if (!e.target.muted) e.target.muted = true; }, true);
}

// Test helpers, only in tabs the spike opened.
function testHelpers() {
  if (flags.has("play")) {
    setTimeout(async () => {
      const v = document.querySelector("video");
      const before = v ? { paused: v.paused, muted: v.muted, t: v.currentTime } : null;
      let playError = null;
      if (v && v.paused) {
        v.muted = true;
        try { await v.play(); } catch (e) { playError = e.message; }
      }
      const t0 = v?.currentTime;
      setTimeout(() => report("cs-play-check", { before, playError, advancedSec: v ? v.currentTime - t0 : null, after: media() }), 2000);
    }, 3000);
  }
  if (flags.has("spa")) {
    setTimeout(() => {
      const here = location.href;
      const link = location.hostname.endsWith("youtube.com")
        ? [...document.querySelectorAll('a[href*="/watch?v="]')].find((a) => new URL(a.href).searchParams.get("v") !== new URL(here).searchParams.get("v"))
        : [...document.querySelectorAll('a[href^="/"]')].find((a) => new URL(a.href).pathname !== location.pathname && !a.href.includes("/accounts/") && !a.href.includes("/legal/"));
      report("cs-spa-click", { target: link?.href ?? null, candidates: document.querySelectorAll("a").length });
      link?.click();
    }, 8000);
  }
}

chrome.runtime.sendMessage({ type: "cs-hello", marker, csInstance, url: location.href, loadedAt, visibility: document.visibilityState, prerendering: document.prerendering ?? null }).then((r) => {
  policy = r.policy;
  enforce = r.enforce;
  if (enforce) testHelpers();
  evaluate("load");
}).catch((e) => console.warn("FocusPilot spike: no service worker answer", e));
