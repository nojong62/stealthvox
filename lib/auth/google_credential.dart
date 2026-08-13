// ============================================================================
// 🔑 [GOOGLE-CREDENTIAL] Google 자격증명 획득 — 여기 한 곳에서만 만든다
// ----------------------------------------------------------------------------
// 로그인이냐 연결이냐는 **호출부가 정한다.** 이 파일은 자격증명만 만들어 준다.
//
//   · 신규/전환 완료 회원 → FirebaseAuth.signInWithCredential
//   · 익명 사용자 승격     → currentUser.linkWithCredential
//   · 기존 커스텀 토큰 회원 → 기존 UID 로그인 후 linkWithCredential
//
// 이 셋이 같은 자격증명을 쓰도록 획득 지점을 하나로 묶었다. 예전에는
// `social_auth_service.dart`와 `firebase_auth/google_auth.dart`가 각자
// GoogleSignIn을 호출해 서로 다른 동작을 할 수 있었다.
// ============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google 계정 선택 UI에 쓰는 단일 인스턴스. scope는 이메일 확인에 필요한
/// 최소값만 둔다 — 서버가 `email_verified`를 보고 기존 회원을 찾는다.
final GoogleSignIn kStealthVoxGoogleSignIn =
    GoogleSignIn(scopes: const ['profile', 'email']);

/// Google 자격증명과 원본 ID Token을 함께 담는다.
///
/// ID Token은 **기존 회원 마이그레이션에서만** 서버로 보낸다. 서버는 그것을
/// Google 공식 검증 라이브러리로 검사해 기존 UID를 찾는다. 신규 로그인과 익명
/// 연결은 Firebase가 자격증명을 자체 검증하므로 서버를 거치지 않는다.
class GoogleCredentialBundle {
  const GoogleCredentialBundle({required this.credential, required this.idToken});

  final AuthCredential credential;
  final String? idToken;
}

/// 계정 선택 UI를 띄우고 자격증명을 만든다. 사용자가 취소하면 null.
///
/// 이전 세션이 남아 있으면 계정 선택이 안 뜨고 지난 계정으로 조용히 진행되는
/// 일이 있어 먼저 로그아웃한다(로그아웃 실패는 무시 — 그냥 안 붙어 있던 것이다).
Future<GoogleCredentialBundle?> obtainGoogleCredential() async {
  try {
    await kStealthVoxGoogleSignIn.signOut();
  } catch (_) {}

  final account = await kStealthVoxGoogleSignIn.signIn();
  if (account == null) return null; // 사용자가 취소

  final auth = await account.authentication;
  return GoogleCredentialBundle(
    credential: GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    ),
    idToken: auth.idToken,
  );
}
