// lib/auth/social_auth_service.dart
//
// Social auth helpers that preserve the current anonymous Firebase uid whenever
// possible, so trial data stored under that uid remains available after login.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import '/flutter_flow/flutter_flow_util.dart';

class SocialAuthService {
  static final _auth = FirebaseAuth.instance;
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<UserCredential> signInWithKakao({
    bool skipAnonymous = false,
  }) async {
    try {
      debugPrint(
          '[KakaoAuth] signInWithKakao start, currentUser=${_auth.currentUser?.uid}, isAnonymous=${_auth.currentUser?.isAnonymous}, skipAnonymous=$skipAnonymous');

      if (_auth.currentUser == null && !skipAnonymous) {
        debugPrint('[KakaoAuth] signInAnonymously start');
        await _auth.signInAnonymously();
        debugPrint(
            '[KakaoAuth] signInAnonymously complete, uid=${_auth.currentUser?.uid}');
      }

      OAuthToken token;
      try {
        if (await isKakaoTalkInstalled()) {
          token = await UserApi.instance.loginWithKakaoTalk();
        } else {
          token = await UserApi.instance.loginWithKakaoAccount();
        }
        debugPrint(
            '[KakaoAuth] Kakao SDK login success, accessToken length=${token.accessToken.length}');
      } catch (e, stack) {
        debugPrint('[KakaoAuth] Kakao SDK login failed: $e');
        debugPrint('[KakaoAuth] Kakao SDK stack: $stack');
        rethrow;
      }

      final callable = _functions.httpsCallable('kakaoCustomAuth');
      debugPrint('[KakaoAuth] kakaoCustomAuth callable call start');
      final result = await callable.call<Map<String, dynamic>>({
        'kakaoAccessToken': token.accessToken,
      });
      debugPrint(
          '[KakaoAuth] kakaoCustomAuth response received, token exists=${result.data['token'] != null}');

      final customToken = result.data['token'] as String;
      debugPrint('[KakaoAuth] signInWithCustomToken call start');
      var credential = await _auth.signInWithCustomToken(customToken);
      credential = await _consumePendingProviderLink(
        'kakao',
        credential,
        kakaoAccessToken: token.accessToken,
      );
      debugPrint(
          '[KakaoAuth] signInWithCustomToken complete, final uid=${_auth.currentUser?.uid}');
      FFAppState().hasLinkedAccount = true;
      return credential;
    } catch (e, stack) {
      debugPrint('[KakaoAuth] exception: $e');
      debugPrint('[KakaoAuth] stack: $stack');
      rethrow;
    }
  }

  static Future<UserCredential> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    // Server resolves the canonical UID. Do not fall back to
    // signInWithCredential, because that can create a separate Firebase UID.
    final checkResult = await _callLinkOrCreate('google', idToken: idToken);
    final serverToken = checkResult['token'] as String;
    var signedIn = await _auth.signInWithCustomToken(serverToken);
    signedIn = await _consumePendingProviderLink(
      'google',
      signedIn,
      idToken: idToken,
    );
    FFAppState().hasLinkedAccount = true;
    return signedIn;
  }

  static Future<Map<String, dynamic>?> createProviderLinkTicket() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      return null;
    }

    final callable = _functions.httpsCallable('createProviderLinkTicket');
    final result = await callable.call<Map<String, dynamic>>({});
    final ticket = result.data['ticket'] as String?;
    final expiresAt = result.data['expiresAt'] as int?;
    if (ticket == null || expiresAt == null) {
      return null;
    }

    FFAppState().pendingProviderLinkTicket = ticket;
    FFAppState().pendingProviderLinkExpiresAt = expiresAt;
    return result.data;
  }

  static Future<UserCredential> _consumePendingProviderLink(
    String provider,
    UserCredential fallbackCredential, {
    String? idToken,
    String? kakaoAccessToken,
  }) async {
    final appState = FFAppState();
    final ticket = appState.pendingProviderLinkTicket;
    final expiresAt = appState.pendingProviderLinkExpiresAt;
    if (ticket.isEmpty || expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      appState.clearPendingProviderLinkTicket();
      return fallbackCredential;
    }

    try {
      final callable = _functions.httpsCallable('consumeProviderLinkTicket');
      final result = await callable.call<Map<String, dynamic>>({
        'ticket': ticket,
        'provider': provider,
        if (idToken != null) 'idToken': idToken,
        if (kakaoAccessToken != null) 'kakaoAccessToken': kakaoAccessToken,
      });
      appState.clearPendingProviderLinkTicket();
      final linkedToken = result.data['token'] as String?;
      if (linkedToken == null || linkedToken.isEmpty) {
        return fallbackCredential;
      }
      debugPrint('[AuthLink] provider=$provider linked to previous account');
      return _auth.signInWithCustomToken(linkedToken);
    } catch (e) {
      debugPrint('[AuthLink] pending provider link failed: $e');
      appState.clearPendingProviderLinkTicket();
      return fallbackCredential;
    }
  }

  static Future<UserCredential?> _consumePendingEmailLink(
    String email,
    String password,
  ) async {
    final appState = FFAppState();
    final ticket = appState.pendingProviderLinkTicket;
    final expiresAt = appState.pendingProviderLinkExpiresAt;
    if (ticket.isEmpty || expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      appState.clearPendingProviderLinkTicket();
      return null;
    }

    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }

    try {
      final callable = _functions.httpsCallable('consumeProviderLinkTicket');
      final result = await callable.call<Map<String, dynamic>>({
        'ticket': ticket,
        'provider': 'email',
        'email': email,
        'password': password,
      });
      appState.clearPendingProviderLinkTicket();
      final linkedToken = result.data['token'] as String?;
      if (linkedToken == null || linkedToken.isEmpty) {
        return null;
      }
      debugPrint('[AuthLink] email linked to previous account');
      return _auth.signInWithCustomToken(linkedToken);
    } catch (e) {
      debugPrint('[AuthLink] pending email link failed: $e');
      appState.clearPendingProviderLinkTicket();
      rethrow;
    }
  }
  static Future<Map<String, dynamic>> linkGoogleToCurrentAccount() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      throw Exception('A signed-in account is required.');
    }

    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final callable = _functions.httpsCallable('linkProviderToCurrentAccount');
    final result = await callable.call<Map<String, dynamic>>({
      'provider': 'google',
      'idToken': idToken,
    });
    return result.data;
  }

  static Future<Map<String, dynamic>> linkKakaoToCurrentAccount() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      throw Exception('A signed-in account is required.');
    }

    OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      token = await UserApi.instance.loginWithKakaoTalk();
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }

    final callable = _functions.httpsCallable('linkProviderToCurrentAccount');
    final result = await callable.call<Map<String, dynamic>>({
      'provider': 'kakao',
      'kakaoAccessToken': token.accessToken,
    });
    return result.data;
  }

  static Future<Map<String, dynamic>> _callLinkOrCreate(
    String provider, {
    String? idToken,
    String? email,
  }) async {
    final callable = _functions.httpsCallable('linkOrCreateAccount');
    final result = await callable.call<Map<String, dynamic>>({
      'provider': provider,
      if (idToken != null) 'idToken': idToken,
      if (email != null) 'email': email,
    });
    return result.data;
  }

  static Future<UserCredential> signInWithEmail(
    String email,
    String password, {
    bool isSignUp = false,
  }) async {
    final credential =
        EmailAuthProvider.credential(email: email, password: password);
    final currentUser = _auth.currentUser;

    if (isSignUp) {
      final linkedByTicket = await _consumePendingEmailLink(email, password);
      if (linkedByTicket != null) {
        FFAppState().hasLinkedAccount = true;
        return linkedByTicket;
      }

      if (currentUser != null && currentUser.isAnonymous) {
        try {
          final linked = await currentUser.linkWithCredential(credential);
          FFAppState().hasLinkedAccount = true;
          return linked;
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            final signedIn = await _auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
            FFAppState().hasLinkedAccount = true;
            return signedIn;
          }
          rethrow;
        }
      }

      final created = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      FFAppState().hasLinkedAccount = true;
      return created;
    }

    final signedIn = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    FFAppState().hasLinkedAccount = true;
    return signedIn;
  }
}
