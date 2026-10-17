const shownAt = Date.now();
const params = Object.fromEntries(new URLSearchParams(location.search));
document.getElementById("details").textContent = JSON.stringify(params);
chrome.runtime.sendMessage({ type: "blocked-shown", params, shownAt, navigationStart: Math.round(performance.timeOrigin) });
