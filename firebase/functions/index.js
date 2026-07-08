// ============================================================================
// firebase/functions/index.js
// ----------------------------------------------------------------------------
// Cloud Functions for StealthVox
//   - onUserDeleted:        cleanup when a Firebase Auth user is deleted
//   - deductRemainingTime:  callable that deducts user's subscription time
//                           (with auth check, range validation, transaction)
//   - kakaoCustomAuth:      callable that maps a Kakao account to a Firebase uid
//   - linkOrCreateAccount:  callable that resolves accounts by email
// Runtime:  Node.js 20
// Region:   us-central1 (default)
// ============================================================================

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");
const { defineSecret } = require("firebase-functions/params");
const revenueCatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");

admin.initializeApp();

// ----------------------------------------------------------------------------
// onUserDeleted
// Trigger: Firebase Auth user.delete
// Cleans up the user's Firestore document when their account is deleted.
// ----------------------------------------------------------------------------
exports.onUserDeleted = functions.auth.user().onDelete(async (user) => {
  const firestore = admin.firestore();
  const userRef = firestore.doc("users/" + user.uid);

  try {
    // Delete the user document and all nested collections.
    await firestore.recursiveDelete(userRef);
    console.log(`[onUserDeleted] Deleted all data for uid=${user.uid}`);
  } catch (err) {
    console.error(`[onUserDeleted] Error deleting data for uid=${user.uid}:`, err);
  }
});

// ----------------------------------------------------------------------------
// deductRemainingTime
// Type:   HTTPS Callable
// Input:  { seconds: number }   integer, 1 to 600
// Output: { remainingTime: number }
//
// Anti-tamper safeguards:
//   1. Caller must be authenticated.
//   2. seconds must be an integer in the range [1, 600].
//   3. Uses a Firestore transaction to avoid race conditions when multiple
//      clients (or rapid successive calls) try to deduct concurrently.
//
// Logs every deduction (uid, before, deducted, after) for audit/debug.
// ----------------------------------------------------------------------------
exports.deductRemainingTime = functions.https.onCall(async (data, context) => {
  // 1. Authentication check
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Request must be authenticated."
    );
  }

  // 2. Input validation
  const seconds = data.seconds;
  if (
    typeof seconds !== "number" ||
    !Number.isInteger(seconds) ||
    seconds <= 0 ||
    seconds > 600
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "seconds must be an integer between 1 and 600."
    );
  }

  // 3. Transactional deduction (prevents race conditions)
  const uid = context.auth.uid;
  const userRef = admin.firestore().doc("users/" + uid);

  const newValue = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) return 0;

    const current = snap.data().remainingTime;
    if (current == null) return 0;

    const updated = Math.max(0, current - seconds);
    tx.update(userRef, { remainingTime: updated });

    functions.logger.info("deductRemainingTime", {
      uid: uid,
      before: current,
      deducted: seconds,
      after: updated,
    });

    return updated;
  });

  return { remainingTime: newValue };
});

// ----------------------------------------------------------------------------
// grantSignupBonus
// Type:   HTTPS Callable
// Output: { granted: boolean, remainingTime: number }
//
// Grants a one-time signup bonus during the test period. The client may call
// this after Google/Kakao auth, but the server owns the idempotency check.
// ----------------------------------------------------------------------------
exports.grantSignupBonus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Request must be authenticated."
    );
  }

  const uid = context.auth.uid;
  const userRef = admin.firestore().doc("users/" + uid);
  const bonusSeconds = 18000;

  const result = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const userData = snap.exists ? snap.data() : {};
    const current =
      userData && typeof userData.remainingTime === "number"
        ? userData.remainingTime
        : 0;

    if (userData && userData.signup_bonus_given === true) {
      return { granted: false, remainingTime: current };
    }

    const updated = current + bonusSeconds;
    tx.set(
      userRef,
      {
        remainingTime: updated,
        signup_bonus_given: true,
        signup_bonus_granted_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    functions.logger.info("grantSignupBonus", {
      uid: uid,
      before: current,
      bonusSeconds: bonusSeconds,
      after: updated,
    });

    return { granted: true, remainingTime: updated };
  });

  return result;
});
// ----------------------------------------------------------------------------
// revenueCatWebhook
// Type:   HTTPS Request (called by RevenueCat, NOT a Firebase callable)
// Purpose: Server-side time top-up. Replaces client-side remainingTime writes.
//
// Secret handling: uses defineSecret() (Cloud Secret Manager), NOT functions.config().
//   Set it once with:
//     firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
//
// Security / safeguards:
//   1. POST only.
//   2. Authorization header must match the configured webhook secret.
//   3. Only INITIAL_PURCHASE / NON_RENEWING_PURCHASE events are processed.
//   4. Only PRODUCTION environment grants time (SANDBOX is acknowledged, ignored).
//   5. product_id must be in PRODUCT_SECONDS map (unknown products ignored).
//   6. Idempotent on event.id (RevenueCat may deliver the same event twice).
//   7. Transactional credit (mirrors deductRemainingTime's pattern).
// ----------------------------------------------------------------------------

// product_id -> seconds to credit (StealthVox consumable packages)
const PRODUCT_SECONDS = {
  stealthvox_10m: 600,
  stealthvox_1h: 3600,
  stealthvox_5h: 18000,
  stealthvox_10h: 36000,
};

exports.revenueCatWebhook = functions
  .runWith({ secrets: [revenueCatWebhookSecret] })
  .https.onRequest(async (req, res) => {
    // 1. POST only
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    // 2. Authorization header check (secret from Cloud Secret Manager)
    const expectedAuth = revenueCatWebhookSecret.value();
    const gotAuth = req.headers["authorization"] || "";
    if (!expectedAuth || gotAuth !== expectedAuth) {
      functions.logger.warn("revenueCatWebhook: unauthorized attempt");
      res.status(401).send("Unauthorized");
      return;
    }

    // 3. Parse event
    const event = req.body && req.body.event ? req.body.event : null;
    if (!event) {
      res.status(400).send("Bad Request: missing event");
      return;
    }

    const eventType = event.type;
    const eventId = event.id;
    const appUserId = event.app_user_id;
    const productId = event.product_id;
    const environment = event.environment;

    // Acknowledge (200) for anything we intentionally skip, so RevenueCat
    // does not retry. Only credit time for the cases below.

    // 3a. Only purchase-type events
    if (
      eventType !== "INITIAL_PURCHASE" &&
      eventType !== "NON_RENEWING_PURCHASE"
    ) {
      res.status(200).send("Ignored: event type " + eventType);
      return;
    }

    // 3b. Production only
    if (environment !== "PRODUCTION") {
      functions.logger.info("revenueCatWebhook: non-production event ignored", {
        eventId: eventId,
        environment: environment,
      });
      res.status(200).send("Ignored: non-production");
      return;
    }

    // 3c. Known product only
    const seconds = PRODUCT_SECONDS[productId];
    if (!seconds) {
      functions.logger.info("revenueCatWebhook: unknown product ignored", {
        eventId: eventId,
        productId: productId,
      });
      res.status(200).send("Ignored: unknown product");
      return;
    }

    // 3d. Must have a user id
    if (!appUserId || typeof appUserId !== "string") {
      res.status(200).send("Ignored: missing app_user_id");
      return;
    }

    // 4. Idempotent transactional credit
    const firestore = admin.firestore();
    const userRef = firestore.doc("users/" + appUserId);
    const purchaseRef = userRef.collection("purchases").doc(eventId); // doc id = event id

    try {
      const result = await firestore.runTransaction(async (tx) => {
        // Idempotency: if this event was already processed, skip.
        const existing = await tx.get(purchaseRef);
        if (existing.exists) {
          return { skipped: true, remainingTime: null };
        }

        const userSnap = await tx.get(userRef);
        const current =
          userSnap.exists && userSnap.data().remainingTime != null
            ? userSnap.data().remainingTime
            : 0;
        const updated = current + seconds;

        // Write only the canonical remainingTime field.
        tx.set(
          userRef,
          {
            remainingTime: updated,
          },
          { merge: true }
        );

        // Record the purchase (doubles as the idempotency marker).
        tx.set(purchaseRef, {
          rc_event_id: eventId,
          product_id: productId,
          seconds_added: seconds,
          source: "revenuecat_webhook",
          event_type: eventType,
          purchased_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        return { skipped: false, remainingTime: updated };
      });

      if (result.skipped) {
        functions.logger.info("revenueCatWebhook: duplicate event skipped", {
          eventId: eventId,
          appUserId: appUserId,
        });
        res.status(200).send("OK: duplicate ignored");
        return;
      }

      functions.logger.info("revenueCatWebhook: credited", {
        eventId: eventId,
        appUserId: appUserId,
        productId: productId,
        secondsAdded: seconds,
        remainingTime: result.remainingTime,
      });
      res.status(200).send("OK");
    } catch (err) {
      functions.logger.error("revenueCatWebhook: transaction failed", {
        eventId: eventId,
        appUserId: appUserId,
        error: String(err),
      });
      // 500 → RevenueCat will retry later, which is what we want on a real failure.
      res.status(500).send("Internal Error");
    }
  });

// [B-BILLING] Server-owned usage_logs writer. The client only calls this
// callable; created_at/after/before are derived on the server for consistency.
// Admin SDK bypasses Firestore rules, so client direct writes remain blocked.
exports.logUsageSession = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Request must be authenticated."
    );
  }
  const uid = context.auth.uid;

  const mode = typeof data.mode === "string" ? data.mode : "";
  const rate = typeof data.rate === "number" ? data.rate : null;
  const secondsUsed = data.seconds_used;
  const actualSeconds = data.actual_seconds;
  const roomId = typeof data.room_id === "string" ? data.room_id : "";
  const sessionId = typeof data.session_id === "string" ? data.session_id : "";

  if (
    typeof secondsUsed !== "number" ||
    !Number.isInteger(secondsUsed) ||
    secondsUsed <= 0 ||
    secondsUsed > 86400
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "seconds_used must be a positive integer (<= 86400)."
    );
  }
  if (
    typeof actualSeconds !== "number" ||
    !Number.isInteger(actualSeconds) ||
    actualSeconds < 0 ||
    actualSeconds > 86400
  ) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "actual_seconds must be a non-negative integer (<= 86400)."
    );
  }

  const userRef = admin.firestore().doc("users/" + uid);
  const snap = await userRef.get();
  const afterSeconds =
    snap.exists && typeof snap.data().remainingTime === "number"
      ? snap.data().remainingTime
      : 0;
  const beforeSeconds = afterSeconds + secondsUsed;

  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("usage_logs")
    .add({
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      mode: mode,
      rate: rate,
      seconds_used: secondsUsed,
      actual_seconds: actualSeconds,
      before_seconds: beforeSeconds,
      after_seconds: afterSeconds,
      room_id: roomId,
      session_id: sessionId,
    });

  functions.logger.info("logUsageSession", {
    uid: uid,
    mode: mode,
    seconds_used: secondsUsed,
    before: beforeSeconds,
    after: afterSeconds,
  });

  return {
    ok: true,
    before_seconds: beforeSeconds,
    after_seconds: afterSeconds,
  };
});

// ----------------------------------------------------------------------------
// kakaoCustomAuth
// Type:   HTTPS Callable (caller must already be authenticated; anonymous ok)
// Input:  { kakaoAccessToken: string }
// Output: { token: string }   // Client uses signInWithCustomToken.
//
// Integration policy:
//   1. Verify the Kakao access token via kapi.kakao.com/v2/user/me.
//   2. Resolve kakao_uid_map/{kakaoId}.
//        - Existing map: return that uid for repeat Kakao logins.
//        - Missing map: bind the current anonymous uid to preserve trial data.
//   3. Issue a Firebase custom token for the resolved uid.
// ----------------------------------------------------------------------------
exports.kakaoCustomAuth = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Request must be authenticated (anonymous ok)."
      );
    }
    const anonUid = context.auth.uid;

    const accessToken = data && data.kakaoAccessToken;
    if (!accessToken || typeof accessToken !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "kakaoAccessToken (string) is required."
      );
    }

    let kakaoId = null;
    let kakaoEmail = null;
    try {
      const resp = await fetch("https://kapi.kakao.com/v2/user/me", {
        method: "GET",
        headers: { Authorization: "Bearer " + accessToken },
      });
      if (!resp.ok) {
        throw new functions.https.HttpsError(
          "unauthenticated",
          "Kakao token rejected (status " + resp.status + ")."
        );
      }
      const profile = await resp.json();
      kakaoId = profile && profile.id != null ? String(profile.id) : null;
      kakaoEmail =
        profile && profile.kakao_account && profile.kakao_account.email
          ? profile.kakao_account.email
          : null;
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      throw new functions.https.HttpsError(
        "internal",
        "Kakao verification failed: " + String(e)
      );
    }
    if (!kakaoId) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "No Kakao id found in profile."
      );
    }

    const firestore = admin.firestore();
    const mapRef = firestore.collection("kakao_uid_map").doc(kakaoId);

    // ------------------------------------------------------------------
    // Fast path: 재방문자는 이메일 매칭/재확인을 스킵하고 바로 토큰 발급.
    // authEmailSet=true 는 과거 로그인에서 이메일 확인 절차를 이미
    // 1회 완료했다는 의미 (카카오 계정에 이메일이 없는 사용자도 포함).
    // ------------------------------------------------------------------
    const preCheckDoc = await mapRef.get();
    if (
      preCheckDoc.exists &&
      preCheckDoc.data().uid &&
      preCheckDoc.data().authEmailSet === true
    ) {
      const resolvedUid = preCheckDoc.data().uid;
      const token = await admin
        .auth()
        .createCustomToken(resolvedUid, { provider: "kakaocorp.com" });

      functions.logger.info("kakaoCustomAuth: fast path (returning user)", {
        anonUid: anonUid,
        resolvedUid: resolvedUid,
        kakaoIdPrefix: kakaoId.substring(0, 6),
      });

      return { token: token };
    }

    // ------------------------------------------------------------------
    // Slow path: 신규 가입자 또는 authEmailSet 미완료 사용자 (최초 1회 또는 재시도)
    // ------------------------------------------------------------------
    let emailMatchUid = null;
    if (kakaoEmail) {
      try {
        const existingUser = await admin.auth().getUserByEmail(kakaoEmail);
        if (existingUser && existingUser.uid) {
          emailMatchUid = existingUser.uid;
          functions.logger.info("kakaoCustomAuth: email match found", {
            kakaoEmail: kakaoEmail,
            existingUid: existingUser.uid,
          });
        }
      } catch (emailErr) {
        if (emailErr.code !== "auth/user-not-found") {
          functions.logger.warn("kakaoCustomAuth: getUserByEmail error", {
            error: String(emailErr),
          });
        }
      }
    }

    const resolvedUid = await firestore.runTransaction(async (tx) => {
      const mapDoc = await tx.get(mapRef);
      if (mapDoc.exists && mapDoc.data().uid) {
        return mapDoc.data().uid;
      }

      const targetUid = emailMatchUid || anonUid;
      tx.set(mapRef, {
        uid: targetUid,
        kakao_id: kakaoId,
        kakao_email: kakaoEmail || null,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return targetUid;
    });

    const token = await admin
      .auth()
      .createCustomToken(resolvedUid, { provider: "kakaocorp.com" });

    // Firebase Auth record email is required for later email-based account linking.
    if (kakaoEmail) {
      try {
        const existingAuthUser = await admin.auth().getUser(resolvedUid);
        if (!existingAuthUser.email) {
          await admin.auth().updateUser(resolvedUid, { email: kakaoEmail });
          functions.logger.info("kakaoCustomAuth: email set on auth record", {
            uid: resolvedUid,
            email: kakaoEmail,
          });
        }
      } catch (updateErr) {
        functions.logger.warn("kakaoCustomAuth: updateUser email failed", {
          uid: resolvedUid,
          error: String(updateErr),
        });
      }
    }

    // 이메일 확인 절차 완료 표시 -> 다음 로그인부터 fast path 진입
    try {
      await mapRef.set({ authEmailSet: true }, { merge: true });
    } catch (flagErr) {
      functions.logger.warn("kakaoCustomAuth: authEmailSet flag write failed", {
        uid: resolvedUid,
        error: String(flagErr),
      });
    }

    functions.logger.info("kakaoCustomAuth", {
      anonUid: anonUid,
      resolvedUid: resolvedUid,
      kakaoIdPrefix: kakaoId.substring(0, 6),
      returning: resolvedUid !== anonUid,
    });

    return { token: token };
  });

// ----------------------------------------------------------------------------
// linkOrCreateAccount
// Type:   HTTPS Callable
// Input:  { provider: "google" | "email", idToken?: string, email?: string }
// Output: { token: string, isNewUser: boolean }
//
// Email-based account linking:
//   1. Extract an email from the provider payload.
//   2. Resolve an existing Firebase Auth account by email.
//   3. Return a custom token for the existing account, or create a new account.
// ----------------------------------------------------------------------------
exports.linkOrCreateAccount = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    const provider = data && data.provider;
    if (!provider || !["google", "email"].includes(provider)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "provider must be 'google' or 'email'."
      );
    }

    let email = null;
    let displayName = null;

    if (provider === "google") {
      const idToken = data.idToken;
      if (!idToken || typeof idToken !== "string") {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "idToken is required for Google provider."
        );
      }

      try {
        const tokenInfoResp = await fetch(
          "https://oauth2.googleapis.com/tokeninfo?id_token=" +
            encodeURIComponent(idToken)
        );
        if (!tokenInfoResp.ok) {
          throw new Error("Google token rejected (status " + tokenInfoResp.status + ")");
        }

        const tokenInfo = await tokenInfoResp.json();
        if (tokenInfo.email_verified !== "true" && tokenInfo.email_verified !== true) {
          throw new Error("Google email is not verified.");
        }
        email = tokenInfo.email || null;
        displayName = tokenInfo.name || null;
      } catch (e) {
        throw new functions.https.HttpsError(
          "unauthenticated",
          "Invalid Google ID token: " + String(e)
        );
      }
    } else if (provider === "email") {
      email = data.email;
      if (!email || typeof email !== "string") {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "email is required for email provider."
        );
      }
    }

    if (!email) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Could not extract email from provider data."
      );
    }

    let existingUser = null;
    try {
      existingUser = await admin.auth().getUserByEmail(email);
    } catch (e) {
      if (e.code !== "auth/user-not-found") {
        throw new functions.https.HttpsError(
          "internal",
          "Failed to check existing account: " + String(e)
        );
      }
    }

    if (existingUser) {
      const token = await admin.auth().createCustomToken(existingUser.uid, {
        provider: provider,
        linked: true,
      });

      functions.logger.info("linkOrCreateAccount: existing user matched", {
        email: email,
        uid: existingUser.uid,
        provider: provider,
      });

      return { token: token, isNewUser: false };
    }

    const newUser = await admin.auth().createUser({
      email: email,
      displayName: displayName,
    });

    const token = await admin.auth().createCustomToken(newUser.uid, {
      provider: provider,
      linked: false,
    });

    functions.logger.info("linkOrCreateAccount: new user created", {
      email: email,
      uid: newUser.uid,
      provider: provider,
    });

    return { token: token, isNewUser: true };
  });


// ----------------------------------------------------------------------------
// Parent consent email token helpers
// ----------------------------------------------------------------------------
const PARENT_CONSENT_TOKEN_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const PARENT_CONSENT_TOKEN_COLLECTION = "parent_consent_tokens";

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function maskEmailForLog(email) {
  const atIndex = email.indexOf("@");
  if (atIndex <= 1) return "***";
  return `${email.slice(0, 2)}***${email.slice(atIndex)}`;
}

function maskTokenForLog(token) {
  return typeof token === "string" ? `${token.slice(0, 8)}...` : null;
}

function hashIp(value) {
  if (!value || typeof value !== "string") return null;
  return crypto.createHash("sha256").update(value).digest("hex");
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function renderConsentPage(title, message, type) {
  const colors = {
    success: "#2F8F5B",
    info: "#4A90D9",
    warning: "#B7791F",
    error: "#D64545",
  };
  const accent = colors[type] || colors.info;

  return `
    <!DOCTYPE html>
    <html lang="ko">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>${escapeHtml(title)} - StealthVox</title>
      <style>
        * { box-sizing: border-box; }
        body {
          margin: 0;
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 32px 18px;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          background: #111827;
          color: #111827;
        }
        .card {
          width: 100%;
          max-width: 440px;
          padding: 32px 26px;
          border-radius: 14px;
          background: #ffffff;
          text-align: center;
          box-shadow: 0 22px 60px rgba(0, 0, 0, 0.28);
        }
        .brand {
          margin: 0 0 18px;
          color: #6B7280;
          font-size: 14px;
          font-weight: 700;
          letter-spacing: 0;
        }
        .mark {
          width: 48px;
          height: 48px;
          margin: 0 auto 18px;
          border-radius: 50%;
          background: ${accent};
        }
        h1 {
          margin: 0 0 14px;
          font-size: 24px;
          line-height: 1.32;
          letter-spacing: 0;
        }
        p {
          margin: 0;
          color: #4B5563;
          font-size: 16px;
          line-height: 1.7;
        }
      </style>
    </head>
    <body>
      <main class="card">
        <div class="brand">StealthVox</div>
        <div class="mark" aria-hidden="true"></div>
        <h1>${escapeHtml(title)}</h1>
        <p>${escapeHtml(message)}</p>
      </main>
    </body>
    </html>
  `;
}

// ----------------------------------------------------------------------------
// sendParentConsentEmail
// Type:   HTTPS Callable
// Input:  { parentEmail: string }
// Output: { sent: boolean, alreadyApproved?: boolean }
//
// 14세 미만 가입자의 보호자에게 1회성 토큰 기반 동의 요청 이메일을 발송한다.
// ----------------------------------------------------------------------------
exports.sendParentConsentEmail = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "로그인이 필요합니다."
      );
    }

    const rawParentEmail = data && data.parentEmail;
    if (!rawParentEmail || typeof rawParentEmail !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "parentEmail is required."
      );
    }

    const parentEmail = rawParentEmail.trim().toLowerCase();
    if (!isValidEmail(parentEmail)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "유효한 보호자 이메일을 입력해 주세요."
      );
    }

    const uid = context.auth.uid;
    const firestore = admin.firestore();
    const userRef = firestore.collection("users").doc(uid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "사용자 정보를 찾을 수 없습니다."
      );
    }

    const userData = userDoc.data() || {};
    if (userData.parentConsentPending === false) {
      functions.logger.info("sendParentConsentEmail: already approved", { uid });
      return { sent: false, alreadyApproved: true };
    }

    if (userData.parentConsentPending !== true) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "보호자 동의가 필요한 상태가 아닙니다."
      );
    }

    const savedParentEmail =
      typeof userData.parentEmail === "string"
        ? userData.parentEmail.trim().toLowerCase()
        : null;

    if (savedParentEmail && savedParentEmail !== parentEmail) {
      functions.logger.warn("sendParentConsentEmail: parent email mismatch", {
        uid,
        requestedParentEmail: maskEmailForLog(parentEmail),
        savedParentEmail: maskEmailForLog(savedParentEmail),
      });
      throw new functions.https.HttpsError(
        "permission-denied",
        "저장된 보호자 이메일과 일치하지 않습니다."
      );
    }

    if (!savedParentEmail) {
      await userRef.set({ parentEmail }, { merge: true });
      functions.logger.info("sendParentConsentEmail: parent email saved", {
        uid,
        parentEmail: maskEmailForLog(parentEmail),
      });
    }

    const token = crypto.randomBytes(32).toString("hex");
    const tokenRef = firestore.collection(PARENT_CONSENT_TOKEN_COLLECTION).doc(token);
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + PARENT_CONSENT_TOKEN_TTL_MS
    );
    const projectId = process.env.GCLOUD_PROJECT || "stealth-vox-3p3rq3";
    const consentUrl =
      `https://us-central1-${projectId}.cloudfunctions.net/confirmParentConsent?token=${encodeURIComponent(token)}`;

    await tokenRef.create({
      uid,
      parentEmail,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
      approvedAt: null,
      consumedCount: 0,
      approvedIpHash: null,
      userAgent: null,
      mailDocId: null,
    });

    const mailRef = firestore.collection("mail").doc();
    await mailRef.set({
      to: [parentEmail],
      message: {
        subject: "StealthVox - 자녀 가입 동의 요청",
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto; padding: 24px; color: #1f2937;">
            <h2 style="margin: 0 0 16px; color: #111827;">StealthVox 보호자 동의 안내</h2>
            <p style="line-height: 1.7; color: #4b5563;">
              자녀가 StealthVox 앱에 가입하려고 합니다.<br>
              만 14세 미만 사용자는 보호자 동의가 필요합니다.
            </p>
            <p style="line-height: 1.7; color: #4b5563;">
              아래 버튼을 눌러 자녀의 StealthVox 이용에 동의해 주세요.
            </p>
            <a href="${consentUrl}"
               style="display: inline-block; padding: 14px 30px; background-color: #4A90D9;
                      color: #ffffff; text-decoration: none; border-radius: 8px; font-weight: bold;
                      margin: 16px 0;">
              동의합니다
            </a>
            <p style="line-height: 1.7; color: #4b5563;">
              버튼이 열리지 않으면 아래 링크를 브라우저에 복사해 주세요.<br>
              <a href="${consentUrl}" style="color: #2563eb; word-break: break-all;">${consentUrl}</a>
            </p>
            <p style="line-height: 1.7; color: #6b7280; font-size: 13px;">
              본인이 요청하지 않았다면 이 이메일을 무시하셔도 됩니다.<br>
              이 링크는 7일 후 만료됩니다.
            </p>
          </div>
        `,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await tokenRef.set({ mailDocId: mailRef.id }, { merge: true });

    functions.logger.info("sendParentConsentEmail: mail queued", {
      uid,
      parentEmail: maskEmailForLog(parentEmail),
      token: maskTokenForLog(token),
      mailDocId: mailRef.id,
    });

    return { sent: true };
  });

// ----------------------------------------------------------------------------
// confirmParentConsent
// Type:   HTTPS Request (GET)
// Query:  ?token=<random_token>
// Action: Validates token and grants parent consent on the server only.
// Response: Mobile-friendly HTML page.
// ----------------------------------------------------------------------------
exports.confirmParentConsent = functions
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    res.set("Content-Type", "text/html; charset=utf-8");

    if (req.method !== "GET") {
      res.status(405).send(renderConsentPage(
        "유효하지 않은 동의 링크입니다",
        "허용되지 않은 요청 방식입니다.",
        "error"
      ));
      return;
    }

    if (req.query.uid) {
      res.status(400).send(renderConsentPage(
        "유효하지 않은 동의 링크입니다",
        "앱에서 보호자 동의 메일을 다시 요청해 주세요.",
        "error"
      ));
      return;
    }

    const token = req.query.token;
    if (!token || typeof token !== "string" || token.length < 64) {
      res.status(400).send(renderConsentPage(
        "유효하지 않은 동의 링크입니다",
        "앱에서 보호자 동의 메일을 다시 요청해 주세요.",
        "error"
      ));
      return;
    }

    const firestore = admin.firestore();
    const tokenRef = firestore.collection(PARENT_CONSENT_TOKEN_COLLECTION).doc(token);

    try {
      const tokenDoc = await tokenRef.get();
      if (!tokenDoc.exists) {
        res.status(404).send(renderConsentPage(
          "유효하지 않은 동의 링크입니다",
          "앱에서 보호자 동의 메일을 다시 요청해 주세요.",
          "error"
        ));
        return;
      }

      const tokenData = tokenDoc.data() || {};
      const expiresAt = tokenData.expiresAt;
      const now = admin.firestore.Timestamp.now();

      if (!expiresAt || expiresAt.toMillis() <= now.toMillis()) {
        await tokenRef.set({ status: "expired" }, { merge: true });
        res.status(410).send(renderConsentPage(
          "동의 링크가 만료되었습니다",
          "앱에서 보호자 동의 메일을 다시 요청해 주세요.",
          "warning"
        ));
        return;
      }

      if (tokenData.status === "approved") {
        res.status(200).send(renderConsentPage(
          "이미 동의가 완료되었습니다",
          "StealthVox 자녀 계정 이용 동의가 이미 완료되었습니다.",
          "info"
        ));
        return;
      }

      if (tokenData.status !== "pending") {
        res.status(400).send(renderConsentPage(
          "유효하지 않은 동의 링크입니다",
          "사용할 수 없는 동의 링크입니다.",
          "error"
        ));
        return;
      }

      const uid = tokenData.uid;
      if (!uid || typeof uid !== "string") {
        res.status(400).send(renderConsentPage(
          "유효하지 않은 동의 링크입니다",
          "사용자 정보를 확인할 수 없습니다.",
          "error"
        ));
        return;
      }

      const userRef = firestore.collection("users").doc(uid);
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        res.status(404).send(renderConsentPage(
          "사용자 정보를 찾을 수 없습니다",
          "앱에서 보호자 동의 메일을 다시 요청해 주세요.",
          "error"
        ));
        return;
      }

      const userAgent = req.headers["user-agent"] || null;
      const forwardedFor = req.headers["x-forwarded-for"];
      const rawIp = Array.isArray(forwardedFor)
        ? forwardedFor[0]
        : (forwardedFor || req.ip || null);
      const approvedIpHash = hashIp(rawIp);

      await firestore.runTransaction(async (transaction) => {
        const freshTokenDoc = await transaction.get(tokenRef);
        if (!freshTokenDoc.exists) {
          throw new Error("token-not-found");
        }

        const freshTokenData = freshTokenDoc.data() || {};
        const freshExpiresAt = freshTokenData.expiresAt;
        if (!freshExpiresAt || freshExpiresAt.toMillis() <= Date.now()) {
          transaction.set(tokenRef, { status: "expired" }, { merge: true });
          throw new Error("token-expired");
        }

        if (freshTokenData.status === "approved") {
          throw new Error("token-approved");
        }
        if (freshTokenData.status !== "pending") {
          throw new Error("token-not-pending");
        }

        const freshUserRef = firestore.collection("users").doc(freshTokenData.uid);
        const freshUserDoc = await transaction.get(freshUserRef);
        if (!freshUserDoc.exists) {
          throw new Error("user-not-found");
        }

        transaction.set(freshUserRef, {
          parentConsentPending: false,
          parentConsentGrantedAt: admin.firestore.FieldValue.serverTimestamp(),
          parentConsentMethod: "email_link",
          parentConsentEmail: freshTokenData.parentEmail || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        transaction.set(tokenRef, {
          status: "approved",
          approvedAt: admin.firestore.FieldValue.serverTimestamp(),
          consumedCount: admin.firestore.FieldValue.increment(1),
          userAgent,
          approvedIpHash,
        }, { merge: true });
      });

      functions.logger.info("confirmParentConsent: consent granted", {
        uid,
        token: maskTokenForLog(token),
      });

      res.status(200).send(renderConsentPage(
        "보호자 동의가 완료되었습니다",
        "StealthVox 자녀 계정 이용 동의가 완료되었습니다. 이제 앱에서 정상 이용할 수 있습니다.",
        "success"
      ));
    } catch (e) {
      const code = e && e.message;
      if (code === "token-expired") {
        res.status(410).send(renderConsentPage(
          "동의 링크가 만료되었습니다",
          "앱에서 보호자 동의 메일을 다시 요청해 주세요.",
          "warning"
        ));
        return;
      }
      if (code === "token-approved") {
        res.status(200).send(renderConsentPage(
          "이미 동의가 완료되었습니다",
          "StealthVox 자녀 계정 이용 동의가 이미 완료되었습니다.",
          "info"
        ));
        return;
      }
      if (code === "token-not-found" || code === "token-not-pending") {
        res.status(400).send(renderConsentPage(
          "유효하지 않은 동의 링크입니다",
          "앱에서 보호자 동의 메일을 다시 요청해 주세요.",
          "error"
        ));
        return;
      }
      if (code === "user-not-found") {
        res.status(404).send(renderConsentPage(
          "사용자 정보를 찾을 수 없습니다",
          "앱에서 보호자 동의 메일을 다시 요청해 주세요.",
          "error"
        ));
        return;
      }

      functions.logger.error("confirmParentConsent: error", {
        token: maskTokenForLog(token),
        error: String(e),
      });
      res.status(500).send(renderConsentPage(
        "일시적인 오류가 발생했습니다",
        "잠시 후 다시 시도해 주세요.",
        "error"
      ));
    }
  });