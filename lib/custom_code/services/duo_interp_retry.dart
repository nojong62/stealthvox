// ====================================================================
// 🔁 [INTERP-RETRY] 만능 통역이 못 붙었을 때 몇 번, 얼마 뒤에 다시 붙나
// --------------------------------------------------------------------
// WebRTC 통역이 기본 경로가 되면서 생긴 자리다. 그 전에는 시작이 실패해도
// `record` + Firestore가 돌고 있었으므로 대화가 이어졌다. 지금은 시작이
// 실패하면 **통역이 통째로 시작되지 않는다.**
//
// 그런데 `_interpAutoStartAttempted`는 시도 **전에** 세워지고 실패 갈래에서
// 풀리지 않는다. 그래서 한 번 못 붙으면 상대가 나갔다 들어올 때까지 아무 일도
// 일어나지 않았다. 여기가 그 한 번을 세 번으로 늘리는 규칙이다.
//
// 🚫 **실패했다고 Firestore로 갈아타지 않는다.** 통로는 통화가 시작될 때
//   한 번 박히고(`_interpTransport`) 끝날 때까지 고정이다. 되돌리는 일은
//   Remote Config(`DuoInterpreterTransport`)가 **다음 통화부터** 한다.
//   "같은 통로 안에서 다시 붙기"와 "통로를 바꾸기"는 다른 기능이다.
//
// 📐 이 파일에 시계가 없는 것은 일부러다. 언제 다시 시도할지만 정하고, 실제로
//   기다리는 일은 호출부의 `Timer`가 한다 — 그래야 이 규칙을 시계 없이
//   그대로 시험할 수 있다.
// ====================================================================

/// 자동 재시도 간격. **길이가 곧 최대 재시도 횟수다.**
///
/// 2초는 일시적인 신호 지연을, 5초는 짧은 망 끊김을, 10초는 상대가 아직 방에
/// 들어오는 중인 경우를 노린다. 대칭 NAT처럼 구조적으로 못 붙는 망에서는 세
/// 번을 다 써도 안 붙으므로, 그 뒤는 사람이 누르는 자리로 넘긴다.
const List<Duration> kDuoInterpRetryDelays = <Duration>[
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
];

/// 재시도를 몇 번 했고 다음은 언제인가. **통화 한 번 = 이 객체 한 개.**
///
/// 시계도 `Timer`도 들고 있지 않다. 호출부가 [takeNextDelay]로 다음 간격을
/// 받아 자기 타이머를 걸고, 성공하면 [reset]한다.
class DuoInterpRetryPolicy {
  int _attempts = 0;

  /// 지금까지 예약한 재시도 횟수. 0이면 아직 한 번도 안 걸었다.
  int get attempts => _attempts;

  /// 자동으로 더 걸 것이 남았는가.
  bool get exhausted => _attempts >= kDuoInterpRetryDelays.length;

  /// 남은 재시도 횟수.
  int get remaining => kDuoInterpRetryDelays.length - _attempts;

  /// 다음 재시도까지 기다릴 시간. **부르면 한 번 소비한다.**
  ///
  /// 더 시도할 것이 없으면 null이고, 그때 호출부는 수동 재시도로 넘긴다.
  /// 소비형인 이유: "간격을 물어보고 안 걸었다"는 상태를 따로 두면 그 둘이
  /// 어긋나는 순간 재시도가 무한히 돈다.
  Duration? takeNextDelay() {
    if (exhausted) return null;
    return kDuoInterpRetryDelays[_attempts++];
  }

  /// 처음으로 되돌린다. 통역이 붙었을 때, 상대가 바뀌었을 때, 사용자가
  /// 직접 다시 시도했을 때 부른다.
  void reset() => _attempts = 0;
}
