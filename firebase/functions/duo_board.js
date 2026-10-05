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

exports.publishDuoBoardPost = functions.https.onCall(async (data, context) => {
  const uid = uidOf(context);
  if (context.auth.token.firebase?.sign_in_provider === 'anonymous') {
    throw new functions.https.HttpsError('permission-denied', '게시글은 회원만 작성할 수 있습니다.');
  }
  const roomId = String(data.roomId || '').trim();
  const historyPath = String(data.historyPath || '').trim();
  const mode = 'interpreter';
  const availability = 'request';
  const topic = text(data.topic, 80);
  const topicLanguage = String(data.topicLanguage || '').trim();
  const directLanguage = '';
  if (!roomId || !historyPath.startsWith(`users/${uid}/chat_history/`) ||
      data.mode === 'direct' || !topicLanguage) {
    throw new functions.https.HttpsError('invalid-argument', '초대 방 정보가 올바르지 않습니다.');
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
    tx.set(postRef, {
      ownerUid: uid, topic, topicLanguage, mode, directLanguage, availability,
      // A successful callable invocation proves that the host app is in the
      // foreground. RTDB presence keeps this synchronized after publishing,
      // but it must not block creation of the post.
      active: true, state: 'active', discoverable: true, ownerPaused: false,
      inactiveSince: admin.firestore.FieldValue.delete(),
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
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 1000);
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
      attemptId,
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
  if (!await isHostForeground(ownerUid)) {
    await requestRef.set({status: 'expired', expiredAt:
      admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    await requesterRef.set({status: 'expired', updatedAt:
      admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    throw new functions.https.HttpsError('failed-precondition', '초대자가 현재 앱에 없습니다.');
  }
  // Host requests are deliberately in-app only. The foreground Firestore
  // listener shows the dialog; no FCM notification is sent to a background app.
  return {requestId, attemptId,
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
      tx.update(requestRef, {status: 'matched', matchedAt:
        admin.firestore.FieldValue.serverTimestamp()});
      tx.set(db().collection('duo_board_requesters').doc(request.get('requesterUid')),
          {status: 'matched', updatedAt: admin.firestore.FieldValue.serverTimestamp()},
          {merge: true});
      tx.update(roomRef, {partnerUid: request.get('requesterUid'),
        boardReservedAt: admin.firestore.FieldValue.serverTimestamp()});
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
      const batch = db().batch();
      posts.docs.filter(doc => doc.get('active') === true).forEach(doc => {
        if (doc.get('state') !== 'reserved') {
          const visible = doc.get('ownerPaused') === true
            ? false
            : discoverable;
          batch.update(doc.ref, {
            discoverable: visible,
            inactiveSince: visible
              ? admin.firestore.FieldValue.delete()
              : (doc.get('inactiveSince') ||
                admin.firestore.FieldValue.serverTimestamp()),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      });
      await batch.commit();
      return null;
    });

const INACTIVE_POST_TTL_MS = 48 * 60 * 60 * 1000;

// Keep temporarily unavailable invitations visible to intro guests, but retire
// them after 48 continuous hours without becoming discoverable again.
exports.expireInactiveDuoBoardPosts = functions.pubsub
    .schedule('every 60 minutes')
    .onRun(async () => {
      const cutoff = admin.firestore.Timestamp.fromMillis(
          Date.now() - INACTIVE_POST_TTL_MS);
      const snapshot = await db().collection('duo_board_posts')
          .where('active', '==', true)
          .get();
      let expired = 0;
      let initialized = 0;
      for (const candidate of snapshot.docs) {
        const result = await db().runTransaction(async tx => {
          const current = await tx.get(candidate.ref);
          if (!current.exists) return null;
          const inactiveSince = current.get('inactiveSince');
          if (current.get('active') !== true ||
              current.get('discoverable') === true ||
              current.get('state') === 'reserved') {
            return null;
          }
          if (!inactiveSince) {
            tx.update(candidate.ref, {
              inactiveSince: admin.firestore.FieldValue.serverTimestamp(),
            });
            return 'initialized';
          }
          if (inactiveSince.toMillis() > cutoff.toMillis()) return null;
          tx.update(candidate.ref, {
            active: false,
            discoverable: false,
            state: 'expired',
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          tx.delete(db().collection('duo_board_runtime').doc(candidate.id));
          return 'expired';
        });
        if (result === 'expired') expired += 1;
        if (result === 'initialized') initialized += 1;
      }
      console.log(
          `Expired ${expired} Duo board posts after 48 inactive hours; ` +
          `initialized ${initialized} legacy inactive posts.`);
      return null;
    });

// The session document is the authoritative proof that the requester really
// entered. Keep the post for audit, but remove it from the board permanently.
exports.completeDuoBoardPostOnJoin = functions.firestore
    .document('duo_sessions/{roomId}')
    .onUpdate(async (change, context) => {
      if (change.before.get('isPartnerJoined') === true ||
          change.after.get('isPartnerJoined') !== true) return null;
      const postRef = db().collection('duo_board_posts').doc(context.params.roomId);
      const post = await postRef.get();
      if (!post.exists || post.get('active') !== true) return null;
      await postRef.update({active: false, discoverable: false, state: 'matched',
        matchedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      return null;
    });

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
