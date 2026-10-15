const test = require("node:test");
const assert = require("node:assert/strict");

const {
  activeDuoGuestAccess,
  normalizedRoomId,
  positiveRemainingTime,
  resolveAiAccess,
} = require("../ai_access");

function fakeDb(docs) {
  return {
    doc(path) {
      return {
        async get() {
          const value = docs[path];
          return {
            exists: value !== undefined,
            data: () => value,
          };
        },
      };
    },
  };
}

test("paid access requires a finite positive server balance", () => {
  assert.equal(positiveRemainingTime({ remainingTime: 1 }), true);
  assert.equal(positiveRemainingTime({ remainingTime: 0 }), false);
  assert.equal(positiveRemainingTime({ remainingTime: Number.POSITIVE_INFINITY }), false);
});

test("Duo access is guest-only and rejects occupied invitations", () => {
  const open = { hostUid: "host", isDuoEnabled: true, isPartnerJoined: false };
  assert.equal(activeDuoGuestAccess(open, "guest"), true);
  assert.equal(activeDuoGuestAccess(open, "host"), false);
  assert.equal(activeDuoGuestAccess({ ...open, isPartnerJoined: true }, "guest"), false);
  assert.equal(activeDuoGuestAccess({ ...open, partnerUid: "guest", isPartnerJoined: true }, "guest"), true);
  assert.equal(activeDuoGuestAccess({ ...open, partnerUid: "other", isPartnerJoined: true }, "guest"), false);
});

test("room ids are constrained before becoming Firestore paths", () => {
  assert.equal(normalizedRoomId("room_123"), "room_123");
  assert.equal(normalizedRoomId("../../users"), "");
  assert.equal(normalizedRoomId("short"), "");
});

test("access resolution accepts paid and invited guest paths", async () => {
  assert.equal((await resolveAiAccess({
    db: fakeDb({ "users/paid": { remainingTime: 5 } }),
    uid: "paid",
  })).reason, "paid");

  assert.equal((await resolveAiAccess({
    db: fakeDb({
      "users/guest": { remainingTime: 0 },
      "duo_sessions/room_123": {
        hostUid: "host", isDuoEnabled: true, isPartnerJoined: false,
      },
    }),
    uid: "guest",
    roomId: "room_123",
  })).reason, "duo_guest");
});

test("access resolution denies zero-balance callers without server evidence", async () => {
  const result = await resolveAiAccess({
    db: fakeDb({ "users/user": { remainingTime: 0 } }),
    uid: "user",
  });
  assert.deepEqual(result, { allowed: false, reason: "no_entitlement" });
});

test("a leftover trial grant no longer opens AI access", async () => {
  const result = await resolveAiAccess({
    db: fakeDb({
      "ai_trial_grants/anon": { uid: "anon", status: "active", expiresAtMs: Date.now() + 60000 },
    }),
    uid: "anon",
  });
  assert.deepEqual(result, { allowed: false, reason: "no_entitlement" });
});
