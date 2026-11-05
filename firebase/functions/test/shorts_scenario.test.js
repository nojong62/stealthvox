const test = require("node:test");
const assert = require("node:assert/strict");
const {
  DAILY_LIMIT,
  MAX_LINES,
  buildGeminiRequest,
  deductSecondsFrom,
  extractScenario,
  isAdultByBirthYear,
  kstDay,
  nextUsage,
  parseGeminiResponse,
  sourceUrlFor,
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

test("the request sends the canonical watch URL, caps the video and asks for a two-person dialogue", () => {
  const req = buildGeminiRequest({videoId: "QEw4oTtNUac", originLanguage: "Korean", targetLanguage: "English"});
  const [video, prompt] = req.contents[0].parts;
  assert.equal(video.fileData.fileUri, "https://www.youtube.com/watch?v=QEw4oTtNUac");
  assert.equal(video.videoMetadata.endOffset, "180s");
  assert.match(prompt.text, /exactly two people/);
  assert.match(prompt.text, /text MUST be written in English/);
  assert.match(prompt.text, /meaning of the line in Korean/);
  assert.match(prompt.text, /never use a tutor/);
  assert.match(prompt.text, /leave it out/);
  assert.deepEqual(req.generationConfig.responseSchema.properties.lines.items.properties.speaker.enum, ["user", "partner"]);
});

function geminiBody(obj, extraParts = []) {
  return {candidates: [{content: {parts: [...extraParts, {text: JSON.stringify(obj)}]}}]};
}

const base = {usable: true, title: "옷가게에서 더 작은 사이즈를 찾는다", user_role: "손님", partner_role: "점원"};

test("a good answer becomes title, two roles and ordered lines", () => {
  const lines = Array.from({length: 20}, (_, i) => ({
    speaker: i % 2 === 0 ? "user" : "partner", text: "  Line   " + i, meaning: "뜻 " + i,
  }));
  const out = parseGeminiResponse(geminiBody({...base, lines}, [{text: "thinking", thought: true}]));
  assert.equal(out.usable, true);
  assert.equal(out.title, "옷가게에서 더 작은 사이즈를 찾는다");
  assert.equal(out.userRole, "손님");
  assert.equal(out.partnerRole, "점원");
  assert.equal(out.lines.length, MAX_LINES);
  assert.deepEqual(out.lines[0], {speaker: "user", text: "Line 0", meaning: "뜻 0"});
  assert.equal(out.lines[1].speaker, "partner");
});

test("lines missing text or meaning are dropped, unknown speakers become partner", () => {
  const out = parseGeminiResponse(geminiBody({...base, lines: [
    {speaker: "user", text: "Hi", meaning: "안녕"},
    {speaker: "narrator", text: "Hello", meaning: "안녕하세요"},
    {speaker: "user", text: "", meaning: "빈 줄"},
    {speaker: "user", text: "No meaning", meaning: ""},
  ]}));
  assert.equal(out.lines.length, 2);
  assert.equal(out.lines[1].speaker, "partner");
});

test("a dialogue needs both people and at least two lines", () => {
  assert.deepEqual(parseGeminiResponse(geminiBody({...base, lines: [
    {speaker: "user", text: "A", meaning: "가"}, {speaker: "user", text: "B", meaning: "나"},
  ]})), {usable: false});
  assert.deepEqual(parseGeminiResponse(geminiBody({...base, lines: [
    {speaker: "partner", text: "A", meaning: "가"},
  ]})), {usable: false});
});

test("lesson roles are rejected, classroom roles pass, unusable and broken answers", () => {
  const lines = [{speaker: "user", text: "A", meaning: "가"}, {speaker: "partner", text: "B", meaning: "나"}];
  assert.equal(parseGeminiResponse(geminiBody({...base, user_role: "영어 학습자", partner_role: "영어 회화 튜터", lines})), null);
  assert.equal(parseGeminiResponse(geminiBody({...base, partner_role: "English Tutor", lines})), null);
  assert.equal(parseGeminiResponse(geminiBody({...base, user_role: "학생", partner_role: "담임 선생님", lines})).usable, true);
  assert.deepEqual(parseGeminiResponse(geminiBody({usable: false, title: "", user_role: "", partner_role: "", lines: []})), {usable: false});
  assert.deepEqual(parseGeminiResponse(geminiBody({...base, title: "", lines})), {usable: false});
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

test("deduction is off unless app_config/shorts_link sets a sane number of seconds", () => {
  assert.equal(deductSecondsFrom(null), 0);
  assert.equal(deductSecondsFrom({}), 0);
  assert.equal(deductSecondsFrom({deductSeconds: 0}), 0);
  assert.equal(deductSecondsFrom({deductSeconds: -60}), 0);
  assert.equal(deductSecondsFrom({deductSeconds: "abc"}), 0);
  assert.equal(deductSecondsFrom({deductSeconds: 99999}), 0);
  assert.equal(deductSecondsFrom({deductSeconds: 60}), 60);
  assert.equal(deductSecondsFrom({deductSeconds: "90"}), 90);
  assert.equal(deductSecondsFrom({deductSeconds: 59.9}), 59);
});

test("source link is rebuilt from the verified id", () => {
  assert.equal(sourceUrlFor("QEw4oTtNUac"), "https://www.youtube.com/shorts/QEw4oTtNUac");
});

test("extractScenario reports upstream errors without throwing", async () => {
  const fetchImpl = async () => ({ok: false, status: 400, json: async () => ({error: {message: "private video"}})});
  const out = await extractScenario({apiKey: "k", videoId: "QEw4oTtNUac", originLanguage: "Korean", targetLanguage: "English", fetchImpl});
  assert.equal(out.ok, false);
  assert.equal(out.status, 400);
  assert.equal(out.message, "private video");
});
