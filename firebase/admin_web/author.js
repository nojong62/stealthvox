// 체험 대사 입력 — 공부방 체험 대화를 만들 때 "다른 폰"에서 쓰는 화면.
//
//   · 호스트폰 서클톡에서 "체험 제작"을 켜면 users/{uid}/chat_history/_trial_author에
//     대화가 올라온다.
//   · 여기서 친 대사는 그 아래 messages에 쌓이고, 호스트가 AI 말이
//     끝날 때마다 한 줄씩 꺼내 유저 발화로 넣는다.
//   · 회원 관리 화면(app.js)과 달리 이 페이지는 Firestore에 직접 쓴다. 회원
//     데이터가 아니라 관리자 자기 계정의 제작 통로뿐이고, 규칙은 owner다.
//   · 서버에서 온 값은 textContent로만 그린다.

import {initializeApp} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, GoogleAuthProvider, onAuthStateChanged, signInWithPopup,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  addDoc, collection, doc, getFirestore, onSnapshot, query, serverTimestamp, where,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js";

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
const $ = (id) => document.getElementById(id);
// 호스트 서클톡과 같은 자리(study_trial_author_relay.dart kChannelDocId).
const CHANNEL = "_trial_author";

let stopState = null;
let stopLines = null;
let uid = null;
let queued = [];
let lastLog = [];

$("signIn").addEventListener("click", async () => {
  $("gateMsg").textContent = "";
  try {
    await signInWithPopup(auth, new GoogleAuthProvider());
  } catch (err) {
    $("gateMsg").textContent = err && err.message ? err.message : String(err);
  }
});

onAuthStateChanged(auth, async (user) => {
  if (stopState) stopState();
  if (stopLines) stopLines();
  stopState = stopLines = null;
  uid = null;
  if (!user) {
    $("who").textContent = "";
    $("pad").hidden = true;
    $("gate").hidden = false;
    return;
  }
  $("who").textContent = user.email || user.uid;
  const token = await user.getIdTokenResult(true);
  if (token.claims.admin !== true) {
    $("pad").hidden = true;
    $("gate").hidden = false;
    $("signIn").hidden = true;
    $("gateMsg").textContent = "이 계정에는 관리자 권한이 없습니다.";
    return;
  }
  uid = user.uid;
  $("gate").hidden = true;
  $("pad").hidden = false;

  stopState = onSnapshot(doc(db, "users", uid, "chat_history", CHANNEL), (snap) => {
    const data = snap.exists() ? snap.data() : null;
    if (!data) {
      $("state").textContent = "호스트폰 서클톡에서 '체험 제작'을 켜 주세요.";
      lastLog = [];
    } else {
      $("state").textContent = data.active
        ? `제작 중 · Chat ${data.chatLang} → Learn ${data.learnLang}`
        : "호스트폰에서 제작이 꺼져 있습니다.";
      lastLog = Array.isArray(data.log) ? data.log : [];
    }
    render();
  }, (err) => { $("state").textContent = "읽기 실패: " + err.message; });

  stopLines = onSnapshot(
    query(collection(db, "users", uid, "chat_history", CHANNEL, "messages"),
      where("consumed", "==", false)),
    (snap) => {
      queued = snap.docs
        .map((d) => d.data())
        .sort((a, b) => millis(a.createdAt) - millis(b.createdAt));
      render();
    },
    (err) => { $("pending").textContent = "대기열 읽기 실패: " + err.message; });
});

function millis(v) {
  return v && typeof v.toMillis === "function" ? v.toMillis() : Date.now();
}

function bubble(cls, text) {
  const div = document.createElement("div");
  div.className = "msg " + cls;
  div.textContent = text;
  return div;
}

function render() {
  const log = $("log");
  log.replaceChildren(
    ...lastLog.map((m) => bubble(m.role === "USER" ? "user" : "ai", String(m.text || ""))),
    ...queued.map((q) => bubble("queued", String(q.text || ""))),
  );
  $("pending").textContent = queued.length
    ? `대기 ${queued.length}줄 — AI 말이 끝나면 차례로 들어갑니다.`
    : "";
  window.scrollTo(0, document.body.scrollHeight);
}

$("lineForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const text = $("line").value.trim();
  if (!text || !uid) return;
  $("line").value = "";
  try {
    await addDoc(collection(db, "users", uid, "chat_history", CHANNEL, "messages"), {
      text, consumed: false, createdAt: serverTimestamp(),
    });
  } catch (err) {
    $("line").value = text;
    $("pending").textContent = "보내기 실패: " + err.message;
  }
  $("line").focus();
});
