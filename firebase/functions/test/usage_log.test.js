const test = require("node:test");
const assert = require("node:assert/strict");
const {
  usageLogDocumentId,
  writeUsageLogIdempotently,
} = require("../usage_log");

class FakeRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }
  collection(name) {
    return new FakeCollection(this.db, `${this.path}/${name}`);
  }
}

class FakeCollection {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }
  doc(id) {
    return new FakeRef(this.db, `${this.path}/${id}`);
  }
}

class FakeDb {
  constructor(docs = {}) {
    this.docs = new Map(Object.entries(docs));
  }
  doc(path) {
    return new FakeRef(this, path);
  }
  async runTransaction(run) {
    return run({
      get: async ref => {
        const value = this.docs.get(ref.path);
        return { exists: value !== undefined, data: () => value };
      },
      set: (ref, value) => this.docs.set(ref.path, value),
    });
  }
}

const fields = {
  mode: "duo",
  rate: 1,
  seconds_used: 12,
  actual_seconds: 14,
  room_id: "room-1",
  session_id: "session-1",
};

test("same request id resolves to the same opaque document id", () => {
  const first = usageLogDocumentId("user-1", "segment_123456");
  assert.equal(first, usageLogDocumentId("user-1", "segment_123456"));
  assert.notEqual(first, usageLogDocumentId("user-1", "segment_123457"));
  assert.notEqual(first, usageLogDocumentId("user-2", "segment_123456"));
  assert.match(first, /^[a-f0-9]{64}$/);
});

test("retry returns the original usage record without a second write", async () => {
  const db = new FakeDb({ "users/user-1": { remainingTime: 88 } });
  const input = {
    db,
    uid: "user-1",
    requestId: "segment_123456",
    fields,
    serverTimestamp: () => "server-time",
  };
  const first = await writeUsageLogIdempotently(input);
  const second = await writeUsageLogIdempotently(input);

  assert.deepEqual(first, {
    duplicate: false,
    beforeSeconds: 100,
    afterSeconds: 88,
  });
  assert.deepEqual(second, {
    duplicate: true,
    beforeSeconds: 100,
    afterSeconds: 88,
  });
  assert.equal(
    [...db.docs.keys()].filter(path => path.includes("/usage_logs/")).length,
    1,
  );
});
