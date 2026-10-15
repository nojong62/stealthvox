"use strict";
// 관리자 웹용 Custom Claim(admin: true)을 붙이거나 뗀다.
//
//   node tool/grant_admin_claim.cjs <uid>            # 확인만 (기본)
//   node tool/grant_admin_claim.cjs <uid> --apply    # admin: true 부여
//   node tool/grant_admin_claim.cjs <uid> --revoke   # admin 제거
//
// firebase CLI 로그인 계정으로 동작한다. 기존 다른 Claim은 그대로 둔다.
// Claim이 하나라도 있는 계정은 functions-cleanup의 자동 정리 대상에서 빠진다.
const base = "C:/Users/u/AppData/Roaming/npm/node_modules/firebase-tools/lib/";
const cliAuth = require(base + "auth");
const {requireAuth} = require(base + "requireAuth");
const {getAccessToken} = require(base + "apiv2");
const admin = require("../firebase/functions/node_modules/firebase-admin");
const project = "stealth-vox-3p3rq3";

const uid = process.argv[2];
const apply = process.argv.includes("--apply");
const revoke = process.argv.includes("--revoke");
if (!uid || uid.startsWith("--") || (apply && revoke)) {
  console.error("usage: node tool/grant_admin_claim.cjs <uid> [--apply | --revoke]");
  process.exit(1);
}

(async () => {
  const options = {project, nonInteractive: true};
  cliAuth.setActiveAccount(options, cliAuth.getGlobalDefaultAccount());
  await requireAuth(options);
  admin.initializeApp({projectId: project, credential: {
    async getAccessToken() { return {access_token: await getAccessToken(), expires_in: 3600}; }
  }});

  const user = await admin.auth().getUser(uid);
  const before = user.customClaims || {};
  console.log(`uid=${uid} email=${user.email} providers=${user.providerData.map((p) => p.providerId).join("+")}`);
  console.log("claims before:", JSON.stringify(before));

  if (apply || revoke) {
    const next = {...before};
    if (apply) next.admin = true;
    else delete next.admin;
    await admin.auth().setCustomUserClaims(uid, next);
    const after = (await admin.auth().getUser(uid)).customClaims || {};
    console.log("claims after: ", JSON.stringify(after));
  } else {
    console.log("dry run — 바꾸려면 --apply 또는 --revoke");
  }
  await admin.app().delete();
})().catch((err) => {
  console.error(err.code || err.message || err);
  process.exit(1);
});
