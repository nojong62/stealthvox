"use strict";

const DAY_MS = 86400000;
const POLICY_PATH = "account_cleanup_policy/designated_google_test_accounts";

function inactive(user, now = Date.now()) {
  const dates = [user.metadata.creationTime, user.metadata.lastSignInTime];
  if (user.metadata.lastRefreshTime) dates.push(user.metadata.lastRefreshTime);
  const times = dates.map(Date.parse);
  return times.every(Number.isFinite) && Math.max(...times) <= now - 30 * DAY_MS;
}

function designated(user, emails, googleMapped) {
  if (!user.email || !emails.has(user.email.toLowerCase()) || user.phoneNumber ||
      Object.keys(user.customClaims || {}).length) return false;
  const providers = user.providerData || [];
  return providers.some(p => p.providerId === "google.com") ||
    (providers.length === 0 && googleMapped.has(user.uid));
}

async function runDesignatedGoogleCleanup({auth, db, dryRun = true,
                                          now = Date.now(), log = console.log}) {
  const result = {startedAt: new Date(now).toISOString(), retentionDays: 30,
    dryRun, considered: 0, deletedUids: [], skippedUids: [], errors: []};
  const policy = await db.doc(POLICY_PATH).get();
  if (!policy.exists) return {...result, policyMissing: true};
  const values = policy.data().emails;
  if (!Array.isArray(values) || values.some(e => typeof e !== "string" || !e.includes("@"))) {
    throw new Error("Invalid designated Google cleanup policy");
  }
  const emails = new Set(values.map(e => e.toLowerCase()));
  const mapping = await db.collection("provider_uid_map").get();
  const googleMapped = new Set(mapping.docs.filter(d => d.data().provider === "google")
    .map(d => d.data().uid));
  const kakaoMapping = await db.collection("kakao_uid_map").get();
  const kakaoUids = new Set(kakaoMapping.docs.map(d => d.data().uid));
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  const candidates = users.filter(u => designated(u, emails, googleMapped) &&
    inactive(u, now) && !kakaoUids.has(u.uid));
  result.considered = candidates.length;
  for (const user of candidates) {
    try {
      const fresh = await auth.getUser(user.uid);
      const kakao = await db.collection("kakao_uid_map").where("uid", "==", user.uid).limit(1).get();
      if (!designated(fresh, emails, googleMapped) || !inactive(fresh, Date.now()) || !kakao.empty) {
        result.skippedUids.push(user.uid);
        continue;
      }
      if (!dryRun) {
        await auth.deleteUser(user.uid);
        result.deletedUids.push(user.uid);
        log("Deleted inactive user-designated Google test account: " + user.uid);
      }
    } catch (error) {
      if (error.code === "auth/user-not-found") result.skippedUids.push(user.uid);
      else result.errors.push({uid: user.uid, code: error.code || "unknown"});
    }
  }
  result.finishedAt = new Date().toISOString();
  return result;
}

module.exports = {inactive, designated, runDesignatedGoogleCleanup};
