"use strict";

// 계정 찾기가 로그인 수단(구글 sub·카카오 id)으로 StealthVox uid를 찾는다.
//
// 구글: provider_uid_map은 옛 계정 연결 경로만 적던 표라, 지금 구글 로그인
// 회원은 거의 다 빠져 있다(10-27 실측 289명 중 1명). 표에 없으면 Firebase
// Auth에서 그 구글 계정이 붙은 사용자를 직접 찾는다.
// 카카오: kakaoCustomAuth가 가입 때마다 kakao_uid_map을 적으므로 표만 본다.
async function resolveDiscoveryUid({db, auth}, provider, providerUid) {
  if (provider === "google") {
    const mapDoc = await db.collection("provider_uid_map")
      .doc("google:" + providerUid).get();
    if (mapDoc.exists && mapDoc.data().uid) return mapDoc.data().uid;
    try {
      const user = await auth.getUserByProviderUid("google.com", providerUid);
      return user.uid;
    } catch (e) {
      if (e.code === "auth/user-not-found") return null;
      throw e;
    }
  }
  if (provider === "kakao") {
    const mapDoc = await db.collection("kakao_uid_map").doc(providerUid).get();
    return mapDoc.exists && mapDoc.data().uid ? mapDoc.data().uid : null;
  }
  return null;
}

module.exports = {resolveDiscoveryUid};
