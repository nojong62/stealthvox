// 헬스체크 결과 — health_check.js가 남긴 health_checks를 최근 순으로 보여 준다.
//
//   · 읽기만 한다. "지금 실행"은 runHealthCheckNow callable을 부른다.
//   · 마지막 실행이 26시간보다 오래면 스케줄이 멈춘 것으로 보고 경고한다.
//   · 서버에서 온 값은 textContent로만 그린다.

import {initializeApp} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, GoogleAuthProvider, onAuthStateChanged, signInWithPopup,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  collection, getDocs, getFirestore, limit, orderBy, query, Timestamp,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js";
import {
  getFunctions, httpsCallable,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-functions.js";

// app.js와 같은 "StealthVox Web" 앱 설정.
const app = initializeApp({
  apiKey: "AIzaSyCDEDlP9kQltGL38V0f7qS0GYjLzsq86bA",
  authDomain: "stealth-vox-3p3rq3.firebaseapp.com",
  projectId: "stealth-vox-3p3rq3",
  storageBucket: "stealth-vox-3p3rq3.firebasestorage.app",
  messagingSenderId: "450483026108",
  appId: "1:450483026108:web:362efbb9c26ec7bb3db8b9",
});
const auth = getAuth(app);
const db = getFirestore(app);
const functions = getFunctions(app, "asia-northeast3");
const $ = (id) => document.getElementById(id);

const RUN_LIMIT = 30;
const STALE_MS = 26 * 60 * 60 * 1000;
const CHECK_COLUMNS = ["scenario_recommend", "circle_recommend"];

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") node.className = v;
    else node.setAttribute(k, v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    node.append(c instanceof Node ? c : String(c));
  }
  return node;
}

function fmtTime(v) {
  if (!(v instanceof Timestamp)) return "—";
  return v.toDate().toLocaleString("ko-KR", {hour12: false});
}

function checkCell(check) {
  if (!check) return el("td", {class: "muted"}, "—");
  const secs = (Number(check.latencyMs) / 1000).toFixed(1) + "초";
  return el("td", {},
    el("span", {class: check.ok ? "ok" : "error"}, check.code || "?"),
    " · ", secs,
    check.slow ? [" ", el("span", {class: "tag"}, "느림")] : null,
    check.sample ? el("div", {class: "muted"}, check.sample) : null);
}

async function loadRuns() {
  $("status").className = "muted";
  $("status").textContent = "불러오는 중…";
  try {
    const snap = await getDocs(query(collection(db, "health_checks"),
      orderBy("ranAt", "desc"), limit(RUN_LIMIT)));
    const rows = snap.docs.map((d) => {
      const r = d.data();
      const byName = new Map((r.checks || []).map((c) => [c.name, c]));
      return el("tr", {},
        el("td", {}, fmtTime(r.ranAt)),
        el("td", {}, r.trigger === "manual" ? "수동" : "자동"),
        el("td", {}, el("strong", {class: r.ok ? "ok" : "error"}, r.ok ? "정상" : "실패")),
        CHECK_COLUMNS.map((name) => checkCell(byName.get(name))));
    });
    $("runs").replaceChildren(...rows);

    const last = snap.docs[0] && snap.docs[0].get("ranAt");
    const age = last instanceof Timestamp ? Date.now() - last.toMillis() : Infinity;
    $("stale").hidden = age <= STALE_MS;
    $("stale").textContent = last ?
      `마지막 실행이 ${Math.floor(age / 3600000)}시간 전입니다 — 스케줄이 멈췄을 수 있습니다.` :
      "실행 기록이 없습니다.";
    $("status").textContent = `최근 ${rows.length}회`;
  } catch (err) {
    $("status").className = "error";
    $("status").textContent = (err && (err.code || err.message)) || String(err);
  }
}

$("runNow").addEventListener("click", async () => {
  const button = $("runNow");
  button.disabled = true;
  $("status").className = "muted";
  $("status").textContent = "실행 중… (최대 40초)";
  try {
    await httpsCallable(functions, "runHealthCheckNow", {timeout: 120000})({});
    await loadRuns();
  } catch (err) {
    $("status").className = "error";
    $("status").textContent = (err && (err.code || err.message)) || String(err);
  } finally {
    button.disabled = false;
  }
});

$("signIn").addEventListener("click", async () => {
  $("gateMsg").textContent = "";
  try {
    await signInWithPopup(auth, new GoogleAuthProvider());
  } catch (err) {
    $("gateMsg").textContent = err && err.message ? err.message : String(err);
  }
});

onAuthStateChanged(auth, async (user) => {
  if (!user) {
    $("who").textContent = "";
    $("console").hidden = true;
    $("gate").hidden = false;
    return;
  }
  $("who").textContent = user.email || user.uid;
  const token = await user.getIdTokenResult(true);
  if (token.claims.admin !== true) {
    $("console").hidden = true;
    $("gate").hidden = false;
    $("gateMsg").textContent = "이 계정에는 관리자 권한이 없습니다.";
    return;
  }
  $("gate").hidden = true;
  $("console").hidden = false;
  loadRuns();
});
