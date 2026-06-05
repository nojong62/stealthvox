// ============================================================================
// firebase/functions/index.js
// ----------------------------------------------------------------------------
// Cloud Functions for StealthVox
//   - onUserDeleted:        cleanup when a Firebase Auth user is deleted
//   - deductRemainingTime:  callable that deducts user's subscription time
//                           (with auth check, range validation, transaction)
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
  // (existing cleanup logic preserved as-is)
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

        // Write both canonical and legacy fields to stay consistent with client.
        tx.set(
          userRef,
          {
            remainingTime: updated,
            remaining_seconds: updated,
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