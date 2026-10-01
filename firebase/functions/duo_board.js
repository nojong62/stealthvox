const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');

const db = () => admin.firestore();
const badTopic = /(https?:\/\/|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}|\b\d{2,3}[- .]?\d{3,4}[- .]?\d{4}\b|시발|씨발|섹스|강간|마약|살인|fuck|porn|rape)/iu;

const duoRequestNotificationCopy = {
  English: {title: 'StealthVox · Duo request', body: topic => `Someone is waiting to talk about “${topic}”.`},
  Korean: {title: 'StealthVox · Duo 요청', body: topic => `“${topic}”를 원하는 사람이 기다리고 있습니다.`},
  Japanese: {title: 'StealthVox · Duoリクエスト', body: topic => `「${topic}」について話したい人が待っています。`},
  Chinese: {title: 'StealthVox · Duo 请求', body: topic => `有人正在等待讨论“${topic}”。`},
  Spanish: {title: 'StealthVox · Solicitud Duo', body: topic => `Alguien espera para hablar sobre “${topic}”.`},
  French: {title: 'StealthVox · Demande Duo', body: topic => `Quelqu’un attend pour parler de « ${topic} ».`},
  German: {title: 'StealthVox · Duo-Anfrage', body: topic => `Jemand wartet, um über „${topic}“ zu sprechen.`},
  Hindi: {title: 'StealthVox · Duo अनुरोध', body: topic => `कोई “${topic}” पर बात करने के लिए इंतज़ार कर रहा है।`},
  Russian: {title: 'StealthVox · Duo-запрос', body: topic => `Кто-то ждёт, чтобы поговорить о «${topic}».`},
  Portuguese: {title: 'StealthVox · Solicitação Duo', body: topic => `Alguém está esperando para falar sobre “${topic}”.`},
  Italian: {title: 'StealthVox · Richiesta Duo', body: topic => `Qualcuno aspetta per parlare di “${topic}”.`},
  Dutch: {title: 'StealthVox · Duo-verzoek', body: topic => `Iemand wacht om over “${topic}” te praten.`},
};

function notificationCopyFor(language) {
  return duoRequestNotificationCopy[String(language || '').trim()] ||
      duoRequestNotificationCopy.English;
}

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
  try {
    const tokens = await db().collection('users').doc(ownerUid)
        .collection('fcm_tokens').get();
    const tokenDocs = tokens.docs.filter(d => Boolean(d.get('token')));
    if (tokenDocs.length) {
      const response = await admin.messaging().sendEach(
          tokenDocs.map(doc => {
            // chatLanguage is the Lobby setting. originLanguage is read only
            // for previously registered installations.
            const copy = notificationCopyFor(
                doc.get('chatLanguage') || doc.get('originLanguage'));
            return {
              token: doc.get('token'),
              notification: {title: copy.title, body: copy.body(topic)},
              data: {type: 'duo_board_request', requestId: postId},
              android: {priority: 'high'},
            };
          }));
      const invalidCodes = new Set([
        'messaging/invalid-registration-token',
        'messaging/registration-token-not-registered',
      ]);
      const cleanup = response.responses
          .map((item, index) => !item.success && invalidCodes.has(item.error?.code)
            ? tokenDocs[index]?.ref.delete() : null)
          .filter(Boolean);
      await Promise.all(cleanup);
    }
  } catch (error) {
    // The transaction above is authoritative. Notification delivery is
    // best-effort and must not turn a saved request into a visible failure.
    console.error('Duo request notification failed', {
      requestId: postId,
      code: error?.code || 'unknown',
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
  const presenceRef = admin.database()
      .ref(`duo_board_waiting/${requestId}/${requesterUid}`);
  const gate = await presenceRef.transaction(current => {
    if (!current || current.online !== true || current.matching === true) {
      return;
    }
    return {...current, matching: true, matchingOwnerUid: uid,
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
