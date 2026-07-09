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
      final credential = await _auth.signInWithCustomToken(customToken);
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
    final signedIn = await _auth.signInWithCustomToken(serverToken);
    FFAppState().hasLinkedAccount = true;
    return signedIn;
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

    if (isSignUp && currentUser != null && currentUser.isAnonymous) {
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

    if (isSignUp) {
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
