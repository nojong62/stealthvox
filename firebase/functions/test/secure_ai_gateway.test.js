const test = require("node:test");
const assert = require("node:assert/strict");

const {
  GATEWAY_AUDIENCE,
  GATEWAY_TOKEN_TTL_SECONDS,
  signGatewayToken,
  verifyGatewayToken,
  containsKorean,
  requestedAudioFormat,
  stripWavContainer,
  chirpLocaleForRequest,
  chirpVoiceForRequest,
  shouldUseChirp,
  openAiSpeechBody,
  splitForGoogleTts,
  chirpAudioConfig,
  chirpMarkupForRequest,
  koreanChirpInputWithOpeningCommaPause,
  realtimeClientSecret,
} = require("../secure_ai_gateway");

test("realtime client secret reads the GA shape and the retired beta shape", () => {
  assert.deepEqual(
    realtimeClientSecret({ value: "ek_ga", expires_at: 1700 }),
    { token: "ek_ga", expiresAt: 1700 },
  );
  assert.deepEqual(
    realtimeClientSecret({ client_secret: { value: "ek_beta", expires_at: 1800 } }),
    { token: "ek_beta", expiresAt: 1800 },
  );
  assert.equal(realtimeClientSecret({ error: { message: "nope" } }), null);
  assert.equal(realtimeClientSecret(null), null);
});

function claims(overrides = {}) {
  return {
    aud: GATEWAY_AUDIENCE,
    uid: "user-1",
    appId: "app-1",
    iat: 1000,
    exp: 1000 + GATEWAY_TOKEN_TTL_SECONDS,
    nonce: "nonce",
    ...overrides,
  };
}

test("valid gateway token verifies", () => {
  const token = signGatewayToken(claims(), "secret");
  assert.equal(verifyGatewayToken(token, "secret", 1001).uid, "user-1");
});

test("tampered gateway token is rejected", () => {
  const token = signGatewayToken(claims(), "secret");
  const [payload, signature] = token.split(".");
  const tampered = Buffer.from(JSON.stringify(claims({ uid: "attacker" })))
    .toString("base64url") + "." + signature;
  assert.equal(verifyGatewayToken(tampered, "secret", 1001), null);
  assert.notEqual(payload, tampered.split(".")[0]);
});

test("expired and overlong gateway tokens are rejected", () => {
  const expired = signGatewayToken(claims({ exp: 1001 }), "secret");
  assert.equal(verifyGatewayToken(expired, "secret", 1001), null);
  const overlong = signGatewayToken(
    claims({ exp: 1000 + GATEWAY_TOKEN_TTL_SECONDS + 1 }),
    "secret",
  );
  assert.equal(verifyGatewayToken(overlong, "secret", 1001), null);
});

test("Korean TTS routing accepts Korean and preserves other languages", () => {
  assert.equal(containsKorean("안녕하세요"), true);
  assert.equal(containsKorean("hello world"), false);
  assert.equal(requestedAudioFormat({ response_format: "pcm" }), "pcm");
  assert.equal(requestedAudioFormat({ response_format: "mp3" }), "mp3");
  assert.equal(requestedAudioFormat({ response_format: "wav" }), null);
});


test("Chirp voices keep Circle Talk female and Scenario Talk male in every locale", () => {
  assert.equal(chirpVoiceForRequest({ voice: "shimmer" }, "ko-KR"), "ko-KR-Chirp3-HD-Aoede");
  assert.equal(chirpVoiceForRequest({ voice: "echo" }, "ko-KR"), "ko-KR-Chirp3-HD-Charon");
  assert.equal(chirpVoiceForRequest({ voice: "shimmer" }, "en-US"), "en-US-Chirp3-HD-Aoede");
  assert.equal(chirpVoiceForRequest({ voice: "echo" }, "cmn-CN"), "cmn-CN-Chirp3-HD-Charon");
  assert.equal(chirpVoiceForRequest({ voice: "google-female" }, "ja-JP"), "ja-JP-Chirp3-HD-Aoede");
  assert.equal(chirpVoiceForRequest({ voice: "google-male" }, "fr-FR"), "fr-FR-Chirp3-HD-Charon");
  assert.equal(chirpVoiceForRequest({ voice: "google-ko-male" }, "ko-KR"), "ko-KR-Chirp3-HD-Charon");
  for (const voice of ["verse", "onyx", "ash", "cedar", "ballad", "fable"]) {
    assert.equal(chirpVoiceForRequest({ voice }, "de-DE"), "de-DE-Chirp3-HD-Charon", voice);
  }
  for (const voice of ["nova", "coral", "marin", "sage", "alloy", "unknown"]) {
    assert.equal(chirpVoiceForRequest({ voice }, "it-IT"), "it-IT-Chirp3-HD-Aoede", voice);
  }
});

test("Chirp locale: Hangul first, then the app's language, then single-language scripts", () => {
  assert.equal(chirpLocaleForRequest({ input: "안녕하세요", language: "en" }), "ko-KR");
  assert.equal(chirpLocaleForRequest({ input: "Hola", language: "es" }), "es-ES");
  assert.equal(chirpLocaleForRequest({ input: "Hallo", language: "nl-NL" }), "nl-NL");
  assert.equal(chirpLocaleForRequest({ input: "Hello", language: "English" }), "en-US");
  assert.equal(chirpLocaleForRequest({ input: "你好", language: "zh" }), "cmn-CN");
  assert.equal(chirpLocaleForRequest({ input: "こんにちは" }), "ja-JP");
  assert.equal(chirpLocaleForRequest({ input: "नमस्ते" }), "hi-IN");
  assert.equal(chirpLocaleForRequest({ input: "Привет" }), "ru-RU");
  assert.equal(chirpLocaleForRequest({ input: "Hello" }), null);
  assert.equal(chirpLocaleForRequest({ input: "你好" }), null);
  assert.equal(chirpLocaleForRequest({ input: "Hello", language: "xx" }), null);
});

test("expressive requests stay on OpenAI", () => {
  assert.equal(shouldUseChirp({ input: "Hello", language: "en", voice: "nova" }), true);
  assert.equal(
    shouldUseChirp({ input: "Hello", language: "en", voice: "nova", instructions: "warm" }),
    false,
  );
  assert.equal(
    shouldUseChirp({ input: "안녕", voice: "nova", instructions: "warm" }),
    false,
  );
  assert.equal(
    shouldUseChirp({ input: "Hello", language: "en", response_format: "wav" }),
    false,
  );
});

test("OpenAI fallback body drops language and provider-neutral voices", () => {
  assert.deepEqual(
    openAiSpeechBody({
      model: "tts-1", input: "Hi", voice: "google-male", language: "en",
      markup: "Hi [pause]",
    }),
    { model: "tts-1", input: "Hi", voice: "echo" },
  );
  assert.deepEqual(
    openAiSpeechBody({ input: "Hi", voice: "nova", instructions: "warm" }),
    { input: "Hi", voice: "nova", instructions: "warm" },
  );
});

test("Google TTS input is split by UTF-8 bytes, not characters", () => {
  assert.deepEqual(splitForGoogleTts("짧은 문장."), ["짧은 문장."]);
  const korean = "가".repeat(1600) + ". " + "나".repeat(1600) + ".";
  const pieces = splitForGoogleTts(korean);
  assert.equal(pieces.length, 2);
  for (const piece of pieces) assert.ok(Buffer.byteLength(piece, "utf8") <= 5000);
  assert.equal(pieces.join(" "), korean);
  const unbroken = "가".repeat(4000);
  const cut = splitForGoogleTts(unbroken);
  assert.equal(cut.join(""), unbroken);
  for (const piece of cut) assert.ok(Buffer.byteLength(piece, "utf8") <= 5000);
});

test("Korean TTS pauses after the first opening comma", () => {
  assert.deepEqual(
    koreanChirpInputWithOpeningCommaPause("네, 기본 포장은 무료예요."),
    { markup: "네, [pause short] 기본 포장은 무료예요." },
  );
  assert.deepEqual(
    koreanChirpInputWithOpeningCommaPause("회원님, PT 시간 변경을 도와드릴게요."),
    { markup: "회원님, [pause short] PT 시간 변경을 도와드릴게요." },
  );
  assert.deepEqual(
    koreanChirpInputWithOpeningCommaPause("기본 포장은 무료예요."),
    { text: "기본 포장은 무료예요." },
  );
  assert.deepEqual(
    koreanChirpInputWithOpeningCommaPause("오늘은 날씨가 좋고, 산책하기 좋아요."),
    { markup: "오늘은 날씨가 좋고, [pause short] 산책하기 좋아요." },
  );
});

test("LINEAR16 WAV container is removed before PCM playback", () => {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0, "ascii");
  header.writeUInt32LE(40, 4);
  header.write("WAVE", 8, "ascii");
  header.write("fmt ", 12, "ascii");
  header.writeUInt32LE(16, 16);
  header.write("data", 36, "ascii");
  header.writeUInt32LE(4, 40);
  const pcm = Buffer.from([1, 2, 3, 4]);
  assert.deepEqual(stripWavContainer(Buffer.concat([header, pcm])), pcm);
  assert.deepEqual(stripWavContainer(pcm), pcm);
});

test("OpenAI speed becomes Chirp pace only when it changes the pace", () => {
  assert.deepEqual(chirpAudioConfig({ speed: 1 }, "mp3"), { audioEncoding: "MP3" });
  assert.deepEqual(chirpAudioConfig({}, "pcm"), { audioEncoding: "LINEAR16", sampleRateHertz: 24000 });
  assert.equal(chirpAudioConfig({ speed: 0.8 }, "mp3").speakingRate, 0.8);
  assert.equal(chirpAudioConfig({ speed: 4 }, "mp3").speakingRate, 2);
  assert.equal(chirpAudioConfig({ speed: 0.1 }, "mp3").speakingRate, 0.25);
});

test("app-written pause markup is used only when it fits one request", () => {
  assert.equal(
    chirpMarkupForRequest({ markup: " Hi, [pause long] there. " }),
    "Hi, [pause long] there.",
  );
  assert.equal(chirpMarkupForRequest({ input: "Hi" }), null);
  assert.equal(chirpMarkupForRequest({ markup: "가".repeat(1700) }), null);
});
