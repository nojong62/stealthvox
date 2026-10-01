"use strict";
const fs = require("fs");
const path = require("path");
const base = "C:/Users/u/AppData/Roaming/npm/node_modules/firebase-tools/lib/";
const cliAuth = require(base + "auth");
const {requireAuth} = require(base + "requireAuth");
const {Client, getAccessToken} = require(base + "apiv2");
const admin = require("../firebase/functions/node_modules/firebase-admin");
const {runCleanup} = require("../firebase/functions-cleanup/anonymous_cleanup");
const project = "stealth-vox-3p3rq3";
const dryRun = !process.argv.includes("--delete");
const client = new Client({urlPrefix: "https://storage.googleapis.com"});
const storage = {
  async getBuckets() {
    const buckets = [];
    let pageToken;
    do {
      const r = await client.get("/storage/v1/b", {queryParams: {project, ...(pageToken ? {pageToken} : {})}});
      for (const item of r.body.items || []) {
        buckets.push({name: item.name, async getFiles(query) {
          const r = await client.get("/storage/v1/b/" + encodeURIComponent(item.name) + "/o",
            {queryParams: {maxResults: query.maxResults, ...(query.pageToken ? {pageToken: query.pageToken} : {})}});
          return [(r.body.items || []).map(f => ({name: f.name, metadata: f})),
            r.body.nextPageToken ? {...query, pageToken: r.body.nextPageToken} : undefined];
        }});
      }
      pageToken = r.body.nextPageToken;
    } while (pageToken);
    return [buckets];
  }
};
(async () => {
  const options = {project, nonInteractive: true};
  cliAuth.setActiveAccount(options, cliAuth.getGlobalDefaultAccount());
  await requireAuth(options);
  admin.initializeApp({projectId: project, credential: {
    async getAccessToken() { return {access_token: await getAccessToken(), expires_in: 3600}; }
  }});
  const db = require("./firebase_cli_firestore.cjs");
  const allowedUids = new Set(fs.readFileSync(path.resolve("anonymous_account_candidates.csv"), "utf8")
    .trim().split(/\r?\n/).slice(1).map(line => line.split(",")[0]));
  console.log("Fresh checks for " + allowedUids.size + " previously reviewed accounts. dryRun=" + dryRun);
  const result = await runCleanup({auth: admin.auth(), db, storage, project, dryRun, allowedUids});
  fs.writeFileSync(dryRun ? "anonymous_cleanup_dry_run.json" : "anonymous_cleanup_result.json",
    JSON.stringify(result, null, 2));
  if (!dryRun) await db.collection("anonymous_cleanup_runs").add(result);
  console.log(JSON.stringify({considered: result.considered, eligible: result.eligibleUids.length,
    deleted: result.deletedUids.length, skipped: result.skippedUids.length,
    storageFiles: result.storageFiles, errors: result.errors}));
  await admin.app().delete();
  if (result.errors.length) process.exitCode = 1;
})().catch(error => {console.error(error.message); process.exitCode = 1;});

