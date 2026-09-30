const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');

const db = () => admin.firestore();
const badTopic = /(https?:\/\/|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}|\b\d{2,3}[- .]?\d{3,4}[- .]?\d{4}\b|시발|씨발|섹스|강간|마약|살인|fuck|porn|rape)/iu;

function text(value, max) {
  const out = String(value || '').trim().replace(/\s+/g, ' ');
  if (out.length < 2 || out.length > max || badTopic.test(out)) {
    throw new functions.https.HttpsError('invalid-argument', '허용되지 않는 대화 주제입니다.');
  }
  return out;
}

function uidOf(context) {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', '로그인이 필요합니다.');
  return context.auth.uid;
}

exports.publishDuoBoardPost = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  if (context.auth.token.firebase?.sign_in_provider === 'anonymous') {
    throw new functions.https.HttpsError('permission-denied', '게시글은 회원만 작성할 수 있습니다.');
  }
  const roomId = String(data.roomId || '').trim();
  const historyPath = String(data.historyPath || '').trim();
  const mode = data.mode === 'direct' ? 'direct' : 'interpreter';
  const availability = data.availability === 'request' ? 'request' : 'now';
  const topic = text(data.topic, 80);
  const directLanguage = mode === 'direct' ? String(data.directLanguage || '').trim() : '';
  if (!roomId || !historyPath.startsWith(`users/${uid}/chat_history/`) ||
      (mode === 'direct' && !directLanguage)) {
    throw new functions.https.HttpsError('invalid-argument', '초대 방 정보가 올바르지 않습니다.');
  }
  const roomRef = db().collection('duo_sessions').doc(roomId);
  const postRef = db().collection('duo_board_posts').doc(roomId);
  const runtimeRef = db().collection('duo_board_runtime').doc(roomId);
  await db().runTransaction(async tx => {
    const room = await tx.get(roomRef);
    if (!room.exists || room.get('hostUid') !== uid || room.get('isDuoEnabled') !== true) {
      throw new functions.https.HttpsError('failed-precondition', '활성화된 본인 Duo 방이 아닙니다.');
    }
    tx.set(postRef, {
      ownerUid: uid, topic, mode, directLanguage, availability,
      active: true, createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.set(runtimeRef, {
      ownerUid: uid, roomId, historyPath, claimUid: null, claimExpiresAt: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  return {postId: postRef.id};
});

exports.claimDuoBoardPost = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const postId = String(data.postId || '').trim();
  if (!postId) throw new functions.https.HttpsError('invalid-argument', 'postId가 필요합니다.');
  const postRef = db().collection('duo_board_posts').doc(postId);
  const runtimeRef = db().collection('duo_board_runtime').doc(postId);
  const now = admin.firestore.Timestamp.now();
  const expires = admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000);
  return db().runTransaction(async tx => {
    const [post, runtime] = await Promise.all([tx.get(postRef), tx.get(runtimeRef)]);
    if (!post.exists || !runtime.exists || post.get('active') !== true ||
        post.get('availability') !== 'now') {
      throw new functions.https.HttpsError('failed-precondition', '지금 참여할 수 없는 글입니다.');
    }
    const ownerUid = post.get('ownerUid');
    if (ownerUid === uid) throw new functions.https.HttpsError('failed-precondition', '본인 글에는 참여할 수 없습니다.');
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
  const postId = String(data.postId || '').trim();
  if (!postId) throw new functions.https.HttpsError('invalid-argument', 'postId가 필요합니다.');
  const postRef = db().collection('duo_board_posts').doc(postId);
  const runtimeRef = db().collection('duo_board_runtime').doc(postId);
  const requestRef = db().collection('duo_board_requests').doc(postId);
  const requesterRef = db().collection('duo_board_requesters').doc(uid);
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000);
  let ownerUid;
  let topic;
  await db().runTransaction(async tx => {
    const [post, runtime, previous, requester] = await Promise.all([
      tx.get(postRef), tx.get(runtimeRef), tx.get(requestRef), tx.get(requesterRef),
    ]);
    if (!post.exists || !runtime.exists || post.get('active') !== true ||
        post.get('availability') !== 'request') {
      throw new functions.https.HttpsError('failed-precondition', '요청을 받을 수 없는 글입니다.');
    }
    ownerUid = post.get('ownerUid');
    topic = post.get('topic');
    if (ownerUid === uid) throw new functions.https.HttpsError('failed-precondition', '본인 글에는 요청할 수 없습니다.');
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
      mode: post.get('mode'), directLanguage: post.get('directLanguage') || '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(), expiresAt,
      roomId,
      historyPath: runtime.get('historyPath') || '',
    });
    tx.set(requesterRef, {
      requestId: postId, status: 'waiting', expiresAt,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  const tokens = await db().collection('users').doc(ownerUid)
      .collection('fcm_tokens').get();
  const tokenValues = tokens.docs.map(d => d.get('token')).filter(Boolean);
  if (tokenValues.length) {
    await admin.messaging().sendEachForMulticast({
      tokens: tokenValues,
      notification: {
        title: 'StealthVox · Duo 요청',
        body: `“${topic}”를 원하는 사람이 기다리고 있습니다.`,
      },
      data: {type: 'duo_board_request', requestId: postId},
      android: {priority: 'high'},
    });
  }
  return {requestId: postId, expiresAtMillis: expiresAt.toMillis()};
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
  const presenceSnap = await admin.database()
      .ref(`duo_board_waiting/${requestId}/${requesterUid}`).once('value');
  if (!presenceSnap.exists()) {
    await requestRef.set({status: 'expired'}, {merge: true});
    await db().collection('duo_board_requesters').doc(requesterUid)
        .set({status: 'expired'}, {merge: true});
    throw new functions.https.HttpsError('not-found', '요청자가 더 이상 기다리고 있지 않습니다.');
  }
  return db().runTransaction(async tx => {
    const request = await tx.get(requestRef);
    if (!request.exists || request.get('ownerUid') !== uid ||
        request.get('status') !== 'waiting' ||
        request.get('expiresAt').toMillis() <= Date.now()) {
      throw new functions.https.HttpsError('not-found', '요청자가 더 이상 기다리고 있지 않습니다.');
    }
    const roomId = request.get('roomId');
    const roomRef = db().collection('duo_sessions').doc(roomId);
    const room = await tx.get(roomRef);
    if (!room.exists || room.get('hostUid') !== uid ||
        room.get('isDuoEnabled') !== true || room.get('isPartnerJoined') === true) {
      throw new functions.https.HttpsError('failed-precondition', 'Duo 방을 다시 열 수 없습니다.');
    }
    tx.update(requestRef, {status: 'matched', matchedAt:
      admin.firestore.FieldValue.serverTimestamp()});
    tx.set(db().collection('duo_board_requesters').doc(request.get('requesterUid')),
        {status: 'matched', updatedAt: admin.firestore.FieldValue.serverTimestamp()},
        {merge: true});
    return {roomId, requestId, mode: request.get('mode'),
      historyPath: request.get('historyPath') || ''};
  });
});

exports.cancelDuoBoardRequest = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  const requestId = String(data.requestId || '').trim();
  if (!requestId) throw new functions.https.HttpsError('invalid-argument', 'requestId가 필요합니다.');
  const requestRef = db().collection('duo_board_requests').doc(requestId);
  const requesterRef = db().collection('duo_board_requesters').doc(uid);
  await db().runTransaction(async tx => {
    const request = await tx.get(requestRef);
    if (!request.exists || request.get('requesterUid') !== uid ||
        request.get('status') !== 'waiting') return;
    tx.update(requestRef, {status: 'cancelled',
      cancelledAt: admin.firestore.FieldValue.serverTimestamp()});
    tx.set(requesterRef, {status: 'cancelled',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  });
  return {cancelled: true};
});
