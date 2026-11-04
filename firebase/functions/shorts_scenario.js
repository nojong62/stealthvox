"use strict";

// 쇼츠 링크 → 시나리오톡 세 칸(상황·AI 역할·내 역할) + 핵심 표현 (2026-11-05 실장님).
//
//   · 유튜브 공개 영상의 URL을 Gemini에 그대로 넘긴다. 영상을 내려받지 않는다.
//   · 돌려주는 것은 상황·역할·핵심 표현(최대 5개)뿐이다. 대사 전문은 앱에
//     보내지도, 저장하지도 않는다(저작권 부담).
//   · 역할은 장면 속 인물이다. "튜터/학습자"가 나오면 시나리오톡이 수업이 된다
//     (11-05 첫 시험에서 실제로 그렇게 나왔다).
//   · 시간이 남은 회원(paid)만. 하루 상한이 있고, 같은 영상·같은 언어 쌍은
//     캐시를 돌려준다(상한에 세지 않는다).

const crypto = require("crypto");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {resolveAiAccess} = require("./ai_access");

const REGION = "asia-northeast3";
const GEMINI_MODEL = "gemini-3.5-flash";
const GEMINI_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/" + GEMINI_MODEL + ":generateContent";
const GEMINI_TIMEOUT_MS = 90 * 1000;
// 쇼츠는 3분까지다. 긴 영상이 들어와도 앞 3분만 본다(토큰 = 비용).
const MAX_VIDEO_SECONDS = 180;
const DAILY_LIMIT = 10;
const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const USAGE_COLLECTION = "shorts_scenario_usage";
const CACHE_COLLECTION = "shorts_scenario_cache";

// 앱 설정 칸(stealth_room_master.dart _setupField)이 maxLength 60이다.
const MAX_SITUATION_CHARS = 60;
const MAX_ROLE_CHARS = 30;
const MAX_EXPRESSIONS = 5;
const MAX_EXPRESSION_CHARS = 160;

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

/** 화면에 붙이는 출처 링크. 앱이 보낸 글자가 아니라 검증한 ID로 만든다. */
function sourceUrlFor(videoId) {
  return "https://www.youtube.com/shorts/" + videoId;
}

function languageOr(value, fallback) {
  const lang = typeof value === "string" ? value.trim() : "";
  return LANGUAGES.includes(lang) ? lang : fallback;
}

function buildPrompt({originLanguage, targetLanguage}) {
  return [
    "You are preparing a role-play for a language-learning app.",
    "Watch this short video and listen to its audio, including any on-screen subtitles.",
    "Turn the scene in the video into a role-play the learner can act out.",
    "",
    "Rules:",
    "- ai_role and user_role must be characters inside the scene (for example a store clerk and a customer).",
    "  Even if the video is a language lesson, do not make it a lesson: never use a tutor, language teacher,",
    "  learner or narrator as a role. Use the people in the acted scene.",
    "- user_role is the character who says the most useful lines; ai_role is the person they talk to.",
    "- situation: one short sentence, written in " + originLanguage + ", describing where they are",
    "  and what the user_role wants, so the conversation can start right away. Max " + MAX_SITUATION_CHARS + " characters.",
    "  Describe only the scene as if it is happening now. Do not mention the video, the lesson,",
    "  any language, expressions, or what the video teaches. Bad: \"...and learns the right English phrase.\"",
    "  Good: \"At a small restaurant, the owner brings the customer a free side dish.\"",
    "- ai_role and user_role: short names written in " + originLanguage + ", max " + MAX_ROLE_CHARS + " characters.",
    "- key_expressions: up to " + MAX_EXPRESSIONS + " of the most useful lines actually spoken or shown in the video.",
    "  text MUST be written in " + targetLanguage + ". If the video speaks another language, translate the line",
    "  into natural " + targetLanguage + " that a native speaker would say in the same moment.",
    "  meaning is its meaning in " + originLanguage + ".",
    "- Do not invent lines that are not in the video.",
    "- If the video presents a line as a mistake or as unnatural (\"don't say this\", Konglish, a wrong example),",
    "  never include that line. Include only the correct version.",
    "- If the video has no conversation that could be role-played (music only, no speech, unrelated content),",
    "  set usable to false and leave the other fields empty.",
  ].join("\n");
}

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    usable: {type: "BOOLEAN"},
    situation: {type: "STRING"},
    ai_role: {type: "STRING"},
    user_role: {type: "STRING"},
    key_expressions: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          text: {type: "STRING"},
          meaning: {type: "STRING"},
        },
        required: ["text", "meaning"],
      },
    },
  },
  required: ["usable", "situation", "ai_role", "user_role", "key_expressions"],
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
  const situation = clip(json.situation, MAX_SITUATION_CHARS);
  const aiRole = clip(json.ai_role, MAX_ROLE_CHARS);
  const userRole = clip(json.user_role, MAX_ROLE_CHARS);
  if (!situation || !aiRole || !userRole) return {usable: false};
  if (LESSON_ROLE.test(aiRole) || LESSON_ROLE.test(userRole)) return null;
  const expressions = (Array.isArray(json.key_expressions) ? json.key_expressions : [])
    .map((e) => ({
      text: clip(e && e.text, MAX_EXPRESSION_CHARS),
      meaning: clip(e && e.meaning, MAX_EXPRESSION_CHARS),
    }))
    .filter((e) => e.text)
    .slice(0, MAX_EXPRESSIONS);
  return {usable: true, situation, aiRole, userRole, expressions};
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

/** KST 날짜 문자열. 하루 상한은 한국 자정에 풀린다. */
function kstDay(nowMs = Date.now()) {
  return new Date(nowMs + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/** 오늘 쓴 횟수 기록 → 이번 호출을 허락하면 다음 기록, 아니면 null. */
function nextUsage(record, day, limit = DAILY_LIMIT) {
  const count = record && record.day === day ? Number(record.count) || 0 : 0;
  if (count >= limit) return null;
  return {day, count: count + 1};
}

function cacheKey(videoId, originLanguage, targetLanguage) {
  return crypto.createHash("sha256")
    .update(videoId + "|" + originLanguage + "|" + targetLanguage)
    .digest("hex").slice(0, 40);
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

    const cacheRef = db.doc(CACHE_COLLECTION + "/" + cacheKey(videoId, originLanguage, targetLanguage));
    const cached = await cacheRef.get();
    if (cached.exists) {
      const c = cached.data();
      const createdMs = c.createdAt && typeof c.createdAt.toMillis === "function" ? c.createdAt.toMillis() : 0;
      if (c.result && Date.now() - createdMs < CACHE_TTL_MS) {
        return {...c.result, sourceUrl: sourceUrlFor(videoId), cached: true};
      }
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
    const refund = () => usageRef.update({count: admin.firestore.FieldValue.increment(-1)}).catch(() => {});

    const key = geminiApiKey.value();
    if (!key) {
      await refund();
      throw new HttpsError("failed-precondition", "Video reader is not configured.");
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
      throw new HttpsError("internal", "Video could not be turned into a scenario.");
    }
    await cacheRef.set({
      result: outcome.result,
      videoId,
      originLanguage,
      targetLanguage,
      model: GEMINI_MODEL,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {...outcome.result, sourceUrl: sourceUrlFor(videoId), cached: false};
  });
  return {extractShortsScenario};
}

module.exports = {
  DAILY_LIMIT,
  GEMINI_MODEL,
  MAX_EXPRESSIONS,
  buildGeminiRequest,
  buildPrompt,
  cacheKey,
  createShortsScenario,
  extractScenario,
  isAdultByBirthYear,
  kstDay,
  sourceUrlFor,
  nextUsage,
  parseGeminiResponse,
  youtubeVideoId,
};
