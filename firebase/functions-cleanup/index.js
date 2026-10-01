"use strict";
const admin = require("firebase-admin");
admin.initializeApp();
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { runCleanup } = require("./anonymous_cleanup");
const { runDesignatedGoogleCleanup } = require("./designated_google_cleanup");

exports.cleanupInactiveAnonymousUsers = onSchedule({
  schedule: "0 3 * * *",
  timeZone: "Asia/Seoul",
  region: "asia-northeast3",
  timeoutSeconds: 1800,
  memory: "512MiB",
  maxInstances: 1,
  retryCount: 0,
}, async () => {
  const db = admin.firestore();
  const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  if (project !== "stealth-vox-3p3rq3") throw new Error("Unexpected cleanup project");
  const result = await runCleanup({
    auth: admin.auth(),
    db,
    storage: admin.storage().bucket(project + ".firebasestorage.app").storage,
    project,
    dryRun: false,
  });
  await db.collection("anonymous_cleanup_runs").add(result);
  console.log("Anonymous cleanup summary", {
    considered: result.considered, deleted: result.deletedUids.length,
    skipped: result.skippedUids.length, errors: result.errors.length,
  });
  const googleResult = await runDesignatedGoogleCleanup({auth: admin.auth(), db, dryRun: false});
  await db.collection("designated_google_cleanup_runs").add(googleResult);
  console.log("Designated Google cleanup summary", {considered: googleResult.considered, deleted: googleResult.deletedUids.length, errors: googleResult.errors.length});
  if (result.errors.length || googleResult.errors.length) throw new Error("Some account deletions failed");
});

