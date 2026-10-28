// blocked.html is web-accessible (redirects and pages navigate to it), so
// any site could load it in a frame and trick a click on "Allow"
// (clickjacking). Framed, it stops loading and shows nothing; blocked.js
// checks the same flag and does not run. Loaded first, in <head>.

var FocusFrameGuard = (() => {
  function isFramed(win) {
    try { return win.top !== win; } catch { return true; }
  }

  function refuseFraming(win, doc) {
    if (!isFramed(win)) return false;
    win.stop();
    doc.documentElement.replaceChildren();
    return true;
  }

  return { refuseFraming };
})();

if (typeof module === "object") module.exports = FocusFrameGuard;
else globalThis.focusPilotFramed = FocusFrameGuard.refuseFraming(window, document);
