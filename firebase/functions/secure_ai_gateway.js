const crypto = require("crypto");
const https = require("https");
const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");
const { onCall } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { GoogleAuth } = require("google-auth-library");
const { claimTrialGrant, resolveAiAccess } = require("./ai_access");
const { createBlockedCache, readBlocked } = require("./block_check");

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
const CHIRP_MALE_VOICE = "Charon";
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
  const provider = request.auth.token && request.auth.token.firebase &&
    request.auth.token.firebase.sign_in_provider;
  return {
    uid: String(request.auth.uid),
    appId: String(request.app.appId),
    isAnonymous: provider === "anonymous",
  };
}

async function requireAiAccess(request, caller) {
  const access = await resolveAiAccess({
    db: admin.firestore(),
    uid: caller.uid,
    isAnonymous: caller.isAnonymous,
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
  const requested = String(body && body.language || "").trim().toLowerCase()
    .split(/[-_]/)[0];
  if (CHIRP_LOCALES.has(requested)) return CHIRP_LOCALES.get(requested);
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
  return locale + "-Chirp3-HD-" + (chirpGenderForRequest(body) === "male"
    ? CHIRP_MALE_VOICE
    : CHIRP_FEMALE_VOICE);
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

// At the start of a Korean reply, a vocative or lead-in ending in a comma can
// run into the next word ("회원님,PT 시간..."). Add a short Chirp pause after
// the first opening comma without changing the text shown in the UI or kept in
// history. This is intentionally limited to the opening 80 characters so a
// later comma in a longer reply retains the model's natural pacing.
function koreanChirpInputWithOpeningCommaPause(text) {
  const input = String(text || "").trim();
  const match = /^([^,，\n]{1,80}[,，])(?=\s*\S)/u.exec(input);
  if (!match) return { text: input };

  const markup = input.slice(0, match[0].length) +
    " [pause short]" + input.slice(match[0].length);
  // Do not make a request that would exceed the provider's input cap solely
  // because the audio-only pause marker was added.
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

async function synthesizeChirp(body, locale) {
  const input = String(body && body.input || "").trim();
  if (!input || input.length > MAX_TTS_INPUT_CHARS) {
    const error = new Error("Invalid TTS input.");
    error.statusCode = 400;
    throw error;
  }
  const format = requestedAudioFormat(body);
  if (!format) return null;
  const voiceName = chirpVoiceForRequest(body, locale);
  const audioConfig = chirpAudioConfig(body, format);
  const client = await googleAuth.getClient();
  const markup = chirpMarkupForRequest(body);
  if (markup) {
    const audio = await synthesizeChirpPiece(
      client, { markup }, locale, voiceName, audioConfig, format);
    return { format, voiceName, audio };
  }
  const pieces = splitForGoogleTts(input);
  const audio = [];
  for (let i = 0; i < pieces.length; i++) {
    const speechInput = i === 0 && locale === "ko-KR"
      ? koreanChirpInputWithOpeningCommaPause(pieces[i])
      : { text: pieces[i] };
    // Raw PCM and MP3 frames both play back correctly when concatenated.
    audio.push(await synthesizeChirpPiece(
      client, speechInput, locale, voiceName, audioConfig, format));
  }
  return { format, voiceName, audio: Buffer.concat(audio) };
}

async function tryProxyChirpSpeech(req, res) {
  const body = req.body && typeof req.body === "object" ? req.body : null;
  if (!shouldUseChirp(body)) return false;
  const locale = chirpLocaleForRequest(body);
  try {
    const synthesized = await synthesizeChirp(body, locale);
    if (!synthesized || synthesized.audio.length === 0) return false;
    res.status(200);
    res.setHeader("cache-control", "no-store");
    res.setHeader(
      "x-stealthvox-tts-provider",
      "google-chirp3-hd-" + locale.toLowerCase() + "-" +
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
  return {
    token: signGatewayToken({
      aud: GATEWAY_AUDIENCE,
      uid: caller.uid,
      appId: caller.appId,
      access: access.reason,
      iat: now,
      exp: now + GATEWAY_TOKEN_TTL_SECONDS,
      nonce: crypto.randomBytes(12).toString("base64url"),
    }, secret),
    expiresAt: now + GATEWAY_TOKEN_TTL_SECONDS,
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

const claimAiTrial = onCall({
  region: REGION,
  enforceAppCheck: true,
}, async request => {
  const caller = requireVerifiedCaller(request);
  if (!caller.isAnonymous) {
    throw callableError("failed-precondition", "Trial access is available only before account registration.");
  }
  if (await readBlocked(admin.firestore(), caller.uid)) {
    throw callableError("permission-denied", "This account is restricted.");
  }
  const installationId = String(request.data && request.data.installationId || "").trim();
  if (!/^[A-Za-z0-9_-]{10,200}$/.test(installationId)) {
    throw callableError("invalid-argument", "A valid installation id is required.");
  }
  const result = await claimTrialGrant({
    db: admin.firestore(),
    uid: caller.uid,
    installationHash: crypto.createHash("sha256").update(installationId).digest("hex"),
  });
  if (!result.granted) {
    throw callableError("permission-denied", "This device has already used its trial.");
  }
  return { granted: true, expiresAt: result.expiresAtMs };
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
  openAiSpeechBody,
  splitForGoogleTts,
  chirpAudioConfig,
  chirpMarkupForRequest,
  koreanChirpInputWithOpeningCommaPause,
  mintAiGatewaySession,
  mintDeepgramToken,
  mintOpenAiRealtimeToken,
  claimAiTrial,
  openAiProxy,
};
