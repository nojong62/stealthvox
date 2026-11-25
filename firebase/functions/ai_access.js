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

// 대화맨이 연 방(openDuoBoardRequest가 talkHostRoom을 박는다). 대화맨 본인
// 시간은 쓰지 않으므로 잔여가 0이어도 통역을 쓴다. 방 필드는 참가자가 쓸 수
// 있어서, 서버만 쓰는 duo_talk_hosts 문서로 대화맨인지 한 번 더 본다.
function activeTalkHostRoom(data, uid) {
  if (!data || data.isDuoEnabled !== true) return false;
  return data.talkHostRoom === true && String(data.hostUid || "") === uid;
}

// 공부방 체험(study_trial.js)이 끝난 뒤에도 화면이 닫히기까지 걸리는 몇 초와
// 마지막 요청을 위한 여유.
const STUDY_TRIAL_GRACE_MS = 60 * 1000;

/** 체험 기록이 아직 살아 있으면 그 끝 시각(ms), 아니면 0. */
function activeStudyTrialUntil(data, nowMs = Date.now()) {
  const expiresAtMs = Number(data && data.expiresAtMs) || 0;
  const until = expiresAtMs + STUDY_TRIAL_GRACE_MS;
  return expiresAtMs > 0 && nowMs < until ? until : 0;
}

function normalizedRoomId(value) {
  const roomId = String(value || "").trim();
  return /^[A-Za-z0-9_-]{6,128}$/.test(roomId) ? roomId : "";
}

// AI 자격은 셋이다: 남은 시간이 있는 본인, 초대받은 Duo 게스트, 공부방 체험
// 10분 중인 사람. (옛 맛보기 체험 자격은 2026-10-15 폐기됐다 — 공부방 체험은
// 그것과 다른 것이다.)
async function resolveAiAccess({ db, uid, roomId }) {
  // 관리자 차단이 시간·Duo 게스트 자격보다 먼저다.
  const [blocked, userSnap, trialSnap] = await Promise.all([
    readBlocked(db, uid),
    db.doc(`users/${uid}`).get(),
    db.doc(`study_trial_users/${uid}`).get(),
  ]);
  if (blocked) return { allowed: false, reason: "blocked" };
  if (userSnap.exists && positiveRemainingTime(userSnap.data())) {
    return { allowed: true, reason: "paid" };
  }
  const trialUntil = trialSnap.exists ? activeStudyTrialUntil(trialSnap.data()) : 0;
  if (trialUntil > 0) {
    return { allowed: true, reason: "study_trial", untilMs: trialUntil };
  }

  const safeRoomId = normalizedRoomId(roomId);
  if (safeRoomId) {
    const roomSnap = await db.doc(`duo_sessions/${safeRoomId}`).get();
    if (roomSnap.exists && activeDuoGuestAccess(roomSnap.data(), uid)) {
      return { allowed: true, reason: "duo_guest", roomId: safeRoomId };
    }
    // 홍보 방(promoGuestRoom) 무료 자격은 2026-11-26 폐지했다. 홍보 서비스를
    // 접었고, 방장이 자기 방 문서에 그 표시를 직접 쓸 수 있어 잔여 0으로도
    // AI를 쓰는 길이 됐다. 방에 표시가 남아 있어도 자격은 주지 않는다.
    if (roomSnap.exists && activeTalkHostRoom(roomSnap.data(), uid)) {
      const hostSnap = await db.doc(`duo_talk_hosts/${uid}`).get();
      const host = hostSnap.exists ? hostSnap.data() : null;
      if (host && host.active === true && host.adminDisabled !== true) {
        return { allowed: true, reason: "duo_talk_host", roomId: safeRoomId };
      }
    }
  }

  return { allowed: false, reason: "no_entitlement" };
}

module.exports = {
  activeDuoGuestAccess,
  activeStudyTrialUntil,
  activeTalkHostRoom,
  normalizedRoomId,
  positiveRemainingTime,
  resolveAiAccess,
};
