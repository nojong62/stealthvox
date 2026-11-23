const crypto = require("crypto");
const https = require("https");
const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");
const { onCall } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { GoogleAuth } = require("google-auth-library");
const { resolveAiAccess } = require("./ai_access");
const { createBlockedCache } = require("./block_check");

const openAiApiKey = defineSecret("OPENAI_API_KEY");
const deepgramApiKey = defineSecret("DEEPGRAM_API_KEY");
const gatewaySigningSecret = defineSecret("AI_GATEWAY_SIGNING_SECRET");

const REGION = "asia-northeast3";
const GATEWAY_AUDIENCE = "stealthvox-openai-proxy";
// Screens mint these once on entry and hold them for the whole conversation
// (Duo, Circle Talk, Scenario Talk, History) with no refresh-on-401 path.
// A 10-minute TTL cut every longer session off mid-call, so keep the lifetimes
// that sessions were verified with. Entitlement is still checked at mint time.
const GATEWAY_TOKEN_TTL_SECONDS = 2 * 60 * 60;
const DEEPGRAM_TOKEN_TTL_SECONDS = 60 * 60;
const GOOGLE_TTS_SCOPE = "https://www.googleapis.com/auth/cloud-platform";
const GOOGLE_TTS_ENDPOINT = "https://texttospeech.googleapis.com/v1/text:synthesize";
// Plain speech in the app's 12 conversation languages is synthesized by Google
// Chirp 3 HD. The app still sends OpenAI-compatible voice IDs; only their
// gender survives the provider boundary, as one representative Chirp voice
// per gender (Leda / Charon): Circle Talk sends `shimmer` (female), Scenario Talk sends `echo`
// (male), and History practice sends `google-female` / `google-male`.
const CHIRP_FEMALE_VOICE = "Leda";
// Chirp 3 HD male is Puck in every locale (2026-11-23, same as Korean).
const CHIRP_MALE_VOICE = "Puck";
// Gemini TTS only (2026-11-23): a brighter, clearer female voice than Leda;
// the male stays Charon.
const GEMINI_FEMALE_VOICE = "Zephyr";
const GEMINI_MALE_VOICE = "Charon";
const KO_CHIRP_FEMALE_VOICE = "Achernar";
const KO_CHIRP_MALE_VOICE = "Puck";
const CHIRP_LOCALES = new Map([
  ["ko", "ko-KR"], ["korean", "ko-KR"],
  ["en", "en-US"], ["english", "en-US"],
  ["ja", "ja-JP"], ["japanese", "ja-JP"],
  ["zh", "cmn-CN"], ["chinese", "cmn-CN"],
  ["es", "es-ES"], ["spanish", "es-ES"],
  ["fr", "fr-FR"], ["french", "fr-FR"],
  ["de", "de-DE"], ["german", "de-DE"],
  ["hi", "hi-IN"], ["hindi", "hi-IN"],
  ["ru", "ru-RU"], ["russian", "ru-RU"],
  ["pt", "pt-BR"], ["portuguese", "pt-BR"],
  ["it", "it-IT"], ["italian", "it-IT"],
  ["nl", "nl-NL"], ["dutch", "nl-NL"],
  ["vi", "vi-VN"], ["vietnamese", "vi-VN"],
  ["id", "id-ID"], ["indonesian", "id-ID"],
]);
// Basic voice tier (2026-11-09): WaveNet at about 1/7 of Chirp 3 HD's price.
// One female and one male voice per locale, taken from the live voices:list
// on 2026-11-09. Value = the voice letter in `<locale>-Wavenet-<letter>`.
const WAVENET_VOICES = new Map([
  ["en-US", { female: "C", male: "D" }],
  ["en-GB", { female: "A", male: "B" }],
  ["ja-JP", { female: "A", male: "C" }],
  ["cmn-CN", { female: "A", male: "B" }],
  ["es-ES", { female: "F", male: "E" }],
  ["fr-FR", { female: "F", male: "G" }],
  ["de-DE", { female: "G", male: "H" }],
  ["ko-KR", { female: "A", male: "C" }],
  ["hi-IN", { female: "A", male: "B" }],
  ["ru-RU", { female: "A", male: "B" }],
  ["pt-BR", { female: "A", male: "B" }],
  ["it-IT", { female: "E", male: "F" }],
  ["nl-NL", { female: "F", male: "G" }],
  ["vi-VN", { female: "A", male: "B" }],
  ["id-ID", { female: "A", male: "B" }],
]);
// Chirp pause tags as SSML breaks for WaveNet. Lengths follow the Chirp
// measurements below ([pause short] 150–280 ms, [pause] 410–830 ms).
const WAVENET_BREAKS = new Map([
  ["[pause short]", "250ms"],
  ["[pause]", "600ms"],
  ["[pause long]", "1000ms"],
]);
const MALE_VOICE_IDS = new Set([
  "male", "google-male", "google-ko-male",
  "ash", "ballad", "cedar", "echo", "fable", "onyx", "verse",
]);
// Provider-neutral IDs must not reach OpenAI as-is while it is still a
// fallback for expressive requests.
const OPENAI_VOICE_FOR_GENDER_ID = new Map([
  ["female", "shimmer"], ["google-female", "shimmer"], ["google-ko-female", "shimmer"],
  ["male", "echo"], ["google-male", "echo"], ["google-ko-male", "echo"],
]);
// Google's limit is on UTF-8 bytes, not characters: a Korean, Japanese,
// Chinese or Hindi character takes three bytes.
const MAX_GOOGLE_TTS_INPUT_BYTES = 5000;
// Upper bound for one request through this gateway, split across Google calls.
const MAX_TTS_INPUT_CHARS = 5000;

// Gemini TTS runs through the same Google endpoint as Chirp, selected by
// `voice.modelName`, and takes a natural-language style prompt that Chirp does
// not. Every language except Korean goes to Gemini first (2026-11-22); Korean
// always stays on Chirp 3 HD. A language Gemini does not have, or any failure,
// falls back to Chirp so a preview-model change can never silence a screen.
// Switches on the function (no app update needed):
//   GEMINI_TTS_DISABLED=1  - Gemini off everywhere, even when the app asks.
//   GEMINI_TTS_DEFAULT=0   - Gemini only when the app sends `engine: "gemini"`.
// A request can also send `engine: "chirp"` to stay on Chirp.
const GEMINI_TTS_MODEL = "gemini-2.5-flash-tts";
// Locales Gemini rejected (a 4xx that names the language/voice/model) are not
// retried for an hour on this instance, so an unsupported language costs one
// failed call instead of one per request.
const GEMINI_UNSUPPORTED_TTL_MS = 60 * 60 * 1000;
const geminiUnsupportedLocales = new Map();
const GEMINI_MAX_PIECES = 40;
const GEMINI_MAX_PROMPT_CHARS = 800;
const GEMINI_SAMPLE_RATE = 24000;
// The app finds breath edges from silence (it needs >= 180 ms), so the gap
// stands in for Chirp's [pause] tags and must be clearly longer than that.
const GEMINI_PAUSE_MS = { short: 450, medium: 700, long: 1000 };

// This authentication object uses the Cloud Functions runtime service account.
// No Google API key is issued to, stored in, or recoverable from the APK.
const googleAuth = new GoogleAuth({ scopes: [GOOGLE_TTS_SCOPE] });

const OPENAI_ROUTES = new Map([
  ["POST /v1/chat/completions", "/v1/chat/completions"],
  ["POST /v1/audio/speech", "/v1/audio/speech"],
  ["POST /v1/audio/transcriptions", "/v1/audio/transcriptions"],
  ["POST /v1/decisions", "/v1/decisions"],
  ["GET /v1/models/gpt-4o-mini", "/v1/models/gpt-4o-mini"],
  ["GET /v1/models/gpt-6-luna", "/v1/models/gpt-6-luna"],
]);

function callableError(code, message) {
  return new functions.https.HttpsError(code, message);
}

function requireVerifiedCaller(request) {
  if (!request.auth || !request.auth.uid) {
    throw callableError("unauthenticated", "Authentication is required.");
  }
  if (!request.app || !request.app.appId) {
    throw callableError("failed-precondition", "App Check is required.");
  }
  return {
    uid: String(request.auth.uid),
    appId: String(request.app.appId),
  };
}

async function requireAiAccess(request, caller) {
  const access = await resolveAiAccess({
    db: admin.firestore(),
    uid: caller.uid,
    roomId: request.data && request.data.roomId,
  });
  if (access.reason === "blocked") {
    throw callableError("permission-denied", "This account is restricted.");
  }
  if (!access.allowed) {
    throw callableError("permission-denied", "AI access requires available time or an active session.");
  }
  return access;
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

function signGatewayToken(payload, secret) {
  const encoded = base64UrlJson(payload);
  const signature = crypto.createHmac("sha256", secret)
    .update(encoded)
    .digest("base64url");
  return encoded + "." + signature;
}

function verifyGatewayToken(token, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (typeof token !== "string" || token.length > 4096) return null;
  const parts = token.split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) return null;
  const expected = crypto.createHmac("sha256", secret)
    .update(parts[0])
    .digest("base64url");
  const receivedBuffer = Buffer.from(parts[1]);
  const expectedBuffer = Buffer.from(expected);
  if (receivedBuffer.length !== expectedBuffer.length ||
      !crypto.timingSafeEqual(receivedBuffer, expectedBuffer)) return null;
  try {
    const payload = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
    if (payload.aud !== GATEWAY_AUDIENCE ||
        typeof payload.uid !== "string" || !payload.uid ||
        typeof payload.appId !== "string" || !payload.appId ||
        !Number.isInteger(payload.iat) || !Number.isInteger(payload.exp) ||
        payload.iat > nowSeconds + 60 || payload.exp <= nowSeconds ||
        payload.exp - payload.iat > GATEWAY_TOKEN_TTL_SECONDS) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

function bearerToken(req) {
  const value = String(req.get("authorization") || "");
  const match = /^Bearer\s+(.+)$/i.exec(value);
  return match ? match[1].trim() : "";
}

function normalizedProxyPath(req) {
  const suffix = String(req.path || req.url || "").split("?")[0];
  return suffix.startsWith("/v1/") ? suffix : "/" + suffix.replace(/^\/+/, "");
}

function containsKorean(text) {
  return /[\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F]/u.test(String(text || ""));
}

function requestedAudioFormat(body) {
  const format = String(body && body.response_format || "mp3").trim().toLowerCase();
  // The app currently consumes only mp3 and raw pcm from this proxy. Keep
  // unknown values on the established OpenAI path instead of guessing a
  // Google encoding and breaking an existing caller.
  if (format === "pcm") return "pcm";
  if (format === "mp3") return "mp3";
  return null;
}


function utf8Bytes(text) {
  return Buffer.byteLength(String(text || ""), "utf8");
}

// Hangul always wins so the verified Korean route keeps its behavior. Next the
// app's explicit `language`, then scripts that name a single language. Latin
// text without a `language` stays on OpenAI rather than being read in a
// guessed accent; Han-only text is skipped because it may be Japanese.
function chirpLocaleForRequest(body) {
  const input = String(body && body.input || "");
  if (containsKorean(input)) return "ko-KR";
  const language = String(body && body.language || "").trim().toLowerCase();
  // The app sends en-GB when its English style is British.
  if (/^en[-_]gb$/.test(language)) return "en-GB";
  const requested = language.split(/[-_]/)[0];
  if (CHIRP_LOCALES.has(requested)) return CHIRP_LOCALES.get(requested);
  // A bare ISO code outside the table ("uk", "bg", "mr") names the language
  // outright. Guessing from the script would read Ukrainian with the Russian
  // voice and Marathi with the Hindi one; the dynamic lookup handles these.
  if (/^[a-z]{2,3}$/.test(language)) return null;
  if (/[぀-ヿ]/u.test(input)) return "ja-JP";
  if (/[ऀ-ॿ]/u.test(input)) return "hi-IN";
  if (/[Ѐ-ӿ]/u.test(input)) return "ru-RU";
  return null;
}

function chirpGenderForRequest(body) {
  const requestedVoice = String(body && body.voice || "").trim().toLowerCase();
  return MALE_VOICE_IDS.has(requestedVoice) ? "male" : "female";
}

function chirpVoiceForRequest(body, locale) {
  const male = chirpGenderForRequest(body) === "male";
  // Korean uses its own pair (2026-11-15): Achernar (female) / Puck (male).
  if (locale === "ko-KR") {
    return "ko-KR-Chirp3-HD-" + (male ? KO_CHIRP_MALE_VOICE : KO_CHIRP_FEMALE_VOICE);
  }
  return locale + "-Chirp3-HD-" + (male ? CHIRP_MALE_VOICE : CHIRP_FEMALE_VOICE);
}

// "basic" is the only non-default tier. Anything else, including a missing
// field from an older app, stays on Chirp 3 HD.
function voiceTierForRequest(body) {
  const tier = String(body && body.voice_tier || "").trim().toLowerCase();
  return tier === "basic" ? "basic" : "premium";
}

// null when the locale has no WaveNet pair; the caller then uses Chirp.
function wavenetVoiceForRequest(body, locale) {
  const pair = WAVENET_VOICES.get(locale);
  if (!pair) return null;
  return locale + "-Wavenet-" + pair[chirpGenderForRequest(body)];
}

function escapeSsml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

// The app's Chirp pause markup as WaveNet SSML. Text is escaped first so a
// `<` in a sentence cannot open a tag; only the three known pause tags turn
// into breaks. null when the SSML would exceed Google's input cap.
function wavenetSsmlFromMarkup(markup) {
  const source = String(markup || "").trim();
  if (!source) return null;
  const parts = source.split(/(\[pause short\]|\[pause long\]|\[pause\])/);
  const body = parts.map(part => WAVENET_BREAKS.has(part)
    ? "<break time=\"" + WAVENET_BREAKS.get(part) + "\"/>"
    : escapeSsml(part)).join("");
  const ssml = "<speak>" + body + "</speak>";
  return utf8Bytes(ssml) <= MAX_GOOGLE_TTS_INPUT_BYTES ? ssml : null;
}

// ── Korean numerals (2026-11-23) ─────────────────────────────────────────────
// Chirp misread "1500원" as "일 오백 원". Digits followed by a unit are written
// out as Korean words just before synthesis; the text shown in the app and kept
// in history is untouched. Sino-Korean numerals go with 원/년/월/일/분..., native
// numerals (1-99) with counters like 시/개/명/살. Decimals, phone numbers, dates
// joined by "-" and units with ambiguous readings (번) are left alone.
const SINO_DIGITS = ["", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구"];
const NATIVE_ONES = ["", "한", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉"];
const NATIVE_TENS = ["", "열", "스물", "서른", "마흔", "쉰", "예순", "일흔", "여든", "아흔"];

function sinoBelow10000(n) {
  let out = "";
  for (const [value, name] of [[1000, "천"], [100, "백"], [10, "십"]]) {
    const digit = Math.floor(n / value) % 10;
    if (digit) out += (digit === 1 ? "" : SINO_DIGITS[digit]) + name;
  }
  return out + SINO_DIGITS[n % 10];
}

function sinoKorean(n) {
  if (n === 0) return "영";
  let rest = n;
  let out = "";
  for (const [value, name] of [[1e12, "조"], [1e8, "억"], [1e4, "만"]]) {
    const group = Math.floor(rest / value);
    rest %= value;
    // 10,000 is "만", not "일만"; 억 and 조 keep the "일".
    if (group) out += (name === "만" && group === 1 ? "" : sinoBelow10000(group)) + name;
  }
  return out + (rest ? sinoBelow10000(rest) : "");
}

function nativeKorean(n) {
  if (n === 20) return "스무";
  return NATIVE_TENS[Math.floor(n / 10)] + NATIVE_ONES[n % 10];
}

const KO_NUM_GUARD = "(?<![\\d.A-Za-z\\-/:])";
const KO_SINO_RE = new RegExp(
  KO_NUM_GUARD + "(\\d{1,3}(?:,\\d{3})+|\\d+)(?!\\.\\d)\\s?" +
  "(원|달러|엔|퍼센트|%|년|월|일|분|초|층|호|킬로그램|킬로|센티미터|미터)", "gu");
const KO_NATIVE_RE = new RegExp(
  KO_NUM_GUARD + "(\\d{1,2})(?!\\.\\d)\\s?" +
  "(시간|시|개(?!월)|명|살|마리|잔|병|권|대|장|곳)", "gu");

function koreanNumbersToWords(text) {
  const source = String(text || "");
  if (!/\d/.test(source)) return source;
  return source
    .replace(KO_SINO_RE, (match, digits, unit) => {
      const plain = digits.replace(/,/g, "");
      if (plain.length > 15) return match;
      const n = Number(plain);
      if (unit === "월" && n === 6) return "유 월";
      if (unit === "월" && n === 10) return "시 월";
      return sinoKorean(n) + " " + (unit === "%" ? "퍼센트" : unit);
    })
    .replace(KO_NATIVE_RE, (match, digits, unit) => {
      const n = Number(digits);
      if (n < 1 || n > 99) return match;
      return nativeKorean(n) + " " + unit;
    });
}

// The markup sent to Google for [locale], or null when it no longer fits one
// request after the numerals are written out (the caller then sends plain text).
function chirpMarkupForLocale(body, locale) {
  const markup = chirpMarkupForRequest(body);
  if (!markup || locale !== "ko-KR") return markup;
  const spoken = koreanNumbersToWords(markup);
  return utf8Bytes(spoken) <= MAX_GOOGLE_TTS_INPUT_BYTES ? spoken : null;
}

// Chirp has no equivalent of `instructions`, so expressive requests keep the
// OpenAI model that honors them.
function shouldUseChirp(body) {
  if (!body || typeof body !== "object") return false;
  if (String(body.instructions || "").trim()) return false;
  if (!requestedAudioFormat(body)) return false;
  return chirpLocaleForRequest(body) !== null;
}

// Pause-control markup the app wrote for this exact `input` ([pause short],
// [pause], [pause long]). Used only when it fits one Google request; a longer
// one falls back to plain text rather than cutting through a tag.
function chirpMarkupForRequest(body) {
  const markup = String(body && body.markup || "").trim();
  if (!markup || utf8Bytes(markup) > MAX_GOOGLE_TTS_INPUT_BYTES) return null;
  return markup;
}

// The body sent on to OpenAI: no `language` / `markup` fields (OpenAI rejects unknown
// parameters) and no provider-neutral voice IDs.
function openAiSpeechBody(body) {
  const sanitized = { ...body };
  delete sanitized.language;
  delete sanitized.markup;
  delete sanitized.voice_tier;
  delete sanitized.engine;
  delete sanitized.style_prompt;
  const voice = String(sanitized.voice || "").trim().toLowerCase();
  if (OPENAI_VOICE_FOR_GENDER_ID.has(voice)) {
    sanitized.voice = OPENAI_VOICE_FOR_GENDER_ID.get(voice);
  }
  return sanitized;
}

// Packs sentences into pieces of at most [maxBytes] UTF-8 bytes. A single
// sentence longer than that is cut by characters.
function splitForGoogleTts(text, maxBytes = MAX_GOOGLE_TTS_INPUT_BYTES) {
  const input = String(text || "").trim();
  if (utf8Bytes(input) <= maxBytes) return input ? [input] : [];
  const sentences = input.split(/(?<=[.!?。！？\n])\s*/u).filter(Boolean);
  const pieces = [];
  let current = "";
  const pushHardSplit = sentence => {
    let piece = "";
    for (const ch of sentence) {
      if (utf8Bytes(piece + ch) > maxBytes) {
        pieces.push(piece);
        piece = "";
      }
      piece += ch;
    }
    return piece;
  };
  for (const sentence of sentences) {
    const joined = current ? current + " " + sentence : sentence;
    if (utf8Bytes(joined) <= maxBytes) {
      current = joined;
      continue;
    }
    if (current) pieces.push(current);
    current = utf8Bytes(sentence) <= maxBytes ? sentence : pushHardSplit(sentence);
  }
  if (current) pieces.push(current);
  return pieces;
}

// Chirp runs clauses together across a comma ("회원님,PT 시간...",
// "Yes, Mom"). Measured 2026-11-02: plain text left 0–120 ms at the comma in
// both Korean and English. `[pause short]` was not enough in English
// (re-measured 2026-11-03: 150–280 ms on Charon, 3 runs each); `[pause]` gave
// 410–830 ms in English and 600–720 ms in Korean. So every locale gets a
// `[pause]` after every comma (incl. 、，،) without changing the
// text shown in the UI or kept in history. Digit grouping ("1,000") is not a
// clause break, and text that already holds brackets is left alone so it is
// not misread as a pause tag.
function chirpInputWithCommaPauses(text) {
  const input = String(text || "").trim();
  if (input.includes("[") || input.includes("]")) return { text: input };
  const markup = input.replace(/(?<!\d)([,，、،])\s*(?=\S)|(?<=\d)([,，、،])(?!\d)\s*(?=\S)/gu,
    (_, a, b) => (a || b) + " [pause] ");
  if (markup === input) return { text: input };
  // Do not make a request that would exceed the provider's input cap solely
  // because the audio-only pause markers were added.
  return utf8Bytes(markup) <= MAX_GOOGLE_TTS_INPUT_BYTES ? { markup } : { text: input };
}
// GA returns `{ value, expires_at }` at the top level; the retired beta shape
// nested it under `client_secret`. Accept both so a response-shape change is
// not silently treated as an auth failure.
function realtimeClientSecret(payload) {
  const source = payload && payload.client_secret ? payload.client_secret : payload;
  const token = source && typeof source.value === "string" ? source.value : "";
  if (!token) return null;
  return { token, expiresAt: Number(source.expires_at || 0) };
}

function stripWavContainer(audio) {
  const source = Buffer.from(audio || []);
  if (source.length < 12 || source.subarray(0, 4).toString("ascii") !== "RIFF" ||
      source.subarray(8, 12).toString("ascii") !== "WAVE") {
    return source;
  }
  let offset = 12;
  while (offset + 8 <= source.length) {
    const id = source.subarray(offset, offset + 4).toString("ascii");
    const size = source.readUInt32LE(offset + 4);
    const dataStart = offset + 8;
    const dataEnd = dataStart + size;
    if (dataEnd > source.length) break;
    if (id === "data") return source.subarray(dataStart, dataEnd);
    offset = dataEnd + (size % 2);
  }
  return source;
}

// OpenAI's `speed` maps onto Chirp 3 HD pace control (0.25-2.0). 1.0 is left
// out so default requests stay byte-identical to the verified Korean route.
function chirpAudioConfig(body, format) {
  const config = format === "pcm"
    ? { audioEncoding: "LINEAR16", sampleRateHertz: 24000 }
    : { audioEncoding: "MP3" };
  const speed = Number(body && body.speed);
  if (Number.isFinite(speed) && speed > 0 && speed !== 1) {
    config.speakingRate = Math.min(2, Math.max(0.25, speed));
  }
  return config;
}

async function synthesizeChirpPiece(client, input, locale, voiceName, audioConfig, format) {
  const response = await client.request({
    url: GOOGLE_TTS_ENDPOINT,
    method: "POST",
    data: {
      input,
      voice: { languageCode: locale, name: voiceName },
      audioConfig,
    },
  });
  const encoded = response && response.data && response.data.audioContent;
  if (typeof encoded !== "string" || !encoded) {
    throw new Error("Google TTS returned no audio.");
  }
  const audio = Buffer.from(encoded, "base64");
  return format === "pcm" ? stripWavContainer(audio) : audio;
}

async function synthesizeChirp(body, locale, voiceNameOverride = null) {
  const input = String(body && body.input || "").trim();
  if (!input || input.length > MAX_TTS_INPUT_CHARS) {
    const error = new Error("Invalid TTS input.");
    error.statusCode = 400;
    throw error;
  }
  const format = requestedAudioFormat(body);
  if (!format) return null;
  const voiceName = voiceNameOverride || chirpVoiceForRequest(body, locale);
  const audioConfig = chirpAudioConfig(body, format);
  const client = await googleAuth.getClient();
  const markup = chirpMarkupForLocale(body, locale);
  if (markup) {
    const audio = await synthesizeChirpPiece(
      client, { markup }, locale, voiceName, audioConfig, format);
    return { format, voiceName, audio };
  }
  const spokenInput = locale === "ko-KR" ? koreanNumbersToWords(input) : input;
  const pieces = splitForGoogleTts(spokenInput);
  const audio = [];
  for (let i = 0; i < pieces.length; i++) {
    const speechInput = chirpInputWithCommaPauses(pieces[i]);
    // Raw PCM and MP3 frames both play back correctly when concatenated.
    audio.push(await synthesizeChirpPiece(
      client, speechInput, locale, voiceName, audioConfig, format));
  }
  return { format, voiceName, audio: Buffer.concat(audio) };
}

// Basic tier. WaveNet reads commas with a natural pause on its own, so plain
// text is sent as-is; only the app's explicit pause markup becomes SSML.
async function synthesizeWavenet(body, locale, voiceName) {
  const input = String(body && body.input || "").trim();
  if (!input || input.length > MAX_TTS_INPUT_CHARS) {
    const error = new Error("Invalid TTS input.");
    error.statusCode = 400;
    throw error;
  }
  const format = requestedAudioFormat(body);
  if (!format) return null;
  const audioConfig = chirpAudioConfig(body, format);
  const client = await googleAuth.getClient();
  const ssml = wavenetSsmlFromMarkup(chirpMarkupForLocale(body, locale));
  if (ssml) {
    const audio = await synthesizeChirpPiece(
      client, { ssml }, locale, voiceName, audioConfig, format);
    return { format, voiceName, audio };
  }
  const spokenInput = locale === "ko-KR" ? koreanNumbersToWords(input) : input;
  const audio = [];
  for (const piece of splitForGoogleTts(spokenInput)) {
    audio.push(await synthesizeChirpPiece(
      client, { text: piece }, locale, voiceName, audioConfig, format));
  }
  return { format, voiceName, audio: Buffer.concat(audio) };
}

// Basic first when asked for; any WaveNet failure falls back to Chirp so the
// user still hears the line.
async function synthesizeForTier(body, locale) {
  const wavenetVoice = voiceTierForRequest(body) === "basic"
    ? wavenetVoiceForRequest(body, locale)
    : null;
  if (wavenetVoice) {
    try {
      const synthesized = await synthesizeWavenet(body, locale, wavenetVoice);
      if (synthesized && synthesized.audio.length > 0) {
        return { ...synthesized, provider: "google-wavenet-" };
      }
    } catch (error) {
      if (Number(error && error.statusCode) === 400) throw error;
      functions.logger.warn("Google WaveNet TTS failed; using Chirp", {
        locale,
        message: error && error.message,
      });
    }
  }
  const synthesized = await synthesizeChirp(body, locale);
  return synthesized ? { ...synthesized, provider: "google-chirp3-hd-" } : null;
}

// ── 🌍 [OTHER-LANG] Languages outside the fixed table (2026-11-10) ─────────
// The app sends an ISO code (e.g. "th", "tr", "fil") for a "Other" chat
// language. The voice is looked up in Google's live voice list, so a language
// Google adds later works without a gateway change. Only when Google has no
// voice for it does the request fall through to the OpenAI route.
const GOOGLE_VOICES_ENDPOINT = "https://texttospeech.googleapis.com/v1/voices";
const GOOGLE_VOICE_LIST_TTL_MS = 24 * 60 * 60 * 1000;
const voiceListCache = { at: 0, voices: null, pending: null };

async function googleVoiceList() {
  const now = Date.now();
  if (voiceListCache.voices && now - voiceListCache.at < GOOGLE_VOICE_LIST_TTL_MS) {
    return voiceListCache.voices;
  }
  if (!voiceListCache.pending) {
    voiceListCache.pending = (async () => {
      const client = await googleAuth.getClient();
      const response = await client.request({ url: GOOGLE_VOICES_ENDPOINT, method: "GET" });
      const voices = (response && response.data && response.data.voices) || [];
      voiceListCache.voices = voices;
      voiceListCache.at = Date.now();
      return voices;
    })().finally(() => { voiceListCache.pending = null; });
  }
  return voiceListCache.pending;
}

// A bare ISO code that the fixed table does not cover. null otherwise.
function dynamicLanguageCode(body) {
  if (!body || typeof body !== "object") return null;
  if (String(body.instructions || "").trim()) return null;
  if (!requestedAudioFormat(body)) return null;
  const code = String(body.language || "").trim().toLowerCase();
  if (!/^[a-z]{2,3}$/.test(code)) return null;
  if (CHIRP_LOCALES.has(code)) return null;
  return code;
}

function voiceFamily(name) {
  if (name.includes("-Chirp3-HD-")) return "chirp";
  if (name.includes("-Wavenet-")) return "wavenet";
  if (name.includes("-Neural2-")) return "neural2";
  if (name.includes("-Standard-")) return "standard";
  return null;
}

// Picks one Google voice for [code]. Premium prefers Chirp 3 HD, basic prefers
// WaveNet; each falls back to whatever the language has. Gender follows the
// app's voice id, the same as the fixed table.
function pickGoogleVoice(voices, code, tier, gender) {
  const order = tier === "basic"
    ? ["wavenet", "standard", "neural2", "chirp"]
    : ["chirp", "wavenet", "neural2", "standard"];
  const wanted = gender === "male" ? "MALE" : "FEMALE";
  const matches = (voices || []).map(v => {
    const locale = (v.languageCodes || []).find(lc =>
      lc.toLowerCase() === code || lc.toLowerCase().startsWith(code + "-"));
    const family = voiceFamily(String(v.name || ""));
    return locale && family ? { locale, name: v.name, family, gender: v.ssmlGender } : null;
  }).filter(Boolean);
  for (const family of order) {
    const pool = matches.filter(m => m.family === family)
      .sort((a, b) => a.locale.localeCompare(b.locale) || a.name.localeCompare(b.name));
    if (pool.length === 0) continue;
    const locale = pool[0].locale;
    const sameLocale = pool.filter(m => m.locale === locale);
    if (family === "chirp") {
      const preferred = locale + "-Chirp3-HD-" +
        (gender === "male" ? CHIRP_MALE_VOICE : CHIRP_FEMALE_VOICE);
      const exact = sameLocale.find(m => m.name === preferred);
      if (exact) return exact;
    }
    return sameLocale.find(m => m.gender === wanted) || sameLocale[0];
  }
  return null;
}

async function tryProxyDynamicGoogleSpeech(req, res, body, code) {
  try {
    const voices = await googleVoiceList();
    const picked = pickGoogleVoice(
      voices, code, voiceTierForRequest(body), chirpGenderForRequest(body));
    if (!picked) {
      functions.logger.info("Google TTS has no voice; using OpenAI", { code });
      return false;
    }
    const synthesized = picked.family === "chirp"
      ? await synthesizeChirp(body, picked.locale, picked.name)
      : await synthesizeWavenet(body, picked.locale, picked.name);
    if (!synthesized || synthesized.audio.length === 0) return false;
    res.status(200);
    res.setHeader("cache-control", "no-store");
    res.setHeader("x-stealthvox-tts-provider",
      "google-" + picked.family + "-" + picked.locale.toLowerCase() + "-" +
        picked.name.split("-").pop().toLowerCase());
    res.setHeader("content-type", synthesized.format === "pcm"
      ? "audio/L16; rate=24000; channels=1"
      : "audio/mpeg");
    res.send(synthesized.audio);
    return true;
  } catch (error) {
    functions.logger.error("Google dynamic TTS failed; using OpenAI", {
      code,
      status: Number(error && error.statusCode) || 0,
      message: error && error.message,
    });
    return false;
  }
}

async function tryProxyChirpSpeech(req, res) {
  const body = req.body && typeof req.body === "object" ? req.body : null;
  if (!shouldUseChirp(body)) {
    const code = dynamicLanguageCode(body);
    return code ? tryProxyDynamicGoogleSpeech(req, res, body, code) : false;
  }
  const locale = chirpLocaleForRequest(body);
  try {
    const synthesized = await synthesizeForTier(body, locale);
    if (!synthesized || synthesized.audio.length === 0) return false;
    res.status(200);
    res.setHeader("cache-control", "no-store");
    res.setHeader(
      "x-stealthvox-tts-provider",
      synthesized.provider + locale.toLowerCase() + "-" +
        synthesized.voiceName.split("-").pop().toLowerCase()
    );
    res.setHeader(
      "content-type",
      synthesized.format === "pcm"
        ? "audio/L16; rate=24000; channels=1"
        : "audio/mpeg"
    );
    res.send(synthesized.audio);
    return true;
  } catch (error) {
    const status = Number(error && error.statusCode) || 502;
    functions.logger.error("Google Chirp TTS failed", {
      status,
      locale,
      message: error && error.message,
    });
    // Newly moved languages fall back to their previous OpenAI route while it
    // exists. Korean keeps its established behavior.
    if (locale !== "ko-KR" && status !== 400) return false;
    res.status(status).json({ error: { message: "Speech service unavailable" } });
    return true;
  }
}

// Korean is never sent to Gemini; a locale Gemini recently rejected is skipped.
function geminiLocaleAllowed(locale) {
  if (!locale || locale === "ko-KR") return false;
  const until = geminiUnsupportedLocales.get(locale);
  if (until === undefined) return true;
  if (until > Date.now()) return false;
  geminiUnsupportedLocales.delete(locale);
  return true;
}

function markGeminiLocaleUnsupported(locale) {
  geminiUnsupportedLocales.set(locale, Date.now() + GEMINI_UNSUPPORTED_TTL_MS);
}

function shouldUseGemini(body) {
  if (process.env.GEMINI_TTS_DISABLED === "1") return false;
  if (!body || typeof body !== "object") return false;
  const engine = String(body.engine || "").trim().toLowerCase();
  if (engine === "chirp") return false;
  // Expressive requests carry OpenAI-only `instructions`; Gemini does not read them.
  if (String(body.instructions || "").trim()) return false;
  const format = requestedAudioFormat(body);
  if (format !== "pcm" && format !== "mp3") return false;
  if (engine !== "gemini") {
    // Default routing for callers that did not ask for an engine.
    if (process.env.GEMINI_TTS_DEFAULT === "0") return false;
    // The cheaper WaveNet tier stays where it is.
    if (voiceTierForRequest(body) === "basic") return false;
    // Gemini has no numeric speed (e.g. shadowing's chosen pace); only Chirp
    // honors it, so such requests stay on Chirp unless a style prompt is sent.
    const speed = Number(body.speed);
    if (Number.isFinite(speed) && speed > 0 && speed !== 1 &&
        !String(body.style_prompt || "").trim()) return false;
  }
  return geminiLocaleAllowed(chirpLocaleForRequest(body));
}

function geminiPromptForRequest(body) {
  const prompt = String(body && body.style_prompt || "").trim();
  return prompt ? prompt.slice(0, GEMINI_MAX_PROMPT_CHARS) : "";
}

// The app writes `unit [pause short] unit ...` for Chirp. Gemini reads each
// unit on its own and the gap between units is real silence.
function geminiPiecesForRequest(body) {
  const source = chirpMarkupForRequest(body) || String(body && body.input || "");
  const parts = source.split(/\s*\[pause(?:\s+(short|long))?\]\s*/u);
  const pieces = [];
  // split() with one capture group yields: text, tag, text, tag, ... text
  for (let i = 0; i < parts.length; i += 2) {
    const text = String(parts[i] || "").trim();
    if (!text) continue;
    const tag = parts[i + 1];
    pieces.push({ text, pauseMs: GEMINI_PAUSE_MS[tag || "medium"] });
  }
  if (pieces.length > 0) pieces[pieces.length - 1].pauseMs = 0;
  return pieces;
}

function silencePcm(ms) {
  const samples = Math.round(GEMINI_SAMPLE_RATE * ms / 1000);
  return Buffer.alloc(samples * 2);
}

function geminiVoiceForRequest(body, locale) {
  return {
    languageCode: locale,
    name: chirpGenderForRequest(body) === "male" ? GEMINI_MALE_VOICE : GEMINI_FEMALE_VOICE,
    modelName: GEMINI_TTS_MODEL,
  };
}

async function synthesizeGeminiPiece(client, text, prompt, voice, format) {
  const audioConfig = format === "mp3"
    ? { audioEncoding: "MP3" }
    : { audioEncoding: "LINEAR16", sampleRateHertz: GEMINI_SAMPLE_RATE };
  const response = await client.request({
    url: GOOGLE_TTS_ENDPOINT,
    method: "POST",
    data: {
      input: prompt ? { text, prompt } : { text },
      voice,
      audioConfig,
    },
  });
  const encoded = response && response.data && response.data.audioContent;
  if (typeof encoded !== "string" || !encoded) {
    throw new Error("Gemini TTS returned no audio.");
  }
  const bytes = Buffer.from(encoded, "base64");
  return format === "mp3" ? bytes : stripWavContainer(bytes);
}

async function synthesizeGemini(body, locale) {
  const format = requestedAudioFormat(body);
  const pieces = geminiPiecesForRequest(body);
  if (pieces.length === 0 || pieces.length > GEMINI_MAX_PIECES) return null;
  // Silence between pieces can only be spliced into raw PCM. An MP3 request
  // with pause tags stays on Chirp, which writes the pauses itself.
  if (format === "mp3" && pieces.length > 1) return null;
  const prompt = geminiPromptForRequest(body);
  const voice = geminiVoiceForRequest(body, locale);
  const client = await googleAuth.getClient();
  const audio = await Promise.all(pieces.map(
    piece => synthesizeGeminiPiece(client, piece.text, prompt, voice, format)));
  const parts = [];
  audio.forEach((pcm, i) => {
    parts.push(pcm);
    if (pieces[i].pauseMs > 0) parts.push(silencePcm(pieces[i].pauseMs));
  });
  return { format, voiceName: voice.name, audio: Buffer.concat(parts) };
}

// Returns false on any problem so the caller continues to the Chirp route.
async function tryProxyGeminiSpeech(req, res) {
  const body = req.body && typeof req.body === "object" ? req.body : null;
  if (!shouldUseGemini(body)) return false;
  const locale = chirpLocaleForRequest(body);
  try {
    const synthesized = await synthesizeGemini(body, locale);
    if (!synthesized || synthesized.audio.length === 0) return false;
    res.status(200);
    res.setHeader("cache-control", "no-store");
    res.setHeader(
      "x-stealthvox-tts-provider",
      "google-gemini-tts-" + locale.toLowerCase() + "-" +
        synthesized.voiceName.toLowerCase()
    );
    res.setHeader(
      "content-type",
      synthesized.format === "mp3"
        ? "audio/mpeg"
        : "audio/L16; rate=24000; channels=1"
    );
    res.send(synthesized.audio);
    return true;
  } catch (error) {
    const status = Number(
      (error && error.response && error.response.status) ||
      (error && error.status) || (error && error.statusCode)) || 0;
    const message = String(error && error.message || "");
    // A 400/404 that names the language, voice or model means Gemini does not
    // have this locale. Other errors (quota, outage, bad input) are not cached.
    if ((status === 400 || status === 404) &&
        /language|locale|voice|model/i.test(message)) {
      markGeminiLocaleUnsupported(locale);
    }
    functions.logger.error("Gemini TTS failed; falling back to Chirp", {
      locale,
      status,
      message,
    });
    return false;
  }
}

function proxyOpenAiRequest(req, res, upstreamPath, apiKey, bodyOverride = null) {
  const headers = {
    authorization: "Bearer " + apiKey,
    accept: String(req.get("accept") || "*/*"),
    "content-type": String(req.get("content-type") || "application/json"),
    "user-agent": "StealthVox-AI-Gateway/1.0",
  };
  if (req.get("openai-beta")) headers["openai-beta"] = req.get("openai-beta");
  const originalUrl = String(req.originalUrl || req.url || "");
  const queryIndex = originalUrl.indexOf("?");
  const query = queryIndex >= 0 ? originalUrl.slice(queryIndex) : "";
  const body = req.method === "GET" || req.method === "HEAD"
    ? null
    : bodyOverride
      ? Buffer.from(JSON.stringify(bodyOverride))
      : (req.rawBody || Buffer.from(JSON.stringify(req.body || {})));
  if (body) headers["content-length"] = String(body.length);

  const upstream = https.request({
    hostname: "api.openai.com",
    port: 443,
    method: req.method,
    path: upstreamPath + query,
    headers,
  }, upstreamRes => {
    res.status(upstreamRes.statusCode || 502);
    for (const [name, value] of Object.entries(upstreamRes.headers)) {
      if (value != null && !["connection", "transfer-encoding"].includes(name)) {
        res.setHeader(name, value);
      }
    }
    res.setHeader("cache-control", "no-store");
    upstreamRes.pipe(res);
  });
  upstream.setTimeout(115000, () => upstream.destroy(new Error("upstream timeout")));
  upstream.on("error", error => {
    functions.logger.error("openAiProxy upstream failed", {
      path: upstreamPath,
      error: error && error.message,
    });
    if (!res.headersSent) res.status(502).json({ error: { message: "AI service unavailable" } });
    else res.end();
  });
  if (body) upstream.end(body);
  else upstream.end();
}

const mintAiGatewaySession = onCall({
  region: REGION,
  enforceAppCheck: true,
  secrets: [gatewaySigningSecret],
}, async request => {
  const caller = requireVerifiedCaller(request);
  const access = await requireAiAccess(request, caller);
  const now = Math.floor(Date.now() / 1000);
  const secret = gatewaySigningSecret.value();
  if (!secret) throw callableError("failed-precondition", "Gateway is not configured.");
  // 공부방 체험의 토큰은 체험이 끝나는 시각을 넘지 않는다. 2시간짜리를 주면
  // 5분 체험이 2시간 무료 AI가 된다.
  const exp = access.untilMs
    ? Math.min(now + GATEWAY_TOKEN_TTL_SECONDS, Math.floor(access.untilMs / 1000))
    : now + GATEWAY_TOKEN_TTL_SECONDS;
  return {
    token: signGatewayToken({
      aud: GATEWAY_AUDIENCE,
      uid: caller.uid,
      appId: caller.appId,
      access: access.reason,
      iat: now,
      exp,
      nonce: crypto.randomBytes(12).toString("base64url"),
    }, secret),
    expiresAt: exp,
  };
});

const mintDeepgramToken = onCall({
  region: REGION,
  enforceAppCheck: true,
  secrets: [deepgramApiKey],
}, async request => {
  const caller = requireVerifiedCaller(request);
  await requireAiAccess(request, caller);
  const key = deepgramApiKey.value();
  if (!key) throw callableError("failed-precondition", "Deepgram is not configured.");
  const response = await fetch("https://api.deepgram.com/v1/auth/grant", {
    method: "POST",
    headers: {
      Authorization: "Token " + key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ ttl_seconds: DEEPGRAM_TOKEN_TTL_SECONDS }),
  });
  if (!response.ok) {
    functions.logger.error("Deepgram token grant failed", { status: response.status });
    throw callableError("unavailable", "Speech service authentication failed.");
  }
  const payload = await response.json();
  if (!payload.access_token) throw callableError("data-loss", "Speech token missing.");
  return {
    token: payload.access_token,
    expiresIn: Number(payload.expires_in || DEEPGRAM_TOKEN_TTL_SECONDS),
  };
});

const mintOpenAiRealtimeToken = onCall({
  region: REGION,
  enforceAppCheck: true,
  secrets: [openAiApiKey],
}, async request => {
  const caller = requireVerifiedCaller(request);
  await requireAiAccess(request, caller);
  const key = openAiApiKey.value();
  if (!key) throw callableError("failed-precondition", "OpenAI is not configured.");
  // GA endpoint. The beta `/v1/realtime/transcription_sessions` returns 404,
  // and the app already speaks the GA protocol (`session.type: transcription`).
  const response = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ session: { type: "transcription" } }),
  });
  const payload = await response.json().catch(() => ({}));
  const minted = realtimeClientSecret(payload);
  if (!response.ok || !minted) {
    functions.logger.error("OpenAI realtime token mint failed", {
      status: response.status,
      message: payload && payload.error && payload.error.message,
    });
    throw callableError("unavailable", "Realtime speech authentication failed.");
  }
  return minted;
});

// 게이트웨이 토큰은 2시간 유효하므로 차단은 요청마다 다시 본다(15초 캐시).
const proxyIsBlocked = createBlockedCache({
  onError: err => functions.logger.warn("openAiProxy block check failed", { message: err.message }),
});

const openAiProxy = functions
  .region(REGION)
  .runWith({
    timeoutSeconds: 120,
    memory: "1GB",
    secrets: [openAiApiKey, gatewaySigningSecret],
  })
  .https.onRequest(async (req, res) => {
    if (req.method === "OPTIONS") {
      res.set("Access-Control-Allow-Origin", "*");
      res.set("Access-Control-Allow-Headers", "Authorization, Content-Type, OpenAI-Beta");
      res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      res.status(204).send("");
      return;
    }
    const token = bearerToken(req);
    const secret = gatewaySigningSecret.value();
    const identity = secret ? verifyGatewayToken(token, secret) : null;
    if (!identity) {
      res.status(401).json({ error: { message: "Unauthorized" } });
      return;
    }
    if (await proxyIsBlocked(admin.firestore(), identity.uid)) {
      res.set("Access-Control-Allow-Origin", "*");
      res.status(403).json({ error: { message: "This account is restricted." } });
      return;
    }
    const path = normalizedProxyPath(req);
    const isSpeech = req.method === "POST" && path === "/v1/audio/speech";
    if (isSpeech && await tryProxyGeminiSpeech(req, res)) {
      return;
    }
    if (isSpeech && await tryProxyChirpSpeech(req, res)) {
      return;
    }
    const upstreamPath = OPENAI_ROUTES.get(req.method + " " + path);
    if (!upstreamPath) {
      res.status(404).json({ error: { message: "Unsupported AI route" } });
      return;
    }
    res.set("Access-Control-Allow-Origin", "*");
    const speechBody = isSpeech && req.body && typeof req.body === "object"
      ? openAiSpeechBody(req.body)
      : null;
    proxyOpenAiRequest(req, res, upstreamPath, openAiApiKey.value(), speechBody);
  });

module.exports = {
  GATEWAY_AUDIENCE,
  GATEWAY_TOKEN_TTL_SECONDS,
  signGatewayToken,
  verifyGatewayToken,
  containsKorean,
  requestedAudioFormat,
  stripWavContainer,
  realtimeClientSecret,
  chirpLocaleForRequest,
  chirpVoiceForRequest,
  shouldUseChirp,
  shouldUseGemini,
  geminiLocaleAllowed,
  markGeminiLocaleUnsupported,
  geminiPiecesForRequest,
  geminiPromptForRequest,
  geminiVoiceForRequest,
  silencePcm,
  openAiSpeechBody,
  splitForGoogleTts,
  chirpAudioConfig,
  chirpMarkupForRequest,
  chirpMarkupForLocale,
  koreanNumbersToWords,
  sinoKorean,
  chirpInputWithCommaPauses,
  voiceTierForRequest,
  wavenetVoiceForRequest,
  dynamicLanguageCode,
  pickGoogleVoice,
  wavenetSsmlFromMarkup,
  mintAiGatewaySession,
  mintDeepgramToken,
  mintOpenAiRealtimeToken,
  openAiProxy,
};
