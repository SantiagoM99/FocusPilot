// Renders FocusBlockedView for this tab and keeps it current: the session
// countdown ticks, and a new policy or app status redraws it.

const params = new URLSearchParams(location.search);
// The content script and worker pass ?from=; network rules put the URL in the fragment.
const from = params.get("from") ?? safelyDecoded(location.hash.slice(1));
const by = params.get("by") ?? "network";
const $ = (id) => document.getElementById(id);

function safelyDecoded(text) {
  try { return decodeURI(text); } catch { return text; }
}

let state = { delivery: null, appRunning: null };
let current = null;
let reported = false;
let unreachable = false;

function render() {
  const m = FocusBlockedView.model({ ...state, url: from, now: Date.now() });
  current = m;
  $("dot").className = "dot " + m.status.tone;
  $("status").textContent = m.status.text;
  $("eyebrow").textContent = m.eyebrow ?? "";
  $("eyebrow").hidden = !m.eyebrow;
  $("title").textContent = m.title;
  $("subtitle").textContent = m.subtitle ?? "";
  $("subtitle").hidden = !m.subtitle;
  $("detail").textContent = m.detail ?? "";
  $("detail").hidden = !m.detail;
  $("primary").textContent = m.primary.label;
  const hint = unreachable ? "FocusPilot couldn't be reached. Open it from Applications or Spotlight." : m.hint;
  $("hint").textContent = hint ?? "";
  $("hint").hidden = !hint;
  $("exception").hidden = !m.exceptionLink;
  $("footer-left").textContent = m.footer[0];
  $("footer-right").textContent = m.footer[1];
  document.title = m.kind === "unblocked" ? "FocusPilot" : `Blocked · ${m.domain}`;
  if (!reported && m.kind !== "unblocked") {
    reported = true;
    chrome.runtime.sendMessage({ type: "blocked-shown", domain: m.domain, view: m.kind, by }).catch(() => {});
  }
}

$("primary").addEventListener("click", async () => {
  if (current.primary.action === "go-back") {
    location.replace(from);
    return;
  }
  const answer = await chrome.runtime.sendMessage({ type: "open-app" }).catch(() => null);
  unreachable = !answer?.sent;
  render();
});

$("exception").addEventListener("click", (event) => {
  event.preventDefault();
  $("exception-panel").hidden = false;
  $("page").hidden = true;
  chrome.runtime.sendMessage({ type: "exception-requested", domain: current.domain }).catch(() => {});
});

$("close-exception").addEventListener("click", () => {
  $("exception-panel").hidden = true;
  $("page").hidden = false;
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "local") return;
  if (changes.delivery) state.delivery = changes.delivery.newValue ?? null;
  if (changes.appRunning) state.appRunning = changes.appRunning.newValue ?? null;
  render();
});

chrome.storage.local.get(["delivery", "appRunning"]).then((stored) => {
  state = { delivery: stored.delivery ?? null, appRunning: stored.appRunning ?? null };
  render();
  setInterval(render, 1000);
});
