// Observe-only mode (#21): what the worker may say about the tab in front.
// Only a domain, never the URL, path or title, and nothing for incognito
// tabs or browser pages.

var FocusObserve = (() => {
  function domainOf(tab) {
    if (!tab || tab.incognito || !/^https?:/.test(tab.url ?? "")) return null;
    try {
      const host = new URL(tab.url).hostname.toLowerCase().replace(/\.$/, "");
      return host.startsWith("www.") ? host.slice(4) : host || null;
    } catch {
      return null;
    }
  }

  return { domainOf };
})();

if (typeof module === "object") module.exports = FocusObserve;
