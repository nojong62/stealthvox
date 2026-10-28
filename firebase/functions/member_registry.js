"use strict";

const {HttpsError, onCall} = require("firebase-functions/v2/https");

const REGION = "asia-northeast3";

function normalizedProviderIds(userRecord, signInProvider) {
  const providers = new Set(
    (userRecord.providerData || [])
      .map((provider) => String(provider.providerId || "").trim())
      .filter(Boolean)
  );
  if (signInProvider && signInProvider !== "anonymous") {
    providers.add(signInProvider);
  }
  return [...providers].sort();
}

// 커스텀 토큰 로그인은 Firebase가 전부 "custom"으로 적는다. 카카오·계정 복구·
// 옛 Google 연결이 다 여기로 들어오므로, 서버가 토큰에 넣은 provider 표시
// (카카오는 경로에 따라 "kakaocorp.com" 또는 "kakao", index.js)로 바꿔 적는다.
// 표시가 없으면 custom 그대로.
function effectiveSignInProvider(token) {
  const signInProvider = String(token && token.firebase && token.firebase.sign_in_provider || "");
  if (signInProvider !== "custom") return signInProvider;
  const claimed = typeof (token && token.provider) === "string" ? token.provider.trim() : "";
  return /^[a-z0-9.-]{3,40}$/.test(claimed) ? claimed : signInProvider;
}

function isRealMemberProvider(signInProvider) {
  return Boolean(signInProvider && signInProvider !== "anonymous");
}

function isKakaoProvider(providerId) {
  return providerId === "kakaocorp.com" || providerId === "kakao";
}

// 카카오 회원은 이메일·이름이 비어 관리자 웹에 UID만 보인다. kakao_uid_map에서
// 회원번호(겹치지 않음)와 닉네임(겹칠 수 있음)을 찾아 명부에 같이 적는다.
async function kakaoMemberFields(db, uid) {
  const snap = await db.collection("kakao_uid_map").where("uid", "==", uid).limit(1).get();
  if (snap.empty) return {};
  const doc = snap.docs[0];
  const data = doc.data() || {};
  const fields = {kakaoId: String(data.kakao_id || doc.id)};
  if (data.kakao_nickname) fields.kakaoNickname = String(data.kakao_nickname);
  return fields;
}

function createSyncRealMemberProfile(admin) {
  return onCall({region: REGION, enforceAppCheck: true}, async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }
    const signInProvider = effectiveSignInProvider(request.auth.token);
    if (!isRealMemberProvider(signInProvider)) {
      return {registered: false, reason: "anonymous"};
    }

    const userRecord = await admin.auth().getUser(uid);
    const providers = normalizedProviderIds(userRecord, signInProvider);
    const kakao = providers.some(isKakaoProvider)
      ? await kakaoMemberFields(admin.firestore(), uid)
      : {};
    const joinedDate = new Date(userRecord.metadata.creationTime);
    const lastSignInDate = new Date(userRecord.metadata.lastSignInTime);
    const Timestamp = admin.firestore.Timestamp;
    const FieldValue = admin.firestore.FieldValue;

    await admin.firestore().doc("real_members/" + uid).set({
      uid,
      email: userRecord.email || null,
      displayName: userRecord.displayName || null,
      providers,
      primaryProvider: signInProvider,
      ...kakao,
      joinedAt: Number.isNaN(joinedDate.getTime())
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(joinedDate),
      lastSignInAt: Number.isNaN(lastSignInDate.getTime())
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(lastSignInDate),
      lastSeenAt: FieldValue.serverTimestamp(),
      isRealMember: true,
    }, {merge: true});

    return {registered: true};
  });
}

module.exports = {
  createSyncRealMemberProfile,
  effectiveSignInProvider,
  isRealMemberProvider,
  kakaoMemberFields,
  normalizedProviderIds,
};
