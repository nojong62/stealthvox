"use strict";

// 이미 가입한 카카오 회원의 real_members에 kakaoId(·kakaoNickname)를 채운다.
// 새 로그인부터는 syncRealMemberProfile이 적는다. 닉네임은 kakao_uid_map에
// 있을 때만(다음 로그인부터 쌓인다).
//   GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) node tools/backfill_kakao_ids.js          # 미리보기
//   GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token) node tools/backfill_kakao_ids.js --apply  # 쓰기

const PROJECT_ID = "stealth-vox-3p3rq3";
const DATABASE = "(default)";
const token = process.env.GOOGLE_ACCESS_TOKEN;
const apply = process.argv.includes("--apply");

if (!token) {
  throw new Error("GOOGLE_ACCESS_TOKEN is required.");
}

const headers = {
  Authorization: `Bearer ${token}`,
  "Content-Type": "application/json",
  "x-goog-user-project": PROJECT_ID,
};
const DOCUMENTS = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/${encodeURIComponent(DATABASE)}/documents`;

async function jsonRequest(url, options = {}) {
  const response = await fetch(url, {...options, headers: {...headers, ...options.headers}});
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`${response.status} ${JSON.stringify(body)}`);
  }
  return body;
}

function documentName(path) {
  return `projects/${PROJECT_ID}/databases/${DATABASE}/documents/${path}`;
}

async function listCollection(collectionId, fields) {
  const rows = await jsonRequest(`${DOCUMENTS}:runQuery`, {
    method: "POST",
    body: JSON.stringify({
      structuredQuery: {
        from: [{collectionId}],
        select: {fields: fields.map((fieldPath) => ({fieldPath}))},
      },
    }),
  });
  return rows.filter((row) => row.document).map((row) => ({
    id: row.document.name.split("/").pop(),
    fields: row.document.fields || {},
  }));
}

const str = (fields, name) => (fields[name] && fields[name].stringValue) || "";

async function main() {
  const [maps, members] = await Promise.all([
    listCollection("kakao_uid_map", ["uid", "kakao_id", "kakao_nickname"]),
    listCollection("real_members", ["kakaoId", "kakaoNickname"]),
  ]);
  const memberById = new Map(members.map((m) => [m.id, m.fields]));

  const writes = [];
  let noMember = 0;
  for (const map of maps) {
    const uid = str(map.fields, "uid");
    const member = uid && memberById.get(uid);
    if (!member) { noMember += 1; continue; }
    const kakaoId = str(map.fields, "kakao_id") || map.id;
    const nickname = str(map.fields, "kakao_nickname");
    if (str(member, "kakaoId") === kakaoId && (!nickname || str(member, "kakaoNickname") === nickname)) {
      continue;
    }
    const fields = {kakaoId: {stringValue: kakaoId}};
    if (nickname) fields.kakaoNickname = {stringValue: nickname};
    writes.push({
      update: {name: documentName(`real_members/${uid}`), fields},
      updateMask: {fieldPaths: Object.keys(fields)},
      currentDocument: {exists: true},
    });
  }

  if (apply) {
    for (let index = 0; index < writes.length; index += 400) {
      await jsonRequest(`${DOCUMENTS}:commit`, {
        method: "POST",
        body: JSON.stringify({writes: writes.slice(index, index + 400)}),
      });
    }
  }
  console.log(JSON.stringify({
    mode: apply ? "apply" : "dry-run",
    kakaoMaps: maps.length,
    withoutMemberRow: noMember,
    membersToUpdate: writes.length,
    withNickname: writes.filter((w) => w.update.fields.kakaoNickname).length,
  }));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
