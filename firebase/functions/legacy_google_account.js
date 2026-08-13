// ============================================================================
// 기존 Google 회원 판정 — **매핑만이 근거다**
// ----------------------------------------------------------------------------
// Google의 불변 식별자는 검증된 ID Token의 `sub`이지 이메일이 아니다.
// 이메일로 기존 UID를 찾으면 이메일/비밀번호 회원을 Google 계정으로 잘못
// 전환시킬 수 있어, 이메일 폴백은 두지 않는다.
//
// 결과는 셋 중 하나이고 **호출부가 서로 다르게 처리한다.**
//
//   valid   매핑이 있고 Auth 계정도 실재 → 기존 UID로 전환(커스텀 토큰 발급)
//   none    매핑 없음                     → 토큰 없음. 앱이 공식 신규 Google 로그인
//   stale   매핑은 있는데 Auth 계정 없음  → **중단.** 과거 연결 흔적이 있으므로
//                                          신규 생성으로 흘려보내지 않는다
//
// `none`과 `stale`을 같이 처리하면 안 된다. 전자는 정상적인 신규 가입이고,
// 후자는 조사가 필요한 상태다.
//
// Firebase 접근을 인자로 주입받아 이 파일은 순수하게 둔다 — 테스트가
// admin.initializeApp() 없이 규칙만 검증할 수 있다.
// ============================================================================

/**
 * @param {object} args
 * @param {string|null} args.googleSub  검증된 ID Token의 sub
 * @param {(sub: string) => Promise<string|null>} args.lookupMapping
 * @param {(uid: string) => Promise<{uid: string}|null>} args.getUser
 * @returns {Promise<{status: "valid"|"none"|"stale", uid?: string}>}
 */
async function resolveLegacyGoogleAccount({ googleSub, lookupMapping, getUser }) {
  if (!googleSub) return { status: "none" };

  const mappedUid = await lookupMapping(googleSub);
  if (!mappedUid) return { status: "none" };

  try {
    const user = await getUser(mappedUid);
    if (!user || !user.uid) return { status: "stale" };
    return { status: "valid", uid: user.uid };
  } catch (e) {
    if (e && e.code === "auth/user-not-found") return { status: "stale" };
    throw e;
  }
}

module.exports = { resolveLegacyGoogleAccount };
