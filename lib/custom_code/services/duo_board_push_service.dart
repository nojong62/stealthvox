import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '/app_state.dart';
import 'duo_board_host_presence.dart';
import 'duo_board_service.dart';
import 'duo_invite_localization.dart';

typedef DuoBoardRequestOpened = Future<void> Function(DuoBoardHostMatch match);

class DuoBoardPushService {
  DuoBoardPushService._();

  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<User?>? _authSubscription;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _requestSubscription;
  static DuoBoardRequestOpened? _onOpened;
  static final Set<String> _handledRequests = <String>{};

  static Future<bool> get isAuthorized async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  static Future<bool> enableForCurrentMember() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return false;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied ||
        settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      return false;
    }
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return false;
    await _saveToken(user.uid, token);
    await _tokenSubscription?.cancel();
    var previousToken = token;
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (next) async {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('fcm_tokens')
            .doc(_tokenDocumentId(previousToken))
            .delete();
        await _saveToken(user.uid, next);
        previousToken = next;
      },
    );
    return true;
  }

  static Future<void> _saveToken(String uid, String token) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcm_tokens')
        .doc(_tokenDocumentId(token))
        .set({
      'token': token,
      'platform': defaultTargetPlatform.name,
      'chatLanguage': FFAppState().chatLang,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Keeps notification language in sync when Lobby Chat Lang changes.
  static Future<void> refreshChatLanguageForCurrentMember() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await _saveToken(user.uid, token);
  }

  static String _tokenDocumentId(String token) =>
      base64Url.encode(utf8.encode(token)).replaceAll('=', '');

  static Future<void> removeTokenForCurrentMember() async {
    final user = FirebaseAuth.instance.currentUser;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    if (user == null || user.isAnonymous) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('fcm_tokens')
            .doc(_tokenDocumentId(token))
            .delete();
      } finally {
        await messaging.deleteToken();
      }
    } catch (error) {
      debugPrint('[DuoBoard] FCM token cleanup skipped: ${error.runtimeType}');
    }
  }

  static Future<void> signOut() async {
    await DuoBoardHostPresence.instance.prepareForSignOut();
    await removeTokenForCurrentMember();
    await FirebaseAuth.instance.signOut();
  }

  static Future<void> initialize({
    required BuildContext Function() context,
    required DuoBoardRequestOpened onOpened,
  }) async {
    _onOpened = onOpened;
    await _openedSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _handle(message, context()),
    );
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      final requestId = message.data['requestId']?.toString();
      if (requestId == null || requestId.isEmpty) return;
      unawaited(_prompt(requestId, context()));
    });
    await _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(_watchRequests(user, context));
    });
    await _watchRequests(FirebaseAuth.instance.currentUser, context);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _handle(initial, context());
    }
  }

  static Future<void> _handle(
      RemoteMessage message, BuildContext context) async {
    if (message.data['type'] != 'duo_board_request') return;
    final requestId = message.data['requestId']?.toString();
    if (requestId == null || requestId.isEmpty) return;
    await _prompt(requestId, context);
  }

  static Future<void> _watchRequests(
      User? user, BuildContext Function() context) async {
    await _requestSubscription?.cancel();
    _requestSubscription = null;
    if (user == null || user.isAnonymous) return;
    _requestSubscription = FirebaseFirestore.instance
        .collection('duo_board_requests')
        .where('ownerUid', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final data = change.doc.data();
        final expires = data?['expiresAt'];
        if (data?['status'] == 'waiting' &&
            expires is Timestamp &&
            expires.toDate().isAfter(DateTime.now())) {
          unawaited(_prompt(change.doc.id, context()));
        }
      }
    });
  }

  static Future<void> _prompt(String requestId, BuildContext context) async {
    if (_handledRequests.contains(requestId) || !context.mounted) return;
    _handledRequests.add(requestId);
    final copy = DuoInviteCopy.forSystemLocale();
    Timer? timeout;
    try {
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          timeout = Timer(const Duration(seconds: 25), () {
            if (dialogContext.mounted) Navigator.pop(dialogContext, 'timeout');
          });
          return AlertDialog(
            title: Text(copy['requestArrived']),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'busy'),
                child: Text(copy['busyNow']),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, 'accept'),
                child: Text(copy['acceptDuo']),
              ),
            ],
          );
        },
      );
      if (choice == 'accept') {
        if (!context.mounted) return;
        await _open(requestId, context);
      } else {
        await DuoBoardService.declineRequest(requestId,
            reason: choice == 'busy' ? 'busy' : 'timeout');
      }
    } finally {
      timeout?.cancel();
      // FCM and Firestore can deliver the same live request. Once it has been
      // handled, allow a later request for the same board post to be shown.
      _handledRequests.remove(requestId);
    }
  }

  static Future<void> _open(String requestId, BuildContext context) async {
    try {
      final match = await DuoBoardService.openRequest(requestId);
      await _onOpened?.call(match);
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
          '[DuoBoard] open request failed: ${error.code} ${error.message}');
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content:
                Text(DuoInviteCopy.forSystemLocale()['requestGone'])),
      );
    } catch (error) {
      debugPrint('[DuoBoard] open request failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content:
                Text(DuoInviteCopy.forSystemLocale()['requestGone'])),
      );
    }
  }
}
