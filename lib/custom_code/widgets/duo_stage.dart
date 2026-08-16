import 'package:flutter/material.dart';

// ============================================================================
// 🖼️ [DUO-STAGE] 통화 화면 가운데를 채우는 그림들.
//
// 두 방식 모두 자막을 만들지 않는다. 그래서 이 화면에는 글자가 없고, 방식마다
// 그림 한 장이 무대를 통째로 쓴다. 예전에는 안내 문장 한 줄과 "나 / 상대"
// 언어 칩이 있었는데, 직접 대화는 양쪽이 들어오면 마이크가 알아서 켜지므로
// 시킬 일이 없고 언어쌍도 그림이 대신 말해 준다.
//
// **이 파일은 Firebase도 앱 상태도 모른다.** 필요한 값만 인자로 받는다.
// 화면 없이 띄워 보고 눈으로 확인할 수 있어야 해서 일부러 갈라놨다.
// ============================================================================

/// 직접 대화 — 제공된 직접 통화 이미지를 무대 전체에 채운다.
///
/// 📐 이미지는 폰 주위가 **투명**이다. 그래서 폭·높이를 줄여 잡을 이유가 없다
///   — 남는 자리는 어차피 배경이 그대로 비쳐 보인다. 예전에는 0.72×0.82로
///   묶고 모서리를 둥글렸는데, 자를 것도 없는 그림을 작게 만들기만 했다.
///   `contain`이라 비율은 그대로고 잘리지도 않는다.
class DuoDirectStage extends StatelessWidget {
  const DuoDirectStage({
    super.key,
    required this.callActive,
    required this.muted,
    required this.partnerOnline,
  });

  final bool callActive;
  final bool muted;
  final bool partnerOnline;

  @override
  Widget build(BuildContext context) {
    final bool live = callActive && !muted;
    final double opacity = live
        ? 1
        : partnerOnline
            ? 0.84
            : 0.62;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: opacity,
      child: SizedBox.expand(
        child: Image.asset(
          'assets/images/duo_direct_call.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

/// 만능 통역 — 제공된 통역기 이미지를 무대 전체에 채운다.
///
/// 📐 [DuoDirectStage]와 같은 규칙이다. 폰 주위가 투명이라 줄여 잡을 이유가
///   없고, `contain`이라 비율도 그대로다. 두 방식의 그림 크기가 같아야
///   방식을 오갈 때 화면이 덜컹거리지 않는다.
class DuoInterpreterStage extends StatelessWidget {
  const DuoInterpreterStage({super.key, required this.recording});

  final bool recording;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: recording ? 1 : 0.72,
      child: SizedBox.expand(
        child: Image.asset(
          'assets/images/duo_interpreter.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
