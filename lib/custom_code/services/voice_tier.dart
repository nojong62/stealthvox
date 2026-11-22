// ====================================================================
// 🎙️ [VOICE-TIER] 음성 등급 — 프리미엄(Chirp 3 HD) / 기본(WaveNet)
// --------------------------------------------------------------------
// 2026-11-09 실장님 결정.
//
//   · 잔액은 초 하나뿐이고 "프리미엄 기준 시간"이다. 등급은 차감 속도만
//     바꾼다(기본 = 1/2). 스토어 상품·쿠폰·가입 보너스는 그대로다.
//   · 등급은 로비에서 고르고(FFAppState.voiceTier), 방에 들어가는 순간
//     [VoiceTierSession.activate]로 그 방에 묶는다. 방 안에서 로비 값이
//     바뀌어도 이미 시작한 대화는 그대로 간다.
//   · TTS 요청 본문(`speechPayload`)과 음성 캐시 이름(`cacheNamespace`)이
//     [VoiceTierSession.active]를 읽는다. 그래서 화면마다 등급을 따로
//     실어 보낼 필요가 없다.
//   · Duo 직접통화는 음성 합성이 없어 등급이 없고 요금만 1/2이다.
// ====================================================================

import 'package:flutter/foundation.dart';

import '/app_state.dart';
import '../actions/billing_ticker.dart';

enum VoiceTier { premium, basic }

/// 저장값·방 문서 값을 읽는다. 모르는 값은 프리미엄(지금까지의 동작)이다.
VoiceTier parseVoiceTier(Object? raw) {
  final value = raw is String ? raw.trim().toLowerCase() : '';
  return value == 'basic' ? VoiceTier.basic : VoiceTier.premium;
}

/// 로비에서 마지막으로 고른 등급.
VoiceTier get lobbyVoiceTier => parseVoiceTier(FFAppState().voiceTier);

set lobbyVoiceTier(VoiceTier tier) => FFAppState().voiceTier = tier.name;

/// 등급별 과금 배율. 통역 통화는 초대자가 양쪽 몫을 낸다.
BillingRate billingRateFor(VoiceTier tier, {bool interp = false}) {
  if (interp) {
    return tier == VoiceTier.basic
        ? BillingRate.interpBasic
        : BillingRate.interpPremium;
  }
  return tier == VoiceTier.basic ? BillingRate.basic : BillingRate.full;
}

/// 프리미엄 기준 잔액(초)을 이 등급으로 쓸 수 있는 초로 바꾼다.
int secondsUsableAt(int premiumSeconds, VoiceTier tier) {
  final rate = billingRateFor(tier).multiplier;
  return (premiumSeconds / rate).floor();
}

class VoiceTierSession {
  VoiceTierSession._();

  static VoiceTier _active = VoiceTier.premium;

  /// 지금 열린 방의 등급. TTS 요청과 캐시 이름이 읽는다.
  static VoiceTier get active => _active;

  static void activate(VoiceTier tier, {required String reason}) {
    _active = tier;
    debugPrint('[VOICE-TIER] active=${tier.name} reason=$reason');
  }

  static String? _handoffPath;

  /// 대화방이 끝나며 공부방을 바로 열 때 부른다. 그 공부방은 대화의 등급을
  /// 그대로 이어받고 등급 팝업을 띄우지 않는다.
  static void handOffToStudy(String historyPath) {
    _handoffPath = historyPath;
  }

  /// 공부방이 열릴 때 한 번. 직전 대화방이 바로 넘겨준 방이면 true.
  /// History 목록 등 다른 길로 들어오면 false다(등급 팝업 대상).
  static bool takeHandoff(String historyPath) {
    final carried = _handoffPath != null && _handoffPath == historyPath;
    _handoffPath = null;
    return carried;
  }
}
