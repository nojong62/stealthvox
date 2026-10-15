const { readBlocked } = require("./block_check");

const TRIAL_GRANT_TTL_MS = 30 * 60 * 1000;

function positiveRemainingTime(data) {
  const value = data && data.remainingTime;
  return typeof value === "number" && Number.isFinite(value) && value > 0;
}

function activeTrialGrant(data, uid, nowMs) {
  return Boolean(data &&
    data.uid === uid &&
    data.status === "active" &&
    Number.isFinite(data.expiresAtMs) &&
    data.expiresAtMs > nowMs);
}

function activeDuoGuestAccess(data, uid) {
  if (!data || data.isDuoEnabled !== true) return false;
  const hostUid = String(data.hostUid || "");
  const partnerUid = String(data.partnerUid || "");
  if (!hostUid || hostUid === uid) return false;
  return partnerUid === uid ||
    (partnerUid === "" && data.isPartnerJoined !== true);
}

function normalizedRoomId(value) {
  const roomId = String(value || "").trim();
  return /^[A-Za-z0-9_-]{6,128}$/.test(roomId) ? roomId : "";
}

async function resolveAiAccess({ db, uid, isAnonymous, roomId, nowMs = Date.now() }) {
  // 관리자 차단이 시간·체험·Duo 게스트 자격보다 먼저다.
  const [blocked, userSnap] = await Promise.all([
    readBlocked(db, uid),
    db.doc(`users/${uid}`).get(),
  ]);
  if (blocked) return { allowed: false, reason: "blocked" };
  if (userSnap.exists && positiveRemainingTime(userSnap.data())) {
    return { allowed: true, reason: "paid" };
  }

  if (isAnonymous) {
    const grantSnap = await db.doc(`ai_trial_grants/${uid}`).get();
    if (grantSnap.exists && activeTrialGrant(grantSnap.data(), uid, nowMs)) {
      return { allowed: true, reason: "trial" };
    }
  }

  const safeRoomId = normalizedRoomId(roomId);
  if (safeRoomId) {
    const roomSnap = await db.doc(`duo_sessions/${safeRoomId}`).get();
    if (roomSnap.exists && activeDuoGuestAccess(roomSnap.data(), uid)) {
      return { allowed: true, reason: "duo_guest", roomId: safeRoomId };
    }
  }

  return { allowed: false, reason: "no_entitlement" };
}

async function claimTrialGrant({
  db,
  uid,
  installationHash,
  nowMs = Date.now(),
  ttlMs = TRIAL_GRANT_TTL_MS,
}) {
  if (!uid || !/^[a-f0-9]{64}$/.test(String(installationHash || ""))) {
    return { granted: false, reason: "invalid_identity" };
  }
  const deviceRef = db.doc(`trial_devices/${installationHash}`);
  const grantRef = db.doc(`ai_trial_grants/${uid}`);
  return db.runTransaction(async tx => {
    const [deviceSnap, grantSnap] = await Promise.all([
      tx.get(deviceRef),
      tx.get(grantRef),
    ]);
    if (deviceSnap.exists) {
      if (deviceSnap.data().uid === uid &&
          grantSnap.exists && activeTrialGrant(grantSnap.data(), uid, nowMs)) {
        return {
          granted: true,
          reason: "existing",
          expiresAtMs: grantSnap.data().expiresAtMs,
        };
      }
      return { granted: false, reason: "device_already_used" };
    }
    if (grantSnap.exists && activeTrialGrant(grantSnap.data(), uid, nowMs)) {
      return {
        granted: true,
        reason: "existing",
        expiresAtMs: grantSnap.data().expiresAtMs,
      };
    }
    const expiresAtMs = nowMs + ttlMs;
    tx.set(deviceRef, { uid, claimedAtMs: nowMs }, { merge: false });
    tx.set(grantRef, {
      uid,
      status: "active",
      claimedAtMs: nowMs,
      expiresAtMs,
    }, { merge: false });
    return { granted: true, reason: "created", expiresAtMs };
  });
}

module.exports = {
  TRIAL_GRANT_TTL_MS,
  activeDuoGuestAccess,
  activeTrialGrant,
  claimTrialGrant,
  normalizedRoomId,
  positiveRemainingTime,
  resolveAiAccess,
};
