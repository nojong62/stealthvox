"use strict";

const {HttpsError, onCall} = require("firebase-functions/v2/https");

const REGION = "asia-northeast3";

function normalizedProviderIds(userRecord, signInProvider) {
  const providers = new Set(
    (userRecord.providerData || [])
      .map((provider) => String(provider.providerId || "").trim())
      .filter(Boolean)
  );
  if (signInProvider && signInProvider !== "anonymous") {
    providers.add(signInProvider);
  }
  return [...providers].sort();
}

function isRealMemberProvider(signInProvider) {
  return Boolean(signInProvider && signInProvider !== "anonymous");
}

function createSyncRealMemberProfile(admin) {
  return onCall({region: REGION, enforceAppCheck: true}, async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }
    const signInProvider = String(
      request.auth.token && request.auth.token.firebase &&
      request.auth.token.firebase.sign_in_provider || ""
    );
    if (!isRealMemberProvider(signInProvider)) {
      return {registered: false, reason: "anonymous"};
    }

    const userRecord = await admin.auth().getUser(uid);
    const joinedDate = new Date(userRecord.metadata.creationTime);
    const lastSignInDate = new Date(userRecord.metadata.lastSignInTime);
    const Timestamp = admin.firestore.Timestamp;
    const FieldValue = admin.firestore.FieldValue;

    await admin.firestore().doc("real_members/" + uid).set({
      uid,
      email: userRecord.email || null,
      displayName: userRecord.displayName || null,
      providers: normalizedProviderIds(userRecord, signInProvider),
      primaryProvider: signInProvider,
      joinedAt: Number.isNaN(joinedDate.getTime())
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(joinedDate),
      lastSignInAt: Number.isNaN(lastSignInDate.getTime())
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(lastSignInDate),
      lastSeenAt: FieldValue.serverTimestamp(),
      isRealMember: true,
    }, {merge: true});

    return {registered: true};
  });
}

module.exports = {
  createSyncRealMemberProfile,
  isRealMemberProvider,
  normalizedProviderIds,
};
