const test = require("node:test");
const assert = require("node:assert/strict");

const {
  activeDuoGuestAccess,
  activeTrialGrant,
  claimTrialGrant,
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

function transactionalDb(docs) {
  const writes = [];
  const db = {
    doc: path => ({ path }),
    async runTransaction(run) {
      return run({
        async get(ref) {
          const value = docs[ref.path];
          return { exists: value !== undefined, data: () => value };
        },
        set(ref, value) {
          writes.push([ref.path, value]);
        },
      });
    },
  };
  return { db, writes };
}

test("paid access requires a finite positive server balance", () => {
  assert.equal(positiveRemainingTime({ remainingTime: 1 }), true);
  assert.equal(positiveRemainingTime({ remainingTime: 0 }), false);
  assert.equal(positiveRemainingTime({ remainingTime: Number.POSITIVE_INFINITY }), false);
});

test("trial grant must belong to the anonymous uid and be unexpired", () => {
  const grant = { uid: "anon-1", status: "active", expiresAtMs: 2000 };
  assert.equal(activeTrialGrant(grant, "anon-1", 1999), true);
  assert.equal(activeTrialGrant(grant, "anon-2", 1999), false);
  assert.equal(activeTrialGrant(grant, "anon-1", 2000), false);
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

test("access resolution accepts paid, trial, and invited guest paths", async () => {
  assert.equal((await resolveAiAccess({
    db: fakeDb({ "users/paid": { remainingTime: 5 } }),
    uid: "paid",
    isAnonymous: false,
  })).reason, "paid");

  assert.equal((await resolveAiAccess({
    db: fakeDb({
      "ai_trial_grants/anon": {
        uid: "anon", status: "active", expiresAtMs: 2000,
      },
    }),
    uid: "anon",
    isAnonymous: true,
    nowMs: 1000,
  })).reason, "trial");

  assert.equal((await resolveAiAccess({
    db: fakeDb({
      "users/guest": { remainingTime: 0 },
      "duo_sessions/room_123": {
        hostUid: "host", isDuoEnabled: true, isPartnerJoined: false,
      },
    }),
    uid: "guest",
    isAnonymous: false,
    roomId: "room_123",
  })).reason, "duo_guest");
});

test("access resolution denies zero-balance callers without server evidence", async () => {
  const result = await resolveAiAccess({
    db: fakeDb({ "users/user": { remainingTime: 0 } }),
    uid: "user",
    isAnonymous: false,
  });
  assert.deepEqual(result, { allowed: false, reason: "no_entitlement" });
});

test("trial claim is one-time and cannot be renewed after expiry", async () => {
  const hash = "a".repeat(64);
  const fresh = transactionalDb({});
  const created = await claimTrialGrant({
    db: fresh.db,
    uid: "anon",
    installationHash: hash,
    nowMs: 1000,
    ttlMs: 500,
  });
  assert.equal(created.reason, "created");
  assert.equal(fresh.writes.length, 2);

  const expired = transactionalDb({
    [`trial_devices/${hash}`]: { uid: "anon" },
    "ai_trial_grants/anon": {
      uid: "anon", status: "active", expiresAtMs: 1000,
    },
  });
  const denied = await claimTrialGrant({
    db: expired.db,
    uid: "anon",
    installationHash: hash,
    nowMs: 1001,
  });
  assert.deepEqual(denied, { granted: false, reason: "device_already_used" });
  assert.equal(expired.writes.length, 0);
});
