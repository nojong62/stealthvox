const functions = require('firebase-functions/v1');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { readBlocked } = require('./block_check');
const talkHost = require('./duo_talk_host');

const db = () => admin.firestore();
const openAiApiKey = defineSecret('OPENAI_API_KEY');
const badTopic = /(https?:\/\/|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}|\b\d{2,3}[- .]?\d{3,4}[- .]?\d{4}\b|시발|씨발|섹스|강간|마약|살인|fuck|porn|rape)/iu;

// 홍보 기간 비회원 초대. 스위치는 app_config/duo_board_promo 문서 하나다.
// 문서가 없거나 guestPostsEnabled가 true가 아니면 비회원 글은 닫힌다.
const PROMO_CONFIG_PATH = 'app_config/duo_board_promo';
const DEFAULT_GUEST_CALL_SECONDS = 180;
const DEFAULT_DAILY_GUEST_CALL_LIMIT = 50;
// 비회원 한 폰(익명 계정)이 하루에 할 수 있는 비회원끼리 통화 수.
// 한 사람이 하루 상한을 혼자 다 쓰지 못하게 한다.
const DEFAULT_PER_GUEST_DAILY_CALLS = 3;
// 서로 다른 사람 3명이 24시간 안에 신고하면 24시간 게시판 정지.
const REPORT_WINDOW_MS = 24 * 60 * 60 * 1000;
const REPORTS_TO_SUSPEND = 3;
const SUSPEND_MS = 24 * 60 * 60 * 1000;
// 글쓴이가 고르는 "몇 시간 동안 푸시 받기". 그동안은 앱을 닫아도 글이 활성으로
// 남고, 누가 누르면 알림이 간다. 0은 끄기(앱이 켜져 있을 때만 받는다).
const PUSH_HOURS = [0, 1, 2, 4, 8];
// 앱이 켜져 있으면 요청 창이 바로 뜬다. 알림으로 부를 때는 상대가 알림을 보고
// 앱을 여는 시간까지 기다린다.
const IN_APP_REQUEST_WAIT_MS = 30 * 1000;
const PUSH_REQUEST_WAIT_MS = 75 * 1000;

function text(value, max) {
  const out = String(value || '').trim().replace(/\s+/g, ' ');
  if (out.length < 2 || out.length > max || badTopic.test(out)) {
    throw new functions.https.HttpsError('invalid-argument', '허용되지 않는 대화 주제입니다.',
        {reason: 'topic_rejected'});
  }
  return out;
}

function isAnonymousAuth(context) {
  return context.auth?.token?.firebase?.sign_in_provider === 'anonymous';
}

async function readPromoConfig() {
  const snap = await db().doc(PROMO_CONFIG_PATH).get();
  return promoConfigFrom(snap.exists ? snap.data() : null);
}

function promoConfigFrom(data) {
  const value = data || {};
  const positive = (raw, fallback) => {
    const n = Number(raw);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
  };
  return {
    guestPostsEnabled: value.guestPostsEnabled === true,
    guestCallSeconds: positive(value.guestCallSeconds, DEFAULT_GUEST_CALL_SECONDS),
    dailyGuestCallLimit: positive(value.dailyGuestCallLimit, DEFAULT_DAILY_GUEST_CALL_LIMIT),
    perGuestDailyCalls: positive(value.perGuestDailyCalls, DEFAULT_PER_GUEST_DAILY_CALLS),
    // 대화맨 하루 통화 상한. 지금은 세기만 한다 — 0(기본)이면 상한 없음.
    talkHostDailyCallLimit: positive(value.talkHostDailyCallLimit, 0),
  };
}

function pushHoursFrom(raw) {
  const hours = Number(raw ?? 0);
  if (!PUSH_HOURS.includes(hours)) {
    throw new functions.https.HttpsError('invalid-argument', '푸시 시간이 올바르지 않습니다.');
  }
  return hours;
}

function pushUntilFor(hours, nowMs = Date.now()) {
  return hours > 0
    ? admin.firestore.Timestamp.fromMillis(nowMs + hours * 60 * 60 * 1000)
    : admin.firestore.FieldValue.delete();
}

// 글쓴이가 고른 푸시 시간이 아직 남았는가. 남았으면 앱이 꺼져 있어도 받는다.
function isPushWindowOpen(postData, nowMs = Date.now()) {
  const until = postData?.pushUntil;
  return until instanceof admin.firestore.Timestamp && until.toMillis() > nowMs;
}

// 푸시 알림 문구. 제목(사용자가 쓴 글)은 넣지 않는다 — 잠금 화면에 보인다.
const PUSH_COPY = {
  ko: ['StealthVox · Duo', '누군가 지금 대화하고 싶어 해요. 눌러서 받아 주세요.'],
  ja: ['StealthVox · Duo', '今、話したい人がいます。タップして応答してください。'],
  zh: ['StealthVox · Duo', '有人现在想和你聊天，点击接听。'],
  es: ['StealthVox · Duo', 'Alguien quiere hablar contigo ahora. Toca para responder.'],
  fr: ['StealthVox · Duo', 'Quelqu’un veut te parler maintenant. Touche pour répondre.'],
  de: ['StealthVox · Duo', 'Jemand möchte jetzt mit dir sprechen. Tippe zum Annehmen.'],
  pt: ['StealthVox · Duo', 'Alguém quer conversar com você agora. Toque para atender.'],
  en: ['StealthVox · Duo', 'Someone wants to talk with you now. Tap to answer.'],
};

function pushCopyFor(chatLanguage) {
  const lang = String(chatLanguage || '').toLowerCase();
  const key = lang.startsWith('ko') || lang.includes('korean') ? 'ko'
    : lang.startsWith('ja') || lang.includes('japanese') ? 'ja'
      : lang.startsWith('zh') || lang.includes('chinese') ? 'zh'
        : lang.startsWith('es') || lang.includes('spanish') ? 'es'
          : lang.startsWith('fr') || lang.includes('french') ? 'fr'
            : lang.startsWith('de') || lang.includes('german') ? 'de'
              : lang.startsWith('pt') || lang.includes('portuguese') ? 'pt'
                : 'en';
  return PUSH_COPY[key];
}

// 글쓴이 폰들에 요청 알림을 보낸다. 죽은 토큰은 지운다. 반환: 보낸 수.
async function sendRequestPush(ownerUid, requestId) {
  const tokens = await db().collection('users').doc(ownerUid)
      .collection('fcm_tokens').get();
  const docs = tokens.docs.filter(doc => doc.get('token'));
  if (!docs.length) return 0;
  let sent = 0;
  await Promise.all(docs.map(async doc => {
    const [title, body] = pushCopyFor(doc.get('chatLanguage'));
    try {
      await admin.messaging().send({
        token: doc.get('token'),
        notification: {title, body},
        data: {type: 'duo_board_request', requestId},
        android: {priority: 'high', ttl: PUSH_REQUEST_WAIT_MS},
      });
      sent += 1;
    } catch (error) {
      const code = error?.errorInfo?.code || error?.code || '';
      if (code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token') {
        await doc.ref.delete().catch(() => null);
      } else {
        console.warn('[DuoBoard] push failed: ' + code);
      }
    }
  }));
  return sent;
}

const guestDailyRef = (uid, nowMs) =>
  dailyGuestCallRef(nowMs).collection('guests').doc(uid);

// 비회원끼리 통화를 더 받을 수 있는지. 하루 전체 상한과 1인 상한을 같이 본다.
// 반환: null(가능) 또는 거절 이유. 트랜잭션 안에서 부른다(읽기만 한다).
// 대화맨 글이면 ownerUid를 비운다 — 대화맨에게는 1인 상한이 없다.
async function guestCallBlockReason(tx, promo, {requesterUid, ownerUid}) {
  const [daily, requester, owner] = await Promise.all([
    tx.get(dailyGuestCallRef()),
    tx.get(guestDailyRef(requesterUid)),
    ownerUid ? tx.get(guestDailyRef(ownerUid)) : Promise.resolve(null),
  ]);
  return guestCallBlockReasonFrom(promo, {
    dailyCalls: Number(daily.get('guestCalls') || 0),
    requesterCalls: Number(requester.get('calls') || 0),
    ownerCalls: Number(owner?.get('calls') || 0),
  });
}

function guestCallBlockReasonFrom(promo, {dailyCalls, requesterCalls, ownerCalls}) {
  if (dailyCalls >= promo.dailyGuestCallLimit) return 'daily_guest_limit';
  if (requesterCalls >= promo.perGuestDailyCalls) return 'guest_daily_limit_personal';
  if (ownerCalls >= promo.perGuestDailyCalls) return 'host_daily_limit';
  return null;
}

const GUEST_LIMIT_MESSAGES = {
  daily_guest_limit: '오늘 비회원 통화가 모두 마감되었습니다.',
  guest_daily_limit_personal: '오늘 비회원 통화를 모두 사용했습니다.',
  host_daily_limit: '이 초대자는 오늘 비회원 통화를 모두 사용했습니다.',
  requester_no_time: '남은 이용 시간이 없습니다.',
};

function guestLimitError(reason) {
  return new functions.https.HttpsError('resource-exhausted',
      GUEST_LIMIT_MESSAGES[reason] || '지금은 통화할 수 없습니다.', {reason});
}

function promoClosedError() {
  return new functions.https.HttpsError('failed-precondition', '비회원 초대 기간이 끝났습니다.',
      {reason: 'promo_closed'});
}

// 하루는 한국 시간 자정에 넘어간다.
function kstDayKey(nowMs = Date.now()) {
  return new Date(nowMs + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

const dailyGuestCallRef = (nowMs) =>
  db().collection('duo_board_promo_daily').doc(kstDayKey(nowMs));

function pairKey(a, b) {
  return [a, b].sort().join('__');
}

// 제목 검사. 정규식이 1차, OpenAI 모더레이션이 2차다(언어 무관).
// 모더레이션 호출이 실패하면 통과시킨다 — 장애로 게시판 전체를 막지 않는다.
async function isTopicFlagged(topic, {apiKey, fetchImpl = fetch} = {}) {
  if (!apiKey) return false;
  try {
    const response = await fetchImpl('https://api.openai.com/v1/moderations', {
      method: 'POST',
      headers: {Authorization: 'Bearer ' + apiKey, 'Content-Type': 'application/json'},
      body: JSON.stringify({model: 'omni-moderation-latest', input: topic}),
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return false;
    const json = await response.json();
    return Boolean(json?.results?.[0]?.flagged);
  } catch (error) {
    console.warn('[DuoBoard] moderation unavailable: ' + error.name);
    return false;
  }
}

async function readSuspendedUntil(uid) {
  const snap = await db().collection('duo_board_suspensions').doc(uid).get();
  const until = snap.exists ? snap.get('until') : null;
  return until instanceof admin.firestore.Timestamp && until.toMillis() > Date.now()
    ? until : null;
}

async function assertNotSuspended(uid) {
  if (await readSuspendedUntil(uid)) {
    throw new functions.https.HttpsError('permission-denied', '신고가 누적되어 잠시 게시판을 이용할 수 없습니다.',
        {reason: 'suspended'});
  }
}

function uidOf(context) {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
  return context.auth.uid;
}

// 관리자 웹에서 차단된 계정은 게시판에 새로 올리거나 들어갈 수 없다.
async function assertNotBlocked(uid) {
  if (await readBlocked(db(), uid)) {
    throw new functions.https.HttpsError('permission-denied', '이용이 제한된 계정입니다.');
  }
}

const hostPresenceRef = uid => admin.database().ref(`duo_board_hosts/${uid}`);

async function isHostForeground(uid) {
  const snapshot = await hostPresenceRef(uid).once('value');
  const cutoff = Date.now() - 60 * 1000;
  let online = false;
  snapshot.forEach(child => {
    const value = child.val() || {};
    if (value.foreground === true && Number(value.lastSeen || 0) >= cutoff) {
      online = true;
    }
  });
  return online;
}

exports.publishDuoBoardPost = functions.runWith({secrets: [openAiApiKey]})
    .https.onCall(async (data, context) => {
  const uid = uidOf(context);
  await assertNotBlocked(uid);
  await assertNotSuspended(uid);
  const anonymous = isAnonymousAuth(context);
  const promo = anonymous ? await readPromoConfig() : null;
  if (anonymous && !promo.guestPostsEnabled) {
    throw new functions.https.HttpsError('permission-denied', '게시글은 회원만 작성할 수 있습니다.');
  }
  const roomId = String(data.roomId || '').trim();
  const historyPath = String(data.historyPath || '').trim();
  const mode = 'interpreter';
  const availability = 'request';
  const topic = text(data.topic, 80);
  const topicLanguage = String(data.topicLanguage || '').trim();
  const pushHours = pushHoursFrom(data.pushHours);
  const directLanguage = '';
  if (!roomId || !historyPath.startsWith(`users/${uid}/chat_history/`) ||
      data.mode === 'direct' || !topicLanguage) {
    throw new functions.https.HttpsError('invalid-argument', '초대 방 정보가 올바르지 않습니다.');
  }
  if (await isTopicFlagged(topic, {apiKey: openAiApiKey.value()})) {
    throw new functions.https.HttpsError('invalid-argument', '허용되지 않는 대화 주제입니다.',
        {reason: 'topic_rejected'});
  }
  if (anonymous) {
    // 폰(익명 계정) 하나에 살아 있는 초대글은 하나뿐이다.
    const own = await db().collection('duo_board_posts')
        .where('ownerUid', '==', uid).where('active', '==', true).limit(5).get();
    // 오늘 비회원 통화를 다 쓴 폰은 새 글을 올려도 받을 수 없다.
    const mine = await guestDailyRef(uid).get();
    if (Number(mine.get('calls') || 0) >= promo.perGuestDailyCalls) {
      throw guestLimitError('guest_daily_limit_personal');
    }
    if (own.docs.some(doc => doc.id !== roomId)) {
      throw new functions.https.HttpsError('already-exists', '이미 올린 초대글이 있습니다.',
          {reason: 'one_post_per_guest'});
    }
  }
  const roomRef = db().collection('duo_sessions').doc(roomId);
  const postRef = db().collection('duo_board_posts').doc(roomId);
  const runtimeRef = db().collection('duo_board_runtime').doc(roomId);
  await db().runTransaction(async tx => {
    const room = await tx.get(roomRef);
    if (!room.exists || room.get('hostUid') !== uid ||
        room.get('isDuoEnabled') !== true || room.get('mode') !== 'interpreter') {
      throw new functions.https.HttpsError('failed-precondition', '활성화된 본인 Duo 방이 아닙니다.');
    }
    if (anonymous) {
      // 비회원이 연 방은 서버 비용이다. 두 폰이 이 값을 읽어 통화를 끊는다.
      tx.update(roomRef, {promoGuestRoom: true, callLimitSeconds: promo.guestCallSeconds});
    }
    tx.set(postRef, {
      ownerUid: uid, ownerIsMember: !anonymous,
      topic, topicLanguage, mode, directLanguage, availability,
      // A successful callable invocation proves that the host app is in the
      // foreground. RTDB presence keeps this synchronized after publishing,
      // but it must not block creation of the post.
      active: true, state: 'active', discoverable: true, ownerPaused: false,
      inactiveSince: admin.firestore.FieldValue.delete(),
      pushHours, pushUntil: pushUntilFor(pushHours),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(runtimeRef, {
      ownerUid: uid, roomId, historyPath, claimUid: null, claimExpiresAt: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  return {postId: postRef.id};
});

// 글을 올린 뒤 푸시 시간을 바꾼다(0 = 끄기). 시간을 켜면 글도 활성으로 켠다.
exports.setDuoBoardPushWindow = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const postId = String(data.postId || '').trim();
  const hours = pushHoursFrom(data.hours);
  if (!postId) throw new functions.https.HttpsError('invalid-argument', 'postId가 필요합니다.');
  const foreground = await isHostForeground(uid);
  const postRef = db().collection('duo_board_posts').doc(postId);
  const pushUntil = pushUntilFor(hours);
  await db().runTransaction(async tx => {
    const post = await tx.get(postRef);
    if (!post.exists || post.get('ownerUid') !== uid || post.get('active') !== true) {
      throw new functions.https.HttpsError('not-found', '본인 초대글이 아닙니다.');
    }
    const reserved = post.get('state') === 'reserved';
    const visible = !reserved && (hours > 0 || (foreground && post.get('ownerPaused') !== true));
    tx.update(postRef, {
      pushHours: hours, pushUntil,
      ...(reserved ? {} : {
        discoverable: visible,
        ownerPaused: hours > 0 ? false : post.get('ownerPaused') === true,
        inactiveSince: visible ? admin.firestore.FieldValue.delete()
          : (post.get('inactiveSince') || admin.firestore.FieldValue.serverTimestamp()),
      }),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {hours, pushUntilMillis: hours > 0 ? pushUntil.toMillis() : 0};
});

exports.withdrawDuoBoardPost = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const postId = String(data.postId || '').trim();
  if (!postId) throw new functions.https.HttpsError('invalid-argument', 'postId가 필요합니다.');
  const postRef = db().collection('duo_board_posts').doc(postId);
  const runtimeRef = db().collection('duo_board_runtime').doc(postId);
  const requestRef = db().collection('duo_board_requests').doc(postId);
  await db().runTransaction(async tx => {
    const [post, request] = await Promise.all([tx.get(postRef), tx.get(requestRef)]);
    if (!post.exists || post.get('ownerUid') !== uid || post.get('active') !== true) {
      throw new functions.https.HttpsError('not-found', '삭제할 수 있는 본인 글이 아닙니다.');
    }
    tx.update(postRef, {active: false, withdrawnAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    tx.delete(runtimeRef);
    if (request.exists && request.get('status') === 'waiting') {
      tx.update(requestRef, {status: 'cancelled', cancelledAt: admin.firestore.FieldValue.serverTimestamp()});
      tx.set(db().collection('duo_board_requesters').doc(request.get('requesterUid')),
          {status: 'cancelled', updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    }
  });
  return {withdrawn: true};
});

exports.claimDuoBoardPost = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  await assertNotBlocked(uid);
  const postId = String(data.postId || '').trim();
  if (!postId) throw new functions.https.HttpsError('invalid-argument', 'postId가 필요합니다.');
  const postRef = db().collection('duo_board_posts').doc(postId);
  const runtimeRef = db().collection('duo_board_runtime').doc(postId);
  const now = admin.firestore.Timestamp.now();
  const expires = admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000);
  const initialPost = await postRef.get();
  if (!initialPost.exists || !await isHostForeground(initialPost.get('ownerUid'))) {
    throw new functions.https.HttpsError('failed-precondition', '초대자가 현재 앱에 없습니다.');
  }
  return db().runTransaction(async tx => {
    const [post, runtime] = await Promise.all([tx.get(postRef), tx.get(runtimeRef)]);
    if (!post.exists || !runtime.exists || post.get('active') !== true ||
        post.get('availability') !== 'now') {
      throw new functions.https.HttpsError('failed-precondition', '지금 참여할 수 없는 글입니다.');
    }
    const ownerUid = post.get('ownerUid');
    if (ownerUid === uid) throw new functions.https.HttpsError('failed-precondition', '본인 글에는 참여할 수 없습니다.');
    if (post.get('ownerIsMember') === false && isAnonymousAuth(context)) {
      throw new functions.https.HttpsError('permission-denied', '비회원 글은 회원만 참여할 수 있습니다.');
    }
    const previousExpiry = runtime.get('claimExpiresAt');
    if (runtime.get('claimUid') && previousExpiry && previousExpiry.toMillis() > now.toMillis()) {
      throw new functions.https.HttpsError('already-exists', '다른 사용자가 먼저 선택했습니다.');
    }
    const roomId = runtime.get('roomId');
    const roomRef = db().collection('duo_sessions').doc(roomId);
    const room = await tx.get(roomRef);
    if (!room.exists || room.get('isDuoEnabled') !== true || room.get('isPartnerJoined') === true) {
      throw new functions.https.HttpsError('failed-precondition', 'Duo 방을 사용할 수 없습니다.');
    }
    tx.update(runtimeRef, {claimUid: uid, claimExpiresAt: expires,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    tx.update(postRef, {availability: 'request',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    return {roomId, ownerUid};
  });
});

exports.requestDuoBoardPost = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  await assertNotBlocked(uid);
  await assertNotSuspended(uid);
  const requesterAnonymous = isAnonymousAuth(context);
  const postId = String(data.postId || '').trim();
  const rawAttemptId = String(data.attemptId || '').trim();
  const attemptId = /^[A-Za-z0-9_-]{8,80}$/.test(rawAttemptId)
    ? rawAttemptId : '';
  if (!postId) throw new functions.https.HttpsError('invalid-argument', 'postId가 필요합니다.');
  const postRef = db().collection('duo_board_posts').doc(postId);
  // New clients supply an auto-id per tap. Legacy clients remain on postId so
  // their existing presence path continues to work until they update.
  const requestId = attemptId || postId;
  const runtimeRef = db().collection('duo_board_runtime').doc(postId);
  const requestRef = db().collection('duo_board_requests').doc(requestId);
  const requesterRef = db().collection('duo_board_requesters').doc(uid);
  const promo = await readPromoConfig();
  // 앱이 켜져 있으면 바로 창을 띄우고, 꺼져 있으면 푸시 시간 안에서만 알림으로
  // 부른다. 주인과 대화맨 여부는 트랜잭션 밖에서 미리 본다(RTDB·다른 문서).
  const initialPost = await postRef.get();
  const initialOwner = initialPost.exists ? initialPost.get('ownerUid') : '';
  const [ownerForeground, ownerIsTalkHost, requesterSnap] = await Promise.all([
    initialOwner ? isHostForeground(initialOwner) : false,
    initialOwner ? talkHost.isActiveTalkHost(initialOwner) : false,
    requesterAnonymous ? null : db().collection('users').doc(uid).get(),
  ]);
  if (ownerIsTalkHost && promo.talkHostDailyCallLimit > 0 &&
      await talkHost.readTalkHostDailyCalls(initialOwner, kstDayKey()) >=
        promo.talkHostDailyCallLimit) {
    throw guestLimitError('host_daily_limit');
  }
  // 대화맨과의 통화는 회원 상대가 낸다. 남은 시간이 없으면 받지 않는다.
  if (ownerIsTalkHost && !requesterAnonymous &&
      !(Number(requesterSnap?.get('remainingTime') || 0) > 0)) {
    throw guestLimitError('requester_no_time');
  }
  const viaPush = !ownerForeground;
  const expiresAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + (viaPush ? PUSH_REQUEST_WAIT_MS : IN_APP_REQUEST_WAIT_MS));
  let ownerUid;
  await db().runTransaction(async tx => {
    const [post, runtime, previous, requester] = await Promise.all([
      tx.get(postRef), tx.get(runtimeRef), tx.get(requestRef), tx.get(requesterRef),
    ]);
    if (!post.exists || !runtime.exists || post.get('active') !== true ||
        post.get('discoverable') !== true) {
      throw new functions.https.HttpsError('failed-precondition', '요청을 받을 수 없는 글입니다.');
    }
    ownerUid = post.get('ownerUid');
    if (ownerUid === uid) throw new functions.https.HttpsError('failed-precondition', '본인 글에는 요청할 수 없습니다.');
    if (ownerUid !== initialOwner) {
      throw new functions.https.HttpsError('failed-precondition', '요청을 받을 수 없는 글입니다.');
    }
    if (viaPush && !isPushWindowOpen(post.data())) {
      throw new functions.https.HttpsError('failed-precondition', '초대자가 현재 앱에 없습니다.');
    }
    // 신고로 갈라진 두 사람은 다시 만나지 않는다. 이유는 알리지 않는다.
    const pairBlock = await tx.get(db().collection('duo_pair_blocks').doc(pairKey(uid, ownerUid)));
    if (pairBlock.exists) {
      throw new functions.https.HttpsError('failed-precondition', '요청을 받을 수 없는 글입니다.');
    }
    if (post.get('ownerIsMember') === false) {
      // 비회원 글은 회원만 받는다. 비회원끼리는 통화하지 않는다.
      if (requesterAnonymous) {
        throw new functions.https.HttpsError('permission-denied',
            '비회원 글은 회원만 참여할 수 있습니다.', {reason: 'guest_post_members_only'});
      }
      // 홍보가 끝나면 비회원 글로는 더 연결하지 않는다(이미 올라간 글 포함).
      if (!promo.guestPostsEnabled) throw promoClosedError();
      if (requesterAnonymous) {
        const reason = await guestCallBlockReason(tx, promo, {requesterUid: uid, ownerUid});
        if (reason) throw guestLimitError(reason);
      }
    } else if (ownerIsTalkHost && requesterAnonymous) {
      // 비회원이 대화맨 글에 들어가면 홍보 3분(서버 부담)이다. 대화맨 쪽 상한은 없다.
      if (!promo.guestPostsEnabled) throw promoClosedError();
      const reason = await guestCallBlockReason(tx, promo, {requesterUid: uid, ownerUid: ''});
      if (reason) throw guestLimitError(reason);
    }
    const pendingRequestId = runtime.get('pendingRequestId') || '';
    const pendingExpiresAt = runtime.get('pendingRequestExpiresAt');
    if (pendingRequestId && pendingExpiresAt?.toMillis() > Date.now()) {
      const pending = await tx.get(
          db().collection('duo_board_requests').doc(pendingRequestId));
      if (pending.exists && ['waiting', 'matched'].includes(pending.get('status'))) {
        if (pending.get('requesterUid') === uid) {
          throw new functions.https.HttpsError('already-exists', '이미 기다리고 있습니다.');
        }
        throw new functions.https.HttpsError('resource-exhausted', '다른 요청자가 기다리고 있습니다.');
      }
    }
    if (previous.exists && ['waiting', 'matched'].includes(previous.get('status')) &&
        previous.get('expiresAt')?.toMillis() > Date.now()) {
      if (previous.get('requesterUid') === uid) {
        throw new functions.https.HttpsError('already-exists', '이미 기다리고 있습니다.');
      }
      throw new functions.https.HttpsError('resource-exhausted', '다른 요청자가 기다리고 있습니다.');
    }
    if (requester.exists && ['waiting', 'matched'].includes(requester.get('status')) &&
        requester.get('expiresAt')?.toMillis() > Date.now()) {
      throw new functions.https.HttpsError('already-exists', '이미 다른 글에서 기다리고 있습니다.');
    }
    const claimExpiry = runtime.get('claimExpiresAt');
    if (runtime.get('claimUid') && claimExpiry &&
        claimExpiry.toMillis() > Date.now()) {
      throw new functions.https.HttpsError('resource-exhausted', '다른 참여자가 연결 중입니다.');
    }
    const roomId = runtime.get('roomId');
    const room = await tx.get(db().collection('duo_sessions').doc(roomId));
    if (!room.exists || room.get('hostUid') !== ownerUid ||
        room.get('isDuoEnabled') !== true || room.get('isPartnerJoined') === true) {
      throw new functions.https.HttpsError('failed-precondition', 'Duo 방을 사용할 수 없습니다.');
    }
    tx.set(requestRef, {
      postId, ownerUid, requesterUid: uid, status: 'waiting',
      attemptId, requesterAnonymous,
      mode: post.get('mode'), directLanguage: post.get('directLanguage') || '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(), expiresAt,
      roomId,
      historyPath: runtime.get('historyPath') || '',
    });
    tx.set(requesterRef, {
      requestId, attemptId, status: 'waiting', expiresAt,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(runtimeRef, {pendingRequestId: requestId,
      pendingRequestExpiresAt: expiresAt,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  });
  // 앱이 켜져 있으면 Firestore 리스너가 창을 띄운다. 꺼져 있으면(푸시 시간 안)
  // 알림을 보낸다. 받을 폰이 하나도 없으면 요청을 바로 닫는다.
  if (viaPush && await sendRequestPush(ownerUid, requestId) === 0) {
    await requestRef.set({status: 'expired', expiredAt:
      admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    await requesterRef.set({status: 'expired', updatedAt:
      admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    throw new functions.https.HttpsError('failed-precondition', '초대자가 현재 앱에 없습니다.');
  }
  return {requestId, attemptId, viaPush,
    expiresAtMillis: expiresAt.toMillis()};
});

exports.openDuoBoardRequest = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const requestId = String(data.requestId || '').trim();
  const requestRef = db().collection('duo_board_requests').doc(requestId);
  const before = await requestRef.get();
  if (!before.exists || before.get('ownerUid') !== uid ||
      before.get('status') !== 'waiting') {
    throw new functions.https.HttpsError('not-found', '요청자가 더 이상 기다리고 있지 않습니다.');
  }
  const requesterUid = before.get('requesterUid');
  const ownerIsTalkHost = await talkHost.isActiveTalkHost(uid);
  const presenceRef = admin.database()
      .ref(`duo_board_waiting/${requestId}/${requesterUid}`);
  const gate = await presenceRef.transaction(current => {
    if (current?.matching === true) return;
    return {...(current || {}), matching: true, matchingOwnerUid: uid,
      matchingAt: admin.database.ServerValue.TIMESTAMP};
  }, undefined, false);
  if (!gate.committed) {
    if (gate.snapshot.val()?.matching === true) {
      throw new functions.https.HttpsError('already-exists', '요청을 확인하고 있습니다.');
    }
    await requestRef.set({status: 'expired'}, {merge: true});
    await db().collection('duo_board_requesters').doc(requesterUid)
        .set({status: 'expired'}, {merge: true});
    throw new functions.https.HttpsError('not-found', '요청자가 더 이상 기다리고 있지 않습니다.');
  }
  try {
    return await db().runTransaction(async tx => {
      const request = await tx.get(requestRef);
      if (!request.exists || request.get('ownerUid') !== uid ||
          request.get('status') !== 'waiting' ||
          request.get('expiresAt').toMillis() <= Date.now()) {
        throw new functions.https.HttpsError('not-found', '요청자가 더 이상 기다리고 있지 않습니다.');
      }
      const roomId = request.get('roomId');
      const roomRef = db().collection('duo_sessions').doc(roomId);
      const postRef = db().collection('duo_board_posts').doc(request.get('postId'));
      const [room, post] = await Promise.all([tx.get(roomRef), tx.get(postRef)]);
      if (!room.exists || room.get('hostUid') !== uid ||
          room.get('isDuoEnabled') !== true || room.get('isPartnerJoined') === true ||
          !post.exists || post.get('active') !== true) {
        throw new functions.https.HttpsError('failed-precondition', 'Duo 방을 다시 열 수 없습니다.');
      }
      // 수락 순간에 한 번 더 본다(요청 뒤 상한이 찼을 수 있다). 세는 것은
      // 게스트가 실제로 들어온 뒤 `completeDuoBoardPostOnJoin`이 한다.
      if (room.get('promoGuestRoom') === true && post.get('ownerIsMember') === false &&
          request.get('requesterAnonymous') === true) {
        throw new functions.https.HttpsError('failed-precondition', '비회원끼리는 통화할 수 없습니다.');
      }
      if (room.get('promoGuestRoom') === true) {
        const promo = await readPromoConfig();
        if (!promo.guestPostsEnabled) throw promoClosedError();
        if (request.get('requesterAnonymous') === true) {
          const reason = await guestCallBlockReason(tx, promo, {
            requesterUid: request.get('requesterUid'), ownerUid: uid});
          if (reason) throw guestLimitError(reason);
        }
      }
      // 대화맨 방은 대화맨 시간을 쓰지 않는다. 비회원 상대면 홍보 3분(서버),
      // 회원 상대면 상대가 낸다(billPartner). 두 폰이 이 값을 읽어 과금을 고른다.
      let talkHostRoom = {};
      if (ownerIsTalkHost && room.get('promoGuestRoom') !== true) {
        if (request.get('requesterAnonymous') === true) {
          const promo = await readPromoConfig();
          if (!promo.guestPostsEnabled) throw promoClosedError();
          const reason = await guestCallBlockReason(tx, promo, {
            requesterUid: request.get('requesterUid'), ownerUid: ''});
          if (reason) throw guestLimitError(reason);
          talkHostRoom = {talkHostRoom: true, promoGuestRoom: true,
            callLimitSeconds: promo.guestCallSeconds, billPartner: false};
        } else {
          talkHostRoom = {talkHostRoom: true, billPartner: true};
        }
      }
      tx.update(requestRef, {status: 'matched', matchedAt:
        admin.firestore.FieldValue.serverTimestamp()});
      tx.set(db().collection('duo_board_requesters').doc(request.get('requesterUid')),
          {status: 'matched', updatedAt: admin.firestore.FieldValue.serverTimestamp()},
          {merge: true});
      tx.update(roomRef, {partnerUid: request.get('requesterUid'),
        boardReservedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...talkHostRoom});
      tx.update(postRef, {state: 'reserved', discoverable: false,
        reservedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      return {roomId, requestId, mode: request.get('mode'),
        historyPath: request.get('historyPath') || ''};
    });
  } catch (error) {
    await presenceRef.transaction(current => {
      if (!current || current.matchingOwnerUid !== uid) return current;
      delete current.matching;
      delete current.matchingOwnerUid;
      delete current.matchingAt;
      return current;
    }, undefined, false);
    throw error;
  }
});

exports.declineDuoBoardRequest = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const requestId = String(data.requestId || '').trim();
  const reason = data.reason === 'timeout' ? 'timeout' : 'busy';
  if (!requestId) throw new functions.https.HttpsError('invalid-argument', 'requestId가 필요합니다.');
  const requestRef = db().collection('duo_board_requests').doc(requestId);
  await db().runTransaction(async tx => {
    const request = await tx.get(requestRef);
    if (!request.exists || request.get('ownerUid') !== uid ||
        request.get('status') !== 'waiting') return;
    tx.update(requestRef, {status: reason, respondedAt:
      admin.firestore.FieldValue.serverTimestamp()});
    tx.set(db().collection('duo_board_requesters').doc(request.get('requesterUid')),
        {status: reason, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
        {merge: true});
  });
  return {declined: true, reason};
});

exports.resumeDuoBoardPost = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const postId = String(data.postId || '').trim();
  const postRef = db().collection('duo_board_posts').doc(postId);
  const roomRef = db().collection('duo_sessions').doc(postId);
  return db().runTransaction(async tx => {
    const [post, room] = await Promise.all([tx.get(postRef), tx.get(roomRef)]);
    if (!post.exists || post.get('ownerUid') !== uid || post.get('active') !== true) {
      return {resumed: false};
    }
    if (!room.exists || room.get('hostUid') !== uid ||
        room.get('isDuoEnabled') !== true || room.get('isPartnerJoined') === true) {
      tx.update(postRef, {active: false, discoverable: false, state: 'expired',
        updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      return {resumed: false};
    }
    tx.update(roomRef, {partnerUid: null, boardReservedAt: null});
    // The member explicitly continued the invitation while using the app.
    tx.update(postRef, {state: 'active', discoverable: true, ownerPaused: false,
      inactiveSince: admin.firestore.FieldValue.delete(),
      reservedAt: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()});
    return {resumed: true};
  });
});

exports.setDuoBoardPostVisibility = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const postId = String(data.postId || '').trim();
  const enabled = data.enabled === true;
  if (!postId) {
    throw new functions.https.HttpsError('invalid-argument', 'postId가 필요합니다.');
  }
  const postRef = db().collection('duo_board_posts').doc(postId);
  await db().runTransaction(async tx => {
    const post = await tx.get(postRef);
    if (!post.exists || post.get('ownerUid') !== uid ||
        post.get('active') !== true || post.get('state') === 'reserved') {
      throw new functions.https.HttpsError(
          'failed-precondition', '상태를 변경할 수 있는 본인 초대글이 아닙니다.');
    }
    tx.update(postRef, {
      ownerPaused: !enabled,
      discoverable: enabled,
      // 직접 끄면 푸시 시간도 끝난다. 다시 받으려면 시간을 다시 고른다.
      ...(enabled ? {} : {pushHours: 0, pushUntil: admin.firestore.FieldValue.delete()}),
      inactiveSince: enabled
        ? admin.firestore.FieldValue.delete()
        : (post.get('inactiveSince') ||
          admin.firestore.FieldValue.serverTimestamp()),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return {discoverable: enabled};
});

// Materialize RTDB foreground presence onto board posts so the public list can
// hide an invitation without opening one RTDB listener per card.
exports.syncDuoBoardHostPresence = functions.database
    .ref('/duo_board_hosts/{uid}/{connectionId}')
    .onWrite(async (change, context) => {
      const uid = context.params.uid;
      const discoverable = await isHostForeground(uid);
      const posts = await db().collection('duo_board_posts')
          .where('ownerUid', '==', uid).get();
      // Presence events can race a member's activate/deactivate tap. Re-read
      // each document transactionally so a stale presence snapshot can never
      // overwrite the newly written ownerPaused flag.
      await Promise.all(posts.docs.map(doc => db().runTransaction(async tx => {
        const current = await tx.get(doc.ref);
        if (!current.exists || current.get('active') !== true ||
            current.get('state') === 'reserved') return;
        const visible = current.get('ownerPaused') === true
          ? false
          : discoverable || isPushWindowOpen(current.data());
        tx.update(doc.ref, {
          discoverable: visible,
          inactiveSince: visible
            ? admin.firestore.FieldValue.delete()
            : (current.get('inactiveSince') ||
              admin.firestore.FieldValue.serverTimestamp()),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      })));
      return null;
    });

const INACTIVE_POST_TTL_MS = 3 * 24 * 60 * 60 * 1000;
const RESERVED_POST_TTL_MS = 5 * 60 * 1000;

// Keep temporarily unavailable invitations visible to intro guests, but delete
// them after 3 continuous days without becoming discoverable again. A board
// match reserves a post before the guest has actually joined; release that
// reservation if the join never arrives so one abandoned request cannot hide a
// post forever.
exports.expireInactiveDuoBoardPosts = functions.pubsub
    .schedule('every 5 minutes')
    .onRun(async () => {
      const cutoff = admin.firestore.Timestamp.fromMillis(
          Date.now() - INACTIVE_POST_TTL_MS);
      const reservedCutoff = admin.firestore.Timestamp.fromMillis(
          Date.now() - RESERVED_POST_TTL_MS);
      const snapshot = await db().collection('duo_board_posts')
          .where('active', '==', true)
          .get();
      const promo = await readPromoConfig();
      // 접속 표시가 멈춘 채 남은 글을 내린다. 동기화는 접속 표시가 **바뀔 때만**
      // 돌아서, 폰이 갑자기 꺼지거나 로그인으로 uid가 바뀌어 옛 표시를 못 지운
      // 경우(10-30 실기기) 글이 "활성"으로 남고 요청은 "앱에 없음"으로 거절됐다.
      const foreground = new Map();
      for (const doc of snapshot.docs) {
        if (doc.get('discoverable') !== true) continue;
        const owner = doc.get('ownerUid');
        if (!foreground.has(owner)) foreground.set(owner, await isHostForeground(owner));
      }
      let staled = 0;
      let expired = 0;
      let deleted = 0;
      let initialized = 0;
      let released = 0;
      let promoClosed = 0;
      for (const candidate of snapshot.docs) {
        const result = await db().runTransaction(async tx => {
          const current = await tx.get(candidate.ref);
          if (!current.exists || current.get('active') !== true) return null;

          // 홍보가 끝났으면 비회원 글을 게시판에서 내린다. 통화 중(예약)인
          // 글은 그 통화가 끝나 matched가 될 때까지 둔다.
          if (!promo.guestPostsEnabled && current.get('ownerIsMember') === false &&
              current.get('state') !== 'reserved') {
            tx.update(candidate.ref, {
              active: false,
              discoverable: false,
              state: 'promo_closed',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            tx.delete(db().collection('duo_board_runtime').doc(candidate.id));
            return 'promo_closed';
          }

          if (current.get('discoverable') === true &&
              current.get('state') !== 'reserved' &&
              foreground.get(current.get('ownerUid')) === false &&
              !isPushWindowOpen(current.data())) {
            tx.update(candidate.ref, {
              discoverable: false,
              inactiveSince: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return 'staled';
          }

          if (current.get('state') === 'reserved') {
            const reservedAt = current.get('reservedAt');
            if (!(reservedAt instanceof admin.firestore.Timestamp) ||
                reservedAt.toMillis() > reservedCutoff.toMillis()) {
              return null;
            }
            const roomRef = db().collection('duo_sessions').doc(candidate.id);
            const room = await tx.get(roomRef);
            if (!room.exists || room.get('isDuoEnabled') !== true) {
              tx.update(candidate.ref, {
                active: false,
                discoverable: false,
                state: 'expired',
                expiredAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              tx.delete(db().collection('duo_board_runtime').doc(candidate.id));
              return 'expired';
            }
            if (room.get('isPartnerJoined') === true) {
              return null;
            }
            // A prior guest joined and later left. Do not re-publish a board
            // post whose completion trigger may only be delayed.
            if (room.get('partnerJoinedAt')) {
              tx.update(candidate.ref, {
                active: false,
                discoverable: false,
                state: 'expired',
                expiredAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              tx.delete(db().collection('duo_board_runtime').doc(candidate.id));
              return 'expired';
            }            tx.update(candidate.ref, {
              state: 'active',
              discoverable: false,
              reservedAt: admin.firestore.FieldValue.delete(),
              inactiveSince: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            if (room.exists) {
              tx.update(roomRef, {partnerUid: null, boardReservedAt: null});
            }
            return 'released';
          }

          const inactiveSince = current.get('inactiveSince');
          if (current.get('discoverable') === true) return null;
          if (!inactiveSince) {
            tx.update(candidate.ref, {
              inactiveSince: admin.firestore.FieldValue.serverTimestamp(),
            });
            return 'initialized';
          }
          if (!(inactiveSince instanceof admin.firestore.Timestamp) ||
              inactiveSince.toMillis() > cutoff.toMillis()) return null;
          tx.delete(candidate.ref);
          tx.delete(db().collection('duo_board_runtime').doc(candidate.id));
          return 'deleted';
        });
        if (result === 'expired') expired += 1;
        if (result === 'deleted') deleted += 1;
        if (result === 'initialized') initialized += 1;
        if (result === 'released') released += 1;
        if (result === 'promo_closed') promoClosed += 1;
        if (result === 'staled') staled += 1;
      }
      if (staled > 0) {
        console.log('Hid ' + staled + ' posts whose host presence went stale.');
      }
      if (promoClosed > 0) {
        console.log('Closed ' + promoClosed + ' guest posts because the promotion is off.');
      }
      console.log('Deleted ' + deleted + ' inactive Duo board posts; expired ' +
          expired + ' unavailable posts; released ' + released +
          ' stale reservations; initialized ' + initialized +
          ' inactive posts.');
      return null;
    });
// The session document is the authoritative proof that the requester really
// entered. Keep the post for audit, but remove it from the board permanently.
exports.completeDuoBoardPostOnJoin = functions.firestore
    .document('duo_sessions/{roomId}')
    .onUpdate(async (change, context) => {
      if (change.before.get('isPartnerJoined') === true ||
          change.after.get('isPartnerJoined') !== true) return null;
      const roomId = context.params.roomId;
      const postRef = db().collection('duo_board_posts').doc(roomId);
      const post = await postRef.get();
      if (post.exists && post.get('active') === true) {
        await postRef.update({active: false, discoverable: false, state: 'matched',
          matchedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      }
      const isTalkHostRoom = change.after.get('talkHostRoom') === true;
      if (change.after.get('promoGuestRoom') === true) {
        await countGuestCallOnJoin(roomId, change.after.get('hostUid'),
            change.after.get('partnerUid'), {countHost: !isTalkHostRoom});
      }
      if (isTalkHostRoom) {
        await talkHost.countTalkHostCallOnJoin(roomId, change.after.get('hostUid'), kstDayKey());
      }
      return null;
    });

async function isAnonymousUid(uid) {
  if (!uid) return false;
  try {
    const user = await admin.auth().getUser(uid);
    return (user.providerData || []).length === 0;
  } catch (error) {
    return false;
  }
}

// 비회원끼리 통화를 게스트가 실제로 들어온 순간에 센다. 수락만 하고 아무도
// 안 들어온 통화는 세지 않는다. 같은 방은 한 번만 센다(재입장·재시도).
async function countGuestCallOnJoin(roomId, hostUid, partnerUid, {countHost = true} = {}) {
  if (!await isAnonymousUid(partnerUid)) return;
  const dailyRef = dailyGuestCallRef();
  const markerRef = dailyRef.collection('rooms').doc(roomId);
  await db().runTransaction(async tx => {
    const marker = await tx.get(markerRef);
    if (marker.exists) return;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const inc = admin.firestore.FieldValue.increment(1);
    tx.set(markerRef, {hostUid, partnerUid, countedAt: now});
    tx.set(dailyRef, {guestCalls: inc, updatedAt: now}, {merge: true});
    if (countHost) tx.set(guestDailyRef(hostUid), {calls: inc, updatedAt: now}, {merge: true});
    tx.set(guestDailyRef(partnerUid), {calls: inc, updatedAt: now}, {merge: true});
  });
}

exports.cancelDuoBoardRequest = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const requestId = String(data.requestId || '').trim();
  if (!requestId) throw new functions.https.HttpsError('invalid-argument', 'requestId가 필요합니다.');
  const attemptId = String(data.attemptId || '').trim();
  const requestRef = db().collection('duo_board_requests').doc(requestId);
  const requesterRef = db().collection('duo_board_requesters').doc(uid);
  await db().runTransaction(async tx => {
    const request = await tx.get(requestRef);
    if (!request.exists || request.get('requesterUid') !== uid ||
        request.get('status') !== 'waiting') return;
    const currentAttemptId = request.get('attemptId') || '';
    // A disposed dialog from an earlier attempt must never cancel a newer
    // request that reused the board post document id.
    if (currentAttemptId !== attemptId) return;
    tx.update(requestRef, {status: 'cancelled',
      cancelledAt: admin.firestore.FieldValue.serverTimestamp()});
    tx.set(requesterRef, {status: 'cancelled',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  });
  return {cancelled: true};
});

// 신고 3단계.
//   1. 신고 한 건: 신고자와 상대는 서로 다시 매칭되지 않는다. 상대에게 다른 불이익은 없다.
//   2. 24시간 안에 서로 다른 신고자 3명: 상대는 24시간 게시판 글쓰기·참여 정지.
//   3. 영구 차단은 관리자가 대화 기록을 보고 user_flags로 정한다.
// 무고 신고 한 건으로는 상대가 잃는 것이 없게 하는 것이 이 설계의 핵심이다.
function distinctRecentReporters(reports, nowMs) {
  const reporters = new Set();
  for (const report of reports) {
    const at = report.createdAt;
    const millis = at instanceof admin.firestore.Timestamp ? at.toMillis() : 0;
    if (nowMs - millis <= REPORT_WINDOW_MS && report.reporterUid) {
      reporters.add(report.reporterUid);
    }
  }
  return reporters.size;
}

exports.reportDuoPartner = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const roomId = String(data.roomId || '').trim();
  if (!roomId) throw new functions.https.HttpsError('invalid-argument', 'roomId가 필요합니다.');
  const room = await db().collection('duo_sessions').doc(roomId).get();
  if (!room.exists) {
    throw new functions.https.HttpsError('not-found', '통화를 찾을 수 없습니다.');
  }
  const hostUid = room.get('hostUid') || '';
  const partnerUid = room.get('partnerUid') || '';
  const targetUid = hostUid === uid ? partnerUid : partnerUid === uid ? hostUid : '';
  if (!targetUid || targetUid === uid) {
    throw new functions.https.HttpsError('failed-precondition', '이 통화의 참가자가 아닙니다.');
  }
  const reportRef = db().collection('duo_reports').doc(`${roomId}__${uid}`);
  const created = await db().runTransaction(async tx => {
    const existing = await tx.get(reportRef);
    if (existing.exists) return false;
    tx.set(reportRef, {
      roomId, reporterUid: uid, targetUid,
      reporterAnonymous: isAnonymousAuth(context),
      promoGuestRoom: room.get('promoGuestRoom') === true,
      status: 'open',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(db().collection('duo_pair_blocks').doc(pairKey(uid, targetUid)), {
      uids: [uid, targetUid].sort(), roomId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!created) return {reported: true, suspended: false};

  const recent = await db().collection('duo_reports')
      .where('targetUid', '==', targetUid).limit(200).get();
  const count = distinctRecentReporters(recent.docs.map(doc => doc.data()), Date.now());
  if (count < REPORTS_TO_SUSPEND) return {reported: true, suspended: false};

  await db().collection('duo_board_suspensions').doc(targetUid).set({
    until: admin.firestore.Timestamp.fromMillis(Date.now() + SUSPEND_MS),
    reason: 'reports', reporterCount: count,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  const posts = await db().collection('duo_board_posts')
      .where('ownerUid', '==', targetUid).where('active', '==', true).get();
  await Promise.all(posts.docs.map(doc => doc.ref.update({
    active: false, discoverable: false, state: 'suspended',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  })));
  console.log('[DuoBoard] suspended ' + targetUid + ' after ' + count + ' reporters');
  return {reported: true, suspended: false};
});

exports._test = {promoConfigFrom, kstDayKey, pairKey, isTopicFlagged, distinctRecentReporters,
  guestCallBlockReasonFrom, pushHoursFrom, isPushWindowOpen, pushCopyFor};
