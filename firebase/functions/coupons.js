"use strict";

// 쿠폰 코드 — 유튜버 홍보용 이용 시간 선물(2026-10-26 실장님).
//
//   · 코드 하나가 공용·개별을 다 맡는다. maxUses 1이면 개별, 2 이상이면 공용(선착순).
//   · 쓰는 쪽(redeemCoupon)은 Google 등으로 로그인한 계정만. 익명(Duo 게스트)은
//     계정을 계속 새로 만들 수 있어 거절한다.
//   · 한 코드는 계정 하나에 한 번, 폰 하나에 한 번. 폰은 기기 ID 해시로 센다.
//   · 지급은 remainingTime만 올린다. purchases·real_members 구매 합계는 실제
//     결제 장부라 건드리지 않는다(admin_ops.adjustTime과 같다).
//   · 틀린 코드를 1시간에 10번 넘게 넣으면 그 계정은 1시간 동안 막는다.
//   · 발급·수정(adminCreateCoupons, adminUpdateCoupon)은 Claim admin만.

const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {requireAdmin, requireRequestId} = require("./admin_ops");
const {readBlocked} = require("./block_check");
const {deviceKey} = require("./study_trial");

const REGION = "asia-northeast3";
const COUPONS = "coupons";
const ATTEMPTS = "coupon_attempts";
const MAX_SECONDS = 10 * 60 * 60;
const MAX_USES = 10000;
const MAX_BATCH = 100;
const MEMO_MAX_LENGTH = 200;
const FAIL_LIMIT = 10;
const FAIL_WINDOW_MS = 60 * 60 * 1000;
// 헷갈리는 글자(0 O 1 I L)는 뺀다. 8자면 31^8 ≈ 8.5e11.
const CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const GENERATED_LENGTH = 8;

/** 사람이 친 코드 → 저장 형식. 공백·하이픈은 빼고 대문자로. 형식이 틀리면 "". */
function normalizeCode(value) {
  const code = typeof value === "string" ? value.replace(/[\s-]/g, "").toUpperCase() : "";
  return /^[A-Z0-9]{4,20}$/.test(code) ? code : "";
}

function generateCode(random = Math.random) {
  let code = "";
  for (let i = 0; i < GENERATED_LENGTH; i++) {
    code += CODE_ALPHABET[Math.floor(random() * CODE_ALPHABET.length)];
  }
  return code;
}

/** 쓰기 직전 판정. 트랜잭션 안에서 읽은 값만 받는다. */
function judgeRedeem({coupon, redeemedByUser, redeemedByDevice, nowMs}) {
  if (!coupon) return "not_found";
  if (coupon.active !== true) return "inactive";
  if (typeof coupon.expiresAtMs === "number" && coupon.expiresAtMs <= nowMs) return "expired";
  if (redeemedByUser) return "already_used";
  if (redeemedByDevice) return "device_used";
  if ((coupon.usedCount || 0) >= coupon.maxUses) return "full";
  return "ok";
}

/** 틀린 코드 횟수. 창이 지났으면 새로 센다. */
function judgeAttempts(attempts, nowMs) {
  const start = attempts && typeof attempts.windowStartMs === "number" ? attempts.windowStartMs : 0;
  if (nowMs - start >= FAIL_WINDOW_MS) return {locked: false, windowStartMs: nowMs, fails: 0};
  const fails = attempts.fails || 0;
  return {locked: fails >= FAIL_LIMIT, windowStartMs: start, fails};
}

/**
 * 익명이 아닌 계정인지. 익명 계정에 Google을 붙인 경우도 providerData가 생긴다.
 * 카카오는 커스텀 토큰 로그인이라 providerData가 비어 있다 — 토큰의
 * sign_in_provider "custom"으로 받는다(익명은 "anonymous").
 */
function isLinkedAccount(userRecord, token) {
  if (userRecord && Array.isArray(userRecord.providerData) && userRecord.providerData.length > 0) {
    return true;
  }
  const provider = token && token.firebase && token.firebase.sign_in_provider;
  return provider === "custom";
}

async function redeem({db, uid, code, devKey, nowMs, now}) {
  const couponRef = db.doc(`${COUPONS}/${code}`);
  const userRedeemRef = db.doc(`${COUPONS}/${code}/redemptions/${uid}`);
  const deviceRef = db.doc(`${COUPONS}/${code}/devices/${devKey}`);
  const userRef = db.doc(`users/${uid}`);
  const attemptRef = db.doc(`${ATTEMPTS}/${uid}`);

  return db.runTransaction(async (tx) => {
    const [attemptSnap, couponSnap, userRedeemSnap, deviceSnap, userSnap] = await Promise.all([
      tx.get(attemptRef), tx.get(couponRef), tx.get(userRedeemRef), tx.get(deviceRef), tx.get(userRef),
    ]);
    const attempts = judgeAttempts(attemptSnap.exists ? attemptSnap.data() : null, nowMs);
    if (attempts.locked) return {ok: false, reason: "too_many"};
    if (!userSnap.exists) return {ok: false, reason: "no_user"};

    const coupon = couponSnap.exists ? couponSnap.data() : null;
    const reason = judgeRedeem({
      coupon,
      redeemedByUser: userRedeemSnap.exists,
      redeemedByDevice: deviceSnap.exists,
      nowMs,
    });
    if (reason === "not_found") {
      tx.set(attemptRef, {windowStartMs: attempts.windowStartMs, fails: attempts.fails + 1});
      return {ok: false, reason};
    }
    if (reason !== "ok") return {ok: false, reason};

    const userData = userSnap.data() || {};
    const current = userData.remainingTime;
    const before = typeof current === "number" && Number.isFinite(current) ? current : 0;
    const after = before + coupon.seconds;
    // 쿠폰 누계는 관리자 웹 회원 목록이 잔여 시간과 같이 읽는다.
    const countOf = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
    tx.update(userRef, {
      remainingTime: after,
      couponSeconds: countOf(userData.couponSeconds) + coupon.seconds,
      couponCount: countOf(userData.couponCount) + 1,
    });
    tx.update(couponRef, {usedCount: (coupon.usedCount || 0) + 1, lastUsedAt: now});
    const row = {uid, deviceKey: devKey, seconds: coupon.seconds, before_seconds: before,
      after_seconds: after, at: now};
    tx.set(userRedeemRef, row);
    tx.set(deviceRef, {uid, at: now});
    // 회원 쪽 장부(관리자 웹 회원 상세). 메모는 쓴 시점 그대로 남긴다.
    tx.set(db.doc(`users/${uid}/coupon_redemptions/${code}`), {
      code, memo: coupon.memo || "", seconds: coupon.seconds,
      before_seconds: before, after_seconds: after, at: now,
    });
    return {ok: true, secondsAdded: coupon.seconds, remainingTime: after};
  });
}

function requireSeconds(value) {
  if (!Number.isInteger(value) || value <= 0 || value > MAX_SECONDS) {
    throw new HttpsError("invalid-argument", "seconds must be an integer within 10 hours.");
  }
  return value;
}

function requireMaxUses(value) {
  if (!Number.isInteger(value) || value < 1 || value > MAX_USES) {
    throw new HttpsError("invalid-argument", `maxUses must be 1..${MAX_USES}.`);
  }
  return value;
}

function optionalExpiry(value) {
  if (value === null || value === undefined) return null;
  if (!Number.isInteger(value) || value <= 0) {
    throw new HttpsError("invalid-argument", "expiresAtMs must be epoch milliseconds or null.");
  }
  return value;
}

function requireMemo(value) {
  const memo = typeof value === "string" ? value.trim() : "";
  if (!memo || memo.length > MEMO_MAX_LENGTH) {
    throw new HttpsError("invalid-argument", "memo is required (max 200 characters).");
  }
  return memo;
}

/** 관리자 화면이 미리 보여 준 코드 목록. 비었으면 null(서버가 뽑는다). */
function wantedCodes(code, codes) {
  const raw = Array.isArray(codes) ? codes : (code === undefined || code === null || code === "" ? [] : [code]);
  if (raw.length === 0) return null;
  const list = raw.map(normalizeCode);
  if (list.some((c) => c === "")) {
    throw new HttpsError("invalid-argument", "codes must be 4-20 letters or digits.");
  }
  if (new Set(list).size !== list.length) throw new HttpsError("invalid-argument", "codes repeat.");
  return list;
}

// 코드 목록(화면의 추천 코드)을 주면 그대로 만든다. 비우면 count개를 서버가 뽑는다.
async function createCoupons({db, adminUid, code, codes: given, count, seconds, maxUses,
  expiresAtMs, memo, requestId, now, random = Math.random}) {
  const logRef = db.doc(`admin_audit/create_coupons_${requestId}`);
  const wanted = wantedCodes(code, given);
  const n = wanted ? wanted.length : count;
  if (!Number.isInteger(n) || n < 1 || n > MAX_BATCH) {
    throw new HttpsError("invalid-argument", `count must be 1..${MAX_BATCH}.`);
  }

  return db.runTransaction(async (tx) => {
    const logSnap = await tx.get(logRef);
    if (logSnap.exists) return {duplicate: true, codes: (logSnap.data().after || {}).codes || []};

    const codes = [];
    const refs = [];
    for (let i = 0; i < n; i++) {
      // 서버가 뽑은 코드가 겹치면 몇 번 다시 뽑는다. 화면이 준 코드가 겹치면 거절.
      let picked = wanted ? wanted[i] : null;
      let ref = null;
      for (let tries = 0; tries < 5; tries++) {
        const candidate = picked || generateCode(random);
        if (codes.includes(candidate)) continue;
        const candidateRef = db.doc(`${COUPONS}/${candidate}`);
        const snap = await tx.get(candidateRef);
        if (!snap.exists) {
          picked = candidate;
          ref = candidateRef;
          break;
        }
        if (wanted) throw new HttpsError("already-exists", `Coupon ${candidate} already exists.`);
      }
      if (!ref) throw new HttpsError("aborted", "Could not pick a free code. Try again.");
      codes.push(picked);
      refs.push(ref);
    }

    for (let i = 0; i < n; i++) {
      tx.set(refs[i], {
        code: codes[i], seconds, maxUses, usedCount: 0, expiresAtMs, memo,
        active: true, batchId: requestId, createdAt: now, createdBy: adminUid,
      });
    }
    tx.set(logRef, {
      action: "create_coupons", targetUid: null, before: null,
      after: {codes, seconds, maxUses, expiresAtMs, memo},
      reason: memo, adminUid, at: now,
    });
    return {duplicate: false, codes};
  });
}

// 켜기/끄기, 인원, 만료일만 바꾼다. 지급 시간은 이미 쓴 사람과 달라지므로 못 바꾼다.
async function updateCoupon({db, adminUid, code, active, maxUses, expiresAtMs, requestId, now}) {
  const couponRef = db.doc(`${COUPONS}/${code}`);
  const logRef = db.doc(`admin_audit/update_coupon_${requestId}`);
  return db.runTransaction(async (tx) => {
    const [logSnap, couponSnap] = await Promise.all([tx.get(logRef), tx.get(couponRef)]);
    if (logSnap.exists) return {duplicate: true};
    if (!couponSnap.exists) throw new HttpsError("not-found", "Coupon not found.");
    const prev = couponSnap.data();
    const patch = {};
    if (active !== undefined) {
      if (typeof active !== "boolean") throw new HttpsError("invalid-argument", "active must be boolean.");
      patch.active = active;
    }
    if (maxUses !== undefined) {
      patch.maxUses = requireMaxUses(maxUses);
      if (patch.maxUses < (prev.usedCount || 0)) {
        throw new HttpsError("invalid-argument", "maxUses cannot be below usedCount.");
      }
    }
    if (expiresAtMs !== undefined) patch.expiresAtMs = optionalExpiry(expiresAtMs);
    if (Object.keys(patch).length === 0) throw new HttpsError("invalid-argument", "Nothing to change.");

    const before = {};
    for (const key of Object.keys(patch)) before[key] = prev[key] === undefined ? null : prev[key];
    tx.update(couponRef, {...patch, updatedAt: now});
    tx.set(logRef, {
      action: "update_coupon", targetUid: null, before, after: {code, ...patch},
      reason: "", adminUid, at: now,
    });
    return {duplicate: false, ...patch};
  });
}

function createCouponFunctions({admin}) {
  const db = () => admin.firestore();
  const now = () => admin.firestore.FieldValue.serverTimestamp();

  return {
    redeemCoupon: onCall({region: REGION, enforceAppCheck: true}, async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Authentication is required.");
      const data = request.data || {};
      const userRecord = await admin.auth().getUser(uid);
      if (!isLinkedAccount(userRecord, request.auth.token)) return {ok: false, reason: "needs_account"};
      if (await readBlocked(db(), uid)) return {ok: false, reason: "blocked"};
      const code = normalizeCode(data.code);
      const devKey = deviceKey(data.deviceId);
      if (!code) return {ok: false, reason: "not_found"};
      const result = await redeem({db: db(), uid, code, devKey, nowMs: Date.now(), now: now()});
      console.log("redeemCoupon", {uid, code, ok: result.ok, reason: result.reason || ""});
      return result;
    }),
    adminCreateCoupons: onCall({region: REGION}, async (request) => {
      const adminUid = requireAdmin(request);
      const data = request.data || {};
      return createCoupons({
        db: db(), adminUid, now: now(),
        code: data.code,
        codes: data.codes,
        count: data.count === undefined ? 1 : data.count,
        seconds: requireSeconds(data.seconds),
        maxUses: requireMaxUses(data.maxUses),
        expiresAtMs: optionalExpiry(data.expiresAtMs),
        memo: requireMemo(data.memo),
        requestId: requireRequestId(data.requestId),
      });
    }),
    adminUpdateCoupon: onCall({region: REGION}, async (request) => {
      const adminUid = requireAdmin(request);
      const data = request.data || {};
      const code = normalizeCode(data.code);
      if (!code) throw new HttpsError("invalid-argument", "code is invalid.");
      return updateCoupon({
        db: db(), adminUid, now: now(), code,
        active: data.active,
        maxUses: data.maxUses,
        expiresAtMs: data.expiresAtMs,
        requestId: requireRequestId(data.requestId),
      });
    }),
  };
}

module.exports = {
  FAIL_LIMIT,
  createCouponFunctions,
  createCoupons,
  generateCode,
  isLinkedAccount,
  judgeAttempts,
  judgeRedeem,
  normalizeCode,
  redeem,
  updateCoupon,
};
