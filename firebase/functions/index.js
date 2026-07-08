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
// sendParentConsentEmail
// Type:   HTTPS Callable
// Input:  { parentEmail: string }
// Output: { sent: boolean }
//
// 14세 미만 가입자의 보호자에게 동의 요청 이메일을 발송한다.
// 이메일에 포함된 링크를 클릭하면 confirmParentConsent 엔드포인트가 호출되어
// Firestore의 parentConsentPending이 false로 업데이트된다.
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

    const parentEmail = data && data.parentEmail;
    if (!parentEmail || typeof parentEmail !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "parentEmail is required."
      );
    }

    const uid = context.auth.uid;
    const projectId = process.env.GCLOUD_PROJECT || "stealth-vox-3p3rq3";
    const consentUrl =
      `https://us-central1-${projectId}.cloudfunctions.net/confirmParentConsent?uid=${encodeURIComponent(uid)}`;

    const mailRef = admin.firestore().collection("mail").doc();
    await mailRef.set({
      to: parentEmail,
      message: {
        subject: "StealthVox - 자녀 가입 동의 요청",
        html: `
          <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; padding: 24px;">
            <h2 style="color: #333;">StealthVox 보호자 동의</h2>
            <p style="color: #555; line-height: 1.6;">
              자녀가 StealthVox 앱에 가입하려고 합니다.<br>
              만 14세 미만 사용자는 보호자의 동의가 필요합니다.
            </p>
            <p style="color: #555; line-height: 1.6;">
              아래 버튼을 눌러 자녀의 가입에 동의해 주세요.
            </p>
            <a href="${consentUrl}"
               style="display: inline-block; padding: 14px 32px; background-color: #4A90D9;
                      color: white; text-decoration: none; border-radius: 8px; font-weight: bold;
                      margin-top: 16px;">
              동의합니다
            </a>
            <p style="color: #999; font-size: 12px; margin-top: 24px;">
              본인이 요청하지 않았다면 이 이메일을 무시하셔도 됩니다.
            </p>
          </div>
        `,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    functions.logger.info("sendParentConsentEmail: mail queued", {
      uid: uid,
      parentEmail: parentEmail,
    });

    return { sent: true };
  });

// ----------------------------------------------------------------------------
// confirmParentConsent
// Type:   HTTPS Request (GET)
// Query:  ?uid=<firebase_uid>
// Action: Firestore users/{uid}.parentConsentPending = false
// Response: HTML 확인 페이지
// ----------------------------------------------------------------------------
exports.confirmParentConsent = functions
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    const uid = req.query.uid;
    if (!uid || typeof uid !== "string") {
      res.status(400).send("<h1>잘못된 요청입니다.</h1>");
      return;
    }

    try {
      const userRef = admin.firestore().collection("users").doc(uid);
      const userDoc = await userRef.get();

      if (!userDoc.exists) {
        res.status(404).send("<h1>사용자를 찾을 수 없습니다.</h1>");
        return;
      }

      await userRef.update({ parentConsentPending: false });

      functions.logger.info("confirmParentConsent: consent granted", {
        uid: uid,
      });

      res.status(200).send(`
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="font-family: sans-serif; text-align: center; padding: 60px 24px;">
          <h1 style="color: #4A90D9;">동의가 완료되었습니다</h1>
          <p style="color: #555; font-size: 16px; line-height: 1.6;">
            자녀의 StealthVox 가입이 승인되었습니다.<br>
            이 페이지를 닫아도 됩니다.
          </p>
        </body>
        </html>
      `);
    } catch (e) {
      functions.logger.error("confirmParentConsent: error", {
        uid: uid,
        error: String(e),
      });
      res.status(500).send("<h1>오류가 발생했습니다. 다시 시도해 주세요.</h1>");
    }
  });
