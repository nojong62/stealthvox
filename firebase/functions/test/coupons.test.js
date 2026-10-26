const test = require("node:test");
const assert = require("node:assert/strict");
const {
  FAIL_LIMIT,
  createCoupons,
  generateCode,
  isLinkedAccount,
  judgeAttempts,
  judgeRedeem,
  normalizeCode,
  redeem,
  updateCoupon,
} = require("../coupons");

// admin_ops.test.js와 같은 가짜 DB. 트랜잭션이 실패하면 아무것도 남지 않는다.
class FakeDb {
  constructor(docs = {}) {
    this.docs = new Map(Object.entries(docs));
  }
  doc(path) {
    return {path};
  }
  async runTransaction(run) {
    const staged = new Map(this.docs);
    const result = await run({
      get: async (ref) => {
        const value = staged.get(ref.path);
        return {exists: value !== undefined, data: () => value};
      },
      set: (ref, value) => staged.set(ref.path, {...value}),
      update: (ref, value) => {
        if (!staged.has(ref.path)) throw new Error("update on missing doc");
        staged.set(ref.path, {...staged.get(ref.path), ...value});
      },
    });
    this.docs = staged;
    return result;
  }
  get(path) {
    return this.docs.get(path);
  }
}

const NOW = 1_800_000_000_000;
const coupon = (extra = {}) => ({
  code: "LUNA2H", seconds: 7200, maxUses: 2, usedCount: 0, expiresAtMs: null,
  memo: "유튜버 A", active: true, ...extra,
});

test("codes are normalized; bad shapes are rejected", () => {
  assert.equal(normalizeCode(" luna-2h "), "LUNA2H");
  assert.equal(normalizeCode("k7m2 qx9p"), "K7M2QX9P");
  assert.equal(normalizeCode("../x"), "");
  assert.equal(normalizeCode("ab"), "");
  assert.equal(normalizeCode(undefined), "");
  const code = generateCode();
  assert.match(code, /^[2-9A-HJKMNP-Z]{8}$/);
});

test("only accounts with a sign-in provider count as real accounts", () => {
  assert.equal(isLinkedAccount({providerData: [{providerId: "google.com"}]}), true);
  assert.equal(isLinkedAccount({providerData: []}), false);
  assert.equal(isLinkedAccount(null), false);
});

test("judgeRedeem covers every refusal before the seat count", () => {
  const base = {redeemedByUser: false, redeemedByDevice: false, nowMs: NOW};
  assert.equal(judgeRedeem({...base, coupon: null}), "not_found");
  assert.equal(judgeRedeem({...base, coupon: coupon({active: false})}), "inactive");
  assert.equal(judgeRedeem({...base, coupon: coupon({expiresAtMs: NOW})}), "expired");
  assert.equal(judgeRedeem({...base, coupon: coupon(), redeemedByUser: true}), "already_used");
  assert.equal(judgeRedeem({...base, coupon: coupon(), redeemedByDevice: true}), "device_used");
  assert.equal(judgeRedeem({...base, coupon: coupon({usedCount: 2})}), "full");
  assert.equal(judgeRedeem({...base, coupon: coupon({expiresAtMs: NOW + 1})}), "ok");
});

test("first come first served: seats run out, then the code is full", async () => {
  const db = new FakeDb({
    "coupons/LUNA2H": coupon(),
    "users/u1": {remainingTime: 60},
    "users/u2": {},
    "users/u3": {remainingTime: 0},
  });
  const r1 = await redeem({db, uid: "u1", code: "LUNA2H", devKey: "d1", nowMs: NOW, now: "t"});
  assert.deepEqual(r1, {ok: true, secondsAdded: 7200, remainingTime: 7260});
  const r2 = await redeem({db, uid: "u2", code: "LUNA2H", devKey: "d2", nowMs: NOW, now: "t"});
  assert.equal(r2.remainingTime, 7200);
  const r3 = await redeem({db, uid: "u3", code: "LUNA2H", devKey: "d3", nowMs: NOW, now: "t"});
  assert.deepEqual(r3, {ok: false, reason: "full"});

  assert.equal(db.get("coupons/LUNA2H").usedCount, 2);
  assert.equal(db.get("users/u3").remainingTime, 0);
  assert.equal(db.get("coupons/LUNA2H/redemptions/u1").before_seconds, 60);
});

test("same account or same phone cannot use a code twice", async () => {
  const db = new FakeDb({
    "coupons/LUNA2H": coupon({maxUses: 10}),
    "users/u1": {remainingTime: 0},
    "users/u2": {remainingTime: 0},
  });
  await redeem({db, uid: "u1", code: "LUNA2H", devKey: "d1", nowMs: NOW, now: "t"});
  assert.equal((await redeem({db, uid: "u1", code: "LUNA2H", devKey: "d9", nowMs: NOW, now: "t"})).reason,
    "already_used");
  assert.equal((await redeem({db, uid: "u2", code: "LUNA2H", devKey: "d1", nowMs: NOW, now: "t"})).reason,
    "device_used");
  assert.equal(db.get("users/u1").remainingTime, 7200);
  assert.equal(db.get("users/u2").remainingTime, 0);
  assert.equal(db.get("coupons/LUNA2H").usedCount, 1);
});

test("wrong codes lock the account for an hour after the limit", async () => {
  const db = new FakeDb({"users/u1": {remainingTime: 0}, "coupons/LUNA2H": coupon()});
  for (let i = 0; i < FAIL_LIMIT; i++) {
    const r = await redeem({db, uid: "u1", code: "NOPE" + i, devKey: "d1", nowMs: NOW, now: "t"});
    assert.equal(r.reason, "not_found");
  }
  const locked = await redeem({db, uid: "u1", code: "LUNA2H", devKey: "d1", nowMs: NOW, now: "t"});
  assert.deepEqual(locked, {ok: false, reason: "too_many"});
  const later = await redeem({db, uid: "u1", code: "LUNA2H", devKey: "d1",
    nowMs: NOW + 60 * 60 * 1000, now: "t"});
  assert.equal(later.ok, true);
  assert.deepEqual(judgeAttempts(null, NOW), {locked: false, windowStartMs: NOW, fails: 0});
});

test("createCoupons makes a batch of individual codes, and a retry makes nothing new", async () => {
  const db = new FakeDb();
  let n = 0;
  const random = () => ((n++ * 7) % 31) / 31;
  const input = {db, adminUid: "admin-1", count: 10, seconds: 7200, maxUses: 1,
    expiresAtMs: null, memo: "유튜버 B 10명", requestId: "req-00001", now: "t", random};
  const first = await createCoupons(input);
  assert.equal(first.duplicate, false);
  assert.equal(first.codes.length, 10);
  assert.equal(new Set(first.codes).size, 10);
  for (const code of first.codes) {
    assert.equal(db.get(`coupons/${code}`).maxUses, 1);
    assert.equal(db.get(`coupons/${code}`).active, true);
  }
  const again = await createCoupons(input);
  assert.deepEqual(again, {duplicate: true, codes: first.codes});
});

test("a chosen code is created once and refused when it already exists", async () => {
  const db = new FakeDb({"coupons/LUNA2H": coupon()});
  await assert.rejects(createCoupons({db, adminUid: "a", code: "luna2h", seconds: 7200,
    maxUses: 10, expiresAtMs: null, memo: "m", requestId: "req-00002", now: "t"}),
  {code: "already-exists"});
  const made = await createCoupons({db, adminUid: "a", code: "event-10", seconds: 7200,
    maxUses: 10, expiresAtMs: NOW, memo: "m", requestId: "req-00003", now: "t"});
  assert.deepEqual(made.codes, ["EVENT10"]);
  await assert.rejects(createCoupons({db, adminUid: "a", code: "x", seconds: 7200,
    maxUses: 1, expiresAtMs: null, memo: "m", requestId: "req-00004", now: "t"}),
  {code: "invalid-argument"});
});

test("updateCoupon toggles, resizes, and never drops below seats already taken", async () => {
  const db = new FakeDb({"coupons/LUNA2H": coupon({usedCount: 3, maxUses: 10})});
  const off = await updateCoupon({db, adminUid: "a", code: "LUNA2H", active: false,
    requestId: "req-00010", now: "t"});
  assert.equal(off.active, false);
  assert.equal(db.get("coupons/LUNA2H").active, false);
  assert.equal(db.get("admin_audit/update_coupon_req-00010").before.active, true);

  await assert.rejects(updateCoupon({db, adminUid: "a", code: "LUNA2H", maxUses: 2,
    requestId: "req-00011", now: "t"}), {code: "invalid-argument"});
  await updateCoupon({db, adminUid: "a", code: "LUNA2H", maxUses: 20, requestId: "req-00012", now: "t"});
  assert.equal(db.get("coupons/LUNA2H").maxUses, 20);
  await assert.rejects(updateCoupon({db, adminUid: "a", code: "NONE", active: true,
    requestId: "req-00013", now: "t"}), {code: "not-found"});
});
