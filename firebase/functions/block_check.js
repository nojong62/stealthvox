"use strict";

// 관리자 웹의 "이용 차단" 판정. 근거는 user_flags/{uid}.blocked == true 하나다.
//
//   · 막는 곳: AI 토큰 발급(resolveAiAccess), openAiProxy 요청마다, Duo 통역,
//     TURN 자격, Duo 게시판 작성·선점·요청, 체험·가입 보너스.
//   · 막지 않는 곳: deductRemainingTime, logUsageSession — 차감과 기록은 계속
//     돌아야 장부가 맞는다.
//   · 이미 발급된 Deepgram 토큰(최대 1시간)과 Realtime client secret은 공급사에
//     직접 붙으므로 여기서 끊을 수 없다. 다음 발급부터 막힌다.

const BLOCK_CACHE_MS = 15 * 1000;

async function readBlocked(db, uid) {
  if (!uid) return false;
  const snap = await db.doc(`user_flags/${uid}`).get();
  return Boolean(snap.exists && snap.data() && snap.data().blocked === true);
}

// 요청마다 부르는 경로(openAiProxy, interpretUtterance)용. 인스턴스마다 따로 갖는
// 메모리 캐시라서 차단 후 최대 ttlMs 동안은 이미 열린 인스턴스가 통과시킬 수 있다.
// 읽기 실패는 통과로 본다 — 일시 장애로 유료 사용자의 대화를 끊지 않는다.
function createBlockedCache({ttlMs = BLOCK_CACHE_MS, now = () => Date.now(), onError} = {}) {
  const entries = new Map();
  return async function isBlocked(db, uid) {
    if (!uid) return false;
    const t = now();
    const hit = entries.get(uid);
    if (hit && hit.expiresAt > t) return hit.blocked;
    try {
      const blocked = await readBlocked(db, uid);
      entries.set(uid, {blocked, expiresAt: t + ttlMs});
      if (entries.size > 5000) entries.delete(entries.keys().next().value);
      return blocked;
    } catch (err) {
      if (onError) onError(err);
      return false;
    }
  };
}

module.exports = {
  BLOCK_CACHE_MS,
  createBlockedCache,
  readBlocked,
};
