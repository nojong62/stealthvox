// 🔐 [ADMIN-GATE] 관리자 판별의 단일 출처.
//
//   **UID exact match만 본다.** 이메일은 보지 않는다 — 이메일은 계정 병합·
//   변경으로 움직이지만 UID는 계정과 함께 죽을 때까지 같다.
//
//   지금 이 게이트를 쓰는 곳은 딱 둘이다.
//     · Lobby 'StealthVox' 3초 롱프레스 → P2 Voice Lab 진입
//     · P2VoiceLabPage 자체 가드(initState + build)
//
//   `store_master.dart`의 이메일 기반 관리자 시트 두 곳은 **이번에 건드리지
//   않는다.** 그쪽 정리는 별도 작업이다. 여기로 옮기고 싶어지면 그때 옮긴다.

import 'package:firebase_auth/firebase_auth.dart';

/// 관리자 판별. UID 정확히 일치할 때만 true.
///
/// ⚠️ **UID는 여기 한 곳에만 둔다.** 화면 코드에 UID 문자열을 복사하지 말고
/// 반드시 [isAdmin]을 부를 것.
class AdminGate {
  AdminGate._();

  /// 관리자 Firebase Auth UID.
  ///
  /// 확인 경로: Firebase Console → Authentication → Users → 해당 계정의
  /// User UID(28자).
  ///
  /// ⚠️ **UID는 여기 말고 어디에도 적지 않는다.** 화면 코드는 [isAdmin]만
  /// 부른다. 계정이 바뀌면 이 Set만 고치면 된다.
  static const Set<String> _adminUids = <String>{
    'rJChsLrIqAhXhLZotYeeLZo6KK42',
  };

  /// 지금 로그인한 사람이 관리자인가.
  ///
  /// 익명(체험) 사용자는 무조건 false다. Lobby route에는 `requireAuth`가 걸려
  /// 있지 않아서 익명 사용자도 로비 화면까지 온다 — "로비에 있으니 회원"이라는
  /// 가정을 쓰면 안 된다.
  static bool get isAdmin {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    if (user.isAnonymous) return false;
    return _adminUids.contains(user.uid);
  }
}
