import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../google_credential.dart';
import '../social_auth_service.dart';

/// ⚠️ Google 로그인 구현은 `SocialAuthService.signInWithGoogle()` **하나뿐이다.**
///
/// 예전에는 이 파일이 자체적으로 `signInWithCredential`을 호출해, UI가 쓰는
/// `SocialAuthService` 경로와 동작이 갈릴 수 있었다(익명 승격·기존 회원 전환이
/// 여기엔 없다). FlutterFlow가 만든 `firebase_auth_manager.dart`가 이 함수를
/// 참조하므로 시그니처는 남기고, 속은 단일 진입점으로 위임한다.
Future<UserCredential?> googleSignInFunc() async {
  if (kIsWeb) {
    return await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
  }
  try {
    return await SocialAuthService.signInWithGoogle();
  } catch (_) {
    // 취소를 예외로 올리는 단일 진입점과 달리, 이 자리의 호출 규약은
    // "취소하면 null"이다. 규약만 맞춰 준다.
    return null;
  }
}

Future signOutWithGoogle() => kStealthVoxGoogleSignIn.signOut();
