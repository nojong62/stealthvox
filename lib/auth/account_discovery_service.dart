import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

class AccountDiscoveryCancelledException implements Exception {
  const AccountDiscoveryCancelledException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AccountDiscoveryResult {
  const AccountDiscoveryResult({
    required this.provider,
    required this.status,
    required this.maskedIdentifier,
    required this.remainingTime,
    required this.historyCount,
    required this.lastUsedAt,
    required this.hasBirthYear,
    required this.parentConsentPending,
    required this.hasMemberData,
    required this.ticket,
    required this.expiresAt,
    required this.providerToken,
  });

  final String provider;
  final String status;
  final String maskedIdentifier;
  final int remainingTime;
  final int historyCount;
  final DateTime? lastUsedAt;
  final bool hasBirthYear;
  final bool parentConsentPending;
  final bool hasMemberData;
  final String ticket;
  final int expiresAt;
  final String providerToken;

  bool get found => status == 'found' && ticket.isNotEmpty;

  String get providerLabel => switch (provider) {
        'google' => 'Google 계정',
        'kakao' => '카카오 계정',
        'email' => '이메일 계정',
        _ => '계정',
      };

  static AccountDiscoveryResult notFound({
    required String provider,
    required String providerToken,
  }) =>
      AccountDiscoveryResult(
        provider: provider,
        status: 'not_found',
        maskedIdentifier: '',
        remainingTime: 0,
        historyCount: 0,
        lastUsedAt: null,
        hasBirthYear: false,
        parentConsentPending: false,
        hasMemberData: false,
        ticket: '',
        expiresAt: 0,
        providerToken: providerToken,
      );

  static AccountDiscoveryResult fromCallableData(
    Map<String, dynamic> data, {
    required String provider,
    required String providerToken,
  }) {
    final status = data['status'] as String? ?? 'not_found';
    if (status != 'found') {
      return AccountDiscoveryResult.notFound(
        provider: provider,
        providerToken: providerToken,
      );
    }

    final account = Map<String, dynamic>.from(data['account'] as Map? ?? {});
    final lastUsedMillis = (account['lastUsedAt'] as num?)?.toInt();
    return AccountDiscoveryResult(
      provider: account['provider'] as String? ?? provider,
      status: status,
      maskedIdentifier: account['maskedIdentifier'] as String? ?? '',
      remainingTime: (account['remainingTime'] as num?)?.toInt() ?? 0,
      historyCount: (account['historyCount'] as num?)?.toInt() ?? 0,
      lastUsedAt: lastUsedMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastUsedMillis),
      hasBirthYear: account['hasBirthYear'] == true,
      parentConsentPending: account['parentConsentPending'] == true,
      hasMemberData: account['hasMemberData'] == true,
      ticket: account['ticket'] as String? ?? '',
      expiresAt: (account['expiresAt'] as num?)?.toInt() ?? 0,
      providerToken: providerToken,
    );
  }
}

class AccountDiscoveryService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<AccountDiscoveryResult> lookupGoogle() async {
    final googleSignIn = GoogleSignIn();
    await googleSignIn.signOut().catchError((_) => null);
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw const AccountDiscoveryCancelledException(
          'Google account check cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google ID token is missing.');
    }

    final callable = _functions.httpsCallable('lookupAccountForRecovery');
    final result = await callable.call<Map<String, dynamic>>({
      'provider': 'google',
      'idToken': idToken,
    });

    return AccountDiscoveryResult.fromCallableData(
      result.data,
      provider: 'google',
      providerToken: idToken,
    );
  }

  static Future<AccountDiscoveryResult> lookupKakao() async {
    OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      token = await UserApi.instance.loginWithKakaoTalk();
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }

    final callable = _functions.httpsCallable('lookupAccountForRecovery');
    final result = await callable.call<Map<String, dynamic>>({
      'provider': 'kakao',
      'kakaoAccessToken': token.accessToken,
    });

    return AccountDiscoveryResult.fromCallableData(
      result.data,
      provider: 'kakao',
      providerToken: token.accessToken,
    );
  }

  static Future<AccountDiscoveryResult> lookupEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw Exception('Email login did not return a Firebase user.');
    }

    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();
    if (!userDoc.exists) {
      return AccountDiscoveryResult.notFound(
        provider: 'email',
        providerToken: user.uid,
      );
    }

    final userData = userDoc.data() ?? {};
    final historyBase = userRef.collection('chat_history');
    int historyCount = 0;
    DateTime? lastUsedAt;

    try {
      final countSnap = await historyBase.count().get();
      historyCount = countSnap.count ?? 0;
    } catch (e) {
      debugPrint('[AccountDiscovery] email history count failed: $e');
    }

    try {
      final latestSnap = await historyBase
          .orderBy('created_at', descending: true)
          .limit(1)
          .get();
      if (latestSnap.docs.isNotEmpty) {
        final createdAt = latestSnap.docs.first.data()['created_at'];
        if (createdAt is Timestamp) {
          lastUsedAt = createdAt.toDate();
        }
      }
    } catch (e) {
      debugPrint('[AccountDiscovery] email latest history failed: $e');
    }

    final remainingTime = (userData['remainingTime'] as num?)?.toInt() ?? 0;
    final hasBirthYear = userData['birthYear'] != null;
    final parentConsentPending = userData['parentConsentPending'] == true;
    final storedEmail = (userData['email'] as String?) ?? user.email ?? email;

    return AccountDiscoveryResult(
      provider: 'email',
      status: 'found',
      maskedIdentifier: _maskEmail(storedEmail),
      remainingTime: remainingTime,
      historyCount: historyCount,
      lastUsedAt: lastUsedAt,
      hasBirthYear: hasBirthYear,
      parentConsentPending: parentConsentPending,
      hasMemberData: remainingTime > 0 ||
          historyCount > 0 ||
          hasBirthYear ||
          parentConsentPending,
      ticket: 'email-authenticated:${user.uid}',
      expiresAt: DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      providerToken: user.uid,
    );
  }

  static Future<UserCredential> signInWithDiscoveredAccount(
    AccountDiscoveryResult account,
  ) async {
    if (!account.found) {
      throw Exception('A discovered account is required.');
    }

    final payload = <String, dynamic>{
      'provider': account.provider,
      'ticket': account.ticket,
      if (account.provider == 'google') 'idToken': account.providerToken,
      if (account.provider == 'kakao')
        'kakaoAccessToken': account.providerToken,
    };

    final callable = _functions.httpsCallable('completeAccountRecoveryLogin');
    final result = await callable.call<Map<String, dynamic>>(payload);
    final token = result.data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Account login token is missing.');
    }

    debugPrint(
        '[AccountDiscovery] final Firebase login provider=${account.provider}');
    return _auth.signInWithCustomToken(token);
  }

  static String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return '';
    final name = parts[0];
    final domain = parts[1];
    final visible = name.substring(0, name.length < 3 ? name.length : 3);
    return '$visible***@$domain';
  }
}
