// ====================================================================
// 🎫 [STUDY-ACCESS] 공부방에서 **무엇을 볼 수 있고 무엇을 쓸 수 있는가**.
// --------------------------------------------------------------------
// 두 가지를 절대 같은 것으로 다루지 않는다.
//
//   보기(read)   — 자기가 실제로 한 말. **누구에게도 막지 않는다.**
//                  익명 게스트도, 잔여 시간이 없는 회원도 자기 대화는 본다.
//   쓰기(paid)   — 서버 비용이 새로 나가는 학습 동작(TTS 생성·GPT 재가공·
//                  녹음 전사·에코잉·쉐도잉). 비용을 **누군가 부담할 때만**
//                  연다.
//
// `isGuestSession == true`는 "Duo 비용을 호스트가 낸다"는 뜻일 뿐,
// "기록을 못 본다"는 뜻이 아니다. 그 둘을 한 조건으로 묶었다가 게스트가
// 방금 자기가 한 말조차 못 보는 화면이 나온 적이 있다.
//
// ⚠️ **버튼과 과금은 반드시 같은 식을 본다.** 버튼만 열리고 차감이 막히면
// 그 구간이 통째로 무료 API 호출이 된다. 그래서 과금 티커의 게스트·체험
// 판정도 이 파일의 [isDuoBillingSuppressed]를 쓴다 — 조건이 두 벌이면
// 한쪽만 고쳐진다. 불변식은 `test/study_access_test.dart`가 지킨다.
// ====================================================================

import 'package:firebase_auth/firebase_auth.dart';

import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/widgets/trial/trial_flow_state.dart';

/// 비용 드는 학습 기능이 막힌 이유. 화면은 이 값으로 안내 문구를 고른다.
enum StudyBlockReason {
  /// 막히지 않았다.
  none,

  /// 아직 회원이 아니다(익명). 로그인하면 열린다.
  notSignedIn,

  /// 지금은 Duo 게스트다. 이 통화의 비용은 호스트가 낸다 — 게스트 쪽에서
  /// 새 비용을 만들지 않는다. 통화가 끝나고 자기 계정으로 돌아오면 열린다.
  duoGuest,
}

/// 지금 이 사람이 공부방에서 할 수 있는 것.
class StudyAccess {
  const StudyAccess._(this.canUsePaidStudy, this.reason);

  /// 새 비용이 나가는 학습 동작을 쓸 수 있는가.
  final bool canUsePaidStudy;

  /// 못 쓴다면 왜인가.
  final StudyBlockReason reason;

  /// 대화 내용을 볼 수 있는가. **언제나 true다.** 필드로 둔 것은 호출부가
  /// "보기도 막히나?"를 묻지 않고 읽을 수 있게 하기 위해서다.
  bool get canReadConversation => true;

  /// 잠긴 버튼에 붙일 짧은 한마디. 눌러도 아무 일이 없는 버튼을 두지 않는다.
  String get gateLabel {
    switch (reason) {
      case StudyBlockReason.none:
        return '';
      case StudyBlockReason.notSignedIn:
        return '로그인하면 연습할 수 있어요';
      case StudyBlockReason.duoGuest:
        // ⚠️ 예전 문구는 '통화가 끝나면 연습할 수 있어요'였다. **거짓말이었다.**
        //   이 문구를 보는 사람은 통화가 이미 끝난 익명 게스트다 — 회원 게스트는
        //   통화를 나가는 순간 딱지가 떨어져(`routine_mode_duo`의 GUEST-EXIT
        //   갈래) 이 상태로 공부방에 오지 않는다. 익명은 그대로 남으므로,
        //   끝난 통화가 끝나기를 기다리라는 말을 읽고 '다시 시도'를 반복해
        //   누르게 된다(2026-08-30 실장님 확인). 실제로 잠금을 푸는 행동은
        //   로그인이고, 로그인하면 그 자리에서 배울글이 만들어진다.
        //
        //   판정(`canUsePaidStudy`)은 손대지 않았다 — 게스트 구간의 비용은
        //   호스트가 내고, 그 정책은 그대로다. 바뀐 것은 안내 문구뿐이다.
        return '로그인하면 연습할 수 있어요';
    }
  }
}

const StudyAccess _kAllowed =
    StudyAccess._(true, StudyBlockReason.none);
const StudyAccess _kNotSignedIn =
    StudyAccess._(false, StudyBlockReason.notSignedIn);
const StudyAccess _kDuoGuest =
    StudyAccess._(false, StudyBlockReason.duoGuest);

/// 지금 차감을 **하지 않기로 되어 있는** 상태인가.
///
/// 과금 티커의 차감 조건과 이 파일의 버튼 조건이 같은 자리를 보게 하려고
/// 따로 뽑았다. 두 경우뿐이고 둘 다 의도된 무료다.
///   · 맛보기 — Duo 10분과 이어지는 공부방 5분은 잔여시간과 무관하다
///   · Duo 게스트 — 회원이든 아니든 초대한 호스트만 부담한다
bool isDuoBillingSuppressed({
  required bool isTrial,
  required bool isDuoGuest,
}) =>
    isTrial || isDuoGuest;

/// 상태 셋으로 권한을 정한다. **순서가 정책이다.**
///
///   ① 맛보기 — 폰 한 대에 한 번 주는 무료 이용권이다. 익명이라고 막으면
///      맛보기 자체가 성립하지 않는다.
///   ② Duo 게스트 — 회원이어도 막는다. 이 구간은 차감이 안 되므로, 버튼만
///      열어 두면 무료 API 호출이 된다.
///   ③ 익명 — 잔여 시간도 구매 권한도 없다. 볼 수는 있고, 쓰지는 못한다.
///
/// [isSignedInMember]는 "익명이 아닌 Firebase 사용자"다. 로그인 여부와
/// Duo 게스트 여부는 **다른 축이다** — 넷(A·B·C·D)이 전부 성립한다.
StudyAccess resolveStudyAccess({
  required bool isTrial,
  required bool isDuoGuest,
  required bool isSignedInMember,
}) {
  if (isTrial) return _kAllowed;
  if (isDuoGuest) return _kDuoGuest;
  if (!isSignedInMember) return _kNotSignedIn;
  return _kAllowed;
}

/// 지금 이 앱의 상태로 판정한다. 화면은 이것만 부른다.
StudyAccess currentStudyAccess() {
  final user = FirebaseAuth.instance.currentUser;
  return resolveStudyAccess(
    isTrial: TrialFlowState.instance.isTrial,
    isDuoGuest: FFAppState().isGuestSession,
    isSignedInMember: user != null && !user.isAnonymous,
  );
}
