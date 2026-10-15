const { readBlocked } = require("./block_check");

function positiveRemainingTime(data) {
  const value = data && data.remainingTime;
  return typeof value === "number" && Number.isFinite(value) && value > 0;
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

// AI 자격은 둘뿐이다: 남은 시간이 있는 본인, 또는 초대받은 Duo 게스트.
// (맛보기 체험 자격은 2026-10-15 폐기됐다.)
async function resolveAiAccess({ db, uid, roomId }) {
  // 관리자 차단이 시간·Duo 게스트 자격보다 먼저다.
  const [blocked, userSnap] = await Promise.all([
    readBlocked(db, uid),
    db.doc(`users/${uid}`).get(),
  ]);
  if (blocked) return { allowed: false, reason: "blocked" };
  if (userSnap.exists && positiveRemainingTime(userSnap.data())) {
    return { allowed: true, reason: "paid" };
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

module.exports = {
  activeDuoGuestAccess,
  normalizedRoomId,
  positiveRemainingTime,
  resolveAiAccess,
};
