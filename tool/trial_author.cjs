"use strict";
// 체험 대화 제작 — PC에서 "다른 폰" 역할을 한다(관리자 웹 author.html과 같은 통로).
//
//   node tool/trial_author.cjs state          # 대화 기록·대기 줄 보기
//   node tool/trial_author.cjs send "대사"    # 유저 대사 한 줄 넣기
//   node tool/trial_author.cjs turn "대사"    # 넣고 AI 대답이 올 때까지 기다려 보여 준다
//
// 통로: users/{uid}/chat_history/_trial_author (+ /messages)
// firebase CLI 로그인 계정의 토큰으로 Firestore REST를 부른다.
const base = "C:/Users/u/AppData/Roaming/npm/node_modules/firebase-tools/lib/";
const cliAuth = require(base + "auth");
const {requireAuth} = require(base + "requireAuth");
const {getAccessToken} = require(base + "apiv2");
const project = "stealth-vox-3p3rq3";
const uid = process.env.TRIAL_AUTHOR_UID || "z3MxTp8WZ3ZHXAKMa93zn68tbXi2";
const root = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const channel = `users/${uid}/chat_history/_trial_author`;

function plain(v) {
  if (!v) return undefined;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(plain);
  if ("mapValue" in v) {
    const out = {};
    for (const [k, x] of Object.entries(v.mapValue.fields || {})) out[k] = plain(x);
    return out;
  }
  return undefined;
}

(async () => {
  const options = {project, nonInteractive: true};
  cliAuth.setActiveAccount(options, cliAuth.getGlobalDefaultAccount());
  await requireAuth(options);
  const headers = {Authorization: "Bearer " + await getAccessToken(), "Content-Type": "application/json"};
  const [cmd, ...rest] = process.argv.slice(2);
  const readLog = async () => {
    const r = await fetch(`${root}/${channel}`, {headers});
    if (!r.ok) return [];
    return plain(((await r.json()).fields || {}).log) || [];
  };
  if (cmd === "turn") {
    const before = (await readLog()).length;
    process.argv.splice(2, 1, "send");
  }
  if (cmd === "send" || cmd === "turn") {
    const text = rest.join(" ").trim();
    if (!text) throw new Error("empty line");
    const res = await fetch(`${root}/${channel}/messages`, {
      method: "POST", headers,
      body: JSON.stringify({fields: {
        text: {stringValue: text},
        consumed: {booleanValue: false},
        createdAt: {timestampValue: new Date().toISOString()},
      }}),
    });
    if (!res.ok) throw new Error(`send ${res.status} ${await res.text()}`);
    console.log("queued:", text);
    if (cmd === "send") return;
    const start = (await readLog()).length;
    const deadline = Date.now() + 90000;
    while (Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 2000));
      const log = await readLog();
      const fresh = log.slice(start);
      if (fresh.some((m) => m.role === "AI")) {
        for (const m of fresh) console.log(`${m.role}: ${m.text}`);
        return;
      }
    }
    console.log("(90초 안에 AI 대답이 오지 않았습니다)");
    return;
  }
  const res = await fetch(`${root}/${channel}`, {headers});
  if (res.status === 404) { console.log("(no channel yet)"); return; }
  if (!res.ok) throw new Error(`state ${res.status} ${await res.text()}`);
  const f = (await res.json()).fields || {};
  console.log(`active=${plain(f.active)} chat=${plain(f.chatLang)} learn=${plain(f.learnLang)} pending=${plain(f.pending)}`);
  for (const m of plain(f.log) || []) console.log(`${m.role}: ${m.text}`);
})().catch((e) => { console.error(e.message); process.exit(1); });
