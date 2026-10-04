import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '/app_state.dart';
import 'duo_board_service.dart';
import 'duo_invite_localization.dart';

/// Publishes presence only while a member with an active board post is visible.
class DuoBoardHostPresence with WidgetsBindingObserver {
  DuoBoardHostPresence._();
  static final DuoBoardHostPresence instance = DuoBoardHostPresence._();

  BuildContext Function()? _context;
  StreamSubscription<User?>? _authSubscription;
  DatabaseReference? _connection;
  Timer? _heartbeat;
  String? _uid;
  bool _ownsActivePost = false;
  bool _promptedThisLaunch = false;
  String? _checkingUid;
  BuildContext? _restoreDialogContext;
  String? _pausedForIncomingInvitePostId;
  bool _incomingInviteTakesPriority = false;

  Future<void> initialize(BuildContext Function() context) async {
    _context = context;
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
      _promptedThisLaunch = false;
      _checkingUid = null;
      _incomingInviteTakesPriority = false;
      return;
    }
    if (_uid == user.uid && _promptedThisLaunch) return;
    if (_checkingUid == user.uid) return;
    _checkingUid = user.uid;
    if (_uid != null && _uid != user.uid) {
      await stop();
      _promptedThisLaunch = false;
    }
    _uid = user.uid;
    QueryDocumentSnapshot<Map<String, dynamic>>? post;
    try {
      post = await DuoBoardService.findOwnActivePost()
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      // 게시글 복원 확인은 앱 진입을 막는 절차가 아니다. 로그아웃 직후처럼
      // 인증이 바뀌는 순간 조회가 실패해도 다음 auth/lifecycle 신호에서 다시
      // 확인할 수 있으므로 여기서는 조용히 빠진다.
      debugPrint('[DuoBoard] active post lookup failed: $error');
      _checkingUid = null;
      return;
    }
    _ownsActivePost = post != null;
    if (!_ownsActivePost) {
      _checkingUid = null;
      return;
    }
    // 받은 초대를 처리하기 시작했다면 내 게시글 복원 질문은 띄우지 않는다.
    // 초대 입장이 끝난 뒤 필요하면 게시판에서 직접 다시 활성화할 수 있다.
    if (_incomingInviteTakesPriority) {
      _checkingUid = null;
      return;
    }
    if (_promptedThisLaunch) {
      await ensureOnline();
      _checkingUid = null;
      return;
    }
    _promptedThisLaunch = true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_incomingInviteTakesPriority ||
        _pausedForIncomingInvitePostId == post?.id) {
      _checkingUid = null;
      return;
    }
    final context = _context?.call();
    if (context == null || !context.mounted) {
      _promptedThisLaunch = false;
      _checkingUid = null;
      return;
    }
    final copy = DuoInviteCopy.forLanguage(FFAppState().chatLang);
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _restoreDialogContext = dialogContext;
        return AlertDialog(
          title: Text(copy['restorePostTitle']),
          content: Text(copy['restorePostBody']),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'end'),
              child: Text(copy['endPost']),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'continue'),
              child: Text(copy['continuePost']),
            ),
          ],
        );
      },
    );
    _restoreDialogContext = null;
    if (choice == 'incoming_invite') {
      _checkingUid = null;
      return;
    }
    if (choice == 'continue') {
      final resumed = await DuoBoardService.resumePost(post!.id);
      if (!resumed) {
        await postEnded();
      } else {
        // Reactivate the Firestore post first. Presence synchronization is
        // best-effort and must not leave the post permanently paused.
        try {
          await ensureOnline().timeout(const Duration(seconds: 8));
        } catch (error) {
          debugPrint('[DuoBoard] presence restore failed: $error');
        }
      }
    } else if (post != null) {
      await DuoBoardService.withdrawPost(post.id);
      _ownsActivePost = false;
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
    _incomingInviteTakesPriority = true;

    // 받은 초대가 최우선이다. 게시글 조회가 끝나기를 기다렸다가 닫으면 앱이
    // 먼저 띄운 "기존 초대를 유지할까요?" 팝업이 딥링크 위를 가릴 수 있다.
    final dialogContext = _restoreDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.pop(dialogContext, 'incoming_invite');
    }

    try {
      final post = await DuoBoardService.findOwnActivePost()
          .timeout(const Duration(seconds: 5));
      if (post == null || post.id == roomId) return;

      _pausedForIncomingInvitePostId = post.id;
      // 위 첫 dismiss와 조회 사이에 복원 팝업이 새로 뜬 경합도 닫는다.
      final lateDialogContext = _restoreDialogContext;
      if (lateDialogContext != null && lateDialogContext.mounted) {
        Navigator.pop(lateDialogContext, 'incoming_invite');
      }
      await DuoBoardService.setPostVisibility(post.id, enabled: false)
          .timeout(const Duration(seconds: 5));
      _ownsActivePost = false;
      await stop().timeout(const Duration(seconds: 5));
    } catch (error) {
      // 내 게시글 숨김은 best-effort다. 실패했다고 받은 초대의 room 상태를
      // 설정하지 않으면 첫 클릭은 앱만 열고 두 번째 클릭에야 입장하게 된다.
      debugPrint('[DuoBoard] incoming invite pause failed: $error');
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
      try {
        await _connection!
            .onDisconnect()
            .remove()
            .timeout(const Duration(seconds: 5));
      } catch (error) {
        debugPrint('[DuoBoard] host onDisconnect unavailable: $error');
      }
    }
    await _writeHeartbeat().timeout(const Duration(seconds: 8));
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
    try {
      final post = await DuoBoardService.findOwnActivePost();
      if (post != null) {
        await DuoBoardService.setPostVisibility(post.id, enabled: false);
      }
    } catch (error) {
      debugPrint(
          '[DuoBoard] post visibility cleanup before sign-out failed: $error');
    }

    try {
      await stop();
    } catch (error) {
      // Keep onDisconnect armed when the explicit remove fails. It can still
      // clean up the presence record when the RTDB connection drops.
      debugPrint('[DuoBoard] presence cleanup before sign-out failed: $error');
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
