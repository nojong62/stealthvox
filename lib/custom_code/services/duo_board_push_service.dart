import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'duo_board_service.dart';

typedef DuoBoardRequestOpened = Future<void> Function(DuoBoardHostMatch match);

class DuoBoardPushService {
  DuoBoardPushService._();

  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<String>? _tokenSubscription;
  static DuoBoardRequestOpened? _onOpened;

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
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
      final current = context();
      // The callback returns the navigator's current, mounted context.
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.maybeOf(current)?.showSnackBar(SnackBar(
        content: Text(message.notification?.body ?? 'Duo 대화 요청이 도착했습니다.'),
        action: SnackBarAction(
          label: '열기',
          onPressed: () => _open(requestId, current),
        ),
      ));
    });

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
    await _open(requestId, context);
  }

  static Future<void> _open(String requestId, BuildContext context) async {
    try {
      final match = await DuoBoardService.openRequest(requestId);
      await _onOpened?.call(match);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('요청자가 더 이상 기다리고 있지 않습니다.')),
      );
    }
  }
}
