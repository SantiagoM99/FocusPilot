// Renders FocusBlockedView for this tab and keeps it current: the session
// countdown ticks, and a new policy or app status redraws it.

// frame-guard.js emptied the page if it is framed; nothing here may run then.
if (globalThis.focusPilotFramed) throw new Error("FocusPilot's blocked page does not run inside a frame.");

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
// The timed exception form (design 05B); null while it is closed.
let form = null;

// Reduce Motion: the countdowns change once a minute instead of every second.
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
reducedMotion.addEventListener("change", () => render());

function render() {
  const m = FocusBlockedView.model({ ...state, url: from, now: Date.now(), reduceMotion: reducedMotion.matches });
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
  document.title = m.kind === "unblocked" || m.kind === "excepted" ? "FocusPilot" : `Blocked · ${m.domain}`;
  // Granted here or in another profile: back to the page once the policy carries it.
  if (form?.phase === "granted" && m.kind === "excepted" && m.backURL) {
    location.replace(m.backURL);
    return;
  }
  if (form && form.phase !== "granted" && m.kind !== "session" && m.kind !== "rule") closeForm();
  if (form) renderForm();
  if (!reported && m.kind !== "unblocked") {
    reported = true;
    chrome.runtime.sendMessage({ type: "blocked-shown", domain: m.domain, view: m.kind, by }).catch(() => {});
  }
}

$("primary").addEventListener("click", async () => {
  if (current.primary.action === "go-back") {
    if (current.backURL) location.replace(current.backURL);
    else chrome.tabs.update({ url: "chrome://newtab/" }).catch(() => {});
    return;
  }
  const answer = await chrome.runtime.sendMessage({ type: "open-app" }).catch(() => null);
  unreachable = !answer?.sent;
  render();
});

// ---- Timed exception form ----

// Arrow keys, Home and End pick within a radio group, as native radios do.
for (const group of [$("x-durations"), $("x-scopes")]) {
  group.addEventListener("keydown", (event) => {
    const radios = [...group.querySelectorAll("[role=radio]")];
    const index = radios.indexOf(document.activeElement);
    const next = index < 0 ? null : FocusBlockedView.nextChoice(index, radios.length, event.key);
    if (next === null || radios[next].disabled) return;
    event.preventDefault();
    radios[next].click();
    group.querySelectorAll("[role=radio]")[next]?.focus();
  });
}

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && form) {
    event.preventDefault();
    closeForm();
  }
});

function openForm() {
  let path = "/";
  try { path = new URL(from).pathname + new URL(from).search; } catch { /* keep the site */ }
  form = { duration: 600, scope: path === "/" ? "site" : "page", reason: "", phase: "editing", availableAt: null, error: null };
  $("x-reason").value = "";
  $("exception-panel").hidden = false;
  $("page").hidden = true;
  renderForm();
  // Keyboard focus follows the form; the link that opened it is now hidden.
  $("x-durations").querySelector("[aria-checked=true]")?.focus();
  chrome.runtime.sendMessage({ type: "exception-opened", domain: current.domain }).catch(() => {});
}

function closeForm() {
  if (form?.phase === "waiting") {
    const { scope } = FocusBlockedView.exceptionForm({ ...state, url: from, now: Date.now(), state: form }).request;
    chrome.runtime.sendMessage({ type: "exception-cancel", scope }).catch(() => {});
  }
  const hadFocus = $("exception-panel").contains(document.activeElement);
  form = null;
  $("exception-panel").hidden = true;
  $("page").hidden = false;
  if (hadFocus) ($("exception").hidden ? $("primary") : $("exception")).focus();
}

function choice(group, { label, detail, selected, disabled }, onPick) {
  const button = document.createElement("button");
  button.type = "button";
  button.setAttribute("role", "radio");
  button.setAttribute("aria-checked", String(selected));
  // One stop per group for Tab; arrow keys move within it.
  button.tabIndex = selected ? 0 : -1;
  button.disabled = disabled;
  const title = document.createElement("span");
  title.textContent = label;
  button.append(title);
  if (detail) {
    const small = document.createElement("small");
    small.textContent = detail;
    button.append(small);
  }
  button.addEventListener("click", onPick);
  group.append(button);
}

function renderForm() {
  const f = FocusBlockedView.exceptionForm({ ...state, url: from, now: Date.now(), state: form });
  $("x-title").textContent = f.title;
  $("x-strict").hidden = !f.strict;
  $("x-note").textContent = f.note;
  // Rebuilt only when they change, so the countdown tick keeps keyboard focus.
  const choices = JSON.stringify([f.durations, f.scopes, f.locked]);
  if ($("x-durations").dataset.choices !== choices) {
    const focused = document.activeElement?.closest?.("[role=radiogroup]") ? document.activeElement.textContent : null;
    $("x-durations").dataset.choices = choices;
    $("x-durations").replaceChildren();
    for (const d of f.durations) {
      choice($("x-durations"), { label: d.label, selected: d.selected, disabled: f.locked }, () => { form.duration = d.seconds; renderForm(); });
    }
    $("x-scopes").replaceChildren();
    for (const s of f.scopes) {
      choice($("x-scopes"), { label: s.label, detail: s.detail, selected: s.selected, disabled: f.locked }, () => { form.scope = s.id; renderForm(); });
    }
    if (focused) [...document.querySelectorAll("[role=radio]")].find((b) => b.textContent === focused)?.focus();
  }
  $("x-reason-row").hidden = !f.reason;
  $("x-reason").required = Boolean(f.reason);
  if (f.reason) {
    $("x-reason").placeholder = f.reason.placeholder;
    $("x-reason").disabled = f.locked;
  }
  $("x-wait").textContent = f.waitNote ?? "";
  $("x-wait").hidden = !f.waitNote;
  $("x-error").textContent = f.error ?? "";
  $("x-error").hidden = !f.error;
  $("x-allow").textContent = form.phase === "granted" ? "Allowed" : f.allow.label;
  $("x-allow").disabled = f.allow.disabled || form.phase === "granted";
}

async function submitForm() {
  const request = FocusBlockedView.exceptionForm({ ...state, url: from, now: Date.now(), state: form }).request;
  const resumeAs = form.phase === "waiting" ? "waiting" : "editing";
  form.phase = "sending";
  form.error = null;
  renderForm();
  const answer = await chrome.runtime.sendMessage({ type: "exception-request", ...request })
    .catch(() => ({ outcome: "refused", message: "FocusPilot isn't reachable. Open FocusPilot and try again." }));
  if (!form) return;
  switch (answer?.outcome) {
    case "granted": form.phase = "granted"; break;
    case "needs-confirmation": form.phase = "confirming"; break;
    case "wait":
      form.phase = "waiting";
      form.availableAt = Date.parse(answer.availableAt);
      // "Allow now" follows this page's clock; FocusPilot's wait runs on its
      // own monotonic clock and can end a moment later. Ask again then.
      if (resumeAs === "waiting") {
        setTimeout(() => { if (form?.phase === "waiting") submitForm(); }, Math.max(0, form.availableAt - Date.now()) + 300);
      }
      break;
    default: form.phase = resumeAs; form.error = answer?.message ?? "FocusPilot didn't answer. Try again.";
  }
  render();
}

$("exception").addEventListener("click", (event) => {
  event.preventDefault();
  openForm();
});

$("x-reason").addEventListener("input", (event) => {
  form.reason = event.target.value;
  renderForm();
});

$("exception-form").addEventListener("submit", (event) => {
  event.preventDefault();
  if (!$("x-allow").disabled) submitForm();
});

$("x-cancel").addEventListener("click", closeForm);

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
