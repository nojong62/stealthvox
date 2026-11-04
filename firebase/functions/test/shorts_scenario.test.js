const test = require("node:test");
const assert = require("node:assert/strict");
const {
  DAILY_LIMIT,
  MAX_EXPRESSIONS,
  buildGeminiRequest,
  cacheKey,
  extractScenario,
  isAdultByBirthYear,
  kstDay,
  sourceUrlFor,
  nextUsage,
  parseGeminiResponse,
  youtubeVideoId,
} = require("../shorts_scenario");

test("youtube links of every common shape give the 11-char id", () => {
  const id = "QEw4oTtNUac";
  for (const url of [
    "https://www.youtube.com/shorts/QEw4oTtNUac",
    "https://youtube.com/shorts/QEw4oTtNUac?si=abc123",
    "youtube.com/shorts/QEw4oTtNUac",
    "https://m.youtube.com/watch?v=QEw4oTtNUac&t=3",
    "https://youtu.be/QEw4oTtNUac",
    "https://www.youtube.com/embed/QEw4oTtNUac",
    "  https://www.youtube.com/shorts/QEw4oTtNUac  ",
  ]) assert.equal(youtubeVideoId(url), id, url);
});

test("anything that is not a youtube video is refused", () => {
  for (const url of [
    "", null, 42, "https://www.tiktok.com/@a/video/123",
    "https://www.youtube.com/@MiamiDaeguMiami",
    "https://www.youtube.com/shorts/short",
    "https://evil.com/shorts/QEw4oTtNUac",
    "https://youtube.com.evil.com/shorts/QEw4oTtNUac",
    "https://www.youtube.com/watch?v=QEw4oTtNUac/../x",
  ]) assert.equal(youtubeVideoId(url), null, String(url));
});

test("the request sends the canonical watch URL and caps the video at 3 minutes", () => {
  const req = buildGeminiRequest({videoId: "QEw4oTtNUac", originLanguage: "Korean", targetLanguage: "English"});
  const [video, prompt] = req.contents[0].parts;
  assert.equal(video.fileData.fileUri, "https://www.youtube.com/watch?v=QEw4oTtNUac");
  assert.equal(video.videoMetadata.endOffset, "180s");
  assert.match(prompt.text, /written in Korean/);
  assert.match(prompt.text, /text MUST be written in English/);
  assert.match(prompt.text, /never include that line/);
  assert.match(prompt.text, /never use a tutor/);
});

function geminiBody(obj, extraParts = []) {
  return {candidates: [{content: {parts: [...extraParts, {text: JSON.stringify(obj)}]}}]};
}

test("a good answer is trimmed to the three fields plus at most five expressions", () => {
  const out = parseGeminiResponse(geminiBody({
    usable: true,
    situation: "  옷가게 피팅룸.   더 작은 사이즈를 찾는다. ",
    ai_role: "점원",
    user_role: "손님",
    key_expressions: Array.from({length: 8}, (_, i) => ({text: "Line " + i, meaning: "뜻 " + i})),
  }, [{text: "thinking...", thought: true}]));
  assert.equal(out.usable, true);
  assert.equal(out.situation, "옷가게 피팅룸. 더 작은 사이즈를 찾는다.");
  assert.equal(out.aiRole, "점원");
  assert.equal(out.userRole, "손님");
  assert.equal(out.expressions.length, MAX_EXPRESSIONS);
  assert.deepEqual(out.expressions[0], {text: "Line 0", meaning: "뜻 0"});
  assert.equal("dialogue" in out, false);
});

test("classroom roles are rejected, unusable videos pass through, broken JSON is null", () => {
  const base = {usable: true, situation: "s", key_expressions: []};
  assert.equal(parseGeminiResponse(geminiBody({...base, ai_role: "영어 회화 튜터", user_role: "영어 학습자"})), null);
  assert.equal(parseGeminiResponse(geminiBody({...base, ai_role: "English Tutor", user_role: "Customer"})), null);
  // 교실 장면의 교사·학생은 정상 역할이다.
  assert.equal(parseGeminiResponse(geminiBody({...base, ai_role: "담임 선생님", user_role: "학생"})).usable, true);
  assert.deepEqual(parseGeminiResponse(geminiBody({usable: false, situation: "", ai_role: "", user_role: "", key_expressions: []})), {usable: false});
  assert.deepEqual(parseGeminiResponse(geminiBody({...base, ai_role: "", user_role: "손님"})), {usable: false});
  assert.equal(parseGeminiResponse({candidates: [{content: {parts: [{text: "not json"}]}}]}), null);
  assert.equal(parseGeminiResponse({}), null);
});

test("daily limit resets on a new KST day", () => {
  const day = kstDay(Date.UTC(2026, 10, 4, 15, 30)); // 11-05 00:30 KST
  assert.equal(day, "2026-11-05");
  assert.deepEqual(nextUsage(null, day), {day, count: 1});
  assert.deepEqual(nextUsage({day, count: 3}, day), {day, count: 4});
  assert.equal(nextUsage({day, count: DAILY_LIMIT}, day), null);
  assert.deepEqual(nextUsage({day: "2026-11-04", count: DAILY_LIMIT}, day), {day, count: 1});
});

test("adults only: year difference of 19 or more, missing birth year is refused", () => {
  const now = Date.UTC(2026, 10, 5, 3, 0); // 2026-11-05 KST
  assert.equal(isAdultByBirthYear(2007, now), true); // 19
  assert.equal(isAdultByBirthYear(2008, now), false); // 18 — 생일 전이면 17세일 수 있다
  assert.equal(isAdultByBirthYear(2012, now), false); // 14
  assert.equal(isAdultByBirthYear("2000", now), true);
  assert.equal(isAdultByBirthYear(null, now), false);
  assert.equal(isAdultByBirthYear(undefined, now), false);
  assert.equal(isAdultByBirthYear("abc", now), false);
  // 12-31 15:00 UTC는 KST로 다음 해 1월 1일이다.
  assert.equal(isAdultByBirthYear(2008, Date.UTC(2026, 11, 31, 15, 0)), true);
});

test("source link is rebuilt from the verified id", () => {
  assert.equal(sourceUrlFor("QEw4oTtNUac"), "https://www.youtube.com/shorts/QEw4oTtNUac");
});

test("cache key depends on the video and both languages", () => {
  const a = cacheKey("QEw4oTtNUac", "Korean", "English");
  assert.equal(a, cacheKey("QEw4oTtNUac", "Korean", "English"));
  assert.notEqual(a, cacheKey("QEw4oTtNUac", "Japanese", "English"));
  assert.notEqual(a, cacheKey("QEw4oTtNUac", "Korean", "Spanish"));
});

test("extractScenario reports upstream errors without throwing", async () => {
  const fetchImpl = async () => ({ok: false, status: 400, json: async () => ({error: {message: "private video"}})});
  const out = await extractScenario({apiKey: "k", videoId: "QEw4oTtNUac", originLanguage: "Korean", targetLanguage: "English", fetchImpl});
  assert.equal(out.ok, false);
  assert.equal(out.status, 400);
  assert.equal(out.message, "private video");
});
