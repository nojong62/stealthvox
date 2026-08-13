// lib/auth/social_auth_service.dart
//
// Social auth helpers that preserve the current anonymous Firebase uid whenever
// possible, so trial data stored under that uid remains available after login.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
// `User`는 firebase_auth와 카카오 SDK 양쪽에 있다. 이 파일에서 User는 항상
// Firebase 사용자다 — 카카오 쪽 이름을 숨겨 충돌을 없앤다.
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;
import '/flutter_flow/flutter_flow_util.dart';
import 'google_credential.dart';

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

  // ==========================================================================
  // 🔑 [GOOGLE] 앱 전체의 단 하나뿐인 Google 로그인 진입점
  // --------------------------------------------------------------------------
  // 세 갈래를 한 함수가 순서대로 처리한다. 갈래마다 UID가 어떻게 되는지가
  // 이 기능의 전부라, 각 단계에서 UID를 확인하고 어긋나면 즉시 멈춘다.
  //
  //   ① 익명 사용자 + 아직 가입 안 된 Google 계정
  //        → 로그아웃하지 않고 linkWithCredential. **UID 유지**
  //   ② 신규 or 이미 전환된 회원
  //        → signInWithCredential. Firebase가 자격증명을 자체 검증
  //   ③ 기존 커스텀 토큰 회원의 최초 전환
  //        → 서버가 Google ID Token을 공식 검증해 기존 UID 확인
  //        → 그 UID로 signInWithCustomToken → 같은 자격증명으로 link
  //        **UID 유지**, 이후 로그인부터는 ②로 직행
  //
  // 취소·실패 시 기존(또는 익명) 로그인 상태를 그대로 둔다.
  // ==========================================================================
  static Future<UserCredential> signInWithGoogle() async {
    final bundle = await obtainGoogleCredential();
    if (bundle == null) {
      throw Exception('Google sign-in cancelled.');
    }
    final credential = bundle.credential;
    final before = _auth.currentUser;

    // ── ① 익명 사용자를 승격한다 ─────────────────────────────────────────
    if (before != null && before.isAnonymous) {
      final anonUid = before.uid;
      try {
        final linked = await before.linkWithCredential(credential);
        _assertSameUid(anonUid, linked.user?.uid, stage: 'anonymous_link');
        _assertGoogleProvider(linked.user, stage: 'anonymous_link');
        FFAppState().hasLinkedAccount = true;
        debugPrint('[GoogleAuth] anonymous linked, uid preserved');
        return linked;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' &&
            e.code != 'email-already-in-use' &&
            e.code != 'account-exists-with-different-credential') {
          rethrow;
        }
        // 이 Google 계정으로 이미 만들어진 회원이 있다. **익명 UID에 붙이지
        // 않는다.** 익명 계정은 지우지도 않는다 — 아래에서 기존 회원으로
        // 로그인하고, 익명 계정 정리는 별도 작업으로 남긴다.
        debugPrint('[GoogleAuth] anonymous link skipped (${e.code})');
      }
    }

    // ── ② 공식 provider 로그인 ──────────────────────────────────────────
    try {
      final signedIn = await _auth.signInWithCredential(credential);
      _assertGoogleProvider(signedIn.user, stage: 'sign_in');
      FFAppState().hasLinkedAccount = true;
      return signedIn;
    } on FirebaseAuthException catch (e) {
      // 이 이메일로 된 계정이 있는데 google.com이 안 붙어 있다 =
      // 커스텀 토큰으로 만들어진 기존 회원이다. ③으로 넘어간다.
      if (e.code != 'account-exists-with-different-credential' &&
          e.code != 'user-not-found' &&
          e.code != 'invalid-credential') {
        rethrow;
      }
      debugPrint('[GoogleAuth] falling back to migration (${e.code})');
    }

    // ── ③ 기존 커스텀 토큰 회원의 최초 전환 ──────────────────────────────
    return _migrateLegacyGoogleMember(bundle);
  }

  /// 기존 UID를 유지한 채 google.com provider를 붙인다.
  /// **마이그레이션 기간에만 쓰는 경로다.** 전환이 끝나면 제거한다.
  static Future<UserCredential> _migrateLegacyGoogleMember(
    GoogleCredentialBundle bundle,
  ) async {
    // 서버가 Google 공식 검증 라이브러리로 ID Token을 검사하고, 그 이메일의
    // 기존 UID가 있을 때만 커스텀 토큰을 준다. 없으면 발급하지 않는다 —
    // 신규 계정 생성은 ②의 공식 경로가 담당한다.
    final result = await _callLinkOrCreate('google', idToken: bundle.idToken);
    final token = result['token'];
    if (token is! String || token.isEmpty) {
      throw Exception('Google sign-in failed: no legacy account to migrate.');
    }

    final signedIn = await _auth.signInWithCustomToken(token);
    final legacyUid = signedIn.user?.uid;
    if (legacyUid == null || legacyUid.isEmpty) {
      throw Exception('Google migration failed: no uid after custom token.');
    }

    // 같은 자격증명을 기존 UID에 붙인다. 여기서 UID가 바뀌면 **사용자 데이터를
    // 건드리기 전에** 멈춘다.
    final linked = await signedIn.user!.linkWithCredential(bundle.credential);
    _assertSameUid(legacyUid, linked.user?.uid, stage: 'legacy_migration');
    _assertGoogleProvider(linked.user, stage: 'legacy_migration');

    FFAppState().hasLinkedAccount = true;
    debugPrint('[GoogleAuth] legacy member migrated, uid preserved');
    return linked;
  }

  static void _assertSameUid(String expected, String? actual,
          {required String stage}) =>
      GoogleLinkGuards.assertSameUid(expected, actual, stage: stage);

  static void _assertGoogleProvider(User? user, {required String stage}) =>
      GoogleLinkGuards.assertGoogleLinked(
          user?.providerData.map((p) => p.providerId),
          stage: stage);

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
