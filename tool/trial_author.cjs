"use strict";
// 체험 대화 제작 — PC에서 "다른 폰" 역할을 한다(관리자 웹 author.html과 같은 통로).
//
//   node tool/trial_author.cjs state          # 대화 기록·대기 줄 보기
//   node tool/trial_author.cjs send "대사"    # 유저 대사 한 줄 넣기
//
// 통로: users/{uid}/chat_history/_trial_author (+ /messages)
// firebase CLI 로그인 계정으로 동작한다.
const base = "C:/Users/u/AppData/Roaming/npm/node_modules/firebase-tools/lib/";
const cliAuth = require(base + "auth");
const {requireAuth} = require(base + "requireAuth");
const {getAccessToken} = require(base + "apiv2");
const admin = require("../firebase/functions/node_modules/firebase-admin");
const project = "stealth-vox-3p3rq3";
const uid = process.env.TRIAL_AUTHOR_UID || "z3MxTp8WZ3ZHXAKMa93zn68tbXi2";

(async () => {
  const options = {project, nonInteractive: true};
  cliAuth.setActiveAccount(options, cliAuth.getGlobalDefaultAccount());
  await requireAuth(options);
  admin.initializeApp({projectId: project, credential: {
    async getAccessToken() { return {access_token: await getAccessToken(), expires_in: 3600}; },
  }});
  const db = admin.firestore();
  const channel = db.doc(`users/${uid}/chat_history/_trial_author`);
  const [cmd, ...rest] = process.argv.slice(2);
  if (cmd === "send") {
    const text = rest.join(" ").trim();
    if (!text) throw new Error("empty line");
    await channel.collection("messages").add({
      text, consumed: false, createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log("queued:", text);
    return;
  }
  const snap = await channel.get();
  const data = snap.exists ? snap.data() : {};
  console.log(`active=${data.active} chat=${data.chatLang} learn=${data.learnLang} pending=${data.pending}`);
  for (const m of data.log || []) console.log(`${m.role}: ${m.text}`);
})().catch((e) => { console.error(e.message); process.exit(1); });
