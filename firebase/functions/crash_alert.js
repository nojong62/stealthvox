"use strict";

// Crashlytics 알림 메일 — 2026-11-10 실장님 지시.
//
//   · 사용자 폰에서 새 치명 오류·ANR(앱 멈춤)이 처음 생기거나, 고친 오류가 다시
//     살아나거나, 오류가 급증하면 mail 컬렉션에 한 통을 넣는다. 실제 발송은
//     헬스체크와 같은 firestore-send-email 확장이 한다.
//   · 본문에는 오류 제목·위치(subtitle)·앱 버전·콘솔 링크만 담는다. Crashlytics가
//     준 값 그대로이고, 대화 내용이나 사용자 정보는 이 경로에 없다.
//   · 이 함수가 하는 일은 알림뿐이다. 코드를 고치거나 배포하지 않는다.

const {
  onNewFatalIssuePublished,
  onNewAnrIssuePublished,
  onRegressionAlertPublished,
  onVelocityAlertPublished,
} = require("firebase-functions/v2/alerts/crashlytics");
const admin = require("firebase-admin");

const REGION = "asia-northeast3";
const ALERT_TO = ["nisiekorea@gmail.com"];
const CONSOLE_URL =
  "https://console.firebase.google.com/project/stealth-vox-3p3rq3/crashlytics";

const KIND_LABELS = {
  fatal: "새 치명 오류",
  anr: "앱 멈춤(ANR)",
  regression: "고친 오류가 다시 발생",
  velocity: "오류 급증",
};

function clip(value, max) {
  const text = String(value == null ? "" : value).trim();
  return text.length > max ? text.slice(0, max) + "…" : text;
}

/** 알림 한 건을 메일 제목·본문으로 만든다. 순수 함수라 시험하기 쉽다. */
function crashMail(kind, payload) {
  const issue = (payload && payload.issue) || {};
  const lines = [
    "[StealthVox Crashlytics] " + (KIND_LABELS[kind] || kind),
    "",
    "오류: " + (clip(issue.title, 200) || "(제목 없음)"),
  ];
  if (issue.subtitle) lines.push("위치: " + clip(issue.subtitle, 300));
  if (issue.appVersion) lines.push("앱 버전: " + clip(issue.appVersion, 60));
  if (kind === "velocity") {
    lines.push("발생: " + payload.crashCount + "건 (세션의 " +
      Number(payload.crashPercentage).toFixed(2) + "%)");
    if (payload.firstVersion) lines.push("처음 나온 버전: " + clip(payload.firstVersion, 60));
  }
  if (issue.id) lines.push("오류 ID: " + clip(issue.id, 80));
  lines.push("", CONSOLE_URL);
  return {
    subject: "[StealthVox] " + (KIND_LABELS[kind] || kind) + ": " +
      (clip(issue.title, 80) || "제목 없음"),
    text: lines.join("\n"),
  };
}

/** mail 컬렉션에 넣는다. 던지지 않는다 — 실패해도 알림 함수가 재시도 폭주하지 않게. */
async function queueCrashMail(db, kind, payload) {
  const message = crashMail(kind, payload);
  try {
    const ref = await db.collection("mail").add({
      to: ALERT_TO,
      message,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {sent: true, mailId: ref.id};
  } catch (_) {
    return {sent: false};
  }
}

function handler(kind) {
  return async (event) => {
    const payload = event && event.data && event.data.payload;
    return queueCrashMail(admin.firestore(), kind, payload);
  };
}

const opts = {region: REGION};

module.exports = {
  crashMail,
  queueCrashMail,
  crashAlertNewFatal: onNewFatalIssuePublished(opts, handler("fatal")),
  crashAlertNewAnr: onNewAnrIssuePublished(opts, handler("anr")),
  crashAlertRegression: onRegressionAlertPublished(opts, handler("regression")),
  crashAlertVelocity: onVelocityAlertPublished(opts, handler("velocity")),
};
