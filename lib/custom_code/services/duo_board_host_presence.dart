import 'dart:async';

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
    final post = await DuoBoardService.findOwnActivePost();
    _ownsActivePost = post != null;
    if (!_ownsActivePost) {
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
    final context = _context?.call();
    if (context == null || !context.mounted) {
      _promptedThisLaunch = false;
      _checkingUid = null;
      return;
    }
    final copy = DuoInviteCopy.forLanguage(FFAppState().chatLang);
    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(copy['restorePostTitle']),
        content: Text(copy['restorePostBody']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(copy['endPost']),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(copy['continuePost']),
          ),
        ],
      ),
    );
    if (keep == true) {
      await ensureOnline();
      final resumed = await DuoBoardService.resumePost(post!.id);
      if (!resumed) await postEnded();
    } else if (post != null) {
      await DuoBoardService.withdrawPost(post.id);
      _ownsActivePost = false;
    }
    _checkingUid = null;
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
          FirebaseDatabase.instance.ref('duo_board_hosts/${user.uid}/$id');
      await _connection!.onDisconnect().remove();
    }
    await _writeHeartbeat();
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
