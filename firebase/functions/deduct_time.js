const crypto = require("crypto");

function deductionDocumentId(uid, requestId) {
  return crypto.createHash("sha256")
    .update(`${uid}:${requestId}`)
    .digest("hex");
}

// A flush whose response was lost (timeout, network drop after commit) is
// retried by the client with the same request id. The marker document makes
// that retry return the current balance instead of deducting a second time.
// Calls without a request id (older installed builds) keep the old behavior.
async function deductTimeIdempotently({
  db,
  uid,
  seconds,
  requestId,
  serverTimestamp,
}) {
  const userRef = db.doc(`users/${uid}`);
  const markerRef = requestId
    ? userRef.collection("deductions").doc(deductionDocumentId(uid, requestId))
    : null;

  return db.runTransaction(async tx => {
    const markerSnap = markerRef ? await tx.get(markerRef) : null;
    const userSnap = await tx.get(userRef);
    const current = userSnap.exists ? userSnap.data().remainingTime : null;

    if (markerSnap && markerSnap.exists) {
      return {
        duplicate: true,
        before: current,
        after: typeof current === "number" ? current : 0,
      };
    }
    if (!userSnap.exists || current == null) {
      return { duplicate: false, before: null, after: 0 };
    }

    const updated = Math.max(0, current - seconds);
    tx.update(userRef, { remainingTime: updated });
    if (markerRef) {
      tx.set(markerRef, {
        created_at: serverTimestamp(),
        request_id: requestId,
        seconds,
        before_seconds: current,
        after_seconds: updated,
      });
    }
    return { duplicate: false, before: current, after: updated };
  });
}

module.exports = { deductionDocumentId, deductTimeIdempotently };
