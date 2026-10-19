// Throwaway spike for issues #1 and #3. declarativeNetRequest only stops the next navigation; it
// cannot end an already loaded single-page app or buffered media when an exception expires. This
// script evaluates the stored policy against its own timer and the page's current URL, stops media
// itself, and asks the background to send the tab to the blocked page (the browser performs that
// navigation, so it does not depend on page timers). Blanking in place is the fallback.
//
// Spike safety: it acts only in probe tabs, which the spike opened itself with #fp-probe=NAME in
// the URL. sessionStorage keeps the mark across the site's own navigations. Probe options, also
// in the hash: autoplay=1 (muted play, allowed without a user gesture), spa=SECONDS (click an
// in-page link to another video after that many seconds).
(() => {
  const P = globalThis.FPPolicy;
  const hash = new URLSearchParams(location.hash.slice(1));
  if (hash.get("fp-probe")) {
    try {
      sessionStorage.setItem("fpProbe", hash.get("fp-probe"));
      sessionStorage.setItem("fpOpts", location.hash.slice(1));
    } catch {}
  }
  let probe = null;
  let opts = new URLSearchParams();
  try {
    probe = sessionStorage.getItem("fpProbe");
    opts = new URLSearchParams(sessionStorage.getItem("fpOpts") ?? "");
  } catch {}
  if (!probe) return;
  let released = false;
  function release() {
    released = true;
    try {
      sessionStorage.removeItem("fpProbe");
      sessionStorage.removeItem("fpOpts");
    } catch {}
  }

  let timer = null;
  let timerDueAt = null;
  let enforced = false;
  let lastHref = location.href;

  function report(event, details = {}) {
    if (released) return;
    browser.runtime
      .sendMessage({ type: "page-event", event, probe, href: location.href, atMs: Date.now(), visibility: document.visibilityState, ...details })
      .catch(() => {});
  }

  function media() {
    return [...document.querySelectorAll("video, audio")];
  }

  function mediaState() {
    return media().map((m) => ({ tag: m.tagName, paused: m.paused, muted: m.muted, t: Math.round(m.currentTime * 10) / 10, ready: m.readyState }));
  }

  function el(tag, text, style) {
    const e = document.createElement(tag);
    if (text != null) e.textContent = text;
    if (style) e.setAttribute("style", style);
    return e;
  }

  // Last resort if the background cannot navigate the tab. DOM calls, not innerHTML: a Trusted
  // Types CSP (instagram.com, youtube.com) rejects string HTML sinks.
  function blank(result) {
    window.stop();
    const head = el("head");
    head.append(el("title", "Blocked by FocusPilot spike"));
    const body = el("body", null, "font: 16px -apple-system, sans-serif; margin: 15vh auto; max-width: 32em;");
    body.append(el("h1", "Blocked by FocusPilot spike"), el("p", `${location.hostname} is blocked by policy revision ${result.revision}.`));
    document.documentElement.replaceChildren(head, body);
  }

  async function enforce(reason, result, dueAt) {
    const { released: r } = await browser.runtime.sendMessage({ type: "hello", probe }).catch(() => ({}));
    if (r) return release();
    enforced = true;
    const now = Date.now();
    const before = mediaState();
    for (const m of media()) {
      m.pause();
      m.muted = true;
    }
    report("media-stopped", { reason, lateMs: dueAt != null ? now - dueAt : null, before, after: mediaState() });
    let resp = null;
    try {
      resp = await browser.runtime.sendMessage({ type: "enforce-me", probe, reason, href: location.href });
    } catch (e) {
      resp = { ok: false, error: String(e?.message ?? e) };
    }
    if (!resp?.ok) {
      report("redirect-failed-blanking", { reason, resp });
      blank(result);
    }
  }

  async function check(reason) {
    if (released) return;
    const { policy = null } = await browser.storage.local.get("policy");
    const now = Date.now();
    const result = P.evaluate(policy, now);
    const blocked = P.isBlocked(result, location.href);
    if (reason === "load") report("content-load", { blocked, revision: result.revision });
    if (blocked && !enforced) {
      const dueAt = reason === "timer" ? timerDueAt : null;
      await enforce(reason, result, dueAt);
      return;
    }
    clearTimeout(timer);
    timerDueAt = result.nextTransitionAt;
    if (timerDueAt != null) {
      const delayMs = Math.max(0, timerDueAt - now) + 50;
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

  // Single-page navigation never reaches DNR (no main_frame request). YouTube fires
  // yt-navigate-finish after its router swaps the page; a 250 ms URL poll covers sites that do
  // not, and history changes made by the page's own pushState are invisible to this isolated world.
  function urlMaybeChanged(via) {
    if (released || location.href === lastHref) return;
    const from = lastHref;
    lastHref = location.href;
    report("spa-nav", { via, from, to: location.href });
    safeCheck("spa:" + via);
  }
  document.addEventListener("yt-navigate-finish", () => urlMaybeChanged("yt-navigate-finish"), true);
  window.addEventListener("popstate", () => urlMaybeChanged("popstate"));
  setInterval(() => urlMaybeChanged("poll"), 250);

  browser.storage.onChanged.addListener((changes) => {
    if (changes.policy) safeCheck("policy-changed");
  });
  document.addEventListener("visibilitychange", () => {
    report("visibility");
    if (!document.hidden) safeCheck("visible");
  });

  // Probe tabs stay muted whatever the site does (YouTube autoplays with sound when Safari's
  // per-site setting allows it, and replaced our muted play() with its own).
  document.addEventListener("play", (e) => { if (!released) e.target.muted = true; }, true);
  document.addEventListener("volumechange", (e) => { if (!released && !e.target.muted) e.target.muted = true; }, true);
  setInterval(() => { if (!released) for (const m of media()) if (!m.muted) m.muted = true; }, 500);

  // Probe helpers: start playback without a user gesture (muted, which WebKit allows), and
  // report media state so "was playing" is measured, not assumed.
  if (opts.get("autoplay") === "1") {
    let tries = 0;
    const kick = setInterval(() => {
      const v = document.querySelector("video");
      if (++tries > 40) {
        clearInterval(kick);
        report("autoplay-gave-up", { media: mediaState() });
      }
      if (!v) return;
      clearInterval(kick);
      v.muted = true;
      v.play().then(
        () => report("autoplay-ok", { media: mediaState() }),
        (e) => report("autoplay-rejected", { error: String(e?.name ?? e), media: mediaState() })
      );
    }, 500);
  }
  setInterval(() => {
    if (!enforced && media().length) report("media-state", { media: mediaState() });
  }, 5000);

  const spaAfter = Number(opts.get("spa") ?? 0);
  if (spaAfter > 0) {
    setTimeout(() => {
      const current = new URL(location.href).searchParams.get("v");
      const link = [...document.querySelectorAll('a[href*="/watch?v="]')].find((a) => {
        const v = new URL(a.href).searchParams.get("v");
        return v && v !== current && a.offsetParent !== null;
      });
      if (!link) return report("spa-click-no-link", { links: document.querySelectorAll('a[href*="/watch?v="]').length });
      report("spa-click", { target: link.href });
      // A synthetic click reaches YouTube's own click handler, which routes in-app (no page load).
      link.click();
    }, spaAfter * 1000);
  }

  browser.runtime.sendMessage({ type: "hello", probe }).then((r) => (r?.released ? release() : safeCheck("load")), () => safeCheck("load"));
})();
