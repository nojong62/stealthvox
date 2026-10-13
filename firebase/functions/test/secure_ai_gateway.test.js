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
  koreanChirpVoiceForRequest,
  koreanChirpInputWithOpeningCommaPause,
} = require("../secure_ai_gateway");

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


test("Korean TTS keeps Circle Talk female and Scenario Talk male", () => {
  assert.equal(
    koreanChirpVoiceForRequest({ voice: "shimmer" }),
    "ko-KR-Chirp3-HD-Aoede",
  );
  assert.equal(
    koreanChirpVoiceForRequest({ voice: "echo" }),
    "ko-KR-Chirp3-HD-Charon",
  );
  assert.equal(
    koreanChirpVoiceForRequest({ voice: "google-ko-female" }),
    "ko-KR-Chirp3-HD-Aoede",
  );
  assert.equal(
    koreanChirpVoiceForRequest({ voice: "google-ko-male" }),
    "ko-KR-Chirp3-HD-Charon",
  );
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
