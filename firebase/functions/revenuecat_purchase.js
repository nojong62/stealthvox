"use strict";

const SANDBOX_ALLOWLIST_PATH = "billing_config/revenuecat_sandbox";
const SUPPORTED_ENVIRONMENTS = new Set(["PRODUCTION", "SANDBOX"]);

function validatePurchaseEvent(event, products) {
  if (!event || typeof event !== "object") {
    return {reason: "missing_event_id"};
  }
  const eventId = typeof event.id === "string" ? event.id.trim() : "";
  if (!eventId) return {reason: "missing_event_id"};

  const product = products[event.product_id];
  if (!product || !Number.isFinite(product.seconds) || product.seconds <= 0) {
    return {reason: "invalid_product", eventId};
  }

  const environment = event.environment;
  if (!SUPPORTED_ENVIRONMENTS.has(environment)) {
    return {reason: "unsupported_environment", eventId};
  }

  const appUserId =
    typeof event.app_user_id === "string" ? event.app_user_id.trim() : "";
  if (!appUserId) return {reason: "user_not_found", eventId};

  return {
    eventId,
    appUserId,
    environment,
    productId: event.product_id,
    product,
  };
}

function sandboxUidIsAllowed(config, uid) {
  if (!config || config.enabled === false || !Array.isArray(config.allowed_uids)) {
    return false;
  }
  return config.allowed_uids.includes(uid);
}

async function processRevenueCatPurchase({
  firestore,
  event,
  products,
  serverTimestamp,
}) {
  const validated = validatePurchaseEvent(event, products);
  if (validated.reason) return validated;

  const {eventId, appUserId, environment, productId, product} = validated;
  const userRef = firestore.doc("users/" + appUserId);
  const purchaseRef = userRef.collection("purchases").doc(eventId);
  const allowlistRef = firestore.doc(SANDBOX_ALLOWLIST_PATH);

  return firestore.runTransaction(async (tx) => {
    const refs = [purchaseRef, userRef];
    if (environment === "SANDBOX") refs.push(allowlistRef);
    const snapshots = await Promise.all(refs.map((ref) => tx.get(ref)));
    const purchaseSnap = snapshots[0];
    const userSnap = snapshots[1];
    const allowlistSnap = snapshots[2];

    if (purchaseSnap.exists) {
      return {reason: "duplicate_event", eventId, appUserId, environment};
    }
    if (!userSnap.exists) {
      return {reason: "user_not_found", eventId, appUserId, environment};
    }
    if (
      environment === "SANDBOX" &&
      (!allowlistSnap.exists ||
        !sandboxUidIsAllowed(allowlistSnap.data(), appUserId))
    ) {
      return {reason: "sandbox_not_allowed", eventId, appUserId, environment};
    }

    const userData = userSnap.data() || {};
    const current =
      typeof userData.remainingTime === "number" ? userData.remainingTime : 0;
    const updated = current + product.seconds;

    tx.update(userRef, {remainingTime: updated});
    tx.set(purchaseRef, {
      rc_event_id: eventId,
      product_id: productId,
      product_title: product.title,
      seconds_added: product.seconds,
      source: "revenuecat_webhook",
      event_type: event.type,
      environment,
      purchased_at: serverTimestamp(),
    });

    return {
      reason: "success",
      eventId,
      appUserId,
      productId,
      environment,
      secondsAdded: product.seconds,
      remainingTime: updated,
    };
  });
}

module.exports = {
  SANDBOX_ALLOWLIST_PATH,
  processRevenueCatPurchase,
  sandboxUidIsAllowed,
  validatePurchaseEvent,
};
