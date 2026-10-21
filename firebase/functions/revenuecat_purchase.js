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

// RevenueCat이 보내는 실제 결제 금액. price는 USD로 환산한 값,
// price_in_purchased_currency와 currency는 사용자가 실제로 낸 돈이다.
// 173개국이 나라별 가격이라 상품 가격표로는 맞출 수 없어 이벤트 값을 그대로 남긴다.
// 없는 이벤트도 있으므로 숫자가 아니면 null.
function paidAmount(event) {
  const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : null);
  const text = (v) => (typeof v === "string" && v.trim() ? v.trim() : null);
  return {
    price_usd: num(event.price),
    price_paid: num(event.price_in_purchased_currency),
    currency: text(event.currency),
    country_code: text(event.country_code),
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
  const realMemberRef = firestore.doc("real_members/" + appUserId);
  const memberPurchaseRef =
    realMemberRef.collection("purchases").doc(eventId);
  const allowlistRef = firestore.doc(SANDBOX_ALLOWLIST_PATH);

  return firestore.runTransaction(async (tx) => {
    const refs = [purchaseRef, userRef, realMemberRef];
    if (environment === "SANDBOX") refs.push(allowlistRef);
    const snapshots = await Promise.all(refs.map((ref) => tx.get(ref)));
    const purchaseSnap = snapshots[0];
    const userSnap = snapshots[1];
    const realMemberSnap = snapshots[2];
    const allowlistSnap = snapshots[3];

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
    const purchaseData = {
      rc_event_id: eventId,
      product_id: productId,
      product_title: product.title,
      seconds_added: product.seconds,
      source: "revenuecat_webhook",
      event_type: event.type,
      environment,
      ...paidAmount(event),
      purchased_at: serverTimestamp(),
    };
    tx.set(purchaseRef, purchaseData);
    tx.set(memberPurchaseRef, purchaseData);

    const memberData = realMemberSnap.exists ? realMemberSnap.data() || {} : {};
    const purchaseCount =
      typeof memberData.purchaseCount === "number" ? memberData.purchaseCount : 0;
    const totalSecondsPurchased =
      typeof memberData.totalSecondsPurchased === "number"
        ? memberData.totalSecondsPurchased
        : 0;
    const totalSpentUsd =
      typeof memberData.totalSpentUsd === "number" ? memberData.totalSpentUsd : 0;
    const priceUsd = purchaseData.price_usd || 0;
    tx.set(realMemberRef, {
      uid: appUserId,
      isRealMember: true,
      hasPurchase: true,
      purchaseCount: purchaseCount + 1,
      totalSecondsPurchased: totalSecondsPurchased + product.seconds,
      // 소수점 누적 오차를 센트 단위로 끊는다.
      totalSpentUsd: Math.round((totalSpentUsd + priceUsd) * 100) / 100,
      lastPricePaid: purchaseData.price_paid,
      lastCurrency: purchaseData.currency,
      lastPurchasedAt: serverTimestamp(),
      lastProductId: productId,
      lastPurchaseEnvironment: environment,
    }, {merge: true});

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
  paidAmount,
  processRevenueCatPurchase,
  sandboxUidIsAllowed,
  validatePurchaseEvent,
};
