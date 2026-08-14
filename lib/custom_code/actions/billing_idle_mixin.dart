// ====================================================================
// 💰 [BILLING-IDLE] 과금 유휴 규칙 — 모든 방이 이 한 벌을 쓴다
// --------------------------------------------------------------------
// 규칙은 하나뿐이다.
//
//   방에 들어가면 과금 시작
//   60초 동안 아무 작동이 없으면 정지
//   다시 움직이면 재개
//
// 예외는 둘이고, 둘 다 의도된 것이다.
//   · 히스토리 **전체 목록** — 무과금이라 이 믹스인을 쓰지 않는다
//     (Keepers 필터로 바꾸는 순간부터는 쓴다)
//   · Duo — 게스트 입장~퇴장까지 무정지라 유휴 타이머가 없다
//
// **왜 공용으로 묶었나.** 예전에는 이 기계가 화면마다 한 벌씩, 다섯 벌
// 복사되어 있었다. 뼈대는 글자 하나까지 같은데 "작동 중"의 정의만 달랐고,
// 그 틈에서 실제 결함이 났다 — Step Expand는 재생기를 둘이나 빠뜨려서
// 완성 문장을 반복해 듣는 동안(가장 오래 머무는 구간) 과금이 멈췄다.
// 히스토리는 같은 성격의 기능을 13가지나 챙기고 있었는데도 그랬다.
// 뼈대를 한 곳에 두면 다음에 재생기가 늘어도 [isBillingBusy] 한 줄만
// 보면 된다.
// ====================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import 'billing_ticker.dart';

/// 무작동으로 판정하기까지의 시간. **한 곳에만 둔다** — 예전에는 다섯 파일에
/// 60이 따로 박혀 있어서, 바꾸려면 다섯 번 고쳐야 했다.
const int kBillingIdlePauseSec = 60;

mixin BillingIdleMixin<T extends StatefulWidget> on State<T> {
  // ── 화면이 채워야 하는 것 ────────────────────────────────────────
  /// 과금 로그에 남길 모드 이름(`free_talk`·`history` 등).
  String get billingModeName;

  /// 지금 이 화면이 **작동 중**인가.
  ///
  /// ⚠️ **이 화면의 재생기·녹음기를 빠짐없이 넣어야 한다.** 하나라도 빠지면
  /// 유저가 그것을 쓰는 동안 유휴로 판정되어 과금이 멈춘다. 재생기를 새로
  /// 추가할 때 여기도 같이 고치는 것을 잊지 말 것.
  bool get isBillingBusy;

  /// 이 화면이 **과금 대상인가.** 체험 중이거나 Duo 게스트처럼 애초에 차감
  /// 대상이 아닌 경우 false로 두면, 유휴에서 돌아올 때 과금을 켜지 않는다.
  /// 유휴 감시 자체는 계속 돈다(화면 상태 표시에 쓰인다).
  bool get isBillingEnabled => true;

  /// 모드별 추가 검사(30분 롤오버·체험 종료 등).
  ///
  /// `true`를 돌려주면 이번 tick은 여기서 끝난다(유휴 누적 없음).
  /// 기본은 아무것도 하지 않는다.
  bool onBillingIdleTick() => false;

  // ── 공용 상태 ────────────────────────────────────────────────────
  Timer? _idleTimer;
  int _idleSec = 0;
  bool _idlePaused = false;

  bool get isBillingIdlePaused => _idlePaused;

  /// 방에 들어갈 때 한 번. 과금을 켜고 유휴 감시를 시작한다.
  void startBillingRoom({BillingRate rate = BillingRate.full}) {
    if (isBillingEnabled) {
      BillingTicker.instance.setRate(rate);
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode(billingModeName);
    }
    resetBillingIdle();
  }

  /// 유저·AI가 움직였다. 유휴 카운터를 되돌리고, 멈춰 있었으면 다시 켠다.
  void resetBillingIdle() {
    _idleSec = 0;
    if (_idlePaused) {
      _idlePaused = false;
      if (mounted) setState(() {});
      if (isBillingEnabled) {
        BillingTicker.instance.resume();
      // 30분 시계는 이어서 간다 — 여기서 되감으면 잠깐 쉴 때마다 세션이
      // 처음으로 돌아가 롤오버가 영영 오지 않는다.
        BillingTicker.instance
            .logMode(billingModeName, startNewConversation: false);
      }
    }
    _idleTimer?.cancel();
    _idleTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _billingIdleTick());
  }

  void _billingIdleTick() {
    if (!mounted) return;
    // 🔒 다른 페이지가 위에 떠 있으면 이 화면은 쉬는 중이다. 그 시간을
    //   유휴로 세면, 돌아왔을 때 곧바로 정지가 걸린다.
    if (ModalRoute.of(context)?.isCurrent == false) {
      _idleSec = 0;
      return;
    }
    if (_idlePaused) return;
    if (onBillingIdleTick()) return;
    if (isBillingBusy) {
      _idleSec = 0;
      return;
    }
    _idleSec++;
    if (_idleSec >= kBillingIdlePauseSec) {
      handleBillingIdlePause();
    }
  }

  void handleBillingIdlePause() {
    if (!mounted || _idlePaused) return;
    _idlePaused = true;
    _idleSec = 0;
    BillingTicker.instance.pause();
    if (mounted) setState(() {});
  }

  /// 화면을 떠날 때. 타이머만 정리한다 — 과금 정지는 호출부가
  /// `BillingTicker.pause()`로 명시한다(저장 순서가 화면마다 다르다).
  void clearBillingIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _idleSec = 0;
  }

  /// 유휴 누적을 0으로만 되돌린다(타이머는 그대로). 롤오버 대기처럼
  /// "정지시키면 안 되는 구간"에서 쓴다.
  void holdBillingIdle() => _idleSec = 0;
}
