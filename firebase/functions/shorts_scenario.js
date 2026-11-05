"use strict";

// 쇼츠 링크 → 공부방에 넣을 두 사람 대화 (2026-11-05 실장님).
//
//   · 유튜브 공개 영상의 URL을 Gemini에 그대로 넘긴다. 영상을 내려받지 않는다.
//   · 영상 속 장면을 두 사람의 대화(최대 20개)로 정리해 돌려준다. 줄마다
//     Target 문장(공부방 위)과 Origin 뜻(공부방 아래)이 있다. 앱이 그대로
//     유저 공부방에 방을 만든다 — 대화방을 거치지 않는다.
//   · 대화는 그 유저 공부방에만 들어간다. 서버에는 남기지 않는다(유저끼리 나눠
//     쓰는 캐시를 두지 않는 이유 — 대사가 거의 그대로라서).
//   · 역할은 장면 속 인물이다. "튜터/학습자"가 나오면 수업 대본이 된다
//     (11-05 첫 시험에서 실제로 그렇게 나왔다).
//   · 만 18세 이상(Gemini API 약관), 시간이 남은 회원(paid)만, 하루 상한.

const crypto = require("crypto");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {resolveAiAccess} = require("./ai_access");
const {deductTimeIdempotently} = require("./deduct_time");

const REGION = "asia-northeast3";
const GEMINI_MODEL = "gemini-3.5-flash";
const GEMINI_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/" + GEMINI_MODEL + ":generateContent";
const GEMINI_TIMEOUT_MS = 90 * 1000;
// 긴 영상이 들어와도 앞 3분만 본다(토큰 = 비용; 초당 약 91토큰이라 3분 ≈ 16,400토큰).
// 2026-11-05 실장님: 3분으로 두고 링크 한 번에 1분을 차감한다(5분 시험은 되돌림).
const MAX_VIDEO_SECONDS = 180;
const DAILY_LIMIT = 10;
const USAGE_COLLECTION = "shorts_scenario_usage";
// 링크 한 번에 차감할 시간(초). 스위치는 app_config/shorts_link 문서의 deductSeconds 하나다.
// 문서가 없거나 0이면 차감하지 않는다 — 입력창 안내("시간이 1분 쓰여요")가 들어간 앱 빌드가
// 나온 뒤에 60으로 켠다(안내 없이 차감되면 회원이 놀란다).
const DEDUCT_CONFIG_PATH = "app_config/shorts_link";
const MAX_DEDUCT_SECONDS = 600;

const MAX_TITLE_CHARS = 60;
const MAX_ROLE_CHARS = 30;
const MAX_LINES = 20;
const MAX_LINE_CHARS = 240;

const geminiApiKey = defineSecret("GEMINI_API_KEY");

const LANGUAGES = [
  "English", "Korean", "Japanese", "Chinese", "Spanish", "French",
  "German", "Hindi", "Russian", "Portuguese", "Italian", "Dutch",
];

/** 유튜브 URL에서 영상 ID(11자)를 꺼낸다. 유튜브가 아니면 null. */
function youtubeVideoId(value) {
  const raw = typeof value === "string" ? value.trim() : "";
  if (!raw || raw.length > 500) return null;
  let url;
  try {
    url = new URL(/^https?:\/\//i.test(raw) ? raw : "https://" + raw);
  } catch (_) {
    return null;
  }
  const host = url.hostname.toLowerCase().replace(/^(www\.|m\.|music\.)/, "");
  let id = null;
  if (host === "youtu.be") {
    id = url.pathname.split("/")[1];
  } else if (host === "youtube.com") {
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts[0] === "watch") id = url.searchParams.get("v");
    else if (["shorts", "embed", "live", "v"].includes(parts[0])) id = parts[1];
  }
  return id && /^[A-Za-z0-9_-]{11}$/.test(id) ? id : null;
}

/** 공부방에 붙이는 출처 링크. 앱이 보낸 글자가 아니라 검증한 ID로 만든다. */
function sourceUrlFor(videoId) {
  return "https://www.youtube.com/shorts/" + videoId;
}

function languageOr(value, fallback) {
  const lang = typeof value === "string" ? value.trim() : "";
  return LANGUAGES.includes(lang) ? lang : fallback;
}

function buildPrompt({originLanguage, targetLanguage}) {
  return [
    "You are turning a short video into a study dialogue for a language-learning app.",
    "Watch the video and listen to its audio, including any on-screen subtitles.",
    "Write the acted scene as a clean dialogue between exactly two people.",
    "",
    "Rules:",
    "- user_role and partner_role are two characters inside the scene (for example a customer and a store clerk).",
    "  Even if the video is a language lesson, never use a tutor, language teacher, learner or narrator.",
    "  user_role is the character who says the most useful lines; partner_role is the person they talk to.",
    "  If more than two people speak, keep the two who talk to each other the most and fold the rest out.",
    "- lines: the dialogue in order, at most " + MAX_LINES + " lines. speaker is \"user\" or \"partner\".",
    "  Keep the lines as they are spoken in the video. You may only remove fillers (um, uh), stutters,",
    "  narration, and on-screen teaching captions such as \"How do you say this in English?\".",
    "- text MUST be written in " + targetLanguage + ". If the video speaks another language, translate each line",
    "  into natural " + targetLanguage + " that a native speaker would say in the same moment.",
    "- meaning is the natural meaning of the line in " + originLanguage + ".",
    "- If the video presents a line as a mistake (\"don't say this\", Konglish, a wrong example), leave it out",
    "  and keep only the correct version.",
    "- title: one short sentence in " + originLanguage + " describing the scene, max " + MAX_TITLE_CHARS + " characters.",
    "  Describe only the scene. Do not mention the video, a lesson or any language.",
    "- user_role and partner_role: short names written in " + originLanguage + ", max " + MAX_ROLE_CHARS + " characters.",
    "- If only one person speaks (explaining, presenting, a monologue or a lesson), do NOT give up. Turn what they",
    "  say into a natural two-person conversation: a second person asks, reacts or answers in short lines, and the",
    "  speaker's own useful sentences and expressions are kept as spoken. Choose everyday roles inside a believable",
    "  scene (for example two friends, a coworker and a colleague), never a tutor, teacher or learner.",
    "  The partner's added lines must stay short and plain and must not add new facts.",
    "- Only when there is nothing to build on (music only, no speech, no readable captions) set usable to false",
    "  and leave the other fields empty.",
  ].join("\n");
}

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    usable: {type: "BOOLEAN"},
    title: {type: "STRING"},
    user_role: {type: "STRING"},
    partner_role: {type: "STRING"},
    lines: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          speaker: {type: "STRING", enum: ["user", "partner"]},
          text: {type: "STRING"},
          meaning: {type: "STRING"},
        },
        required: ["speaker", "text", "meaning"],
      },
    },
  },
  required: ["usable", "title", "user_role", "partner_role", "lines"],
};

function buildGeminiRequest({videoId, originLanguage, targetLanguage}) {
  return {
    contents: [{
      role: "user",
      parts: [
        {
          fileData: {
            mimeType: "video/mp4",
            fileUri: "https://www.youtube.com/watch?v=" + videoId,
          },
          videoMetadata: {startOffset: "0s", endOffset: MAX_VIDEO_SECONDS + "s"},
        },
        {text: buildPrompt({originLanguage, targetLanguage})},
      ],
    }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: RESPONSE_SCHEMA,
    },
  };
}

function clip(value, max) {
  const text = typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
  return text.length > max ? text.slice(0, max).trim() : text;
}

// 장면 속 교사·학생은 정상이다(교실 장면). 막는 건 "영상이 수업이라서" 붙는
// 역할 — 튜터·학습자·내레이터 — 뿐이다.
const LESSON_ROLE = /(tutor|learner|narrator|튜터|학습자|내레이터|회화\s*선생|language teacher|english teacher)/i;

/**
 * Gemini 응답 본문 → 앱에 돌려줄 결과. 쓸 수 없는 영상이면 {usable:false}.
 * 형식이 깨졌으면 null(서버 오류로 처리).
 */
function parseGeminiResponse(body) {
  const parts = body && body.candidates && body.candidates[0] &&
    body.candidates[0].content && body.candidates[0].content.parts;
  if (!Array.isArray(parts)) return null;
  const text = parts.filter((p) => p && typeof p.text === "string" && !p.thought)
    .map((p) => p.text).join("");
  let json;
  try {
    json = JSON.parse(text);
  } catch (_) {
    return null;
  }
  if (!json || typeof json !== "object") return null;
  if (json.usable === false) return {usable: false};
  const title = clip(json.title, MAX_TITLE_CHARS);
  const userRole = clip(json.user_role, MAX_ROLE_CHARS);
  const partnerRole = clip(json.partner_role, MAX_ROLE_CHARS);
  if (!title || !userRole || !partnerRole) return {usable: false};
  if (LESSON_ROLE.test(userRole) || LESSON_ROLE.test(partnerRole)) return null;
  const lines = (Array.isArray(json.lines) ? json.lines : [])
    .map((l) => ({
      speaker: l && l.speaker === "user" ? "user" : "partner",
      text: clip(l && l.text, MAX_LINE_CHARS),
      meaning: clip(l && l.meaning, MAX_LINE_CHARS),
    }))
    .filter((l) => l.text && l.meaning)
    .slice(0, MAX_LINES);
  // 공부방은 내가 말할 줄이 있어야 연습이 된다. 두 사람이 다 말해야 대화다.
  if (lines.length < 2 || !lines.some((l) => l.speaker === "user") ||
      !lines.some((l) => l.speaker === "partner")) {
    return {usable: false};
  }
  return {usable: true, title, userRole, partnerRole, lines};
}

/** Gemini 한 번 호출. 테스트·로컬 시험에서도 그대로 쓴다. */
async function extractScenario({apiKey, videoId, originLanguage, targetLanguage, fetchImpl = fetch}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);
  const startedAt = Date.now();
  try {
    const response = await fetchImpl(GEMINI_ENDPOINT, {
      method: "POST",
      headers: {"x-goog-api-key": apiKey, "Content-Type": "application/json"},
      body: JSON.stringify(buildGeminiRequest({videoId, originLanguage, targetLanguage})),
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

/** KST 날짜 문자열. 하루 상한은 한국 자정에 풀린다. */
function kstDay(nowMs = Date.now()) {
  return new Date(nowMs + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/**
 * Gemini API 약관(Age Requirements): 이용자는 18세 이상이어야 한다.
 * 가입 때 받는 건 태어난 해뿐이라(intro_master.dart birthYear) 생일 전인
 * 17세를 걸러 내려면 연도 차가 19 이상이어야 한다. 그래서 올해 18세가 되는
 * 사람 일부도 내년까지 막힌다 — 약관 쪽으로 기운 선택이다(2026-11-05).
 * 태어난 해가 없으면 막는다.
 */
function isAdultByBirthYear(birthYear, nowMs = Date.now()) {
  const year = Number(birthYear);
  if (!Number.isInteger(year) || year < 1900) return false;
  const nowYear = Number(kstDay(nowMs).slice(0, 4));
  return nowYear - year >= 19;
}

/** 오늘 쓴 횟수 기록 → 이번 호출을 허락하면 다음 기록, 아니면 null. */
function nextUsage(record, day, limit = DAILY_LIMIT) {
  const count = record && record.day === day ? Number(record.count) || 0 : 0;
  if (count >= limit) return null;
  return {day, count: count + 1};
}

/** app_config/shorts_link 문서 → 차감 초(0이면 끔). 숫자가 아니거나 음수·과대 값은 0으로 본다. */
function deductSecondsFrom(config) {
  const v = Number(config && config.deductSeconds);
  if (!Number.isFinite(v) || v <= 0 || v > MAX_DEDUCT_SECONDS) return 0;
  return Math.floor(v);
}

function createShortsScenario({admin}) {
  const extractShortsScenario = onCall({
    region: REGION,
    enforceAppCheck: true,
    secrets: [geminiApiKey],
    timeoutSeconds: 120,
  }, async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication is required.");
    const data = request.data || {};
    const videoId = youtubeVideoId(data.url);
    if (!videoId) throw new HttpsError("invalid-argument", "Not a YouTube link.");
    const originLanguage = languageOr(data.originLanguage, "English");
    const targetLanguage = languageOr(data.targetLanguage, "English");
    const db = admin.firestore();

    const userSnap = await db.doc("users/" + uid).get();
    if (!isAdultByBirthYear(userSnap.exists ? userSnap.get("birthYear") : null)) {
      // 앱은 out-of-range를 "만 18세 이상만" 안내로 바꾼다.
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
      const next = nextUsage(snap.exists ? snap.data() : null, day);
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
      throw new HttpsError("failed-precondition", "Video reader is not configured.");
    }

    // 링크 한 번에 일정 시간을 뺀다(켜져 있을 때만). 읽지 못하거나 대화가 없으면 아래에서 되돌린다.
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
          requestId: "shorts:" + videoId + ":" + Date.now() + ":" + crypto.randomBytes(4).toString("hex"),
          serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
        });
        deducted = deductSeconds;
        remainingSeconds = res.after;
      } catch (error) {
        await refund();
        console.error("extractShortsScenario deduction failed", {message: error.message});
        throw new HttpsError("unavailable", "Time could not be deducted.");
      }
    }

    let outcome;
    try {
      outcome = await extractScenario({apiKey: key, videoId, originLanguage, targetLanguage});
    } catch (error) {
      await refund();
      console.error("extractShortsScenario call failed", {videoId, message: error.message});
      throw new HttpsError("unavailable", "Video could not be read.");
    }
    console.log("extractShortsScenario", {
      videoId, status: outcome.ok ? 200 : outcome.status, elapsedMs: outcome.elapsedMs,
      tokens: outcome.usage && outcome.usage.totalTokenCount,
      usable: outcome.result && outcome.result.usable,
      lines: outcome.result && outcome.result.lines && outcome.result.lines.length,
    });
    if (!outcome.ok) {
      await refund();
      // 비공개·삭제·지역 제한 영상은 Gemini가 400으로 돌려준다.
      if (outcome.status === 400 || outcome.status === 403 || outcome.status === 404) {
        throw new HttpsError("not-found", "Video is not available.");
      }
      throw new HttpsError("unavailable", "Video could not be read.");
    }
    if (!outcome.result) {
      await refund();
      throw new HttpsError("internal", "Video could not be turned into a dialogue.");
    }
    if (!outcome.result.usable) {
      const back = deducted;
      await refund();
      if (remainingSeconds !== null) remainingSeconds += back;
    }
    // remainingSeconds: 차감을 켠 경우에만 있다(앱이 남은 시간 표시를 맞춘다)
    return {
      ...outcome.result,
      sourceUrl: sourceUrlFor(videoId),
      ...(remainingSeconds !== null ? {remainingSeconds} : {}),
    };
  });
  return {extractShortsScenario};
}

module.exports = {
  DAILY_LIMIT,
  GEMINI_MODEL,
  MAX_LINES,
  buildGeminiRequest,
  buildPrompt,
  createShortsScenario,
  deductSecondsFrom,
  extractScenario,
  isAdultByBirthYear,
  kstDay,
  nextUsage,
  parseGeminiResponse,
  sourceUrlFor,
  youtubeVideoId,
};
