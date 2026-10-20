"use strict";

// 헬스체크(자가진단) A단계 — 2026-10-21 실장님 지시.
//
//   · 매일 07:00(KST) 서클톡·시나리오톡 추천과 같은 계약으로 OpenAI를 직접
//     한 번씩 부르고, 결과를 health_checks에 한 줄로 남긴다.
//   · 추천 로직(씨앗·프롬프트·중복 검사)은 앱 안에 있다. 여기서 잡는 것은
//     "서버 키·모델·응답 형식·지연"까지다. 앱 코드 고장은 B단계(앱 실패 보고)가
//     잡는다.
//   · 테스트 계정을 쓰지 않는다. 과금·real_members·사용 기록에 아무것도 남지 않는다.
//   · 모델·reasoning·토큰 예산은 앱과 같아야 의미가 있다. 앱의
//     kDialogBrainModel(dialog_brain_model.dart)이나 max_completion_tokens를
//     바꾸면 여기도 바꾼다.

const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

const openAiApiKey = defineSecret("OPENAI_API_KEY");

const REGION = "asia-northeast3";
const COLLECTION = "health_checks";
const MODEL = "gpt-6-luna";
const REASONING_EFFORT = "low";
const MAX_COMPLETION_TOKENS = 400;
// 정상이어도 이보다 느리면 slow로 표시한다. 앱 타임아웃(15·20초)보다 한참 앞이다.
const SLOW_MS = 8000;

const CHECKS = [
  {
    name: "scenario_recommend",
    // 앱 _generateDramaticScenarioOnce 타임아웃과 같다.
    timeoutMs: 20000,
    fields: ["situation", "ai_role", "user_role"],
    system:
      "You are setting up ONE ordinary, everyday scene between TWO people for a spoken roleplay app.\n" +
      "OUTPUT: Return ONLY valid JSON, no extra text.\n" +
      "Write every JSON string value naturally in Korean only.\n" +
      "{\"situation\": \"...\", \"ai_role\": \"...\", \"user_role\": \"...\"}\n" +
      "- ai_role and user_role: the ROLE ONLY, a plain job, position, or relationship noun.\n" +
      "- BASE SITUATION: \"카페에서 음료 고르기\". Shift it slightly into a nearby variant.",
    user: "Generate the JSON now. All values must be in Korean.",
  },
  {
    name: "circle_recommend",
    // 앱 _recommendCircle 타임아웃과 같다.
    timeoutMs: 15000,
    fields: ["name"],
    system:
      "Name ONE real circle that matches this seed: \"물류센터\".\n" +
      "The seed is written in Korean. Write the returned name naturally in English only.\n" +
      "A circle is a workplace team, a shop and its regulars, a club, or a local community.\n" +
      "Return ONLY valid JSON: {\"name\":\"...\"}.",
    user: "Recommend one circle for \"물류센터\". Return its name in English.",
  },
];

/** 한 항목을 부르고 판정한다. 던지지 않는다 — 실패도 결과 한 줄이다. */
async function runCheck(check, {apiKey, fetchImpl = fetch, nowMs = Date.now}) {
  const startedAt = nowMs();
  const result = {name: check.name, ok: false, code: "UNKNOWN", latencyMs: 0,
    finishReason: null, sample: null, slow: false};
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), check.timeoutMs);
  try {
    const response = await fetchImpl("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {Authorization: "Bearer " + apiKey, "Content-Type": "application/json"},
      body: JSON.stringify({
        model: MODEL,
        reasoning_effort: REASONING_EFFORT,
        response_format: {type: "json_object"},
        max_completion_tokens: MAX_COMPLETION_TOKENS,
        messages: [
          {role: "system", content: check.system},
          {role: "user", content: check.user},
        ],
      }),
      signal: controller.signal,
    });
    if (!response.ok) {
      result.code = "HTTP_" + response.status;
      return result;
    }
    const payload = await response.json();
    const choice = payload && Array.isArray(payload.choices) ? payload.choices[0] : null;
    result.finishReason = choice && choice.finish_reason ? String(choice.finish_reason) : null;
    const content = choice && choice.message ? choice.message.content : null;
    if (result.finishReason === "length") {
      result.code = "TRUNCATED";
      return result;
    }
    if (typeof content !== "string" || !content.trim()) {
      result.code = "EMPTY";
      return result;
    }
    let parsed;
    try {
      parsed = JSON.parse(content.trim());
    } catch (_) {
      result.code = "INVALID_JSON";
      return result;
    }
    const values = check.fields.map((f) => String((parsed && parsed[f]) || "").trim());
    if (values.some((v) => !v)) {
      result.code = "MISSING_FIELDS";
      return result;
    }
    result.ok = true;
    result.code = "OK";
    result.sample = values.join(" / ").slice(0, 200);
    return result;
  } catch (error) {
    result.code = error && error.name === "AbortError" ? "TIMEOUT" : "NETWORK";
    return result;
  } finally {
    clearTimeout(timer);
    result.latencyMs = nowMs() - startedAt;
    result.slow = result.ok && result.latencyMs > SLOW_MS;
  }
}

/** 모든 항목을 돌리고 health_checks에 한 줄 남긴다. */
async function runHealthCheck({db, apiKey, trigger, fetchImpl, nowMs}) {
  const checks = [];
  for (const check of CHECKS) {
    // 순서대로 부른다. 동시에 부르면 한쪽 지연이 다른 쪽 판정을 흐린다.
    checks.push(await runCheck(check, {apiKey, fetchImpl, nowMs}));
  }
  const record = {
    ranAt: admin.firestore.FieldValue.serverTimestamp(),
    trigger,
    ok: checks.every((c) => c.ok),
    failed: checks.filter((c) => !c.ok).map((c) => c.name + ":" + c.code),
    checks,
  };
  const ref = await db.collection(COLLECTION).add(record);
  return {id: ref.id, ok: record.ok, failed: record.failed, checks};
}

const dailyHealthCheck = onSchedule(
  {schedule: "0 7 * * *", timeZone: "Asia/Seoul", region: REGION,
    timeoutSeconds: 120, secrets: [openAiApiKey]},
  async () => {
    await runHealthCheck({db: admin.firestore(), apiKey: openAiApiKey.value(),
      trigger: "schedule"});
  },
);

// 배포 직후 손으로 한 번 돌리는 용도. 관리자 웹에서 부른다.
const runHealthCheckNow = onCall(
  {region: REGION, timeoutSeconds: 120, secrets: [openAiApiKey]},
  async (request) => {
    const auth = request && request.auth;
    if (!auth || !auth.token || auth.token.admin !== true) {
      throw new HttpsError("permission-denied", "Admin only.");
    }
    return runHealthCheck({db: admin.firestore(), apiKey: openAiApiKey.value(),
      trigger: "manual"});
  },
);

module.exports = {
  CHECKS,
  dailyHealthCheck,
  runCheck,
  runHealthCheck,
  runHealthCheckNow,
};
