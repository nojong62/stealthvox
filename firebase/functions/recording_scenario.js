"use strict";

// 녹음 가져오기 → 공부방에 넣을 두 사람 대화 (2026-11-14 실장님 구상).
//
//   · 유저가 고른 통화 녹음(앞 3분)을 Gemini에 바로 넘겨 듣게 한다. 서버에
//     오디오를 저장하지 않는다 — 요청 안에서만 쓰고 버린다.
//   · 녹음 내용을 옮기지 않는다. 통화의 "상황과 말의 흐름"을 바탕으로 배울
//     언어의 새 두 사람 대화(최대 20줄)를 쓴다. 전화번호·계좌·주소는 넣지 않는다.
//   · 결과는 그 유저의 공부방에만 들어간다(공개 안 됨). 서버에 캐시하지 않는다.
//   · 쇼츠 링크와 같은 규칙: 만 18세 이상, 시간이 남은 회원(paid)만, 하루 상한,
//     실패하면 횟수·차감 시간을 되돌린다. 차감 스위치는
//     app_config/recording_import 의 deductSeconds 하나(없거나 0이면 차감 안 함).
//   · 응답 해석·역할 검사는 쇼츠 링크의 parseGeminiResponse를 그대로 쓴다.

const crypto = require("crypto");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {resolveAiAccess} = require("./ai_access");
const {deductTimeIdempotently} = require("./deduct_time");
const {
  GEMINI_ENDPOINT,
  GEMINI_TIMEOUT_MS,
  MAX_LINES,
  MAX_ROLE_CHARS,
  MAX_TITLE_CHARS,
  RESPONSE_SCHEMA,
  deductSecondsFrom,
  geminiApiKey,
  isAdultByBirthYear,
  kstDay,
  languageOr,
  nextUsage,
  parseGeminiResponse,
} = require("./shorts_scenario");

const REGION = "asia-northeast3";
// 3분은 앱이 올리기 전에 자른다(서버는 오디오를 자르지 못한다). 서버는 크기로
// 한 번 더 막는다 — 호출 본문 한도(10MB, base64로 4/3배)보다 작게.
const MAX_AUDIO_SECONDS = 180;
const MAX_AUDIO_BYTES = 6 * 1024 * 1024;
const DAILY_LIMIT = 5;
const USAGE_COLLECTION = "recording_scenario_usage";
const DEDUCT_CONFIG_PATH = "app_config/recording_import";

// Gemini가 듣는 오디오 형식. 삼성 통화 녹음은 m4a(audio/mp4)다.
const AUDIO_MIME_TYPES = {
  "audio/mp4": "audio/mp4",
  "audio/m4a": "audio/mp4",
  "audio/x-m4a": "audio/mp4",
  "audio/aac": "audio/aac",
  "audio/mpeg": "audio/mp3",
  "audio/mp3": "audio/mp3",
  "audio/wav": "audio/wav",
  "audio/x-wav": "audio/wav",
  "audio/ogg": "audio/ogg",
  "audio/flac": "audio/flac",
};

/** 앱이 보낸 mimeType → Gemini 형식. 지원하지 않으면 null. */
function normalizeMimeType(value) {
  const key = typeof value === "string" ? value.trim().toLowerCase() : "";
  return AUDIO_MIME_TYPES[key] || null;
}

/** base64 글자 → 바이트 수. 형식이 아니면 -1. */
function base64ByteLength(value) {
  if (typeof value !== "string" || value.length === 0) return -1;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return -1;
  const pad = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  return Math.floor(value.length * 3 / 4) - pad;
}

function buildPrompt({originLanguage, targetLanguage}) {
  return [
    "You are turning a phone call recording into a practice dialogue for a language-learning app.",
    "Listen to the recording. Use only roughly the first " + (MAX_AUDIO_SECONDS / 60) + " minutes.",
    "Write a NEW, clean dialogue between exactly two people, based on the situation and the flow of the call.",
    "Do not copy the call word for word; keep the situation, the purpose and the useful points, and say them",
    "the way a native speaker naturally would.",
    "",
    "Rules:",
    "- user_role is the person whose phone this seems to be (the one who talks about their own matter);",
    "  partner_role is the other person. Use their real roles in the situation (for example a customer and a",
    "  store clerk, two friends, a patient and a receptionist). Never use a tutor, teacher, learner or narrator.",
    "- If more than two people speak, keep the two who talk the most.",
    "- lines: the dialogue in order, at most " + MAX_LINES + " lines. speaker is \"user\" or \"partner\".",
    "  Remove fillers, stutters, hold music, automated menus, and small talk that adds nothing.",
    "- Never include phone numbers, account or ID numbers, passwords, addresses or other private identifiers.",
    "  Replace people's names with plain generic ones, or leave them out.",
    "- text MUST be written in " + targetLanguage + ". If the call is in another language, express each line",
    "  naturally in " + targetLanguage + ".",
    "- meaning is the natural meaning of the line in " + originLanguage + ".",
    "- title: one short sentence in " + originLanguage + " describing the situation, max " + MAX_TITLE_CHARS + " characters.",
    "  Describe only the situation. Do not mention the recording or the call itself.",
    "- user_role and partner_role: short names written in " + originLanguage + ", max " + MAX_ROLE_CHARS + " characters.",
    "- If only one person can be heard, do NOT give up. Build a natural two-person conversation: a second person",
    "  asks, reacts or answers in short lines, and the speaker's useful sentences are kept in spirit. The partner's",
    "  added lines must stay short and plain and must not add new facts.",
    "- Only when there is nothing to build on (silence, noise, music only, no understandable speech) set usable",
    "  to false and leave the other fields empty.",
  ].join("\n");
}

function buildGeminiRequest({audioBase64, mimeType, originLanguage, targetLanguage}) {
  return {
    contents: [{
      role: "user",
      parts: [
        {inlineData: {mimeType, data: audioBase64}},
        {text: buildPrompt({originLanguage, targetLanguage})},
      ],
    }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: RESPONSE_SCHEMA,
    },
  };
}

/** Gemini 한 번 호출. 테스트에서는 fetchImpl을 바꿔 끼운다. */
async function extractScenario({apiKey, audioBase64, mimeType, originLanguage, targetLanguage, fetchImpl = fetch}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);
  const startedAt = Date.now();
  try {
    const response = await fetchImpl(GEMINI_ENDPOINT, {
      method: "POST",
      headers: {"x-goog-api-key": apiKey, "Content-Type": "application/json"},
      body: JSON.stringify(buildGeminiRequest({audioBase64, mimeType, originLanguage, targetLanguage})),
      signal: controller.signal,
    });
    const body = await response.json().catch(() => ({}));
    const elapsedMs = Date.now() - startedAt;
    if (!response.ok) {
      return {ok: false, status: response.status, message: body && body.error && body.error.message, elapsedMs};
    }
    return {ok: true, result: parseGeminiResponse(body), usage: body.usageMetadata || null, elapsedMs};
  } finally {
    clearTimeout(timer);
  }
}

function createRecordingScenario({admin}) {
  const extractRecordingScenario = onCall({
    region: REGION,
    enforceAppCheck: true,
    secrets: [geminiApiKey],
    timeoutSeconds: 120,
    memory: "512MiB",
  }, async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication is required.");
    const data = request.data || {};
    const mimeType = normalizeMimeType(data.mimeType);
    if (!mimeType) throw new HttpsError("invalid-argument", "Unsupported audio type.");
    const size = base64ByteLength(data.audio);
    if (size <= 0) throw new HttpsError("invalid-argument", "Audio is missing or malformed.");
    if (size > MAX_AUDIO_BYTES) throw new HttpsError("invalid-argument", "Audio is too large.");
    const originLanguage = languageOr(data.originLanguage, "English");
    const targetLanguage = languageOr(data.targetLanguage, "English");
    const db = admin.firestore();

    const userSnap = await db.doc("users/" + uid).get();
    if (!isAdultByBirthYear(userSnap.exists ? userSnap.get("birthYear") : null)) {
      throw new HttpsError("out-of-range", "Adults only.");
    }

    const access = await resolveAiAccess({db, uid});
    if (access.reason === "blocked") throw new HttpsError("permission-denied", "This account is restricted.");
    if (!access.allowed || access.reason !== "paid") {
      throw new HttpsError("permission-denied", "Requires available time.");
    }

    const usageRef = db.doc(USAGE_COLLECTION + "/" + uid);
    const day = kstDay();
    const allowed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(usageRef);
      const next = nextUsage(snap.exists ? snap.data() : null, day, DAILY_LIMIT);
      if (!next) return false;
      tx.set(usageRef, next);
      return true;
    });
    if (!allowed) throw new HttpsError("resource-exhausted", "Daily limit reached.");
    // 되돌릴 것: 하루 횟수 1, 그리고 이미 뺀 시간(deducted)
    let deducted = 0;
    const refund = async () => {
      await usageRef.update({count: admin.firestore.FieldValue.increment(-1)}).catch(() => {});
      if (deducted > 0) {
        await db.doc("users/" + uid)
          .update({remainingTime: admin.firestore.FieldValue.increment(deducted)}).catch(() => {});
        deducted = 0;
      }
    };

    const key = geminiApiKey.value();
    if (!key) {
      await refund();
      throw new HttpsError("failed-precondition", "Recording reader is not configured.");
    }

    const cfgSnap = await db.doc(DEDUCT_CONFIG_PATH).get();
    const deductSeconds = deductSecondsFrom(cfgSnap.exists ? cfgSnap.data() : null);
    let remainingSeconds = null;
    if (deductSeconds > 0) {
      const balance = Number(userSnap.get("remainingTime"));
      if (!(balance >= deductSeconds)) {
        await refund();
        throw new HttpsError("permission-denied", "Requires available time.");
      }
      try {
        const res = await deductTimeIdempotently({
          db, uid, seconds: deductSeconds,
          requestId: "recording:" + Date.now() + ":" + crypto.randomBytes(4).toString("hex"),
          serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
        });
        deducted = deductSeconds;
        remainingSeconds = res.after;
      } catch (error) {
        await refund();
        console.error("extractRecordingScenario deduction failed", {message: error.message});
        throw new HttpsError("unavailable", "Time could not be deducted.");
      }
    }

    let outcome;
    try {
      outcome = await extractScenario({
        apiKey: key, audioBase64: data.audio, mimeType, originLanguage, targetLanguage,
      });
    } catch (error) {
      await refund();
      console.error("extractRecordingScenario call failed", {message: error.message});
      throw new HttpsError("unavailable", "Recording could not be read.");
    }
    // 로그에는 오디오·대화 내용을 남기지 않는다(크기·상태·시간만).
    console.log("extractRecordingScenario", {
      bytes: size, status: outcome.ok ? 200 : outcome.status, elapsedMs: outcome.elapsedMs,
      tokens: outcome.usage && outcome.usage.totalTokenCount,
      usable: outcome.result && outcome.result.usable,
      lines: outcome.result && outcome.result.lines && outcome.result.lines.length,
    });
    if (!outcome.ok) {
      await refund();
      // 읽을 수 없는 파일은 Gemini가 400으로 돌려준다.
      if (outcome.status === 400) throw new HttpsError("invalid-argument", "Recording is not readable.");
      throw new HttpsError("unavailable", "Recording could not be read.");
    }
    if (!outcome.result) {
      await refund();
      throw new HttpsError("internal", "Recording could not be turned into a dialogue.");
    }
    if (!outcome.result.usable) {
      const back = deducted;
      await refund();
      if (remainingSeconds !== null) remainingSeconds += back;
    }
    return {
      ...outcome.result,
      ...(remainingSeconds !== null ? {remainingSeconds} : {}),
    };
  });
  return {extractRecordingScenario};
}

module.exports = {
  AUDIO_MIME_TYPES,
  DAILY_LIMIT,
  MAX_AUDIO_BYTES,
  MAX_AUDIO_SECONDS,
  base64ByteLength,
  buildGeminiRequest,
  buildPrompt,
  createRecordingScenario,
  extractScenario,
  normalizeMimeType,
};
