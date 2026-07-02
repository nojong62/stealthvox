// lib/auth/social_auth_service.dart
//
// Social auth helpers that preserve the current anonymous Firebase uid whenever
// possible, so trial data stored under that uid remains available after login.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import '/flutter_flow/flutter_flow_util.dart';

class SocialAuthService {
  static final _auth = FirebaseAuth.instance;
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<UserCredential> signInWithKakao() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }

    OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      token = await UserApi.instance.loginWithKakaoTalk();
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }

    final callable = _functions.httpsCallable('kakaoCustomAuth');
    final result = await callable.call<Map<String, dynamic>>({
      'kakaoAccessToken': token.accessToken,
    });

    final customToken = result.data['token'] as String;
    final credential = await _auth.signInWithCustomToken(customToken);
    FFAppState().hasLinkedAccount = true;
    return credential;
  }

  static Future<UserCredential> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final currentUser = _auth.currentUser;
    if (currentUser != null && currentUser.isAnonymous) {
      try {
        final linked = await currentUser.linkWithCredential(credential);
        FFAppState().hasLinkedAccount = true;
        return linked;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use') {
          final signedIn = await _auth.signInWithCredential(credential);
          FFAppState().hasLinkedAccount = true;
          return signedIn;
        }
        rethrow;
      }
    }

    final signedIn = await _auth.signInWithCredential(credential);
    FFAppState().hasLinkedAccount = true;
    return signedIn;
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
