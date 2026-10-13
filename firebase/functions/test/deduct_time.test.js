const test = require("node:test");
const assert = require("node:assert/strict");
const {
  deductionDocumentId,
  deductTimeIdempotently,
} = require("../deduct_time");

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
      update: (ref, value) =>
        this.docs.set(ref.path, { ...this.docs.get(ref.path), ...value }),
    });
  }
}

const input = db => ({
  db,
  uid: "user-1",
  seconds: 60,
  requestId: "flush_1700000000_1",
  serverTimestamp: () => "server-time",
});

test("deduction id is stable per uid and request", () => {
  const first = deductionDocumentId("user-1", "flush_1");
  assert.equal(first, deductionDocumentId("user-1", "flush_1"));
  assert.notEqual(first, deductionDocumentId("user-2", "flush_1"));
  assert.match(first, /^[a-f0-9]{64}$/);
});

test("retried flush with the same request id deducts only once", async () => {
  const db = new FakeDb({ "users/user-1": { remainingTime: 300 } });
  const first = await deductTimeIdempotently(input(db));
  const retry = await deductTimeIdempotently(input(db));

  assert.deepEqual(first, { duplicate: false, before: 300, after: 240 });
  assert.equal(retry.duplicate, true);
  assert.equal(retry.after, 240);
  assert.equal(db.docs.get("users/user-1").remainingTime, 240);
});

test("different request ids are separate deductions", async () => {
  const db = new FakeDb({ "users/user-1": { remainingTime: 300 } });
  await deductTimeIdempotently(input(db));
  await deductTimeIdempotently({ ...input(db), requestId: "flush_1700000000_2" });
  assert.equal(db.docs.get("users/user-1").remainingTime, 180);
});

test("legacy call without request id still deducts and never goes below zero", async () => {
  const db = new FakeDb({ "users/user-1": { remainingTime: 30 } });
  const result = await deductTimeIdempotently({ ...input(db), requestId: "" });
  assert.deepEqual(result, { duplicate: false, before: 30, after: 0 });
  assert.equal(
    [...db.docs.keys()].filter(path => path.includes("/deductions/")).length,
    0,
  );
});

test("missing user returns zero without writes", async () => {
  const db = new FakeDb();
  const result = await deductTimeIdempotently(input(db));
  assert.deepEqual(result, { duplicate: false, before: null, after: 0 });
  assert.equal(db.docs.size, 0);
});
