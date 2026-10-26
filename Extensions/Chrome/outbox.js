// Observations waiting for the native host. Each stays in storage until the
// host acknowledges its sequence number: posting to a port does not throw
// even when the port is about to fail (spike S2 lost one that way).

var FocusOutbox = (() => {
  // Runs storage read-modify-writes one at a time, so sequence numbers
  // never collide when several wake events fire together.
  function serial() {
    let tail = Promise.resolve();
    return (fn) => (tail = tail.then(fn, fn));
  }

  // Front-tab reports (#21) are raw activity: kept a day at most, and
  // capped on their own so they never push out diagnostics.
  const ACTIVITY = new Set(["tab-front"]);
  const ACTIVITY_MS = 24 * 3600 * 1000;

  function trim(outbox, at, limit, activityLimit) {
    const fresh = outbox.filter((o) => !ACTIVITY.has(o.kind) || at - Date.parse(o.observedAt) <= ACTIVITY_MS);
    const keep = new Set([
      ...fresh.filter((o) => !ACTIVITY.has(o.kind)).slice(-limit),
      ...fresh.filter((o) => ACTIVITY.has(o.kind)).slice(-activityLimit),
    ]);
    return fresh.filter((o) => keep.has(o));
  }

  function create(storage, profileId, now = Date.now, { limit = 500, activityLimit = 200 } = {}) {
    const queue = serial();

    function add(kind, details = {}) {
      return queue(async () => {
        const { nextSeq = 1, outbox = [] } = await storage.get(["nextSeq", "outbox"]);
        const observation = {
          ...details, type: "observation", kind, seq: nextSeq,
          observedAt: new Date(now()).toISOString(), profileId: await profileId(),
        };
        outbox.push(observation);
        await storage.set({ nextSeq: nextSeq + 1, outbox: trim(outbox, now(), limit, activityLimit) });
        return observation;
      });
    }

    function acknowledge(seq) {
      return queue(async () => {
        const { outbox = [] } = await storage.get(["outbox"]);
        await storage.set({ outbox: outbox.filter((o) => o.seq !== seq) });
      });
    }

    function pending() {
      return queue(async () => (await storage.get(["outbox"])).outbox ?? []);
    }

    return { add, acknowledge, pending };
  }

  // Posts the outbox over one connection in sequence order, each observation
  // once per connection, and only after `open` (called once hello is sent):
  // the host treats anything below the last number it saw as a resend.
  function sender(outbox, post) {
    const queue = serial();
    let isOpen = false;
    let sentUpTo = 0;

    function send() {
      return queue(async () => {
        if (!isOpen) return;
        for (const observation of await outbox.pending()) {
          if (observation.seq <= sentUpTo) continue;
          post(observation);
          sentUpTo = observation.seq;
        }
      });
    }

    function open() {
      isOpen = true;
      sentUpTo = 0;
      return send();
    }

    function close() {
      isOpen = false;
    }

    return { send, open, close };
  }

  return { create, serial, sender };
})();

if (typeof module === "object") module.exports = FocusOutbox;
