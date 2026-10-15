"use strict";
// Auth에는 있는데 real_members에 없는 가입 회원을 채운다(관리자 웹 "전체"용).
//
//   node tool/backfill_real_members.cjs          # 확인만 (기본)
//   node tool/backfill_real_members.cjs --apply  # 빠진 문서만 만든다
//
// real_members는 앱이 syncRealMemberProfile을 부를 때 생긴다. 그 함수가 생기기
// 전에 가입하고 그 뒤로 앱을 안 연 회원은 빠져 있다. 익명(Duo 게스트)은 넣지
// 않는다. 이미 있는 문서는 건드리지 않는다. lastSeenAt은 지어내지 않고 Auth의
// 마지막 로그인으로 채우며, backfilled: true를 남긴다.
const base = "C:/Users/u/AppData/Roaming/npm/node_modules/firebase-tools/lib/";
const cliAuth = require(base + "auth");
const {requireAuth} = require(base + "requireAuth");
const {getAccessToken} = require(base + "apiv2");
const admin = require("../firebase/functions/node_modules/firebase-admin");
const project = "stealth-vox-3p3rq3";
const apply = process.argv.includes("--apply");
const docsUrl = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;

const ts = (v) => ({timestampValue: new Date(v).toISOString()});
const str = (v) => (v ? {stringValue: v} : {nullValue: null});

(async () => {
  const options = {project, nonInteractive: true};
  cliAuth.setActiveAccount(options, cliAuth.getGlobalDefaultAccount());
  await requireAuth(options);
  admin.initializeApp({projectId: project, credential: {
    async getAccessToken() { return {access_token: await getAccessToken(), expires_in: 3600}; },
  }});

  const members = [];
  let token;
  do {
    const page = await admin.auth().listUsers(1000, token);
    for (const u of page.users) {
      // 익명: 공급자도 이메일도 이름도 없다. 카카오(custom token)는 이메일·이름이 있다.
      if (u.providerData.length === 0 && !u.email && !u.displayName) continue;
      members.push(u);
    }
    token = page.pageToken;
  } while (token);

  const at = await getAccessToken();
  const have = new Set();
  let pageToken = "";
  do {
    const r = await fetch(`${docsUrl}/real_members?pageSize=300&mask.fieldPaths=uid` +
      (pageToken ? `&pageToken=${pageToken}` : ""), {headers: {Authorization: `Bearer ${at}`}});
    const j = await r.json();
    if (j.error) throw new Error(JSON.stringify(j.error));
    for (const d of j.documents || []) have.add(d.name.split("/").pop());
    pageToken = j.nextPageToken || "";
  } while (pageToken);

  const missing = members.filter((u) => !have.has(u.uid));
  console.log(`가입 회원 ${members.length} · real_members ${have.size} · 빠짐 ${missing.length}`);
  for (const u of missing) {
    const providers = [...new Set(u.providerData.map((p) => p.providerId))].sort();
    const primary = providers[0] || "custom";
    if (!providers.length) providers.push("custom");
    console.log(`  ${u.uid}  ${u.email || u.displayName || "-"}  ${primary}  가입 ${u.metadata.creationTime}`);
    if (!apply) continue;
    const fields = {
      uid: str(u.uid),
      email: str(u.email),
      displayName: str(u.displayName),
      providers: {arrayValue: {values: providers.map((p) => ({stringValue: p}))}},
      primaryProvider: str(primary),
      joinedAt: ts(u.metadata.creationTime),
      lastSignInAt: ts(u.metadata.lastSignInTime || u.metadata.creationTime),
      lastSeenAt: ts(u.metadata.lastSignInTime || u.metadata.creationTime),
      isRealMember: {booleanValue: true},
      backfilled: {booleanValue: true},
    };
    // currentDocument.exists=false — 그사이 앱이 만든 문서는 덮지 않는다.
    const r = await fetch(`${docsUrl}/real_members/${u.uid}?currentDocument.exists=false`, {
      method: "PATCH",
      headers: {Authorization: `Bearer ${at}`, "Content-Type": "application/json"},
      body: JSON.stringify({fields}),
    });
    if (!r.ok) console.log(`    실패 ${r.status} ${await r.text()}`);
  }
  console.log(apply ? "적용 완료" : "확인만 했다. 적용은 --apply");
})().catch((e) => { console.error(e.message); process.exit(1); });
