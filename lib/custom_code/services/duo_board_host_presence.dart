import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'duo_board_service.dart';

/// Publishes presence only while a member with an active board post is visible.
class DuoBoardHostPresence with WidgetsBindingObserver {
  DuoBoardHostPresence._();
  static final DuoBoardHostPresence instance = DuoBoardHostPresence._();

  StreamSubscription<User?>? _authSubscription;
  DatabaseReference? _connection;
  Timer? _heartbeat;
  String? _uid;
  bool _ownsActivePost = false;
  String? _checkingUid;
  String? _pausedForIncomingInvitePostId;
  bool _incomingInviteTakesPriority = false;
  int _incomingInviteGeneration = 0;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    await _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(_handleUser(user));
    });
    await _handleUser(FirebaseAuth.instance.currentUser);
  }

  Future<void> _handleUser(User? user) async {
    if (user == null || user.isAnonymous) {
      await stop();
      _uid = null;
      _ownsActivePost = false;
      _checkingUid = null;
      _incomingInviteTakesPriority = false;
      return;
    }
    if (_uid == user.uid && _ownsActivePost) return;
    if (_checkingUid == user.uid) return;
    _checkingUid = user.uid;
    if (_uid != null && _uid != user.uid) {
      await stop();
    }
    _uid = user.uid;
    QueryDocumentSnapshot<Map<String, dynamic>>? post;
    try {
      post = await DuoBoardService.findOwnActivePost()
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('[DuoBoard] active post lookup failed: $error');
      _checkingUid = null;
      return;
    }
    _ownsActivePost = post != null;
    if (!_ownsActivePost || _incomingInviteTakesPriority) {
      _checkingUid = null;
      return;
    }

    // 사용자가 직접 끈 글은 같은 로그인 중 계속 꺼져 있어야 한다.
    if (post!.data()['ownerPaused'] == true) {
      _ownsActivePost = false;
      _checkingUid = null;
      return;
    }

    // 그 외 본인 통역 게시글은 로그인 직후 기본값으로 바로 다시 활성화한다.
    try {
      final resumed = await DuoBoardService.resumePost(post.id)
          .timeout(const Duration(seconds: 8));
      if (!resumed) {
        await postEnded();
      } else {
        await ensureOnline().timeout(const Duration(seconds: 8));
      }
    } catch (error) {
      debugPrint('[DuoBoard] automatic post restore failed: $error');
    }
    _checkingUid = null;
  }

  /// 다른 사람의 Duo 방으로 들어갈 때 내 게시글이 다시 노출되지 않게 한다.
  /// 글은 삭제하지 않고 비공개로 두므로 받은 통화가 끝난 뒤 다시 켤 수 있다.
  Future<void> prepareForIncomingInvite(String incomingRoomId) async {
    final roomId = incomingRoomId.trim();
    if (roomId.isEmpty) return;

    // 이 플래그는 조회보다 먼저 세운다. 앱 시작 복원 조회와 받은 초대 조회가
    // 동시에 끝나더라도 복원 팝업이 뒤늦게 초대 화면 위에 뜨면 안 된다.
    final generation = ++_incomingInviteGeneration;
    _incomingInviteTakesPriority = true;

    try {
      final post = await DuoBoardService.findOwnActivePost()
          .timeout(const Duration(seconds: 5));
      if (post == null ||
          post.id == roomId ||
          generation != _incomingInviteGeneration ||
          !_incomingInviteTakesPriority) {
        return;
      }

      _pausedForIncomingInvitePostId = post.id;

      await DuoBoardService.setPostVisibility(post.id, enabled: false)
          .timeout(const Duration(seconds: 5));
      // A call can finish while the visibility write is in flight. Do not let
      // that stale pause win after resume; best-effortly undo only our write.
      if (generation != _incomingInviteGeneration ||
          !_incomingInviteTakesPriority) {
        // A newer incoming invite may already be pausing the same post. Only
        // undo our write when the current state says the pause was cancelled.
        if (!_incomingInviteTakesPriority) {
          try {
            await DuoBoardService.setPostVisibility(post.id, enabled: true)
                .timeout(const Duration(seconds: 5));
          } catch (restoreError) {
            debugPrint('[DuoBoard] stale invite pause restore failed: ' +
                restoreError.toString());
          }
        }
        return;
      }
      _ownsActivePost = false;
      await stop().timeout(const Duration(seconds: 5));
    } catch (error) {
      // 내 게시글 숨김은 best-effort다. 실패했다고 받은 초대의 room 상태를
      // 설정하지 않으면 첫 클릭은 앱만 열고 두 번째 클릭에야 입장하게 된다.
      debugPrint('[DuoBoard] incoming invite pause failed: $error');
    }
  }

  /// Restores the member's own invitation after a different board call ends.
  ///
  /// Joining someone else's invitation temporarily hides this post so the
  /// member cannot receive two requests at once. The old flow stopped its
  /// presence but never resumed the paused post when the call ended.
  Future<void> resumePausedPostAfterIncomingInvite() async {
    ++_incomingInviteGeneration;
    final postId = _pausedForIncomingInvitePostId;
    _pausedForIncomingInvitePostId = null;
    _incomingInviteTakesPriority = false;
    if (postId == null || postId.isEmpty) return;
    try {
      final resumed = await DuoBoardService.resumePost(postId)
          .timeout(const Duration(seconds: 8));
      if (!resumed) {
        debugPrint('[DuoBoard] paused post was not resumable: $postId');
        return;
      }
      await ensureOnline().timeout(const Duration(seconds: 8));
      _ownsActivePost = true;
      debugPrint('[DuoBoard] paused post resumed after incoming call: $postId');
    } catch (error) {
      debugPrint('[DuoBoard] paused post resume failed: $error');
    }
  }

  Future<void> ensureOnline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    _uid = user.uid;
    _ownsActivePost = true;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (_connection == null) {
      final id = '${DateTime.now().millisecondsSinceEpoch}';
      _connection =
          DuoBoardService.database.ref('duo_board_hosts/${user.uid}/$id');
      final connection = _connection!;
      unawaited(connection
          .onDisconnect()
          .remove()
          .timeout(const Duration(seconds: 5))
          .catchError((Object error) {
        debugPrint('[DuoBoard] host onDisconnect unavailable: $error');
      }));
    }
    // The visible state should react to the heartbeat immediately. Registering
    // the disconnect cleanup above remains best-effort and must not hold the UI.
    await _writeHeartbeat().timeout(const Duration(seconds: 3));
    _heartbeat ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_writeHeartbeat()),
    );
  }

  Future<void> _writeHeartbeat() async {
    final ref = _connection;
    if (ref == null) return;
    await ref.set({
      'foreground': true,
      'lastSeen': ServerValue.timestamp,
    });
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final ref = _connection;
    _connection = null;
    if (ref != null) {
      await ref.remove();
      await ref.onDisconnect().cancel();
    }
  }

  /// Hides an owned board post while Firebase authentication is still valid.
  ///
  /// Authentication listeners run after sign-out, which is too late to make
  /// authenticated Realtime Database and callable-function writes reliably.
  Future<void> prepareForSignOut() async {
    final hidePost = () async {
      final post = await DuoBoardService.findOwnActivePost();
      if (post != null) {
        await DuoBoardService.setPostVisibility(post.id, enabled: false);
      }
    }();
    final clearPresence = stop();

    try {
      await Future.wait<void>([hidePost, clearPresence])
          .timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint(
          '[DuoBoard] board cleanup before sign-out continued in background: $error');
    }
  }

  Future<void> postEnded() async {
    _ownsActivePost = false;
    await stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ownsActivePost) {
      unawaited(ensureOnline());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(stop());
    }
  }
}
