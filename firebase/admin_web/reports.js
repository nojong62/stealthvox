// Duo 신고 목록 — duo_board.js의 reportDuoPartner가 남긴 duo_reports를 최근 순으로 보여 준다.
//
//   · 읽기만 한다. 영구 차단은 회원 관리와 같은 adminSetBlocked callable을 부른다.
//   · 대화는 duo_sessions/{roomId}/messages에 남은 원문을 그대로 보여 준다.
//   · 서버에서 온 값은 textContent로만 그린다.

import {initializeApp} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, GoogleAuthProvider, onAuthStateChanged, signInWithPopup,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  collection, doc, getDoc, getDocs, getFirestore, limit, orderBy, query, Timestamp, where,
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
const call = (name, data) =>
  httpsCallable(functions, name)({...data, requestId: crypto.randomUUID()}).then((r) => r.data);
const $ = (id) => document.getElementById(id);

const REPORT_LIMIT = 100;
const WINDOW_MS = 24 * 60 * 60 * 1000;

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") node.className = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
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

function kstDayKey(ms = Date.now()) {
  return new Date(ms + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function uidCell(uid, anonymous) {
  return el("td", {},
    el("code", {}, uid || "—"),
    anonymous == null ? null :
      el("div", {class: "muted"}, anonymous ? "비회원" : "회원"));
}

// 대상별 누적: 전체 신고 수와 24시간 안의 서로 다른 신고자 수.
function tallyByTarget(reports) {
  const now = Date.now();
  const map = new Map();
  for (const r of reports) {
    const t = map.get(r.targetUid) || {total: 0, recent: new Set()};
    t.total += 1;
    const at = r.createdAt instanceof Timestamp ? r.createdAt.toMillis() : 0;
    if (now - at <= WINDOW_MS) t.recent.add(r.reporterUid);
    map.set(r.targetUid, t);
  }
  return map;
}

async function readTargetState(uid) {
  const [suspension, flags] = await Promise.all([
    getDoc(doc(db, "duo_board_suspensions", uid)),
    getDoc(doc(db, "user_flags", uid)),
  ]);
  const until = suspension.exists() ? suspension.get("until") : null;
  return {
    suspendedUntil: until instanceof Timestamp && until.toMillis() > Date.now() ? until : null,
    blocked: flags.exists() && flags.get("blocked") === true,
  };
}

async function showConversation(roomId, reporterUid, cell) {
  cell.replaceChildren(el("span", {class: "muted"}, "불러오는 중…"));
  try {
    const snap = await getDocs(query(collection(db, "duo_sessions", roomId, "messages"),
      orderBy("createdAt"), limit(200)));
    if (snap.empty) {
      cell.replaceChildren(el("span", {class: "muted"}, "남은 대화 기록이 없습니다."));
      return;
    }
    cell.replaceChildren(...snap.docs.map((d) => {
      const m = d.data();
      const who = m.senderUid === reporterUid ? "신고자" : "대상";
      return el("div", {},
        el("strong", {class: who === "대상" ? "error" : "muted"}, `${who} `),
        el("span", {class: "muted"}, `[${m.srcLang || "?"}] `),
        m.text || "");
    }));
  } catch (err) {
    cell.replaceChildren(el("span", {class: "error"}, (err && (err.code || err.message)) || String(err)));
  }
}

async function loadDaily() {
  try {
    const snap = await getDoc(doc(db, "duo_board_promo_daily", kstDayKey()));
    const used = snap.exists() ? Number(snap.get("guestCalls") || 0) : 0;
    $("daily").textContent = `· 오늘 비회원끼리 통화 ${used}통`;
  } catch (_) {
    $("daily").textContent = "";
  }
}

async function loadReports() {
  $("status").className = "muted";
  $("status").textContent = "불러오는 중…";
  try {
    const snap = await getDocs(query(collection(db, "duo_reports"),
      orderBy("createdAt", "desc"), limit(REPORT_LIMIT)));
    const reports = snap.docs.map((d) => ({id: d.id, ...d.data()}));
    const tally = tallyByTarget(reports);
    const targets = [...new Set(reports.map((r) => r.targetUid))];
    const states = new Map(await Promise.all(
      targets.map(async (uid) => [uid, await readTargetState(uid)])));

    const rows = [];
    for (const r of reports) {
      const t = tally.get(r.targetUid);
      const state = states.get(r.targetUid) || {};
      const detail = el("td", {colspan: "6"});
      const detailRow = el("tr", {hidden: ""}, detail);
      const blockButton = el("button", {
        class: "small",
        onclick: async () => {
          if (!confirm(`이 사용자를 영구 차단할까요?\n${r.targetUid}\n\nAI 대화·통역·Duo 게시판이 막힙니다.`)) return;
          blockButton.disabled = true;
          try {
            await call("adminSetBlocked", {uid: r.targetUid, blocked: true,
              reason: `Duo 신고 ${r.roomId}`});
            await loadReports();
          } catch (err) {
            blockButton.disabled = false;
            alert((err && (err.code || err.message)) || String(err));
          }
        },
      }, "영구 차단");
      const viewButton = el("button", {
        class: "small ghost",
        onclick: () => {
          const open = detailRow.hasAttribute("hidden");
          if (open) {
            detailRow.removeAttribute("hidden");
            showConversation(r.roomId, r.reporterUid, detail);
          } else {
            detailRow.setAttribute("hidden", "");
          }
        },
      }, "대화 보기");
      rows.push(el("tr", {},
        el("td", {}, fmtTime(r.createdAt),
          r.promoGuestRoom ? el("div", {}, el("span", {class: "tag"}, "비회원 방")) : null),
        uidCell(r.reporterUid, r.reporterAnonymous),
        uidCell(r.targetUid, null),
        el("td", {}, `전체 ${t.total}건`, el("div", {class: "muted"}, `24시간 ${t.recent.size}명`)),
        el("td", {},
          state.blocked ? el("strong", {class: "error"}, "영구 차단됨") :
          state.suspendedUntil ? el("span", {class: "error"}, `정지 ~${fmtTime(state.suspendedUntil)}`) :
          el("span", {class: "muted"}, "정상")),
        el("td", {}, viewButton, " ", state.blocked ? null : blockButton)));
      rows.push(detailRow);
    }
    $("reports").replaceChildren(...rows);
    $("status").textContent = `최근 ${reports.length}건`;
  } catch (err) {
    $("status").className = "error";
    $("status").textContent = (err && (err.code || err.message)) || String(err);
  }
}

$("reload").addEventListener("click", () => { loadReports(); loadDaily(); });

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
  loadReports();
  loadDaily();
});
