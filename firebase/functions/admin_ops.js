"use strict";

// 관리자 웹(stealthvox-admin.web.app) 전용 쓰기 함수.
//
//   · 통과 조건은 Custom Claim admin == true 하나다.
//   · 웹에는 App Check가 없으므로 enforceAppCheck를 켜지 않는다. Claim이 그 몫이다.
//   · 모든 쓰기는 같은 트랜잭션 안에서 admin_audit에 한 줄을 남긴다.
//   · requestId로 같은 요청이 두 번 반영되지 않게 한다.

const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {SANDBOX_ALLOWLIST_PATH} = require("./revenuecat_purchase");

const REGION = "asia-northeast3";
const NOTE_MAX_LENGTH = 2000;
const LABEL_MAX_LENGTH = 60;

function requireAdmin(request) {
  const auth = request && request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  if (!auth.token || auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admin only.");
  }
  return String(auth.uid);
}

function requireUid(value) {
  const uid = typeof value === "string" ? value.trim() : "";
  if (!/^[A-Za-z0-9_-]{6,128}$/.test(uid)) {
    throw new HttpsError("invalid-argument", "uid is invalid.");
  }
  return uid;
}

function requireRequestId(value) {
  const id = typeof value === "string" ? value.trim() : "";
  if (!/^[A-Za-z0-9-]{8,64}$/.test(id)) {
    throw new HttpsError("invalid-argument", "requestId is invalid.");
  }
  return id;
}

function auditRef(db, action, requestId) {
  return db.doc(`admin_audit/${action}_${requestId}`);
}

function auditEntry({action, targetUid, before, after, reason, adminUid, now}) {
  return {
    action,
    targetUid,
    before: before === undefined ? null : before,
    after: after === undefined ? null : after,
    reason: reason || "",
    adminUid,
    at: now,
  };
}

async function addNote({db, adminUid, uid, text, requestId, now}) {
  const body = typeof text === "string" ? text.trim() : "";
  if (!body || body.length > NOTE_MAX_LENGTH) {
    throw new HttpsError("invalid-argument", "Note must be 1-2000 characters.");
  }
  const noteRef = db.doc(`admin_notes/${uid}/notes/${requestId}`);
  const logRef = auditRef(db, "add_note", requestId);
  return db.runTransaction(async (tx) => {
    const existing = await tx.get(noteRef);
    if (existing.exists) return {duplicate: true, noteId: requestId};
    tx.set(noteRef, {text: body, adminUid, createdAt: now, deleted: false});
    tx.set(logRef, auditEntry({
      action: "add_note", targetUid: uid, after: {noteId: requestId, text: body},
      adminUid, now,
    }));
    return {duplicate: false, noteId: requestId};
  });
}

async function deleteNote({db, adminUid, uid, noteId, now}) {
  const noteRef = db.doc(`admin_notes/${uid}/notes/${noteId}`);
  const logRef = auditRef(db, "delete_note", noteId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(noteRef);
    if (!snap.exists) throw new HttpsError("not-found", "Note not found.");
    const note = snap.data() || {};
    if (note.deleted === true) return {duplicate: true};
    tx.set(noteRef, {deleted: true, deletedAt: now, deletedBy: adminUid}, {merge: true});
    tx.set(logRef, auditEntry({
      action: "delete_note", targetUid: uid, before: {noteId, text: note.text || ""},
      adminUid, now,
    }));
    return {duplicate: false};
  });
}

async function setTestAccount({db, adminUid, uid, isTest, label, requestId, now}) {
  if (typeof isTest !== "boolean") {
    throw new HttpsError("invalid-argument", "isTest must be boolean.");
  }
  const testLabel = isTest && typeof label === "string"
    ? label.trim().slice(0, LABEL_MAX_LENGTH)
    : "";
  const flagRef = db.doc(`user_flags/${uid}`);
  const allowRef = db.doc(SANDBOX_ALLOWLIST_PATH);
  const logRef = auditRef(db, "set_test_account", requestId);

  return db.runTransaction(async (tx) => {
    const [logSnap, flagSnap, allowSnap] = await Promise.all([
      tx.get(logRef), tx.get(flagRef), tx.get(allowRef),
    ]);
    if (logSnap.exists) return {duplicate: true};

    const flags = flagSnap.exists ? flagSnap.data() || {} : {};
    const allow = allowSnap.exists ? allowSnap.data() || {} : {};
    const allowed = Array.isArray(allow.allowed_uids) ? allow.allowed_uids : [];
    const nextAllowed = isTest
      ? (allowed.includes(uid) ? allowed : [...allowed, uid])
      : allowed.filter((id) => id !== uid);

    const before = {
      isTest: flags.isTest === true,
      testLabel: flags.testLabel || "",
      sandboxAllowed: allowed.includes(uid),
    };
    const after = {isTest, testLabel, sandboxAllowed: isTest};

    tx.set(flagRef, {isTest, testLabel, updatedAt: now}, {merge: true});
    tx.set(allowRef, {allowed_uids: nextAllowed}, {merge: true});
    tx.set(logRef, auditEntry({
      action: "set_test_account", targetUid: uid, before, after, adminUid, now,
    }));
    return {duplicate: false, ...after};
  });
}

function createAdminOps(admin) {
  const db = () => admin.firestore();
  const now = () => admin.firestore.FieldValue.serverTimestamp();
  const options = {region: REGION};

  return {
    adminAddNote: onCall(options, async (request) => {
      const adminUid = requireAdmin(request);
      const data = request.data || {};
      return addNote({
        db: db(), adminUid, now: now(),
        uid: requireUid(data.uid),
        text: data.text,
        requestId: requireRequestId(data.requestId),
      });
    }),
    adminDeleteNote: onCall(options, async (request) => {
      const adminUid = requireAdmin(request);
      const data = request.data || {};
      return deleteNote({
        db: db(), adminUid, now: now(),
        uid: requireUid(data.uid),
        noteId: requireRequestId(data.noteId),
      });
    }),
    adminSetTestAccount: onCall(options, async (request) => {
      const adminUid = requireAdmin(request);
      const data = request.data || {};
      return setTestAccount({
        db: db(), adminUid, now: now(),
        uid: requireUid(data.uid),
        isTest: data.isTest,
        label: data.label,
        requestId: requireRequestId(data.requestId),
      });
    }),
  };
}

module.exports = {
  addNote,
  createAdminOps,
  deleteNote,
  requireAdmin,
  requireRequestId,
  requireUid,
  setTestAccount,
};
