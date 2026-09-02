// 🔐 duo_sessions 규칙을 **에뮬레이터에서** 검증한다.
//
//   firebase emulators:exec --only firestore "node tool/rules_test/run.js"
//
// 이 규칙 변경에는 canonical 허용뿐 아니라 **기존 쓰기 권한 축소**가 섞여
// 있다. 좁힌 쪽이 틀리면 게스트 입장이나 발화 저장이 통째로 막힌다 —
// 프로덕션에 올리기 전에 여기서 다 밟아 본다.
//
// 통과해야 하는 것과 막혀야 하는 것을 같은 무게로 센다. "막히는 것"만 세면
// 아무도 못 쓰는 규칙이 만점을 받는다.

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, addDoc,
  serverTimestamp,
} = require('firebase/firestore');

const HOST = 'host-uid';
const GUEST = 'guest-uid';
const GUEST2 = 'guest2-uid';
const MEMBER = 'member-uid'; // 통화 뒤 기존 계정으로 로그인한 사람
const ROOM = 'room-1';

let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    console.log(`  ✗ ${name}`);
    console.log(`      ${(e && e.message ? e.message : e).split('\n')[0]}`);
  }
}

function section(title) {
  console.log(`\n── ${title}`);
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'stealth-vox-rules-test',
    firestore: {
      rules: fs.readFileSync(
          path.join(__dirname, '..', '..', 'firebase', 'firestore.rules'),
          'utf8'),
    },
  });

  const host = env.authenticatedContext(HOST).firestore();
  const guest = env.authenticatedContext(GUEST).firestore();
  const guest2 = env.authenticatedContext(GUEST2).firestore();
  const member = env.authenticatedContext(MEMBER).firestore();
  const anon = env.unauthenticatedContext().firestore();

  // 규칙을 끈 눈으로 방 문서를 들여다본다. 실패가 **규칙 탓인지 문서 상태
  // 탓인지** 가르는 유일한 방법이다.
  async function dumpRoom(label) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), 'duo_sessions', ROOM));
      if (!snap.exists()) return console.log(`    · [${label}] 방 문서 없음`);
      const d = snap.data();
      console.log(`    · [${label}] hostUid=${d.hostUid} ` +
          `partnerUid=${d.partnerUid} joined=${d.isPartnerJoined}`);
    });
  }

  const room = (db) => doc(db, 'duo_sessions', ROOM);
  const msgs = (db) => collection(db, 'duo_sessions', ROOM, 'messages');
  const canon = (db) => doc(db, 'duo_sessions', ROOM, 'canonical', 'current');

  // ── ① 호스트가 방을 만든다 ────────────────────────────────────────
  section('방 만들기');
  await check('호스트는 자기 uid로 방을 만든다', () => assertSucceeds(
      setDoc(room(host), {
        hostUid: HOST,
        createdAt: serverTimestamp(),
        isDuoEnabled: false,
        isPartnerJoined: false,
        mode: 'direct',
        hostLang: 'Korean',
      })));

  await check('남의 uid를 hostUid로 적어 방을 만들지 못한다', () => assertFails(
      setDoc(doc(guest2, 'duo_sessions', 'room-x'), {
        hostUid: HOST,
        isPartnerJoined: false,
      })));

  await check('로그인하지 않으면 방을 못 만든다', () => assertFails(
      setDoc(doc(anon, 'duo_sessions', 'room-y'), {hostUid: 'nobody'})));

  await dumpRoom('create 뒤');

  // ── ② 초대 수락 전의 읽기 ─────────────────────────────────────────
  section('초대 링크를 받은 사람의 읽기 (참가자가 되기 전이다)');
  await check('아직 참가자가 아닌 게스트도 방을 읽는다', () => assertSucceeds(
      getDoc(room(guest))));
  await check('로그인하지 않으면 못 읽는다', () => assertFails(
      getDoc(room(anon))));

  // ── ③ 빈 자리 잡기 ───────────────────────────────────────────────
  section('게스트 입장 — 빈 자리 잡기');
  await check('호스트가 방을 연다(isDuoEnabled)', () => assertSucceeds(
      updateDoc(room(host), {isDuoEnabled: true})));

  await check('빈 자리를 자기 uid로 잡는다', () => assertSucceeds(
      updateDoc(room(guest), {
        isPartnerJoined: true,
        partnerUid: GUEST,
        partnerJoinedAt: serverTimestamp(),
        partnerLang: 'English',
      })));

  await check('남의 uid로 자리를 잡지 못한다', () => assertFails(
      updateDoc(room(guest2), {isPartnerJoined: true, partnerUid: GUEST})));

  await check('통화 중인 방을 제3자가 가로채지 못한다', () => assertFails(
      updateDoc(room(guest2), {
        isPartnerJoined: true,
        partnerUid: GUEST2,
      })));

  await check('hostUid를 바꾸지 못한다', () => assertFails(
      updateDoc(room(guest), {hostUid: GUEST})));

  await dumpRoom('입장 뒤');

  // ── ④ 발화 저장 ──────────────────────────────────────────────────
  section('messages — 통화 중 발화 저장');
  await check('호스트가 자기 발화를 올린다', () => assertSucceeds(
      addDoc(msgs(host), {
        senderUid: HOST, senderRole: 'HOST', text: '여보세요?',
        srcLang: 'Korean', createdAt: serverTimestamp(), duoMode: 'direct',
      })));

  await check('게스트가 자기 발화를 올린다', () => assertSucceeds(
      addDoc(msgs(guest), {
        senderUid: GUEST, senderRole: 'GUEST', text: 'Hello?',
        srcLang: 'English', createdAt: serverTimestamp(), duoMode: 'direct',
      })));

  await check('양쪽 다 채널 전체를 읽는다', async () => {
    await assertSucceeds(getDoc(room(guest)));
    await assertSucceeds(getDoc(room(host)));
  });

  await check('참가자가 아닌 사람은 발화를 못 올린다', () => assertFails(
      addDoc(msgs(guest2), {
        senderUid: GUEST2, senderRole: 'GUEST', text: '끼어들기',
      })));

  // ── ⑤ flush 표시 ────────────────────────────────────────────────
  section('flush_done — 내 몫을 다 올렸다는 표시');
  await check('게스트가 자기 표시를 찍는다', () => assertSucceeds(
      setDoc(room(guest), {flush_done: {[GUEST]: serverTimestamp()}},
          {merge: true})));
  await check('호스트가 자기 표시를 찍는다', () => assertSucceeds(
      setDoc(room(host), {flush_done: {[HOST]: serverTimestamp()}},
          {merge: true})));
  await check('참가자가 아닌 사람은 못 찍는다', () => assertFails(
      setDoc(room(guest2), {flush_done: {[GUEST2]: serverTimestamp()}},
          {merge: true})));

  // ── ⑥ canonical ─────────────────────────────────────────────────
  section('canonical — 공유 결과');
  await check('게스트가 작업을 잡는다(building)', () => assertSucceeds(
      setDoc(canon(guest), {
        status: 'building', writer_uid: GUEST, updated_at: serverTimestamp(),
      }, {merge: true})));

  await check('호스트가 결과를 쓴다(ready)', () => assertSucceeds(
      setDoc(canon(host), {
        status: 'ready',
        writer_uid: HOST,
        canonical_version: 1,
        turns: [{role: 'HOST', text: '여보세요?', source_ids: ['a'],
          state: 'included'}],
        updated_at: serverTimestamp(),
      }, {merge: true})));

  await check('참가자가 아닌 사람은 canonical을 못 쓴다', () => assertFails(
      setDoc(canon(guest2), {status: 'ready', turns: []}, {merge: true})));

  await check('양쪽 참가자가 canonical을 읽는다', async () => {
    await assertSucceeds(getDoc(canon(host)));
    await assertSucceeds(getDoc(canon(guest)));
  });

  // ── ⑥-B webrtc signaling ────────────────────────────────────────
  //
  // 여기만 **읽기가 참가자로 좁혀져 있다.** messages·canonical·replay는
  // 로그인한 누구나 읽는다(통화 뒤 계정 복구가 그 읽기에 기댄다). 그런데
  // signaling은 다르다 — offer를 읽을 수 있으면 answer를 만들어 **통화
  // 오디오에 끼어들 수 있다.** 그래서 이 층만 규칙이 다르고, 그 차이가
  // 실수로 느슨해지지 않도록 여기서 못 박는다.
  section('webrtc signaling — offer/answer/ICE 후보');

  const rtc = (db) => doc(db, 'duo_sessions', ROOM, 'webrtc', 'current');
  const cand = (db) =>
      collection(db, 'duo_sessions', ROOM, 'webrtc', 'current', 'candidates');

  await check('호스트가 offer를 올린다', () => assertSucceeds(
      setDoc(rtc(host), {
        sessionId: `${ROOM}#1`,
        offer: {sdp: 'v=0...', type: 'offer'},
        offerUid: HOST,
        updatedAt: serverTimestamp(),
      }, {merge: true})));

  await check('게스트가 answer를 올린다', () => assertSucceeds(
      setDoc(rtc(guest), {
        sessionId: `${ROOM}#1`,
        answer: {sdp: 'v=0...', type: 'answer'},
        answerUid: GUEST,
        updatedAt: serverTimestamp(),
      }, {merge: true})));

  await check('두 참가자가 서로의 SDP를 읽는다', async () => {
    await assertSucceeds(getDoc(rtc(host)));
    await assertSucceeds(getDoc(rtc(guest)));
  });

  await check('양쪽이 ICE 후보를 올린다', async () => {
    await assertSucceeds(addDoc(cand(host), {
      sessionId: `${ROOM}#1`, role: 'HOST',
      candidate: 'candidate:1 1 udp ...', sdpMid: '0', sdpMLineIndex: 0,
      createdAt: serverTimestamp(),
    }));
    await assertSucceeds(addDoc(cand(guest), {
      sessionId: `${ROOM}#1`, role: 'GUEST',
      candidate: 'candidate:2 1 udp ...', sdpMid: '0', sdpMLineIndex: 0,
      createdAt: serverTimestamp(),
    }));
  });

  // ↓↓↓ 여기부터가 이 층을 따로 둔 이유다 ↓↓↓

  await check('제3자는 offer를 **읽지 못한다** (읽으면 통화에 끼어든다)',
      () => assertFails(getDoc(rtc(guest2))));

  await check('제3자는 SDP를 못 쓴다', () => assertFails(
      setDoc(rtc(guest2), {
        sessionId: `${ROOM}#1`,
        answer: {sdp: 'hijack', type: 'answer'},
      }, {merge: true})));

  await check('제3자는 ICE 후보를 못 읽는다', () => assertFails(
      getDoc(doc(guest2, 'duo_sessions', ROOM, 'webrtc', 'current',
          'candidates', 'anything'))));

  await check('제3자는 ICE 후보를 못 올린다', () => assertFails(
      addDoc(cand(guest2), {
        sessionId: `${ROOM}#1`, role: 'GUEST', candidate: 'hijack',
      })));

  await check('로그인하지 않으면 signaling에 손도 못 댄다', async () => {
    await assertFails(getDoc(rtc(anon)));
    await assertFails(setDoc(rtc(anon), {sessionId: 'x'}, {merge: true}));
  });

  // 통화 **뒤에** 자기 계정으로 로그인한 회원은 canonical을 읽어 방을
  // 복구한다(⑦). 그 읽기 권한이 signaling까지 번지면 안 된다 — 그 사람은
  // 이 방의 참가자가 아니고, 통화 오디오에 낄 이유도 없다.
  await check('복구하러 온 회원도 signaling은 못 읽는다 (canonical과 다르다)',
      () => assertFails(getDoc(rtc(member))));

  // 다른 방의 신호에 손대는 경로. roomId가 규칙 경로에 묶여 있으므로
  // get()이 **그 방** 문서를 보고 참가자인지 따진다.
  section('webrtc signaling — 다른 방 접근 차단');
  await check('두 번째 방을 만든다 (주인은 guest2)', () => assertSucceeds(
      setDoc(doc(guest2, 'duo_sessions', 'room-2'), {
        hostUid: GUEST2,
        isDuoEnabled: true,
        isPartnerJoined: false,
        mode: 'direct',
      })));

  await check('room-1 참가자가 room-2의 signaling을 못 읽는다', () => assertFails(
      getDoc(doc(host, 'duo_sessions', 'room-2', 'webrtc', 'current'))));

  await check('room-1 참가자가 room-2에 offer를 못 심는다', () => assertFails(
      setDoc(doc(guest, 'duo_sessions', 'room-2', 'webrtc', 'current'), {
        sessionId: 'room-2#1',
        offer: {sdp: 'hijack', type: 'offer'},
      }, {merge: true})));

  await check('room-2 주인은 자기 방 signaling을 쓴다', () => assertSucceeds(
      setDoc(doc(guest2, 'duo_sessions', 'room-2', 'webrtc', 'current'), {
        sessionId: 'room-2#1',
        offer: {sdp: 'v=0...', type: 'offer'},
      }, {merge: true})));

  // ── ⑦ handoff — 통화 뒤 기존 계정으로 로그인한 사람 ────────────────
  section('handoff — 방이 한 번도 본 적 없는 uid의 복구 경로');
  await check('회원이 세션 문서를 읽는다 (참가자 검증에 필요하다)',
      () => assertSucceeds(getDoc(room(member))));
  await check('회원이 canonical을 읽는다 (복구의 근거다)',
      () => assertSucceeds(getDoc(canon(member))));
  await check('그래도 쓰지는 못한다', () => assertFails(
      setDoc(canon(member), {status: 'ready'}, {merge: true})));
  await check('회원이 자기 chat_history에 복구본을 짓는다', () => assertSucceeds(
      setDoc(doc(member, 'users', MEMBER, 'chat_history', 'restored-1'), {
        room_name: 'Duo Connect Mode',
        duo_room_id: ROOM,
        duo_restore_expected: 2,
        duo_restore_complete: false,
      })));
  await check('남의 chat_history에는 못 쓴다', () => assertFails(
      setDoc(doc(member, 'users', HOST, 'chat_history', 'stolen'), {
        room_name: 'Duo Connect Mode',
      })));

  await dumpRoom('canonical 뒤');

  // ── ⑧ 방 지우기 ─────────────────────────────────────────────────
  section('방 지우기');
  await check('게스트는 방을 못 지운다', () => assertFails(
      deleteDoc(room(guest))));
  await check('호스트는 방을 지운다 (만능 통역 경로)', () => assertSucceeds(
      deleteDoc(room(host))));

  await env.cleanup();

  console.log(`\n${'─'.repeat(56)}`);
  console.log(`통과 ${passed} / 실패 ${failed}`);
  if (failed > 0) {
    console.log('배포하지 말 것 — 위 실패를 먼저 볼 것.');
    process.exit(1);
  }
  console.log('규칙 검증 통과.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
