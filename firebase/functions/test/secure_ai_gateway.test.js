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
  chirpInputWithCommaPauses,
  realtimeClientSecret,
  voiceTierForRequest,
  wavenetVoiceForRequest,
  wavenetSsmlFromMarkup,
} = require("../secure_ai_gateway");

test("voice tier: only an explicit basic leaves Chirp", () => {
  assert.equal(voiceTierForRequest({ voice_tier: "basic" }), "basic");
  assert.equal(voiceTierForRequest({ voice_tier: " BASIC " }), "basic");
  assert.equal(voiceTierForRequest({ voice_tier: "premium" }), "premium");
  assert.equal(voiceTierForRequest({}), "premium");
  assert.equal(voiceTierForRequest(null), "premium");
});

test("WaveNet voice keeps the requested gender in every app locale", () => {
  const locales = ["ko-KR", "en-US", "en-GB", "ja-JP", "cmn-CN", "es-ES", "fr-FR",
    "de-DE", "hi-IN", "ru-RU", "pt-BR", "it-IT", "nl-NL", "vi-VN", "id-ID"];
  for (const locale of locales) {
    const female = wavenetVoiceForRequest({ voice: "shimmer" }, locale);
    const male = wavenetVoiceForRequest({ voice: "echo" }, locale);
    assert.match(female, new RegExp("^" + locale + "-Wavenet-[A-Z]$"));
    assert.match(male, new RegExp("^" + locale + "-Wavenet-[A-Z]$"));
    assert.notEqual(female, male);
  }
  assert.equal(wavenetVoiceForRequest({ voice: "shimmer" }, "ko-KR"), "ko-KR-Wavenet-A");
  assert.equal(wavenetVoiceForRequest({ voice: "google-male" }, "ko-KR"), "ko-KR-Wavenet-C");
  assert.equal(wavenetVoiceForRequest({ voice: "shimmer" }, "xx-XX"), null);
});

test("WaveNet SSML turns Chirp pause tags into breaks and escapes text", () => {
  assert.equal(
    wavenetSsmlFromMarkup("Yes, [pause short] Mom [pause] I'm home [pause long] ok"),
    "<speak>Yes, <break time=\"250ms\"/> Mom <break time=\"600ms\"/> I&apos;m home " +
      "<break time=\"1000ms\"/> ok</speak>");
  assert.equal(
    wavenetSsmlFromMarkup("a < b & c"),
    "<speak>a &lt; b &amp; c</speak>");
  assert.equal(wavenetSsmlFromMarkup(""), null);
  assert.equal(wavenetSsmlFromMarkup(null), null);
  assert.equal(wavenetSsmlFromMarkup("가".repeat(1700)), null);
});

test("OpenAI fallback body drops voice_tier", () => {
  const sanitized = openAiSpeechBody({ input: "hi", voice: "shimmer", voice_tier: "basic" });
  assert.equal("voice_tier" in sanitized, false);
});

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
  assert.equal(chirpVoiceForRequest({ voice: "shimmer" }, "ko-KR"), "ko-KR-Chirp3-HD-Leda");
  assert.equal(chirpVoiceForRequest({ voice: "echo" }, "ko-KR"), "ko-KR-Chirp3-HD-Charon");
  assert.equal(chirpVoiceForRequest({ voice: "shimmer" }, "en-US"), "en-US-Chirp3-HD-Leda");
  assert.equal(chirpVoiceForRequest({ voice: "echo" }, "cmn-CN"), "cmn-CN-Chirp3-HD-Charon");
  assert.equal(chirpVoiceForRequest({ voice: "google-female" }, "ja-JP"), "ja-JP-Chirp3-HD-Leda");
  assert.equal(chirpVoiceForRequest({ voice: "google-male" }, "fr-FR"), "fr-FR-Chirp3-HD-Charon");
  assert.equal(chirpVoiceForRequest({ voice: "google-ko-male" }, "ko-KR"), "ko-KR-Chirp3-HD-Charon");
  for (const voice of ["verse", "onyx", "ash", "cedar", "ballad", "fable"]) {
    assert.equal(chirpVoiceForRequest({ voice }, "de-DE"), "de-DE-Chirp3-HD-Charon", voice);
  }
  for (const voice of ["nova", "coral", "marin", "sage", "alloy", "unknown"]) {
    assert.equal(chirpVoiceForRequest({ voice }, "it-IT"), "it-IT-Chirp3-HD-Leda", voice);
  }
});

test("Chirp locale: Hangul first, then the app's language, then single-language scripts", () => {
  assert.equal(chirpLocaleForRequest({ input: "안녕하세요", language: "en" }), "ko-KR");
  assert.equal(chirpLocaleForRequest({ input: "Hola", language: "es" }), "es-ES");
  assert.equal(chirpLocaleForRequest({ input: "Hallo", language: "nl-NL" }), "nl-NL");
  assert.equal(chirpLocaleForRequest({ input: "Hello", language: "English" }), "en-US");
  assert.equal(chirpLocaleForRequest({ input: "Hello", language: "en-GB" }), "en-GB");
  assert.equal(chirpLocaleForRequest({ input: "Hello", language: "en_gb" }), "en-GB");
  assert.equal(chirpLocaleForRequest({ input: "Hello", language: "en-US" }), "en-US");
  assert.equal(chirpVoiceForRequest({ voice: "google-female" }, "en-GB"), "en-GB-Chirp3-HD-Leda");
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

test("Chirp TTS pauses after every comma", () => {
  assert.deepEqual(
    chirpInputWithCommaPauses("네, 기본 포장은 무료예요."),
    { markup: "네, [pause] 기본 포장은 무료예요." },
  );
  assert.deepEqual(
    chirpInputWithCommaPauses("회원님,PT 시간 변경을 도와드릴게요."),
    { markup: "회원님, [pause] PT 시간 변경을 도와드릴게요." },
  );
  assert.deepEqual(
    chirpInputWithCommaPauses("기본 포장은 무료예요."),
    { text: "기본 포장은 무료예요." },
  );
  assert.deepEqual(
    chirpInputWithCommaPauses("날씨가 좋고, 바람도 시원하고, 산책하기 좋아요."),
    { markup: "날씨가 좋고, [pause] 바람도 시원하고, [pause] 산책하기 좋아요." },
  );
});

test("Comma pause applies to English and CJK commas too", () => {
  assert.deepEqual(
    chirpInputWithCommaPauses("Yes, Mom. Still, I was wrong."),
    { markup: "Yes, [pause] Mom. Still, [pause] I was wrong." },
  );
  assert.deepEqual(
    chirpInputWithCommaPauses("It costs 1,000 dollars."),
    { text: "It costs 1,000 dollars." },
  );
  assert.deepEqual(
    chirpInputWithCommaPauses("はい、わかりました。"),
    { markup: "はい、 [pause] わかりました。" },
  );
  assert.deepEqual(
    chirpInputWithCommaPauses("好的，没问题。"),
    { markup: "好的， [pause] 没问题。" },
  );
});

test("Comma pause skips digit grouping and bracketed text", () => {
  assert.deepEqual(
    chirpInputWithCommaPauses("가격은 1,000원이에요."),
    { text: "가격은 1,000원이에요." },
  );
  assert.deepEqual(
    chirpInputWithCommaPauses("3, 4번 중에 고르세요."),
    { markup: "3, [pause] 4번 중에 고르세요." },
  );
  assert.deepEqual(
    chirpInputWithCommaPauses("[참고] 네, 좋아요."),
    { text: "[참고] 네, 좋아요." },
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
