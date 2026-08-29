// 🗂️ 실기기 통화 하나를 Replay probe가 읽는 모양으로 뽑아 온다.
//
//   node tool/dump_duo_call.js <roomId> [출력경로]
//   node tool/dump_duo_call.js --list [개수]     최근 방 id 훑어보기
//
// 왜 필요한가. Replay의 진짜 시험대는 **실제 STT 찌꺼기**다 — 잘린 음절,
// 같은 발화의 부분 반복, 상대 스피커 소리가 내 마이크로 들어온 줄. 사람이
// 지어낸 견본에는 그 모양이 없다. 그런데 그 기록은 Firestore에 있고,
// 콘솔에서 50줄을 손으로 옮겨 적는 것은 현실적이지 않다.
//
// 🔑 서비스 계정 키가 필요하다. **저장소에 넣지 말 것.**
//      $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\\...\\service-account.json"
//      node tool/dump_duo_call.js <roomId>
//
//    Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성.
//
// 무엇을 뽑는가. canonical이 있으면 그것을, 없으면 원본 채널(messages)을
// 뽑는다. **둘 다 뽑아 두는 편이 낫다** — canonical과 Replay를 견주려면
// 그 앞 단계인 원본도 있어야 한다.
//
//   <출력경로>.txt        probe 입력 (HOST: / GUEST: 한 줄에 하나)
//   <출력경로>.json       원본 그대로 (source_ids까지 살아 있다)

const fs = require('fs');
const path = require('path');
const admin = require(path.join(__dirname, '..', 'firebase', 'functions',
    'node_modules', 'firebase-admin'));

function die(msg) {
  console.error(msg);
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  die('GOOGLE_APPLICATION_CREDENTIALS가 없다. 서비스 계정 키 경로를 환경변수로 줄 것.');
}

admin.initializeApp({credential: admin.credential.applicationDefault()});
const db = admin.firestore();

async function list(limit) {
  const snap = await db.collection('duo_sessions')
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();
  if (snap.empty) return console.log('(방이 없다)');
  for (const doc of snap.docs) {
    const d = doc.data();
    const at = d.createdAt ? d.createdAt.toDate().toISOString().slice(0, 16) : '?';
    // uid는 찍지 않는다 — 방 id와 규모만 있으면 고를 수 있다.
    console.log(`${doc.id}  ${at}  mode=${d.mode || '?'}  ` +
        `ended=${d.ended_at ? 'y' : 'n'}`);
  }
}

/** canonical 한 판. 없으면 null. */
async function readCanonical(roomId) {
  const snap = await db.collection('duo_sessions').doc(roomId)
      .collection('canonical').doc('current').get();
  if (!snap.exists) return null;
  const d = snap.data();
  if (d.status !== 'ready') {
    console.error(`(canonical status=${d.status} — 아직 안 만들어졌다)`);
    return null;
  }
  return (d.turns || []).map((t) => ({
    role: t.role || 'HOST',
    text: (t.text || '').trim(),
    state: t.state || 'included',
    source_ids: t.source_ids || [],
  }));
}

/** 원본 채널. 말한 순서로 세운다 — 저장 순서가 아니다. */
async function readSource(roomId) {
  const snap = await db.collection('duo_sessions').doc(roomId)
      .collection('messages').get();
  const rows = [];
  snap.forEach((doc) => {
    const d = doc.data();
    const text = (d.text || '').trim();
    if (!text) return;
    rows.push({
      role: d.senderRole || 'HOST',
      text,
      state: 'included',
      source_ids: [doc.id],
      spoken_at_ms: d.spokenAt ||
          (d.createdAt ? d.createdAt.toMillis() : 0),
      seq: d.seq || 0,
    });
  });
  rows.sort((a, b) =>
    (a.spoken_at_ms - b.spoken_at_ms) || (a.seq - b.seq));
  return rows;
}

function toProbeText(turns, header) {
  const lines = header.map((h) => `# ${h}`);
  lines.push('');
  for (const t of turns) {
    // 감춘 줄에는 표시를 남긴다. Replay가 canonical과 무엇이 다른지 보려면
    // 그 앞 단계가 무엇을 이미 가렸는지 알아야 한다.
    const mark = t.state && t.state !== 'included' ? `  # ${t.state}` : '';
    lines.push(`${t.role}: ${t.text}${mark}`);
  }
  return lines.join('\n') + '\n';
}

async function main() {
  const args = process.argv.slice(2);
  if (args[0] === '--list') return list(parseInt(args[1] || '15', 10));
  const roomId = args[0];
  if (!roomId) die('사용법: node tool/dump_duo_call.js <roomId> [출력경로]');

  const out = args[1] || path.join('tool', 'replay_samples', `real_${roomId}`);
  const canonical = await readCanonical(roomId);
  const source = await readSource(roomId);
  if (!source.length && !canonical) die(`${roomId}: 남은 발화가 없다`);

  const turns = canonical || source;
  const where = canonical ? 'canonical' : 'messages(원본)';
  fs.writeFileSync(`${out}.json`,
      JSON.stringify({room_id: roomId, from: where, turns, source}, null, 2));
  fs.writeFileSync(`${out}.txt`, toProbeText(turns, [
    `실기기 통화 ${roomId} — ${where}에서 뽑음`,
    `원본 ${source.length}줄 / 이 파일 ${turns.length}줄`,
    '# 로 시작하는 꼬리표는 canonical이 이미 가린 줄이다.',
  ]));
  console.log(`${out}.txt  (${turns.length}줄, ${where})`);
  console.log(`${out}.json (원본 ${source.length}줄 포함)`);
}

main().catch((e) => die(`실패: ${e.message}`));
