// StealthVox 관리자 웹 — 회원 검색·조회, 메모, 테스트 계정.
//
//   · 통과 조건은 Custom Claim admin == true 하나다. 화면 검사는 편의일 뿐이고
//     실제 문은 firestore.rules의 isAdmin()과 admin_ops.js의 requireAdmin()이 지킨다.
//   · 이 페이지는 Firestore에 직접 쓰지 않는다. 쓰기는 전부 admin* callable로.
//   · 서버에서 온 값은 전부 textContent로만 그린다(innerHTML 금지).

import {initializeApp} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth, GoogleAuthProvider, onAuthStateChanged, signInWithPopup, signOut,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  collection, doc, getCountFromServer, getDoc, getDocs, getFirestore, limit,
  orderBy, query, startAfter, Timestamp, where,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js";
import {
  getFunctions, httpsCallable,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-functions.js";

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
const functions = getFunctions(app, "asia-northeast3");
const call = (name, data) =>
  httpsCallable(functions, name)({...data, requestId: crypto.randomUUID()}).then((r) => r.data);

const LIST_LIMIT = 30;

// "전체"는 가입 순으로 한 쪽씩 끝까지 넘겨 본다.
const ALL_PAGE = 100;
let allCursor = null;

// 테스트·차단 표시는 수가 적으니 한 번에 읽어 두고 목록 태그에 쓴다.
let flagsByUid = new Map();
async function loadFlags() {
  const [tests, blocked, robots] = await Promise.all([
    getDocs(query(collection(db, "user_flags"), where("isTest", "==", true))),
    getDocs(query(collection(db, "user_flags"), where("blocked", "==", true))),
    getDocs(query(collection(db, "user_flags"), where("isRobot", "==", true))),
  ]);
  flagsByUid = new Map();
  for (const d of [...tests.docs, ...blocked.docs, ...robots.docs]) flagsByUid.set(d.id, d.data());
}

function flagTags(uid) {
  const f = flagsByUid.get(uid) || {};
  return [
    f.isTest ? [" ", el("span", {class: "tag test"}, f.testLabel ? `TEST · ${f.testLabel}` : "TEST")] : null,
    f.blocked ? [" ", el("span", {class: "tag blocked"}, "차단")] : null,
    // 출시 전 테스트 로봇(2026-10-21 일괄 표시). 테스트 계정과 달리 SANDBOX 결제 허용이 없다.
    f.isRobot ? [" ", el("span", {class: "tag"}, "로봇")] : null,
  ];
}
const $ = (id) => document.getElementById(id);

// ── 작은 DOM 도우미 ───────────────────────────────────────────────────────
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") node.className = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of children.flat(Infinity)) {
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

// 회원 화면의 잔액·충전량은 시간 단위까지만 보인다(분·초 생략, 2026-10-21).
// 정확한 값이 필요한 시간 조정 확인창·조정 내역·사용 기록은 fmtSeconds를 쓴다.
function fmtHours(s) {
  if (typeof s !== "number") return "—";
  if (s > 0 && s < 3600) return "1시간 미만";
  return `${s < 0 ? "-" : ""}${Math.floor(Math.abs(s) / 3600)}시간`;
}

// 실제 낸 돈(현지 통화)과 USD 환산. 2026-10-21 이전 기록은 금액이 없다.
function fmtPaid(p) {
  if (typeof p.price_paid !== "number") return "—";
  const local = `${p.price_paid.toLocaleString("ko-KR")} ${p.currency || ""}`.trim();
  return typeof p.price_usd === "number" && p.currency !== "USD" ? `${local} ($${p.price_usd})` : local;
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
  const code = err && String(err.code || "").replace(/^functions\//, "");
  if (code === "permission-denied") {
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
$("filter").addEventListener("change", () => runSearch($("q").value.trim()));

// Firebase UID: 영숫자 20~36자, '@' 없음.
const looksLikeUid = (q) => /^[A-Za-z0-9]{20,36}$/.test(q);

function prefixQuery(field, q) {
  return query(collection(db, "real_members"),
    where(field, ">=", q),
    where(field, "<=", q + "\uf8ff"),
    orderBy(field), limit(LIST_LIMIT));
}

// user_flags 목록 → 회원 행. 익명이면 real_members가 없어 UID만 보인다.
async function membersForUids(uids) {
  const snaps = await Promise.all(uids.map((uid) => getDoc(doc(db, "real_members", uid))));
  return snaps.map((s, i) => ({id: uids[i], data: s.exists() ? s.data() : {}}));
}

async function runSearch(q) {
  $("results").replaceChildren();
  $("detail").replaceChildren();
  setStatus("검색 중…");
  const filter = $("filter").value;
  try {
    await loadFlags();
    if (looksLikeUid(q)) {
      setStatus(`UID ${q}`);
      await showMember(q);
      return;
    }

    let rows;
    let label;
    if (filter === "test" || filter === "blocked") {
      const uids = [...flagsByUid.entries()]
        .filter(([, f]) => (filter === "test" ? f.isTest : f.blocked))
        .map(([uid]) => uid);
      rows = await membersForUids(uids);
      label = filter === "test" ? "테스트 계정" : "차단 계정";
    } else if (filter === "members") {
      // 정식회원 = real_members(익명 제외) 중 테스트·차단 표시가 없는 사람.
      const snap = await getDocs(query(collection(db, "real_members"),
        orderBy("joinedAt", "desc"), limit(1000)));
      rows = snap.docs.map((d) => ({id: d.id, data: d.data()}))
        .filter(({id}) => {
          const f = flagsByUid.get(id) || {};
          return !f.isTest && !f.blocked && !f.isRobot;
        });
      label = "정식회원 (테스트·차단·로봇 제외)";
    } else if (filter === "buyers") {
      const snap = await getDocs(query(collection(db, "real_members"),
        where("hasPurchase", "==", true), limit(200)));
      rows = snap.docs.map((d) => ({id: d.id, data: d.data()}));
      label = "구매자";
    } else if (q) {
      // 이메일 앞부분과 이름 앞부분을 같이 찾는다(카카오 회원은 이메일이 없을 수 있다).
      const [byEmail, byName] = await Promise.all([
        getDocs(prefixQuery("email", q.toLowerCase())),
        getDocs(prefixQuery("displayName", q)),
      ]);
      const seen = new Map();
      for (const d of [...byEmail.docs, ...byName.docs]) seen.set(d.id, {id: d.id, data: d.data()});
      rows = [...seen.values()];
      label = `"${q}"로 시작하는 이메일·이름`;
    } else if (filter === "recent") {
      const snap = await getDocs(query(collection(db, "real_members"),
        orderBy("lastSeenAt", "desc"), limit(LIST_LIMIT)));
      rows = snap.docs.map((d) => ({id: d.id, data: d.data()}));
      label = "최근 접속";
    } else {
      await showAllMembers();
      return;
    }

    // 필터 목록 안에서도 검색어가 있으면 이메일·이름·UID로 거른다.
    if (q && filter !== "all") {
      const needle = q.toLowerCase();
      rows = rows.filter(({id, data}) =>
        [data.email, data.displayName, id].some((v) => String(v || "").toLowerCase().includes(needle)));
    }
    if (filter !== "all" && filter !== "members") {
      rows.sort((a, b) => timeValue(b.data.lastSeenAt) - timeValue(a.data.lastSeenAt));
    }
    setStatus(`${label} ${rows.length}명`);
    renderList(rows);
  } catch (err) {
    setStatus(explain(err), "error");
  }
}

// 가입한 회원 전체(real_members). 최근 가입이 위, [더 보기]로 끝까지 넘긴다.
async function showAllMembers(more = false) {
  const members = collection(db, "real_members");
  if (!more) allCursor = null;
  const [countSnap, snap] = await Promise.all([
    more ? null : getCountFromServer(members),
    getDocs(allCursor
      ? query(members, orderBy("joinedAt", "desc"), startAfter(allCursor), limit(ALL_PAGE))
      : query(members, orderBy("joinedAt", "desc"), limit(ALL_PAGE))),
  ]);
  if (countSnap) showAllMembers.total = countSnap.data().count;
  allCursor = snap.docs.length ? snap.docs[snap.docs.length - 1] : allCursor;
  const rows = snap.docs.map((d) => ({id: d.id, data: d.data()}));
  renderList(rows, more);
  const shown = $("results").querySelectorAll(".row").length;
  setStatus(`전체 회원 ${showAllMembers.total}명 · 가입 순 · ${shown}명 표시`);
  if (snap.docs.length === ALL_PAGE && shown < showAllMembers.total) {
    $("results").append(el("button", {
      class: "more",
      onclick: async (e) => {
        e.target.remove();
        try { await showAllMembers(true); } catch (err) { setStatus(explain(err), "error"); }
      },
    }, "더 보기"));
  }
}

function timeValue(v) {
  return v instanceof Timestamp ? v.toMillis() : 0;
}

function renderList(rows, append = false) {
  const nodes = rows.map(({id, data: m}) => {
    const row = el("div", {
      class: "row",
      onclick: () => {
        for (const r of $("results").children) r.classList.remove("active");
        row.classList.add("active");
        showMember(id);
      },
    },
    el("div", {},
      m.email || m.displayName || el("span", {class: "muted mono"}, id),
      m.hasPurchase ? [" ", el("span", {class: "tag"}, `구매 ${m.purchaseCount || 0}`)] : null,
      flagTags(id)),
    el("div", {class: "sub"},
      `${(m.providers || []).join(", ") || "익명"} · 가입 ${fmtTime(m.joinedAt)} · 최근 ${fmtTime(m.lastSeenAt)}`),
    m.hasPurchase ? el("div", {class: "sub"},
      `구매 ${m.purchaseCount || 0}건 · ${m.totalSpentUsd ? `$${m.totalSpentUsd} · ` : ""}충전 ${fmtHours(m.totalSecondsPurchased)} · 마지막 구매 ${fmtTime(m.lastPurchasedAt)}`,
      m.lastPurchaseEnvironment === "SANDBOX" ? [" ", el("span", {class: "tag sandbox"}, "SANDBOX")] : null) : null);
    return row;
  });
  if (append) $("results").append(...nodes);
  else $("results").replaceChildren(...nodes);
}

// ── 회원 상세 ─────────────────────────────────────────────────────────────
async function showMember(uid) {
  const box = $("detail");
  box.replaceChildren(el("p", {class: "muted"}, "불러오는 중…"));
  try {
    const userRef = doc(db, "users", uid);
    const [memberSnap, userSnap, purchases, usage, flagSnap, notes, adjustments] = await Promise.all([
      getDoc(doc(db, "real_members", uid)),
      getDoc(userRef),
      getDocs(query(collection(userRef, "purchases"), orderBy("purchased_at", "desc"), limit(50))),
      getDocs(query(collection(userRef, "usage_logs"), orderBy("created_at", "desc"), limit(LIST_LIMIT))),
      getDoc(doc(db, "user_flags", uid)),
      getDocs(query(collection(db, "admin_notes", uid, "notes"), orderBy("createdAt", "desc"), limit(100))),
      getDocs(query(collection(userRef, "admin_adjustments"), orderBy("created_at", "desc"), limit(LIST_LIMIT))),
    ]);
    if (!memberSnap.exists() && !userSnap.exists()) {
      box.replaceChildren(el("p", {class: "error"}, `UID ${uid}: 회원 문서가 없습니다.`));
      return;
    }
    const m = memberSnap.exists() ? memberSnap.data() : {};
    const u = userSnap.exists() ? userSnap.data() : {};

    // 조정 이력이 없으면 null이 들어온다. replaceChildren은 null을 "null" 글자로 그리므로 거른다.
    box.replaceChildren(...[
      el("div", {class: "card"},
        el("h2", {}, m.email || (memberSnap.exists() ? "(이메일 없음)" : "체험(익명) 사용자")),
        el("div", {class: "muted"}, m.displayName || ""),
        el("div", {class: "mono"}, uid, " ", copyButton(uid), flagTags(uid)),
        el("h3", {}, "계정"),
        kv([
          ["로그인 방식", (m.providers || []).join(", ") || "익명"],
          ["가입", fmtTime(m.joinedAt)],
          ["마지막 로그인", fmtTime(m.lastSignInAt)],
          ["마지막 접속", fmtTime(m.lastSeenAt)],
        ]),
        el("h3", {}, "이용 시간·결제"),
        kv([
          ["남은 시간", fmtHours(u.remainingTime)],
          ["구매 횟수", m.purchaseCount ?? 0],
          ["총 구매 시간", fmtHours(m.totalSecondsPurchased ?? 0)],
          ["마지막 구매", m.lastPurchasedAt
            ? `${fmtTime(m.lastPurchasedAt)} · ${m.lastProductId || ""} · ${m.lastPurchaseEnvironment || ""}`
            : "—"],
        ])),
      userSnap.exists() ? timeCard(uid, u.remainingTime) : null,
      adjustmentTable(adjustments.docs),
      testAccountCard(uid, flagSnap.exists() ? flagSnap.data() : {}),
      blockCard(uid, flagSnap.exists() ? flagSnap.data() : {}),
      notesCard(uid, notes.docs.filter((d) => d.data().deleted !== true)),
      purchaseTable(purchases.docs),
      usageTable(usage.docs),
      el("div", {class: "card"},
        el("details", {},
          el("summary", {}, "users 문서 원본"),
          el("pre", {}, JSON.stringify(plain(u), null, 2)))),
    ].filter(Boolean));
  } catch (err) {
    box.replaceChildren(el("p", {class: "error"}, explain(err)));
  }
}

// 버튼을 누르는 동안 잠그고, 끝나면 목록 태그와 상세를 새로 읽는다.
async function runAction(button, uid, work) {
  button.disabled = true;
  try {
    await work();
    await loadFlags();
    await showMember(uid);
  } catch (err) {
    button.disabled = false;
    alertLine(button, explain(err));
  }
}

function alertLine(anchor, text) {
  const card = anchor.closest(".card");
  card.querySelector(".action-error")?.remove();
  card.append(el("p", {class: "error action-error"}, text));
}

// 이용 시간 지급·회수. 사유는 필수, 확인창에서 "현재 → 변경 후"를 보여 준다.
function timeCard(uid, remaining) {
  const current = typeof remaining === "number" ? remaining : 0;
  const reason = el("input", {type: "text", maxlength: "200", placeholder: "사유 (필수, 예: 장애 보상)"});
  const minutes = el("input", {type: "number", min: "1", max: "6000", step: "1", placeholder: "분"});

  const adjust = (button, deltaSeconds) => {
    if (!reason.value.trim()) {
      alertLine(button, "사유를 입력하세요.");
      reason.focus();
      return;
    }
    const after = Math.max(0, current + deltaSeconds);
    const verb = deltaSeconds > 0 ? "지급" : "회수";
    if (!confirm(`${verb}: ${fmtSeconds(Math.abs(deltaSeconds))}\n\n` +
        `${fmtSeconds(current)} → ${fmtSeconds(after)}\n사유: ${reason.value.trim()}`)) return;
    runAction(button, uid, () => call("adminAdjustTime", {uid, deltaSeconds, reason: reason.value}));
  };
  const preset = (label, seconds) => {
    const b = el("button", {class: "ghost", onclick: () => adjust(b, seconds)}, label);
    return b;
  };
  const customMinutes = () => {
    const m = Number(minutes.value);
    return Number.isInteger(m) && m > 0 && m <= 6000 ? m * 60 : 0;
  };
  const grant = el("button", {
    onclick: () => customMinutes() ? adjust(grant, customMinutes()) : alertLine(grant, "1~6000분 사이 정수를 입력하세요."),
  }, "지급");
  const revoke = el("button", {
    class: "danger",
    onclick: () => customMinutes() ? adjust(revoke, -customMinutes()) : alertLine(revoke, "1~6000분 사이 정수를 입력하세요."),
  }, "회수");

  return el("div", {class: "card"},
    el("h3", {}, "이용 시간 조정"),
    el("p", {}, "현재 남은 시간 ", el("strong", {}, fmtHours(current))),
    el("div", {class: "inline"}, reason),
    el("div", {class: "inline"},
      preset("+30분", 1800), preset("+1시간", 3600), preset("+10시간", 36000)),
    el("div", {class: "inline"}, minutes, el("span", {class: "muted"}, "분"), grant, revoke),
    el("p", {class: "muted"}, "구매 기록·구매 합계에는 들어가지 않습니다. 0 밑으로는 내려가지 않습니다."));
}

function adjustmentTable(docs) {
  if (docs.length === 0) return null;
  return el("div", {class: "card"},
    el("h3", {}, `관리자 조정 이력 (${docs.length})`),
    el("table", {},
      el("tr", {}, el("th", {}, "시각"), el("th", {}, "반영"), el("th", {}, "잔여 (전 → 후)"), el("th", {}, "사유")),
      docs.map((d) => {
        const a = d.data();
        const sign = a.applied_seconds > 0 ? "+" : "";
        return el("tr", {},
          el("td", {}, fmtTime(a.created_at)),
          el("td", {class: a.applied_seconds < 0 ? "num error" : "num ok"}, sign + fmtSeconds(a.applied_seconds)),
          el("td", {class: "num"}, `${fmtSeconds(a.before_seconds)} → ${fmtSeconds(a.after_seconds)}`),
          el("td", {}, a.reason || ""));
      })));
}

// 이용 차단. 서버가 AI 토큰 발급·통역·게시판·TURN을 거절한다.
// 차감·사용 기록은 막지 않는다. 이미 받은 음성 토큰은 최대 1시간 남을 수 있다.
function blockCard(uid, flags) {
  const blocked = flags.blocked === true;
  if (blocked) {
    const button = el("button", {
      class: "ghost",
      onclick: () => {
        if (!confirm("차단을 해제할까요?")) return;
        runAction(button, uid, () => call("adminSetBlocked", {uid, blocked: false}));
      },
    }, "차단 해제");
    return el("div", {class: "card blocked-card"},
      el("h3", {}, "이용 차단됨"),
      kv([
        ["사유", flags.blockReason || "—"],
        ["차단 시각", fmtTime(flags.blockedAt)],
      ]),
      el("div", {class: "inline"}, button));
  }
  const reason = el("input", {type: "text", maxlength: "200", placeholder: "차단 사유 (필수)"});
  const button = el("button", {
    class: "danger",
    onclick: () => {
      if (!reason.value.trim()) {
        alertLine(button, "차단 사유를 입력하세요.");
        reason.focus();
        return;
      }
      if (!confirm(`이 회원의 이용을 차단할까요?\n사유: ${reason.value.trim()}\n\n` +
          "AI 대화·통역·Duo 게시판이 막힙니다. 남은 시간은 그대로 둡니다.")) return;
      runAction(button, uid, () => call("adminSetBlocked", {uid, blocked: true, reason: reason.value}));
    },
  }, "이용 차단");
  return el("div", {class: "card"},
    el("h3", {}, "이용 차단"),
    el("p", {class: "muted"}, "AI 대화·통역·Duo 게시판·체험 지급을 서버에서 거절합니다. 15초 안에 반영됩니다."),
    el("div", {class: "inline"}, reason, button),
    flags.unblockedAt ? el("p", {class: "muted"}, `마지막 해제 ${fmtTime(flags.unblockedAt)}`) : null);
}

function testAccountCard(uid, flags) {
  const isTest = flags.isTest === true;
  const label = el("input", {type: "text", maxlength: "60", placeholder: "라벨 (예: QA 폰)"});
  label.value = flags.testLabel || "";
  const button = el("button", {
    class: isTest ? "ghost" : "",
    onclick: () => runAction(button, uid, () =>
      call("adminSetTestAccount", {uid, isTest: !isTest, label: label.value})),
  }, isTest ? "테스트 계정 해제" : "테스트 계정으로 지정");
  return el("div", {class: "card"},
    el("h3", {}, "테스트 계정"),
    el("p", {class: "muted"}, isTest
      ? `지정됨${flags.testLabel ? ` · ${flags.testLabel}` : ""} — SANDBOX 결제가 시간으로 충전됩니다.`
      : "지정하면 SANDBOX(테스트) 결제가 시간으로 충전됩니다. 과금 면제는 아닙니다."),
    el("div", {class: "inline"}, isTest ? null : label, button));
}

function notesCard(uid, docs) {
  const text = el("textarea", {rows: "3", maxlength: "2000", placeholder: "메모 (관리자만 보임)"});
  const add = el("button", {
    onclick: () => {
      if (!text.value.trim()) return;
      runAction(add, uid, () => call("adminAddNote", {uid, text: text.value}));
    },
  }, "메모 추가");
  return el("div", {class: "card"},
    el("h3", {}, `메모 (${docs.length})`),
    docs.map((d) => {
      const n = d.data();
      const del = el("button", {
        class: "ghost small",
        onclick: () => {
          if (!confirm("이 메모를 지울까요?")) return;
          runAction(del, uid, () => call("adminDeleteNote", {uid, noteId: d.id}));
        },
      }, "삭제");
      return el("div", {class: "note"},
        el("div", {class: "note-text"}, n.text),
        el("div", {class: "sub"}, fmtTime(n.createdAt), " ", del));
    }),
    text, el("div", {class: "inline"}, add));
}

function purchaseTable(docs) {
  return el("div", {class: "card"},
    el("h3", {}, `구매 이력 (${docs.length})`),
    docs.length === 0 ? el("p", {class: "muted"}, "없음") : el("table", {},
      el("tr", {}, el("th", {}, "시각"), el("th", {}, "상품"), el("th", {}, "추가 시간"), el("th", {}, "결제 금액"), el("th", {}, "환경")),
      docs.map((d) => {
        const p = d.data();
        return el("tr", {},
          el("td", {}, fmtTime(p.purchased_at)),
          el("td", {}, p.product_title || p.product_id || "—"),
          el("td", {class: "num"}, fmtHours(p.seconds_added)),
          el("td", {class: "num"}, fmtPaid(p)),
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
