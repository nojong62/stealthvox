"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { verifyRelayMembership } = require("../auth");

function verify(overrides = {}) {
  return verifyRelayMembership({
    roomId: "room-1",
    uid: "guest-uid",
    idToken: "valid-token",
    verifyRoom: true,
    verifyIdToken: async () => ({ uid: "guest-uid" }),
    loadRoom: async () => ({
      isDuoEnabled: true,
      hostUid: "host-uid",
      partnerUid: "guest-uid",
    }),
    ...overrides,
  });
}

test("production room verification requires an ID token", async () => {
  let roomRead = false;
  const result = await verify({
    idToken: "",
    loadRoom: async () => {
      roomRead = true;
      return null;
    },
  });

  assert.deepEqual(result, { ok: false, reason: "missing_id_token" });
  assert.equal(roomRead, false);
});

test("verified token UID must match the claimed participant UID", async () => {
  const result = await verify({
    verifyIdToken: async () => ({ uid: "attacker-uid" }),
  });

  assert.deepEqual(result, { ok: false, reason: "uid_mismatch" });
});

test("verified room participant is accepted", async () => {
  assert.deepEqual(await verify(), { ok: true });
});

test("verified non-participant is rejected", async () => {
  const result = await verify({ uid: "third-uid", verifyIdToken: async () => ({ uid: "third-uid" }) });

  assert.deepEqual(result, { ok: false, reason: "not_a_member" });
});

test("invalid Firebase token fails closed", async () => {
  const error = Object.assign(new Error("bad token"), { code: "auth/invalid-id-token" });
  const result = await verify({
    verifyIdToken: async () => { throw error; },
  });

  assert.deepEqual(result, {
    ok: false,
    reason: "verify_failed(auth/invalid-id-token)",
  });
});

test("explicit local development bypass remains available", async () => {
  const result = await verify({ verifyRoom: false, idToken: "" });

  assert.deepEqual(result, { ok: true });
});
