const test = require("node:test");
const assert = require("node:assert/strict");
const {cleanUpDeletedAccount} = require("../account_deletion");

class FakeDb {
  constructor(docs = {}) {
    this.docs = new Map(Object.entries(docs));
  }
  doc(path) {
    return {path};
  }
  collection(name) {
    return {
      where: (field, op, value) => ({
        get: async () => ({
          docs: [...this.docs.entries()]
            .filter(([p, v]) => p.split("/")[0] === name &&
              p.split("/").length === 2 && v[field] === value)
            .map(([p]) => ({ref: {path: p}})),
        }),
      }),
    };
  }
  batch() {
    const deletes = [];
    return {
      delete: (ref) => deletes.push(ref.path),
      commit: async () => deletes.forEach((p) => this.docs.delete(p)),
    };
  }
}

test("deleting an account clears the member row and its login maps", async () => {
  const db = new FakeDb({
    "real_members/gone": {uid: "gone"},
    "real_members/gone/purchases/e1": {product_id: "p"},
    "real_members/other": {uid: "other"},
    "kakao_uid_map/123": {uid: "gone"},
    "kakao_uid_map/456": {uid: "other"},
    "provider_uid_map/google:9": {uid: "gone"},
    "coupons/ABC/redemptions/gone": {uid: "gone"},
  });

  await cleanUpDeletedAccount(db, "gone");

  assert.deepEqual([...db.docs.keys()].sort(), [
    // 결제 장부와 쿠폰 사용 기록은 남는다.
    "coupons/ABC/redemptions/gone",
    "kakao_uid_map/456",
    "real_members/gone/purchases/e1",
    "real_members/other",
  ]);
});

test("an account with no maps still clears its member row", async () => {
  const db = new FakeDb({"real_members/solo": {uid: "solo"}});
  const removed = await cleanUpDeletedAccount(db, "solo");
  assert.deepEqual(removed, ["real_members/solo"]);
  assert.equal(db.docs.size, 0);
});
