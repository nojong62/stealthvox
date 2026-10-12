const crypto = require("crypto");

function usageLogDocumentId(uid, requestId) {
  return crypto.createHash("sha256")
    .update(`${uid}:${requestId}`)
    .digest("hex");
}

async function writeUsageLogIdempotently({
  db,
  uid,
  requestId,
  fields,
  serverTimestamp,
}) {
  const userRef = db.doc(`users/${uid}`);
  const logRef = userRef.collection("usage_logs")
    .doc(usageLogDocumentId(uid, requestId));

  return db.runTransaction(async tx => {
    const existing = await tx.get(logRef);
    if (existing.exists) {
      const data = existing.data() || {};
      return {
        duplicate: true,
        beforeSeconds: data.before_seconds,
        afterSeconds: data.after_seconds,
      };
    }

    const userSnap = await tx.get(userRef);
    const afterSeconds = userSnap.exists &&
      typeof userSnap.data().remainingTime === "number"
      ? userSnap.data().remainingTime
      : 0;
    const beforeSeconds = afterSeconds + fields.seconds_used;
    tx.set(logRef, {
      created_at: serverTimestamp(),
      ...fields,
      request_id: requestId,
      before_seconds: beforeSeconds,
      after_seconds: afterSeconds,
    });
    return { duplicate: false, beforeSeconds, afterSeconds };
  });
}

module.exports = { usageLogDocumentId, writeUsageLogIdempotently };
