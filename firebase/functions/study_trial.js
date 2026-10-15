"use strict";

// 공부방 체험 — 인트로 "공부방 체험" 버튼이 부르는 함수(2026-10-15 실장님 지시).
//
//   · 원본 = 관리자 계정 서클톡으로 만든 방 중 study_trial 표시가 붙고
//     확정(history_state=finalized)까지 끝난 방. Chat Lang마다 가장 최근 것 하나.
//   · 체험자는 익명 계정이다. 원본을 그 계정 공부방에 **사본**으로 복사한다.
//     공부방은 화면에서 문서에 직접 쓰는 곳이 많아, 원본을 열어 주면 체험자가
//     원본을 고치게 된다.
//   · 폰 하나에 한 번. 기기 ID(해시)를 서버에 남긴다. 5분 안에 같은 익명
//     계정으로 다시 부르면 남은 시간만큼 이어서 쓴다.
//   · 연습 설정은 고정: 에코잉 여성 ×2, 쉐도잉 남성 0.87x.
//   · 체험 중 AI 자격은 study_trial_users/{uid}가 쥔다(ai_access.js).

const crypto = require("crypto");
const {HttpsError, onCall} = require("firebase-functions/v2/https");

const REGION = "asia-northeast3";
const TRIAL_SECONDS = 5 * 60;
const DEVICE_COLLECTION = "study_trial_devices";
const USER_COLLECTION = "study_trial_users";
const COPY_BATCH_LIMIT = 400;

const CHAT_LANGUAGES = [
  "English", "Korean", "Japanese", "Chinese", "Spanish", "French",
  "German", "Hindi", "Russian", "Portuguese", "Italian", "Dutch",
];

const FIXED_PRACTICE_SETTINGS = {
  echoing: {voice: "google-female", repeat: 2},
  shadowing: {voice: "google-male", speed: 0.87},
};

// 원본에만 있는 표시. 사본에 남으면 사본이 다음 체험의 원본 후보가 된다.
const MASTER_ONLY_FIELDS = ["study_trial", "study_trial_chat_lang"];

// 한국어·중국어 → 영어, 나머지 10개 → 한국어 (2026-10-16 실장님).
function learnLangFor(chatLang) {
  return chatLang === "Korean" || chatLang === "Chinese" ? "English" : "Korean";
}

/** 폰 언어 → 체험 Chat Lang. 목록 밖이면 영어. */
function chatLangForSystem(value) {
  const lang = typeof value === "string" ? value.trim() : "";
  return CHAT_LANGUAGES.includes(lang) ? lang : "English";
}

/** 기기 ID는 경로에 그대로 쓰지 않는다. 형식을 보고 해시한다. */
function deviceKey(value) {
  const id = typeof value === "string" ? value.trim() : "";
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(id)) {
    throw new HttpsError("invalid-argument", "deviceId is invalid.");
  }
  return crypto.createHash("sha256").update(id).digest("hex");
}

function millisOf(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value === "number") return value;
  return 0;
}

/**
 * 후보 방들 중 이 Chat Lang의 원본 하나를 고른다.
 * rooms: [{ownerUid, roomId, data}], adminUids: 관리자 클레임이 확인된 uid 집합.
 */
function pickMasterRoom(rooms, chatLang, adminUids) {
  const learn = learnLangFor(chatLang);
  const ready = rooms.filter(({ownerUid, data}) =>
    adminUids.has(ownerUid) &&
    data &&
    data.study_trial === true &&
    data.study_trial_chat_lang === chatLang &&
    data.target_lang === learn &&
    data.history_state === "finalized");
  ready.sort((a, b) =>
    (millisOf(b.data.history_finalized_at) || millisOf(b.data.created_at)) -
    (millisOf(a.data.history_finalized_at) || millisOf(a.data.created_at)));
  return ready[0] || null;
}

/** 사본 방 문서. 원본 표시를 빼고, 체험 표시와 고정 연습 설정을 넣는다. */
function copyRoomData(source, {sourcePath, now}) {
  const out = {...source};
  for (const field of MASTER_ONLY_FIELDS) delete out[field];
  return {
    ...out,
    created_at: now,
    last_active: now,
    is_pinned: false,
    practice_settings: FIXED_PRACTICE_SETTINGS,
    study_trial_copy: true,
    study_trial_source: sourcePath,
  };
}

/**
 * 기기 기록을 보고 이번 호출을 판정한다.
 *   new     — 처음. 복사한다.
 *   resume  — 같은 계정이 5분 안에 다시 왔다. 남은 시간으로 이어서.
 *   used    — 이 폰은 이미 썼다.
 *   busy    — 같은 계정의 복사가 아직 도는 중.
 */
function judgeDevice(record, uid, nowMs) {
  if (!record) return {kind: "new"};
  if (record.uid === uid) {
    if (record.status === "copying") return {kind: "busy"};
    const expiresAtMs = Number(record.expiresAtMs) || 0;
    if (record.status === "ready" && nowMs < expiresAtMs) {
      return {
        kind: "resume",
        roomId: record.roomId,
        remainingSeconds: Math.ceil((expiresAtMs - nowMs) / 1000),
      };
    }
  }
  return {kind: "used"};
}

async function findMasterRoom({db, auth, chatLang}) {
  const snap = await db.collectionGroup("chat_history")
    .where("study_trial", "==", true)
    .get();
  const rooms = snap.docs.map((doc) => ({
    ownerUid: doc.ref.parent.parent.id,
    roomId: doc.id,
    data: doc.data(),
  }));
  const adminUids = new Set();
  for (const uid of new Set(rooms.map((r) => r.ownerUid))) {
    try {
      const user = await auth.getUser(uid);
      if (user.customClaims && user.customClaims.admin === true) adminUids.add(uid);
    } catch (_) {
      // 지워진 계정의 방은 원본이 될 수 없다.
    }
  }
  return pickMasterRoom(rooms, chatLang, adminUids);
}

async function copyRoom({db, master, uid, now}) {
  const sourceRef = db.doc(`users/${master.ownerUid}/chat_history/${master.roomId}`);
  const targetRef = db.collection(`users/${uid}/chat_history`).doc();
  const messages = await sourceRef.collection("messages").get();
  let batch = db.batch();
  let pending = 0;
  batch.set(targetRef, copyRoomData(master.data, {sourcePath: sourceRef.path, now}));
  pending++;
  for (const doc of messages.docs) {
    batch.set(targetRef.collection("messages").doc(doc.id), doc.data());
    if (++pending >= COPY_BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();
  return targetRef.id;
}

function createStudyTrial({admin}) {
  const startStudyTrial = onCall({
    region: REGION,
    enforceAppCheck: true,
  }, async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication is required.");
    const data = request.data || {};
    const key = deviceKey(data.deviceId);
    const chatLang = chatLangForSystem(data.systemLanguage);
    const db = admin.firestore();
    const deviceRef = db.doc(`${DEVICE_COLLECTION}/${key}`);
    const now = admin.firestore.FieldValue.serverTimestamp();

    const verdict = await db.runTransaction(async (tx) => {
      const snap = await tx.get(deviceRef);
      const judged = judgeDevice(snap.exists ? snap.data() : null, uid, Date.now());
      if (judged.kind === "new") {
        tx.set(deviceRef, {uid, chatLang, status: "copying", requestedAt: now});
      }
      return judged;
    });
    if (verdict.kind === "resume") {
      return {roomId: verdict.roomId, remainingSeconds: verdict.remainingSeconds, resumed: true};
    }
    if (verdict.kind === "busy") throw new HttpsError("aborted", "Trial is being prepared.");
    if (verdict.kind === "used") throw new HttpsError("failed-precondition", "Trial already used on this device.");

    try {
      const master = await findMasterRoom({db, auth: admin.auth(), chatLang});
      if (!master) throw new HttpsError("not-found", `No trial room for ${chatLang}.`);
      const roomId = await copyRoom({db, master, uid, now});
      const expiresAtMs = Date.now() + TRIAL_SECONDS * 1000;
      const batch = db.batch();
      batch.update(deviceRef, {status: "ready", roomId, expiresAtMs, startedAt: now});
      batch.set(db.doc(`${USER_COLLECTION}/${uid}`), {roomId, expiresAtMs, startedAt: now});
      await batch.commit();
      return {roomId, remainingSeconds: TRIAL_SECONDS, resumed: false};
    } catch (error) {
      // 복사를 못 했으면 이 폰의 기회를 쓰지 않은 것으로 되돌린다.
      await deviceRef.delete().catch(() => {});
      if (error instanceof HttpsError) throw error;
      console.error("startStudyTrial copy failed", error);
      throw new HttpsError("internal", "Trial could not be prepared.");
    }
  });
  return {startStudyTrial};
}

module.exports = {
  CHAT_LANGUAGES,
  FIXED_PRACTICE_SETTINGS,
  TRIAL_SECONDS,
  USER_COLLECTION,
  chatLangForSystem,
  copyRoomData,
  createStudyTrial,
  deviceKey,
  judgeDevice,
  learnLangFor,
  pickMasterRoom,
};
