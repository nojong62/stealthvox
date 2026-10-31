const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { readBlocked } = require('./block_check');

const db = () => admin.firestore();

// 대화맨: 여러 사람과 대화하고 싶어 스스로 신청한 회원(유료 구독 불필요).
// 게시판에서는 일반 글과 똑같이 보인다. 다른 점은 셋뿐이다.
//   · 하루 통화 횟수를 세기만 한다(상한은 app_config/duo_board_promo의
//     talkHostDailyCallLimit, 0이면 없음).
//   · 통화가 끝나면 앱이 같은 주제로 글을 다시 올린다(통화 중에는 안 보인다).
//   · 대화맨 본인 시간은 쓰지 않는다. 상대가 회원이면 상대가, 비회원이면
//     홍보 비용(3분)으로 낸다.
// 문서 duo_talk_hosts/{uid}는 서버만 쓴다. adminDisabled는 관리자가 해제한 표시로,
// 본인이 다시 켤 수 없다.
const TALK_HOST_DAILY_HOURS = [2, 3, 4, 6, 8];
const TALK_HOST_PLEDGE_VERSION = 1;

const talkHostRef = uid => db().collection('duo_talk_hosts').doc(uid);

function isActiveTalkHostData(data) {
  return Boolean(data) && data.active === true && data.adminDisabled !== true;
}

async function isActiveTalkHost(uid) {
  if (!uid) return false;
  const snap = await talkHostRef(uid).get();
  return snap.exists && isActiveTalkHostData(snap.data());
}

function talkHostChange({enabled, dailyHours, pledge}) {
  if (!enabled) return {active: false};
  const hours = Number(dailyHours);
  if (!TALK_HOST_DAILY_HOURS.includes(hours)) {
    throw new functions.https.HttpsError('invalid-argument', '하루 시간을 골라 주세요.',
        {reason: 'talk_host_hours'});
  }
  if (pledge !== true) {
    throw new functions.https.HttpsError('invalid-argument', '건전 대화 서약에 동의해야 합니다.',
        {reason: 'talk_host_pledge'});
  }
  return {active: true, dailyHours: hours, pledgeVersion: TALK_HOST_PLEDGE_VERSION};
}

exports.setDuoTalkHost = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
  const uid = context.auth.uid;
  if (context.auth.token?.firebase?.sign_in_provider === 'anonymous') {
    throw new functions.https.HttpsError('permission-denied', '대화맨은 회원만 신청할 수 있습니다.',
        {reason: 'members_only'});
  }
  if (await readBlocked(db(), uid)) {
    throw new functions.https.HttpsError('permission-denied', '이용이 제한된 계정입니다.');
  }
  const change = talkHostChange({
    enabled: data?.enabled === true, dailyHours: data?.dailyHours, pledge: data?.pledge,
  });
  const ref = talkHostRef(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();
  return db().runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (change.active && snap.exists && snap.get('adminDisabled') === true) {
      throw new functions.https.HttpsError('permission-denied', '대화맨을 다시 켤 수 없습니다.',
          {reason: 'talk_host_admin_disabled'});
    }
    tx.set(ref, {
      ...change,
      ...(change.active ? {pledgedAt: now} : {leftAt: now}),
      ...(snap.exists ? {} : {createdAt: now, callCount: 0}),
      email: context.auth.token?.email || '',
      updatedAt: now,
    }, {merge: true});
    return {active: change.active, dailyHours: change.dailyHours || snap.get('dailyHours') || 0};
  });
});

// 대화맨 통화 한 통을 센다. 같은 방은 한 번만(재입장·트리거 재시도).
async function countTalkHostCallOnJoin(roomId, hostUid, dayKey) {
  const ref = talkHostRef(hostUid);
  const markerRef = ref.collection('rooms').doc(roomId);
  const dailyRef = ref.collection('daily').doc(dayKey);
  await db().runTransaction(async tx => {
    const marker = await tx.get(markerRef);
    if (marker.exists) return;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const inc = admin.firestore.FieldValue.increment(1);
    tx.set(markerRef, {countedAt: now, day: dayKey});
    tx.set(dailyRef, {calls: inc, updatedAt: now}, {merge: true});
    tx.set(ref, {callCount: inc, lastCallAt: now}, {merge: true});
  });
}

async function readTalkHostDailyCalls(uid, dayKey) {
  const snap = await talkHostRef(uid).collection('daily').doc(dayKey).get();
  return Number(snap.get('calls') || 0);
}

exports._test = {talkHostChange, isActiveTalkHostData, TALK_HOST_DAILY_HOURS};
exports.isActiveTalkHost = isActiveTalkHost;
exports.isActiveTalkHostData = isActiveTalkHostData;
exports.countTalkHostCallOnJoin = countTalkHostCallOnJoin;
exports.readTalkHostDailyCalls = readTalkHostDailyCalls;
exports.talkHostRef = talkHostRef;
