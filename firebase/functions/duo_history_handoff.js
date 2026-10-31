// 익명으로 한 통역 통화를 기존 회원 계정으로 로그인한 뒤에 되찾는 표.
//
// 직접 대화는 공유 결과(canonical)로 다시 짓는다(앱 duo_guest_handoff.dart).
// 통역 통화에는 그런 공유 결과가 없고, 호스트가 나가면 방 문서도 지워진다.
// 남는 것은 익명 계정 아래의 개인 기록뿐이라 그것을 옮긴다.
//
//   1. 통화가 끝나면 익명 폰이 issueDuoHistoryHandoff로 표를 받는다.
//      표는 그 폰에만 있다(무작위 32바이트). 서버에는 해시만 남긴다.
//   2. 로그인으로 uid가 바뀌면 redeemDuoHistoryHandoff로 표를 낸다.
//      서버가 기록과 messages를 새 계정 아래로 복사한다. 같은 표는 한 번만.
//
// 처음 가입(익명 계정에 연결, uid 유지)은 옮길 것이 없어 표를 쓰지 않는다.

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const crypto = require("crypto");

const db = () => admin.firestore();
const TICKET_TTL_MS = 30 * 24 * 60 * 60 * 1000;

const hashTicket = (ticket) =>
  crypto.createHash("sha256").update(String(ticket)).digest("hex");

function requireAuth(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "로그인이 필요합니다.");
  }
  return context.auth.uid;
}

const isAnonymous = (context) =>
  context.auth?.token?.firebase?.sign_in_provider === "anonymous";

exports.issueDuoHistoryHandoff = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  if (!isAnonymous(context)) {
    throw new functions.https.HttpsError("failed-precondition", "익명 계정만 받을 수 있습니다.");
  }
  const historyId = String(data.historyId || "").trim();
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(historyId)) {
    throw new functions.https.HttpsError("invalid-argument", "historyId가 올바르지 않습니다.");
  }
  const history = await db().doc(`users/${uid}/chat_history/${historyId}`).get();
  if (!history.exists) {
    throw new functions.https.HttpsError("not-found", "기록이 없습니다.");
  }
  const ticket = crypto.randomBytes(32).toString("hex");
  await db().collection("duo_history_handoffs").doc(hashTicket(ticket)).set({
    anonUid: uid, historyId, redeemedBy: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + TICKET_TTL_MS),
  });
  return {ticket};
});

exports.redeemDuoHistoryHandoff = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);
  if (isAnonymous(context)) {
    throw new functions.https.HttpsError("failed-precondition", "회원 계정으로 로그인해야 합니다.");
  }
  const ticket = String(data.ticket || "").trim();
  if (!/^[0-9a-f]{64}$/.test(ticket)) {
    throw new functions.https.HttpsError("invalid-argument", "표가 올바르지 않습니다.");
  }
  const ticketRef = db().collection("duo_history_handoffs").doc(hashTicket(ticket));
  const claim = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ticketRef);
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "표가 없습니다.");
    const t = snap.data();
    if (t.redeemedBy) {
      return {already: true, anonUid: t.anonUid, historyId: t.historyId};
    }
    if (t.expiresAt && t.expiresAt.toMillis() < Date.now()) {
      throw new functions.https.HttpsError("deadline-exceeded", "표가 만료되었습니다.");
    }
    if (t.anonUid === uid) return {same: true, historyId: t.historyId};
    tx.update(ticketRef, {redeemedBy: uid,
      redeemedAt: admin.firestore.FieldValue.serverTimestamp()});
    return {anonUid: t.anonUid, historyId: t.historyId};
  });
  if (claim.same || claim.already) {
    return {historyId: claim.historyId, copied: 0};
  }
  const copied = await copyHistory(claim.anonUid, uid, claim.historyId);
  return {historyId: claim.historyId, copied};
});

// 기록 문서와 messages를 그대로 옮긴다. 이미 있으면 덮지 않는다.
async function copyHistory(fromUid, toUid, historyId) {
  const fromRef = db().doc(`users/${fromUid}/chat_history/${historyId}`);
  const toRef = db().doc(`users/${toUid}/chat_history/${historyId}`);
  const [from, to] = await Promise.all([fromRef.get(), toRef.get()]);
  if (!from.exists || to.exists) return 0;
  const messages = await fromRef.collection("messages").get();
  let batch = db().batch();
  let pending = 0;
  batch.set(toRef, {...from.data(), handoffFromUid: fromUid,
    handoffAt: admin.firestore.FieldValue.serverTimestamp()});
  pending += 1;
  for (const message of messages.docs) {
    batch.set(toRef.collection("messages").doc(message.id), message.data());
    pending += 1;
    if (pending >= 450) {
      await batch.commit();
      batch = db().batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();
  return messages.size;
}

exports._test = {hashTicket};
