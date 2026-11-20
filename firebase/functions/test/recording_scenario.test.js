const test = require("node:test");
const assert = require("node:assert/strict");
const {
  MAX_AUDIO_BYTES,
  base64ByteLength,
  buildGeminiRequest,
  buildPrompt,
  extractScenario,
  normalizeMimeType,
} = require("../recording_scenario");

test("audio types: m4a variants map to audio/mp4, unknown types are refused", () => {
  assert.equal(normalizeMimeType("audio/m4a"), "audio/mp4");
  assert.equal(normalizeMimeType(" Audio/X-M4A "), "audio/mp4");
  assert.equal(normalizeMimeType("audio/mpeg"), "audio/mp3");
  for (const bad of ["", null, 7, "video/mp4", "application/pdf", "audio/unknown"]) {
    assert.equal(normalizeMimeType(bad), null, String(bad));
  }
});

test("base64 length is measured without decoding; bad input is -1", () => {
  const raw = Buffer.from("hello world!");
  assert.equal(base64ByteLength(raw.toString("base64")), raw.length);
  const odd = Buffer.from("hello world");
  assert.equal(base64ByteLength(odd.toString("base64")), odd.length);
  for (const bad of ["", null, 5, "not base64!", "a b"]) {
    assert.equal(base64ByteLength(bad), -1, String(bad));
  }
  assert.ok(MAX_AUDIO_BYTES < 10 * 1024 * 1024);
});

test("request carries the audio inline and a prompt that forbids copying and private numbers", () => {
  const req = buildGeminiRequest({
    audioBase64: "QUJD", mimeType: "audio/mp4",
    originLanguage: "Korean", targetLanguage: "English",
  });
  const parts = req.contents[0].parts;
  assert.deepEqual(parts[0].inlineData, {mimeType: "audio/mp4", data: "QUJD"});
  const prompt = parts[1].text;
  assert.match(prompt, /NEW, clean dialogue/);
  assert.match(prompt, /Never include phone numbers/);
  assert.match(prompt, /written in English/);
  assert.match(prompt, /in Korean/);
  assert.equal(prompt, buildPrompt({originLanguage: "Korean", targetLanguage: "English"}));
});

test("extractScenario turns a Gemini reply into a dialogue and reports http errors", async () => {
  const reply = {
    candidates: [{content: {parts: [{text: JSON.stringify({
      usable: true, title: "병원 예약 바꾸기", user_role: "환자", partner_role: "접수 직원",
      lines: [
        {speaker: "user", text: "Can I move my appointment?", meaning: "예약을 옮길 수 있나요?"},
        {speaker: "partner", text: "Sure, which day works?", meaning: "네, 언제가 좋으세요?"},
      ],
    })}]}}],
    usageMetadata: {totalTokenCount: 10},
  };
  const ok = await extractScenario({
    apiKey: "k", audioBase64: "QUJD", mimeType: "audio/mp4",
    originLanguage: "Korean", targetLanguage: "English",
    fetchImpl: async () => ({ok: true, json: async () => reply}),
  });
  assert.equal(ok.ok, true);
  assert.equal(ok.result.usable, true);
  assert.equal(ok.result.lines.length, 2);

  const bad = await extractScenario({
    apiKey: "k", audioBase64: "QUJD", mimeType: "audio/mp4",
    originLanguage: "Korean", targetLanguage: "English",
    fetchImpl: async () => ({ok: false, status: 400, json: async () => ({error: {message: "x"}})}),
  });
  assert.equal(bad.ok, false);
  assert.equal(bad.status, 400);
});
