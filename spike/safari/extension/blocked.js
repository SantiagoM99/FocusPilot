// Throwaway spike for issue #3. Reports its own arrival so the delay from expiry (or session
// start, or SPA navigation) to the blocked page can be measured.
const params = Object.fromEntries(new URLSearchParams(location.search));
document.getElementById("from").textContent = params.from || "";
browser.runtime.sendMessage({ type: "blocked-page-load", loadedAtMs: Date.now(), params }).catch(() => {});
