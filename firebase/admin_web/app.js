// StealthVox 관리자 웹 — 1단계: 회원 검색·조회 (읽기 전용).
//
//   · 통과 조건은 Custom Claim admin == true 하나다. 화면 검사는 편의일 뿐이고
//     실제 문은 firestore.rules의 isAdmin()이 지킨다.
//   · 이 페이지는 아무것도 쓰지 않는다. 지급·차단·메모는 다음 단계에서
//     Cloud Function을 거쳐서 붙인다.
//   · 서버에서 온 값은 전부 textContent로만 그린다(innerHTML 금지).

import {initializeApp} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, GoogleAuthProvider, onAuthStateChanged, signInWithPopup, signOut,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  collection, doc, getDoc, getDocs, getFirestore, limit, orderBy, query,
  Timestamp, where,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js";

// 기존 "StealthVox Web" 앱 설정 (lib/backend/firebase/firebase_config.dart와 같은 값).
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

const LIST_LIMIT = 30;
const $ = (id) => document.getElementById(id);

// ── 작은 DOM 도우미 ───────────────────────────────────────────────────────
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
  if (v instanceof Timestamp) v = v.toDate();
  if (!(v instanceof Date)) return "—";
  return v.toLocaleString("ko-KR", {hour12: false});
}

function fmtSeconds(s) {
  if (typeof s !== "number") return "—";
  const sign = s < 0 ? "-" : "";
  s = Math.abs(Math.round(s));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return `${sign}${h}시간 ${m}분 ${sec}초`;
}

function kv(pairs) {
  return el("dl", {class: "kv"},
    pairs.map(([k, v]) => [el("dt", {}, k), el("dd", {}, v ?? "—")]));
}

function copyButton(text) {
  return el("button", {
    class: "ghost small",
    onclick: async (e) => {
      await navigator.clipboard.writeText(text);
      e.target.textContent = "복사됨";
      setTimeout(() => (e.target.textContent = "복사"), 1200);
    },
  }, "복사");
}

// Firestore 값을 사람이 읽을 JSON으로.
function plain(value) {
  if (value instanceof Timestamp) return fmtTime(value);
  if (Array.isArray(value)) return value.map(plain);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((k) => [k, plain(value[k])]));
  }
  return value;
}

function explain(err) {
  if (err && err.code === "permission-denied") {
    return "권한 거부 — 관리자 Claim 또는 Firestore 규칙이 아직 반영되지 않았습니다.";
  }
  return (err && (err.code || err.message)) || String(err);
}

function setStatus(text, cls = "muted") {
  $("status").className = cls;
  $("status").textContent = text;
}

// ── 로그인 ────────────────────────────────────────────────────────────────
$("signIn").addEventListener("click", async () => {
  $("gateMsg").textContent = "";
  try {
    await signInWithPopup(auth, new GoogleAuthProvider());
  } catch (err) {
    $("gateMsg").textContent = explain(err);
  }
});
$("signOut").addEventListener("click", () => signOut(auth));

onAuthStateChanged(auth, async (user) => {
  $("results").replaceChildren();
  $("detail").replaceChildren();
  if (!user) {
    $("who").textContent = "";
    $("signOut").hidden = true;
    $("console").hidden = true;
    $("gate").hidden = false;
    $("signIn").hidden = false;
    $("gateMsg").textContent = "";
    return;
  }
  $("who").textContent = user.email || user.uid;
  $("signOut").hidden = false;

  // 강제 갱신: Claim을 방금 붙였어도 다시 로그인할 필요 없게.
  const token = await user.getIdTokenResult(true);
  if (token.claims.admin !== true) {
    $("console").hidden = true;
    $("gate").hidden = false;
    $("signIn").hidden = true;
    $("gateMsg").textContent = "이 계정에는 관리자 권한이 없습니다.";
    return;
  }
  $("signIn").hidden = false;
  $("gate").hidden = true;
  $("console").hidden = false;
  runSearch("");
});

// ── 검색 ──────────────────────────────────────────────────────────────────
$("searchForm").addEventListener("submit", (e) => {
  e.preventDefault();
  runSearch($("q").value.trim());
});

// Firebase UID: 영숫자 20~36자, '@' 없음.
const looksLikeUid = (q) => /^[A-Za-z0-9]{20,36}$/.test(q);

async function runSearch(q) {
  $("results").replaceChildren();
  $("detail").replaceChildren();
  setStatus("검색 중…");
  try {
    if (looksLikeUid(q)) {
      setStatus(`UID ${q}`);
      await showMember(q);
      return;
    }
    const members = collection(db, "real_members");
    const snap = q
      ? await getDocs(query(members,
        where("email", ">=", q.toLowerCase()),
        where("email", "<=", q.toLowerCase() + ""),
        orderBy("email"), limit(LIST_LIMIT)))
      : await getDocs(query(members, orderBy("lastSeenAt", "desc"), limit(LIST_LIMIT)));

    setStatus(q
      ? `"${q}"로 시작하는 이메일 ${snap.size}명${snap.size === LIST_LIMIT ? " (최대치, 더 좁혀 주세요)" : ""}`
      : `최근 접속 ${snap.size}명`);
    renderList(snap.docs);
  } catch (err) {
    setStatus(explain(err), "error");
  }
}

function renderList(docs) {
  const rows = docs.map((d) => {
    const m = d.data();
    const row = el("div", {
      class: "row",
      onclick: () => {
        for (const r of $("results").children) r.classList.remove("active");
        row.classList.add("active");
        showMember(d.id);
      },
    },
    el("div", {}, m.email || el("span", {class: "muted"}, "(이메일 없음)"),
      m.hasPurchase ? [" ", el("span", {class: "tag"}, `구매 ${m.purchaseCount || 0}`)] : null),
    el("div", {class: "sub"},
      `${(m.providers || []).join(", ") || "—"} · 최근 ${fmtTime(m.lastSeenAt)}`));
    return row;
  });
  $("results").replaceChildren(...rows);
}

// ── 회원 상세 ─────────────────────────────────────────────────────────────
async function showMember(uid) {
  const box = $("detail");
  box.replaceChildren(el("p", {class: "muted"}, "불러오는 중…"));
  try {
    const userRef = doc(db, "users", uid);
    const [memberSnap, userSnap, purchases, usage] = await Promise.all([
      getDoc(doc(db, "real_members", uid)),
      getDoc(userRef),
      getDocs(query(collection(userRef, "purchases"), orderBy("purchased_at", "desc"), limit(50))),
      getDocs(query(collection(userRef, "usage_logs"), orderBy("created_at", "desc"), limit(LIST_LIMIT))),
    ]);
    if (!memberSnap.exists() && !userSnap.exists()) {
      box.replaceChildren(el("p", {class: "error"}, `UID ${uid}: 회원 문서가 없습니다.`));
      return;
    }
    const m = memberSnap.exists() ? memberSnap.data() : {};
    const u = userSnap.exists() ? userSnap.data() : {};

    box.replaceChildren(
      el("div", {class: "card"},
        el("h2", {}, m.email || (memberSnap.exists() ? "(이메일 없음)" : "체험(익명) 사용자")),
        el("div", {class: "muted"}, m.displayName || ""),
        el("div", {class: "mono"}, uid, " ", copyButton(uid)),
        el("h3", {}, "계정"),
        kv([
          ["로그인 방식", (m.providers || []).join(", ") || "익명"],
          ["가입", fmtTime(m.joinedAt)],
          ["마지막 로그인", fmtTime(m.lastSignInAt)],
          ["마지막 접속", fmtTime(m.lastSeenAt)],
        ]),
        el("h3", {}, "이용 시간·결제"),
        kv([
          ["남은 시간", fmtSeconds(u.remainingTime)],
          ["구매 횟수", m.purchaseCount ?? 0],
          ["총 구매 시간", fmtSeconds(m.totalSecondsPurchased ?? 0)],
          ["마지막 구매", m.lastPurchasedAt
            ? `${fmtTime(m.lastPurchasedAt)} · ${m.lastProductId || ""} · ${m.lastPurchaseEnvironment || ""}`
            : "—"],
        ])),
      purchaseTable(purchases.docs),
      usageTable(usage.docs),
      el("div", {class: "card"},
        el("details", {},
          el("summary", {}, "users 문서 원본"),
          el("pre", {}, JSON.stringify(plain(u), null, 2)))),
    );
  } catch (err) {
    box.replaceChildren(el("p", {class: "error"}, explain(err)));
  }
}

function purchaseTable(docs) {
  return el("div", {class: "card"},
    el("h3", {}, `구매 이력 (${docs.length})`),
    docs.length === 0 ? el("p", {class: "muted"}, "없음") : el("table", {},
      el("tr", {}, el("th", {}, "시각"), el("th", {}, "상품"), el("th", {}, "추가 시간"), el("th", {}, "환경")),
      docs.map((d) => {
        const p = d.data();
        return el("tr", {},
          el("td", {}, fmtTime(p.purchased_at)),
          el("td", {}, p.product_title || p.product_id || "—"),
          el("td", {class: "num"}, fmtSeconds(p.seconds_added)),
          el("td", {}, el("span", {class: p.environment === "SANDBOX" ? "tag sandbox" : "tag"},
            p.environment || "—")));
      })));
}

function usageTable(docs) {
  return el("div", {class: "card"},
    el("h3", {}, `최근 이용 기록 (${docs.length})`),
    docs.length === 0 ? el("p", {class: "muted"}, "없음") : el("table", {},
      el("tr", {}, el("th", {}, "시각"), el("th", {}, "모드"), el("th", {}, "차감"), el("th", {}, "잔여 (전 → 후)")),
      docs.map((d) => {
        const l = d.data();
        return el("tr", {},
          el("td", {}, fmtTime(l.created_at)),
          el("td", {}, l.mode || "—"),
          el("td", {class: "num"}, fmtSeconds(l.seconds_used)),
          el("td", {class: "num"}, `${fmtSeconds(l.before_seconds)} → ${fmtSeconds(l.after_seconds)}`));
      })));
}
