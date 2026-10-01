"use strict";

const DAY_MS = 24 * 60 * 60 * 1000;
const RETENTION_DAYS = 30;

function eligible(user, now = Date.now()) {
  if (user.email || user.phoneNumber || (user.providerData || []).length ||
      Object.keys(user.customClaims || {}).length) return false;
  const created = Date.parse(user.metadata.creationTime);
  const signedIn = Date.parse(user.metadata.lastSignInTime);
  const refreshed = Date.parse(user.metadata.lastRefreshTime || "");
  return Number.isFinite(created) && Number.isFinite(signedIn) &&
    Math.max(created, signedIn, Number.isFinite(refreshed) ? refreshed : 0) <= now - RETENTION_DAYS * DAY_MS;
}

function findUids(value, uids, found = new Set()) {
  if (typeof value === "string") {
    if (uids.has(value)) found.add(value);
    for (const token of value.split(/[^a-zA-Z0-9_-]+/)) {
      if (uids.has(token)) found.add(token);
    }
  } else if (Array.isArray(value)) {
    for (const item of value) findUids(item, uids, found);
  } else if (value && typeof value === "object") {
    if (typeof value.path === "string") findUids(value.path, uids, found);
    for (const [key, item] of Object.entries(value)) {
      // Firestore references are handled through their public path above.
      if (key.startsWith("_")) continue;
      findUids(key, uids, found);
      findUids(item, uids, found);
    }
  }
  return found;
}

async function mapLimit(values, limit, fn) {
  let cursor = 0;
  await Promise.all(Array.from({length: Math.min(limit, values.length)}, async () => {
    while (cursor < values.length) await fn(values[cursor++]);
  }));
}

async function hasOwnedData(db, uid) {
  const ref = db.doc("users/" + uid);
  if ((await ref.get()).exists) return true;
  for (const collection of await ref.listCollections()) {
    // listDocuments includes missing ancestors that still have descendants.
    if ((await collection.listDocuments()).length) return true;
  }
  return false;
}

async function collectFirestoreProtection(db, uids) {
  const protectedUids = new Set();
  await mapLimit([...uids], 8, async (uid) => {
    if (await hasOwnedData(db, uid)) protectedUids.add(uid);
  });
  const queue = (await db.listCollections()).filter(c =>
    c.id !== "users" && c.id !== "anonymous_cleanup_runs");
  while (queue.length) {
    const collections = queue.splice(0, 8);
    await mapLimit(collections, 8, async (collection) => {
      const refs = await collection.listDocuments();
      for (let start = 0; start < refs.length; start += 100) {
        const batch = refs.slice(start, start + 100);
        const docs = await db.getAll(...batch);
        await mapLimit(docs, 8, async (doc) => {
          // Paths themselves can encode ownership, even for missing ancestors.
          findUids(doc.ref.path, uids, protectedUids);
          if (doc.exists) findUids(doc.data(), uids, protectedUids);
          queue.push(...await doc.ref.listCollections());
        });
      }
    });
  }
  return protectedUids;
}

async function storageProtection(storage, project, uids) {
  const protectedUids = new Set();
  const [buckets] = await storage.getBuckets();
  // Build/deployment source buckets are not application user data.
  const names = new Set([project + ".firebasestorage.app", project + ".appspot.com"]);
  let fileCount = 0;
  for (const bucket of buckets.filter(b => names.has(b.name))) {
    let query = {autoPaginate: false, maxResults: 1000};
    do {
      const [files, next] = await bucket.getFiles(query);
      for (const file of files) {
        findUids(file.name, uids, protectedUids);
        findUids(file.metadata.metadata || {}, uids, protectedUids);
        fileCount++;
      }
      query = next;
    } while (query);
  }
  return {protectedUids, fileCount};
}

async function runCleanup({auth, db, storage, project, dryRun = true,
                           allowedUids, now = Date.now(), log = console.log}) {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  const candidates = users.filter(user => eligible(user, now) &&
    (!allowedUids || allowedUids.has(user.uid)));
  const uids = new Set(candidates.map(user => user.uid));
  // Complete every data check before deleting anyone. A failed read aborts the run.
  const firestoreProtected = await collectFirestoreProtection(db, uids);
  const storageResult = await storageProtection(storage, project, uids);
  const result = {startedAt: new Date(now).toISOString(), retentionDays: RETENTION_DAYS,
    dryRun, considered: candidates.length, firestoreProtected: firestoreProtected.size,
    storageProtected: storageResult.protectedUids.size, storageFiles: storageResult.fileCount,
    eligibleUids: [], deletedUids: [], skippedUids: [], errors: []};
  for (const user of candidates) {
    if (firestoreProtected.has(user.uid) || storageResult.protectedUids.has(user.uid)) {
      result.skippedUids.push(user.uid);
      continue;
    }
    // Recheck sign-in/link changes and owned data immediately before each deletion.
    try {
      const fresh = await auth.getUser(user.uid);
      const identityMaps = ["kakao_uid_map", "provider_uid_map"];
      let linked = false;
      for (const name of identityMaps) {
        if (!(await db.collection(name).where("uid", "==", user.uid).limit(1).get()).empty) linked = true;
      }
      if (!eligible(fresh, Date.now()) || linked || await hasOwnedData(db, user.uid)) {
        result.skippedUids.push(user.uid);
        continue;
      }
      result.eligibleUids.push(user.uid);
      if (!dryRun) {
        await auth.deleteUser(user.uid);
        result.deletedUids.push(user.uid);
        log("Deleted inactive data-free anonymous account: " + user.uid);
      }
    } catch (error) {
      if (error.code === "auth/user-not-found") result.skippedUids.push(user.uid);
      else result.errors.push({uid: user.uid, code: error.code || "unknown"});
    }
  }
  result.finishedAt = new Date().toISOString();
  return result;
}

exports.eligible = eligible;
exports.findUids = findUids;
exports.hasOwnedData = hasOwnedData;
exports.runCleanup = runCleanup;

