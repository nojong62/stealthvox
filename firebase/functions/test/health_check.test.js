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
