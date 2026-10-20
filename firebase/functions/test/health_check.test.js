const test = require("node:test");
const assert = require("node:assert/strict");
const {CHECKS, runCheck, runHealthCheck} = require("../health_check");

const scenario = CHECKS.find((c) => c.name === "scenario_recommend");
const circle = CHECKS.find((c) => c.name === "circle_recommend");

function reply(content, finishReason = "stop", status = 200) {
  return async () => ({
    ok: status === 200,
    status,
    json: async () => ({choices: [{finish_reason: finishReason, message: {content}}]}),
  });
}

test("a complete JSON answer passes and keeps a short sample", async () => {
  const result = await runCheck(scenario, {apiKey: "k", fetchImpl: reply(
    JSON.stringify({situation: "테이크아웃 주문", ai_role: "바리스타", user_role: "손님"}))});
  assert.equal(result.ok, true);
  assert.equal(result.code, "OK");
  assert.equal(result.sample, "테이크아웃 주문 / 바리스타 / 손님");
});

test("failures are named, never thrown", async () => {
  const cases = [
    [reply("", "stop", 429), "HTTP_429"],
    [reply("{\"name\":\"x\"}", "length"), "TRUNCATED"],
    [reply("   "), "EMPTY"],
    [reply("not json"), "INVALID_JSON"],
    [reply("{\"name\":\"  \"}"), "MISSING_FIELDS"],
    [async () => { throw new TypeError("fetch failed"); }, "NETWORK"],
  ];
  for (const [fetchImpl, code] of cases) {
    const result = await runCheck(circle, {apiKey: "k", fetchImpl});
    assert.equal(result.ok, false, code);
    assert.equal(result.code, code);
  }
});

test("a call that outlives the app timeout is TIMEOUT", async () => {
  const fetchImpl = (_url, {signal}) => new Promise((_, reject) => {
    signal.addEventListener("abort", () => {
      const error = new Error("aborted");
      error.name = "AbortError";
      reject(error);
    });
  });
  const result = await runCheck({...circle, timeoutMs: 10}, {apiKey: "k", fetchImpl});
  assert.equal(result.code, "TIMEOUT");
});

test("a passing but slow call is flagged slow", async () => {
  let t = 0;
  const result = await runCheck(circle, {apiKey: "k", nowMs: () => (t += 9000),
    fetchImpl: reply("{\"name\":\"Night Shift Crew\"}")});
  assert.equal(result.ok, true);
  assert.equal(result.slow, true);
});

test("one run writes one record listing what failed", async () => {
  const written = [];
  const db = {collection: () => ({add: async (doc) => { written.push(doc); return {id: "r1"}; }})};
  let call = 0;
  const fetchImpl = async (...args) => (call++ === 0 ?
    reply("{}")(...args) : reply("{\"name\":\"Dock Crew\"}")(...args));
  const summary = await runHealthCheck({db, apiKey: "k", trigger: "manual", fetchImpl});
  assert.equal(written.length, 1);
  assert.equal(summary.ok, false);
  assert.deepEqual(summary.failed, ["scenario_recommend:MISSING_FIELDS"]);
  assert.equal(written[0].trigger, "manual");
});

test("a failing run notifies once and records the alert; a passing run stays quiet", async () => {
  const written = [];
  const db = {collection: () => ({add: async (doc) => { written.push(doc); return {id: "r"}; }})};
  const texts = [];
  const notify = async (text) => { texts.push(text); return {sent: true, code: "SENT"}; };
  await runHealthCheck({db, apiKey: "k", trigger: "schedule", notify,
    fetchImpl: reply("", "stop", 500)});
  assert.equal(texts.length, 1);
  assert.match(texts[0], /HTTP_500/);
  assert.deepEqual(written[0].alert, {sent: true, code: "SENT"});

  await runHealthCheck({db, apiKey: "k", trigger: "schedule", notify,
    fetchImpl: reply("{\"name\":\"a\",\"situation\":\"b\",\"ai_role\":\"c\",\"user_role\":\"d\"}")});
  assert.equal(texts.length, 1);
  assert.equal(written[1].alert, null);
});

test("the mail notifier queues one message for the extension", async () => {
  const {mailNotifier} = require("../health_check");
  const added = [];
  const db = {collection: (name) => ({add: async (doc) => { added.push([name, doc]); return {id: "m1"}; }})};
  const result = await mailNotifier(db)("[StealthVox 헬스체크] 실패\n· 서클톡 추천: TIMEOUT (15.0초)");
  assert.deepEqual(result, {sent: true, code: "QUEUED", mailId: "m1"});
  assert.equal(added[0][0], "mail");
  assert.deepEqual(added[0][1].to, ["nisiekorea@gmail.com"]);
  assert.match(added[0][1].message.text, /TIMEOUT[\s\S]*health\.html$/);
});

test("failure text names the broken mode in Korean", () => {
  const {failureText} = require("../health_check");
  assert.equal(failureText([
    {name: "scenario_recommend", ok: false, code: "HTTP_429", latencyMs: 1200},
    {name: "circle_recommend", ok: true, code: "OK", latencyMs: 900},
  ]), "[StealthVox 헬스체크] 실패\n· 시나리오톡 추천: HTTP_429 (1.2초)");
});
