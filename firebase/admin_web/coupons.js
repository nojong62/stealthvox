// 쿠폰 — 발급·켜고 끄기·인원 조정, 코드별 사용자 보기.
//
//   · 쓰기는 coupons.js의 adminCreateCoupons·adminUpdateCoupon callable만 부른다.
//   · 읽기는 coupons 컬렉션 규칙(isAdmin)으로 직접 한다.
//   · 서버에서 온 값은 textContent로만 그린다.

import {initializeApp} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, GoogleAuthProvider, onAuthStateChanged, signInWithPopup,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  collection, doc, getDoc, getDocs, getFirestore, limit, orderBy, query, Timestamp,
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

const LIST_LIMIT = 200;

const call = (name, data) =>
  httpsCallable(functions, name)({...data, requestId: crypto.randomUUID()}).then((r) => r.data);

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") node.className = v;
    else if (k === "onclick") node.addEventListener("click", v);
    else node.setAttribute(k, v);
  }
  for (const c of children.flat()) {
    if (c == null || c === false) continue;
    node.append(c instanceof Node ? c : String(c));
  }
  return node;
}

const errText = (err) => (err && (err.message || err.code)) || String(err);

function fmtTime(v) {
  if (!(v instanceof Timestamp)) return "—";
  return v.toDate().toLocaleString("ko-KR", {hour12: false});
}

function fmtExpiry(ms) {
  if (typeof ms !== "number") return "무기한";
  return new Date(ms).toLocaleDateString("ko-KR", {timeZone: "Asia/Seoul"});
}

function fmtHours(seconds) {
  const h = seconds / 3600;
  return `${Number.isInteger(h) ? h : h.toFixed(1)}시간`;
}

// 서버 coupons.js와 같은 글자판(0 O 1 I L 제외). 겹치면 서버가 already-exists로 거절한다.
const CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";

function randomCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

function suggestCode() {
  $("code").value = randomCode();
}
$("suggest").addEventListener("click", suggestCode);

// 개별 모드 미리보기: 인원 수만큼 서로 다른 코드. 인원을 바꾸면 늘리거나 줄인다.
function suggestList(fresh) {
  const n = Math.max(1, Math.min(100, Math.floor(Number($("count").value)) || 1));
  const codes = fresh ? [] : previewCodes().slice(0, n);
  while (codes.length < n) {
    const c = randomCode();
    if (!codes.includes(c)) codes.push(c);
  }
  $("preview").value = codes.join("\n");
}
const previewCodes = () => $("preview").value.split("\n").map((s) => s.trim()).filter(Boolean);
$("suggestAll").addEventListener("click", () => suggestList(true));
$("count").addEventListener("input", () => suggestList(false));

// 개별: 미리 보여 준 코드를 그대로 만든다(코드당 1명). 공용: 추천 코드 하나를 선착순 N명.
function syncMode() {
  const manual = $("mode").value === "manual";
  for (const id of ["countLabel", "countRow", "previewLabel", "previewRow"]) $(id).hidden = manual;
  for (const id of ["codeLabel", "codeRow", "maxUsesLabel", "maxUsesRow"]) $(id).hidden = !manual;
  if (manual && !$("code").value) suggestCode();
  if (!manual && previewCodes().length === 0) suggestList(true);
}
$("mode").addEventListener("change", syncMode);

$("createForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  const manual = $("mode").value === "manual";
  const hours = Number($("hours").value);
  const date = $("expires").value;
  const data = {
    seconds: Math.round(hours * 3600),
    maxUses: manual ? Number($("maxUses").value) : 1,
    expiresAtMs: date ? new Date(`${date}T23:59:59+09:00`).getTime() : null,
    memo: $("memo").value,
  };
  if (manual) data.code = $("code").value;
  else data.codes = previewCodes();

  const summary = manual
    ? `코드 ${data.code.toUpperCase()} 1개, ${fmtHours(data.seconds)}, 선착순 ${data.maxUses}명`
    : `개별 코드 ${data.codes.length}개(${data.codes.length}명), 각 ${fmtHours(data.seconds)}`;
  if (!confirm(`${summary}\n만료: ${fmtExpiry(data.expiresAtMs)}\n발급할까요?`)) return;

  $("createBtn").disabled = true;
  $("createMsg").className = "muted";
  $("createMsg").textContent = "발급 중…";
  try {
    const result = await call("adminCreateCoupons", data);
    $("issued").hidden = false;
    $("issued").value = result.codes.join("\n");
    $("createMsg").textContent = `${result.codes.length}개 발급. 아래 목록을 복사해 보내세요.`;
    // 다음 발급용으로 새 추천 코드를 깔아 둔다.
    if (manual) suggestCode();
    else suggestList(true);
    await loadList();
  } catch (err) {
    $("createMsg").className = "error";
    $("createMsg").textContent = errText(err);
  } finally {
    $("createBtn").disabled = false;
  }
});

async function update(code, patch, button) {
  button.disabled = true;
  try {
    await call("adminUpdateCoupon", {code, ...patch});
    await loadList();
  } catch (err) {
    alert(errText(err));
    button.disabled = false;
  }
}

async function showUsedBy(code) {
  const box = $("usedBy");
  box.hidden = false;
  box.replaceChildren(el("p", {class: "muted"}, `${code} 불러오는 중…`));
  try {
    const snap = await getDocs(query(collection(db, "coupons", code, "redemptions"),
      orderBy("at", "desc"), limit(LIST_LIMIT)));
    // 정식회원 명부에서 이메일을 붙인다. 없으면 UID만.
    const members = await Promise.all(snap.docs.map((d) =>
      getDoc(doc(db, "real_members", d.id)).catch(() => null)));
    const rows = snap.docs.map((d, i) => {
      const r = d.data();
      const m = members[i] && members[i].exists() ? members[i].data() : {};
      return el("tr", {},
        el("td", {}, fmtTime(r.at)),
        el("td", {}, m.email || "—"),
        el("td", {class: "mono"}, d.id),
        el("td", {class: "num"}, fmtHours(r.seconds || 0)));
    });
    box.replaceChildren(
      el("h3", {style: "margin-top:0"}, `${code} 사용자 ${rows.length}명`),
      rows.length === 0 ? el("p", {class: "muted"}, "아직 없음") : el("table", {},
        el("thead", {}, el("tr", {}, el("th", {}, "시각"), el("th", {}, "이메일"),
          el("th", {}, "UID"), el("th", {}, "지급"))),
        el("tbody", {}, rows)));
  } catch (err) {
    box.replaceChildren(el("p", {class: "error"}, errText(err)));
  }
}

async function loadList() {
  $("status").className = "muted";
  $("status").textContent = "불러오는 중…";
  try {
    const snap = await getDocs(query(collection(db, "coupons"),
      orderBy("createdAt", "desc"), limit(LIST_LIMIT)));
    const now = Date.now();
    const rows = snap.docs.map((d) => {
      const c = d.data();
      const expired = typeof c.expiresAtMs === "number" && c.expiresAtMs <= now;
      const full = (c.usedCount || 0) >= c.maxUses;
      const state = !c.active ? el("span", {class: "muted"}, "꺼짐")
        : expired ? el("span", {class: "error"}, "만료")
          : full ? el("span", {class: "muted"}, "마감")
            : el("span", {class: "ok"}, "사용 가능");
      const toggle = el("button", {class: "small ghost", onclick: (e) =>
        update(d.id, {active: !c.active}, e.currentTarget)}, c.active ? "끄기" : "켜기");
      const resize = el("button", {class: "small ghost", onclick: (e) => {
        const next = prompt(`${d.id} 인원 (지금 ${c.maxUses}, 사용 ${c.usedCount || 0})`, String(c.maxUses));
        if (next === null) return;
        update(d.id, {maxUses: Number(next)}, e.currentTarget);
      }}, "인원");
      const reexpire = el("button", {class: "small ghost", onclick: (e) => {
        const cur = typeof c.expiresAtMs === "number"
          ? new Date(c.expiresAtMs).toLocaleDateString("sv-SE", {timeZone: "Asia/Seoul"}) : "";
        const next = prompt(`${d.id} 만료일 YYYY-MM-DD, 그날 23:59(KST)까지. 비우면 무기한 (지금 ${fmtExpiry(c.expiresAtMs)})`, cur);
        if (next === null) return;
        const date = next.trim();
        if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) { alert("YYYY-MM-DD 형식으로 적어 주세요."); return; }
        update(d.id, {expiresAtMs: date ? new Date(`${date}T23:59:59+09:00`).getTime() : null}, e.currentTarget);
      }}, "만료");
      const users = el("button", {class: "small ghost", onclick: () => showUsedBy(d.id)}, "사용자");
      return el("tr", {},
        el("td", {class: "mono"}, d.id),
        el("td", {}, c.memo || ""),
        el("td", {}, fmtHours(c.seconds || 0)),
        el("td", {class: "num"}, `${c.usedCount || 0}/${c.maxUses}`),
        el("td", {}, fmtExpiry(c.expiresAtMs)),
        el("td", {}, state),
        el("td", {}, toggle, " ", resize, " ", reexpire, " ", users));
    });
    $("list").replaceChildren(...rows);
    $("status").textContent = `최근 ${rows.length}개`;
  } catch (err) {
    $("status").className = "error";
    $("status").textContent = errText(err);
  }
}

$("signIn").addEventListener("click", async () => {
  $("gateMsg").textContent = "";
  try {
    await signInWithPopup(auth, new GoogleAuthProvider());
  } catch (err) {
    $("gateMsg").textContent = errText(err);
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
  syncMode();
  loadList();
});
