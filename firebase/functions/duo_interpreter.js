const crypto = require("crypto");
const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");
const { onCall } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const openAiApiKey = defineSecret("OPENAI_API_KEY");

const CALLABLE_PROTOCOL = "callable_pc_v2";
const INTERPRETER_MODE = "interpreter";
const PROCESSING = "processing";
const READY = "ready";
const FAILED = "failed";
const LEASE_MS = 120000;
const MAX_SOURCE_LENGTH = 12000;

function callableError(code, message) {
  return new functions.https.HttpsError(code, message);
}

function requireAuth(context) {
  if (!context || !context.auth || !context.auth.uid) {
    throw callableError("unauthenticated", "Authentication is required.");
  }
  return String(context.auth.uid);
}

function textValue(value, field, maxLength = MAX_SOURCE_LENGTH) {
  if (typeof value !== "string") {
    throw callableError("invalid-argument", field + " must be a string.");
  }
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maxLength) {
    throw callableError("invalid-argument", field + " has an invalid length.");
  }
  return trimmed;
}

function deriveDirection(room, uid) {
  const hostUid = String(room.hostUid || "");
  const partnerUid = String(room.partnerUid || "");
  if (uid !== hostUid && uid !== partnerUid) {
    throw callableError("permission-denied", "Caller is not a room participant.");
  }
  if (!hostUid || !partnerUid || room.isPartnerJoined !== true) {
    throw callableError("failed-precondition", "The interpreter room is not joined.");
  }
  if (uid === hostUid) {
    return {
      fromUid: hostUid,
      toUid: partnerUid,
      sourceLanguage: String(room.hostLang || ""),
      targetLanguage: String(room.partnerLang || ""),
    };
  }
  return {
    fromUid: partnerUid,
    toUid: hostUid,
    sourceLanguage: String(room.partnerLang || ""),
    targetLanguage: String(room.hostLang || ""),
  };
}

function assertAcceptingRoom(room, uid) {
  if (!room || String(room.mode || "") !== INTERPRETER_MODE) {
    throw callableError("failed-precondition", "This is not an interpreter room.");
  }
  const closed = ["endedAt", "callStoppedAt", "finalizedAt"].some(
    (field) => room[field] != null
  );
  const state = String(room.state || "").toLowerCase();
  if (closed || state === "closing" || state === "closed") {
    throw callableError("failed-precondition", "The interpreter room is closed.");
  }
  return deriveDirection(room, uid);
}

function millis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return 0;
}

function isStaleProcessing(data, now = Date.now()) {
  return String(data.status || "") === PROCESSING &&
    (!data.processingToken ||
      !data.leaseExpiresAt ||
      millis(data.leaseExpiresAt) <= now);
}

function immutableMatches(existing, expected) {
  return ["utteranceId", "fromUid", "toUid", "sourceLanguage",
    "targetLanguage", "sourceText"].every(
    (field) => String(existing[field] || "") === String(expected[field] || "")
  );
}

function reservationResult(data, extra = {}) {
  return {
    accepted: true,
    utteranceId: data.utteranceId,
    seq: Number(data.seq),
    status: String(data.status || PROCESSING),
    processingToken: data.processingToken || null,
    shouldProcess: false,
    ...extra,
  };
}

async function reserveUtterance({
  db,
  context,
  data,
  now = () => Date.now(),
  tokenFactory = () => crypto.randomUUID(),
}) {
  const uid = requireAuth(context);
  const roomId = textValue(data && data.roomId, "roomId", 128);
  const utteranceId = textValue(data && data.utteranceId, "utteranceId", 128);
  const sourceText = textValue(data && data.sourceText, "sourceText");
  const roomRef = db.doc("duo_sessions/" + roomId);
  const utteranceRef = roomRef.collection("utterances").doc(utteranceId);
  const Timestamp = admin.firestore.Timestamp;
  const FieldValue = admin.firestore.FieldValue;
  const nowMs = typeof now === "function" ? now() : now;
  return db.runTransaction(async (tx) => {
    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) {
      throw callableError("not-found", "Duo room was not found.");
    }
    const room = roomSnap.data() || {};
    if (String(room.interpreterProtocol || "") !== CALLABLE_PROTOCOL) {
      throw callableError("failed-precondition", "Room protocol is not callable_pc_v2.");
    }
    const direction = assertAcceptingRoom(room, uid);
    const expected = {
      utteranceId,
      ...direction,
      sourceText,
    };
    const existingSnap = await tx.get(utteranceRef);
    if (existingSnap.exists) {
      const existing = existingSnap.data() || {};
      if (!immutableMatches(existing, expected)) {
        throw callableError("already-exists", "utteranceId payload does not match.");
      }
      if (String(existing.status || "") !== PROCESSING) {
        return reservationResult(existing, { terminal: true });
      }
      if (!isStaleProcessing(existing, nowMs)) {
        return reservationResult(existing, { reused: true });
      }
      const processingToken = tokenFactory();
      const leaseExpiresAt = Timestamp.fromMillis(nowMs + LEASE_MS);
      tx.update(utteranceRef, {
        processingToken,
        processingStartedAt: FieldValue.serverTimestamp(),
        leaseExpiresAt,
        attempt: Number(existing.attempt || 1) + 1,
      });
      return {
        ...reservationResult({
          ...existing,
          processingToken,
          seq: existing.seq,
          status: PROCESSING,
        }, { reclaimed: true }),
        shouldProcess: true,
      };
    }

    const lastSeq = Number(room.lastSeq || 0);
    const seq = Number.isInteger(lastSeq) && lastSeq >= 0 ? lastSeq + 1 : 1;
    const processingToken = tokenFactory();
    const leaseExpiresAt = Timestamp.fromMillis(nowMs + LEASE_MS);
    tx.set(utteranceRef, {
      utteranceId,
      seq,
      fromUid: direction.fromUid,
      toUid: direction.toUid,
      sourceLanguage: direction.sourceLanguage,
      targetLanguage: direction.targetLanguage,
      sourceText,
      targetText: null,
      status: PROCESSING,
      createdAt: FieldValue.serverTimestamp(),
      processingStartedAt: FieldValue.serverTimestamp(),
      processingToken,
      leaseExpiresAt,
      attempt: 1,
    });
    tx.update(roomRef, { lastSeq: seq });
    return {
      accepted: true,
      utteranceId,
      seq,
      status: PROCESSING,
      processingToken,
      shouldProcess: true,
      created: true,
    };
  });
}

async function finishUtterance({
  db,
  roomId,
  utteranceId,
  processingToken,
  status,
  targetText = null,
  failureCode = null,
}) {
  if (![READY, FAILED].includes(status)) {
    throw new Error("invalid terminal status");
  }
  const ref = db.doc(
    "duo_sessions/" + roomId + "/utterances/" + utteranceId
  );
  const FieldValue = admin.firestore.FieldValue;
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    const current = snap.data() || {};
    if (current.status !== PROCESSING ||
        current.processingToken !== processingToken) {
      return false;
    }
    const update = status === READY
      ? {
        status: READY,
        targetText: String(targetText || "").trim(),
        readyAt: FieldValue.serverTimestamp(),
      }
      : {
        status: FAILED,
        failedAt: FieldValue.serverTimestamp(),
        failureCode: String(failureCode || "translation_failed"),
      };
    tx.update(ref, update);
    return true;
  });
}

function buildTranslationPrompt({ sourceText, sourceLanguage, targetLanguage, context }) {
  const contextText = context.length === 0
    ? "(no previous accepted utterances)"
    : context.map((item) => {
      const translated = item.status === READY && item.targetText
        ? " => " + item.targetText
        : "";
      const failed = item.status === FAILED ? " [translation failed]" : "";
      return "[" + item.seq + "] " + item.sourceLanguage + ": " +
        item.sourceText + translated + failed;
    }).join("\n");
  return [
    "Translate one spoken utterance for a live two-person interpreter.",
    "Return only the translation, with no explanation or quotation marks.",
    "Source language: " + sourceLanguage,
    "Target language: " + targetLanguage,
    "Previous accepted utterances (oldest first):",
    contextText,
    "Current speaker direction: " + sourceLanguage + " to " + targetLanguage,
    "Current utterance:",
    sourceText,
  ].join("\n");
}

async function loadContext(db, roomId, seq) {
  const snapshot = await db.collection(
    "duo_sessions/" + roomId + "/utterances"
  ).where("seq", "<", seq).orderBy("seq", "desc").limit(6).get();
  return snapshot.docs.map((doc) => doc.data()).reverse().filter(
    (item) => item && typeof item.sourceText === "string" &&
      item.sourceText.trim()
  );
}

async function translateWithOpenAi({
  apiKey,
  sourceText,
  sourceLanguage,
  targetLanguage,
  context,
  fetchImpl = fetch,
}) {
  if (sourceLanguage.trim().toLowerCase() ===
      targetLanguage.trim().toLowerCase()) {
    return sourceText.trim();
  }
  const key = typeof apiKey === "function" ? apiKey() : apiKey;
  if (!key) throw new Error("OPENAI_API_KEY is not configured");
  const response = await fetchImpl("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-6-luna",
      reasoning_effort: "none",
      messages: [{ role: "user", content: buildTranslationPrompt({
        sourceText,
        sourceLanguage,
        targetLanguage,
        context,
      }) }],
    }),
  });
  if (!response.ok) {
    throw new Error("OpenAI translation failed: " + response.status);
  }
  const payload = await response.json();
  const translated = payload &&
    payload.choices &&
    payload.choices[0] &&
    payload.choices[0].message &&
    payload.choices[0].message.content;
  if (typeof translated !== "string" || !translated.trim()) {
    throw new Error("OpenAI returned no translation");
  }
  return translated.trim().replace(/^\`\`\`(?:\w+)?\s*/, "")
    .replace(/\s*\`\`\`$/, "").trim();
}

function safeFailureCode(error) {
  const message = String(error && error.message || "");
  if (message.includes("OPENAI_API_KEY")) return "translation_not_configured";
  if (message.includes("OpenAI translation failed")) return "translation_unavailable";
  return "translation_failed";
}

function createInterpretUtteranceHandler({
  db,
  apiKey = () => {
    try {
      return openAiApiKey.value() || process.env.OPENAI_API_KEY || "";
    } catch (_) {
      return process.env.OPENAI_API_KEY || "";
    }
  },
  fetchImpl = fetch,
  now = () => Date.now(),
  tokenFactory = () => crypto.randomUUID(),
} = {}) {
  return async (data, context) => {
    const firestore = db || admin.firestore();
    const startedAt = now();
    const reservation = await reserveUtterance({
      db,
      context,
      data,
      now: now(),
      tokenFactory,
    });
    functions.logger.info("interpretUtterance accepted", {
      roomId: data && data.roomId,
      utteranceId: reservation.utteranceId,
      seq: reservation.seq,
      attempt: reservation.reclaimed ? 2 : reservation.created ? 1 : undefined,
      reused: reservation.reused === true,
    });
    if (!reservation.shouldProcess) return reservation;

    const contextItems = await loadContext(firestore, data.roomId, reservation.seq);
    functions.logger.info("interpretUtterance gpt_start", {
      roomId: data.roomId,
      utteranceId: reservation.utteranceId,
      seq: reservation.seq,
      contextCount: contextItems.length,
    });
    try {
      const roomSnap = await firestore.doc("duo_sessions/" + data.roomId).get();
      const room = roomSnap.data() || {};
      const sourceLanguage = reservation.seq && reservation.status
        ? (reservation.fromUid === String(room.hostUid)
          ? String(room.hostLang || "")
          : String(room.partnerLang || ""))
        : "";
      const targetLanguage = reservation.fromUid === String(room.hostUid)
        ? String(room.partnerLang || "")
        : String(room.hostLang || "");
      const targetText = await translateWithOpenAi({
        apiKey,
        sourceText: String(data.sourceText).trim(),
        sourceLanguage,
        targetLanguage,
        context: contextItems,
        fetchImpl,
      });
      const fenced = await finishUtterance({
        db,
        roomId: data.roomId,
        utteranceId: reservation.utteranceId,
        processingToken: reservation.processingToken,
        status: READY,
        targetText,
      });
      functions.logger.info("interpretUtterance ready", {
        roomId: data.roomId,
        utteranceId: reservation.utteranceId,
        seq: reservation.seq,
        fenced,
        elapsedMs: now() - startedAt,
      });
      return { ...reservation, status: fenced ? READY : PROCESSING, completed: fenced };
    } catch (error) {
      const failureCode = safeFailureCode(error);
      const fenced = await finishUtterance({
        db,
        roomId: data.roomId,
        utteranceId: reservation.utteranceId,
        processingToken: reservation.processingToken,
        status: FAILED,
        failureCode,
      });
      functions.logger.warn("interpretUtterance failed", {
        roomId: data.roomId,
        utteranceId: reservation.utteranceId,
        seq: reservation.seq,
        failureCode,
        fenced,
      });
      return { ...reservation, status: fenced ? FAILED : PROCESSING, completed: fenced };
    }
  };
}

const interpretUtterance = onCall(
  { region: "asia-northeast3", timeoutSeconds: 120, secrets: [openAiApiKey] },
  (request) => createInterpretUtteranceHandler()(request.data, { auth: request.auth })
);

module.exports = {
  CALLABLE_PROTOCOL,
  PROCESSING,
  READY,
  FAILED,
  LEASE_MS,
  isStaleProcessing,
  reserveUtterance,
  finishUtterance,
  buildTranslationPrompt,
  loadContext,
  translateWithOpenAi,
  createInterpretUtteranceHandler,
  interpretUtterance,
};
