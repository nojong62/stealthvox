import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'duo_board_service.dart';
import 'duo_invite_localization.dart';

/// Publishes presence only while a member with an active board post is visible.
class DuoBoardHostPresence with WidgetsBindingObserver {
  DuoBoardHostPresence._();
  static final DuoBoardHostPresence instance = DuoBoardHostPresence._();

  BuildContext Function()? _context;
  BuildContext? _restoreDialogContext;
  String? _restoreChoice;
  StreamSubscription<User?>? _authSubscription;
  DatabaseReference? _connection;
  Timer? _heartbeat;
  String? _uid;
  bool _ownsActivePost = false;
  bool _restoredThisSession = false;
  Timer? _restoreRetry;
  int _authGeneration = 0;
  String? _checkingUid;

  String? _pausedForIncomingInvitePostId;
  bool _incomingInviteTakesPriority = false;
  int _incomingInviteGeneration = 0;

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
    if (user == null || user.isAnonymous || _uid != user.uid) {
      ++_authGeneration;
      _restoreRetry?.cancel();
      _restoreRetry = null;
      _uid = user == null || user.isAnonymous ? null : user.uid;
      _ownsActivePost = false;
      _restoredThisSession = false;
      _restoreChoice = null;
      _checkingUid = null;
      _incomingInviteTakesPriority = false;
      _pausedForIncomingInvitePostId = null;
      try {
        await stop().timeout(const Duration(seconds: 3));
      } catch (error) {
        debugPrint('[DuoBoard] old presence cleanup failed: $error');
      }
    }
    debugPrint('[DuoBoard] restore lifecycle: ' +
        WidgetsBinding.instance.lifecycleState.toString());
    if (user == null ||
        user.isAnonymous ||
        _restoredThisSession ||
        _checkingUid == user.uid ||
        _incomingInviteTakesPriority ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final generation = _authGeneration;
    final inviteGeneration = _incomingInviteGeneration;
    bool stillCurrent() =>
        generation == _authGeneration &&
        FirebaseAuth.instance.currentUser?.uid == user.uid &&
        inviteGeneration == _incomingInviteGeneration &&
        !_incomingInviteTakesPriority;
    _checkingUid = user.uid;
    try {
      final posts = await DuoBoardService.findOwnActivePosts()
          .timeout(const Duration(seconds: 5));
      if (!stillCurrent()) return;
      _ownsActivePost = false;
      debugPrint(
          '[DuoBoard] own active posts found: ' + posts.length.toString());
      if (posts.isEmpty) {
        _restoredThisSession = true;
        return;
      }
      if (_restoreChoice == null) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!stillCurrent()) return;
        final context = _context?.call();
        if (context == null || !context.mounted) {
          throw StateError('Post restore dialog is not ready');
        }
        final copy = DuoInviteCopy.forSystemLocale();
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
        if (!stillCurrent() || (choice != 'continue' && choice != 'end')) {
          return;
        }
        _restoreChoice = choice;
      }
      if (_restoreChoice == 'end') {
        for (final post in posts) {
          if (!stillCurrent()) return;
          await DuoBoardService.withdrawPost(post.id);
        }
        if (stillCurrent()) await postEnded();
        return;
      }
      // Retry the accepted choice without asking again on a network failure.
      // Presence is best-effort; its failure must not block login recovery.
      try {
        await ensureOnline();
      } catch (error) {
        debugPrint('[DuoBoard] login presence pending: $error');
      }
      if (!stillCurrent() ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      String? resumedPostId;
      for (final post in posts) {
        if (!stillCurrent()) return;
        if (await DuoBoardService.resumePost(post.id)) {
          resumedPostId = post.id;
          break;
        }
      }
      if (!stillCurrent()) return;
      if (resumedPostId == null) {
        _restoredThisSession = true;
        await postEnded();
      } else {
        await _confirmPostVisible(resumedPostId, stillCurrent);
        if (!stillCurrent()) return;
        _restoredThisSession = true;
        _restoreRetry?.cancel();
        _restoreRetry = null;
        _ownsActivePost = true;
        debugPrint(
            '[DuoBoard] own post restored after login: ' + resumedPostId);
      }
    } catch (error) {
      debugPrint('[DuoBoard] login post restore failed: $error');
      if (stillCurrent() && !_restoredThisSession) {
        _restoreRetry?.cancel();
        _restoreRetry = Timer(const Duration(seconds: 5), () {
          _restoreRetry = null;
          unawaited(_handleUser(FirebaseAuth.instance.currentUser));
        });
      }
    } finally {
      if (generation == _authGeneration) _checkingUid = null;
    }
  }

  Future<void> _confirmPostVisible(
    String postId,
    bool Function() stillCurrent,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!stillCurrent()) return;
      await ensureOnline().timeout(const Duration(seconds: 4));
      await DuoBoardService.setPostVisibility(postId, enabled: true)
          .timeout(const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!stillCurrent()) return;
      if (await DuoBoardService.isPostDiscoverable(postId)
          .timeout(const Duration(seconds: 5))) {
        return;
      }
    }
    throw StateError('Duo post did not become discoverable');
  }

  /// 다른 사람의 Duo 방으로 들어갈 때 내 게시글이 다시 노출되지 않게 한다.
  /// 글은 삭제하지 않고 비공개로 두므로 받은 통화가 끝난 뒤 다시 켤 수 있다.
  Future<void> prepareForIncomingInvite(String incomingRoomId) async {
    final roomId = incomingRoomId.trim();
    if (roomId.isEmpty) return;

    // 이 플래그는 조회보다 먼저 세운다. 앱 시작 복원 조회와 받은 초대 조회가
    // 동시에 끝나더라도 내 글이 초대 입장 중 다시 활성화되면 안 된다.
    final generation = ++_incomingInviteGeneration;
    _incomingInviteTakesPriority = true;
    final dialogContext = _restoreDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.pop(dialogContext, 'incoming_invite');
    }

    _restoreRetry?.cancel();
    _restoreRetry = null;
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

    _heartbeat ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshHeartbeat()),
    );
    await _writeHeartbeat().timeout(const Duration(seconds: 3));
  }

  Future<void> _refreshHeartbeat() async {
    try {
      await _writeHeartbeat().timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('[DuoBoard] host heartbeat will retry: $error');
    }
  }

  Future<void> _refreshOnline() async {
    try {
      await ensureOnline();
    } catch (error) {
      debugPrint('[DuoBoard] foreground presence will retry: $error');
    }
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

  /// Explicit board actions win over pending automatic login retries.
  void postVisibilityChanged() {
    _restoredThisSession = true;
    ++_authGeneration;
    _checkingUid = null;
    _restoreRetry?.cancel();
    _restoreRetry = null;
  }

  Future<void> postEnded() async {
    _restoredThisSession = true;
    _restoreRetry?.cancel();
    _restoreRetry = null;
    _ownsActivePost = false;
    await stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleUser(FirebaseAuth.instance.currentUser));
      if (_ownsActivePost) unawaited(_refreshOnline());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(stop());
    }
  }
}
