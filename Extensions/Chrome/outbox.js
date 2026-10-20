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

  function create(storage, profileId, now = Date.now, { limit = 500 } = {}) {
    const queue = serial();

    function add(kind, details = {}) {
      return queue(async () => {
        const { nextSeq = 1, outbox = [] } = await storage.get(["nextSeq", "outbox"]);
        const observation = {
          ...details, type: "observation", kind, seq: nextSeq,
          observedAt: new Date(now()).toISOString(), profileId: await profileId(),
        };
        outbox.push(observation);
        await storage.set({ nextSeq: nextSeq + 1, outbox: outbox.slice(-limit) });
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

  return { create, serial };
})();

if (typeof module === "object") module.exports = FocusOutbox;
