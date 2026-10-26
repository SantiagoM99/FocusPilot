// blocked.html is web-accessible, so any site could frame it and trick a
// click on "Allow" (clickjacking). Run with scripts/test-extension.sh.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const FocusFrameGuard = require("../../Extensions/Chrome/frame-guard.js");

function page(framed) {
  const calls = [];
  const win = { stop: () => calls.push("stop") };
  win.top = framed ? {} : win;
  const doc = { documentElement: { replaceChildren: () => calls.push("emptied") } };
  return { win, doc, calls };
}

test("framed, the blocked page stops loading and shows nothing", () => {
  const { win, doc, calls } = page(true);
  assert.equal(FocusFrameGuard.refuseFraming(win, doc), true);
  assert.deepEqual(calls, ["stop", "emptied"]);
});

test("as the tab's own page it runs normally", () => {
  const { win, doc, calls } = page(false);
  assert.equal(FocusFrameGuard.refuseFraming(win, doc), false);
  assert.deepEqual(calls, []);
});

test("if the top window can't even be read, it counts as framed", () => {
  const { doc, calls } = page(true);
  const win = { stop: () => calls.push("stop"), get top() { throw new Error("cross-origin"); } };
  assert.equal(FocusFrameGuard.refuseFraming(win, doc), true);
});
