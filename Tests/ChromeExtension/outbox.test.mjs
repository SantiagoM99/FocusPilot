import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const FocusOutbox = require("../../Extensions/Chrome/outbox.js");

// chrome.storage.local stand-in.
function memoryStorage() {
  const data = {};
  return {
    data,
    get: async (keys) => Object.fromEntries(keys.filter((k) => k in data).map((k) => [k, structuredClone(data[k])])),
    set: async (values) => Object.assign(data, structuredClone(values)),
  };
}

const profile = () => Promise.resolve("4f5ce721-0000-4000-8000-000000000001");

test("observations get increasing sequence numbers and wait for their ack", async () => {
  const outbox = FocusOutbox.create(memoryStorage(), profile, () => 1000);

  await outbox.add("worker-start");
  await outbox.add("blocked-shown", { domain: "youtube.com" });

  const pending = await outbox.pending();
  assert.deepEqual(pending.map((o) => [o.seq, o.kind]), [[1, "worker-start"], [2, "blocked-shown"]]);
  assert.equal(pending[1].type, "observation");
  assert.equal(pending[1].domain, "youtube.com");
  assert.equal(pending[1].profileId, "4f5ce721-0000-4000-8000-000000000001");
  assert.equal(pending[1].observedAt, new Date(1000).toISOString());
});

// Spike S2 lost an observation by clearing the outbox after posting to a
// port that then failed: postMessage does not throw.
test("only an ack removes an observation; sending does not", async () => {
  const storage = memoryStorage();
  const outbox = FocusOutbox.create(storage, profile, () => 0);
  await outbox.add("a");
  await outbox.add("b");

  await outbox.acknowledge(1);

  assert.deepEqual((await outbox.pending()).map((o) => o.seq), [2]);
  const reopened = FocusOutbox.create(storage, profile, () => 0);
  assert.deepEqual((await reopened.pending()).map((o) => o.seq), [2]);
  await reopened.add("c");
  assert.deepEqual((await reopened.pending()).map((o) => o.seq), [2, 3]);
});

test("concurrent adds never reuse a sequence number", async () => {
  const outbox = FocusOutbox.create(memoryStorage(), profile, () => 0);

  await Promise.all([outbox.add("a"), outbox.add("b"), outbox.add("c")]);

  assert.deepEqual((await outbox.pending()).map((o) => o.seq), [1, 2, 3]);
});

test("a full outbox drops the oldest, which the host then reports as a gap", async () => {
  const outbox = FocusOutbox.create(memoryStorage(), profile, () => 0, { limit: 2 });

  await outbox.add("a");
  await outbox.add("b");
  await outbox.add("c");

  assert.deepEqual((await outbox.pending()).map((o) => o.seq), [2, 3]);
});

// A restarted worker used to post its new observation before resending older
// unacknowledged ones, and before hello; the host then took the older ones
// for resends of something it already had.
test("a connection sends waiting observations after hello, in order, each once", async () => {
  const outbox = FocusOutbox.create(memoryStorage(), profile, () => 0);
  const posted = [];
  const sender = FocusOutbox.sender(outbox, (o) => posted.push(o.seq));
  await outbox.add("policy-applied");
  await outbox.add("worker-start");
  await sender.send();
  assert.deepEqual(posted, []);

  await sender.open();
  await outbox.add("blocked-shown");
  await Promise.all([sender.send(), sender.send()]);

  assert.deepEqual(posted, [1, 2, 3]);
});

test("a new connection resends everything not yet acknowledged", async () => {
  const outbox = FocusOutbox.create(memoryStorage(), profile, () => 0);
  const posted = [];
  const sender = FocusOutbox.sender(outbox, (o) => posted.push(o.seq));
  await outbox.add("a");
  await outbox.add("b");
  await sender.open();
  await outbox.acknowledge(1);

  sender.close();
  await outbox.add("c");
  await sender.send();
  await sender.open();

  assert.deepEqual(posted, [1, 2, 2, 3]);
});
