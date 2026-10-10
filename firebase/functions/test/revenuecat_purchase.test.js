"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  SANDBOX_ALLOWLIST_PATH,
  processRevenueCatPurchase,
} = require("../revenuecat_purchase");

const PRODUCTS = {
  stealthvox_10m: {seconds: 600, title: "10 Minutes"},
};

class Ref {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }
  collection(name) {
    return {doc: (id) => new Ref(this.db, this.path + "/" + name + "/" + id)};
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    this.docs = new Map(Object.entries(seed));
  }
  doc(path) {
    return new Ref(this, path);
  }
  async runTransaction(callback) {
    const writes = [];
    const tx = {
      get: async (ref) => ({
        exists: this.docs.has(ref.path),
        data: () => this.docs.get(ref.path),
      }),
      update: (ref, data) => writes.push({kind: "update", ref, data}),
      set: (ref, data) => writes.push({kind: "set", ref, data}),
    };
    const result = await callback(tx);
    for (const write of writes) {
      const previous = this.docs.get(write.ref.path) || {};
      this.docs.set(write.ref.path, {...previous, ...write.data});
    }
    return result;
  }
}

function event(overrides = {}) {
  return {
    id: "event-1",
    type: "NON_RENEWING_PURCHASE",
    app_user_id: "tester-uid",
    product_id: "stealthvox_10m",
    environment: "SANDBOX",
    ...overrides,
  };
}

async function process(db, overrides = {}) {
  return processRevenueCatPurchase({
    firestore: db,
    event: event(overrides),
    products: PRODUCTS,
    serverTimestamp: () => "server-time",
  });
}

test("allowed SANDBOX purchase credits once and stores environment", async () => {
  const db = new FakeFirestore({
    "users/tester-uid": {remainingTime: 120},
    [SANDBOX_ALLOWLIST_PATH]: {allowed_uids: ["tester-uid"]},
  });

  const first = await process(db);
  assert.equal(first.reason, "success");
  assert.equal(first.remainingTime, 720);
  assert.equal(db.docs.get("users/tester-uid").remainingTime, 720);
  const purchase = db.docs.get("users/tester-uid/purchases/event-1");
  assert.equal(purchase.environment, "SANDBOX");
  assert.equal(purchase.seconds_added, 600);
  const member = db.docs.get("real_members/tester-uid");
  assert.equal(member.purchaseCount, 1);
  assert.equal(member.totalSecondsPurchased, 600);
  assert.equal(
    db.docs.get("real_members/tester-uid/purchases/event-1").product_id,
    "stealthvox_10m"
  );

  const duplicate = await process(db);
  assert.equal(duplicate.reason, "duplicate_event");
  assert.equal(db.docs.get("users/tester-uid").remainingTime, 720);
  assert.equal(
    [...db.docs.keys()].filter((path) =>
      path.startsWith("users/tester-uid/purchases/")).length,
    1
  );
  assert.equal(db.docs.get("real_members/tester-uid").purchaseCount, 1);
});

test("SANDBOX purchase rejects a UID outside the allowlist", async () => {
  const db = new FakeFirestore({
    "users/tester-uid": {remainingTime: 120},
    [SANDBOX_ALLOWLIST_PATH]: {allowed_uids: ["another-uid"]},
  });
  const result = await process(db);
  assert.equal(result.reason, "sandbox_not_allowed");
  assert.equal(db.docs.get("users/tester-uid").remainingTime, 120);
});

test("PRODUCTION uses the same transaction without the sandbox allowlist", async () => {
  const db = new FakeFirestore({"users/tester-uid": {remainingTime: 0}});
  const result = await process(db, {environment: "PRODUCTION"});
  assert.equal(result.reason, "success");
  assert.equal(db.docs.get("users/tester-uid").remainingTime, 600);
  assert.equal(
    db.docs.get("users/tester-uid/purchases/event-1").environment,
    "PRODUCTION"
  );
});

test("invalid product is rejected without writes", async () => {
  const db = new FakeFirestore({"users/tester-uid": {remainingTime: 0}});
  const result = await process(db, {product_id: "unknown"});
  assert.equal(result.reason, "invalid_product");
  assert.equal(db.docs.size, 1);
});

test("missing event id is rejected without writes", async () => {
  const db = new FakeFirestore({"users/tester-uid": {remainingTime: 0}});
  const result = await process(db, {id: ""});
  assert.equal(result.reason, "missing_event_id");
  assert.equal(db.docs.size, 1);
});

test("unknown user is rejected without creating a user", async () => {
  const db = new FakeFirestore({
    [SANDBOX_ALLOWLIST_PATH]: {allowed_uids: ["tester-uid"]},
  });
  const result = await process(db);
  assert.equal(result.reason, "user_not_found");
  assert.equal(db.docs.has("users/tester-uid"), false);
});

test("unsupported environment is rejected", async () => {
  const db = new FakeFirestore({"users/tester-uid": {remainingTime: 0}});
  const result = await process(db, {environment: "UNKNOWN"});
  assert.equal(result.reason, "unsupported_environment");
  assert.equal(db.docs.get("users/tester-uid").remainingTime, 0);
});
