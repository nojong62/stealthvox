import 'dart:math' as math;

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
///
/// 🔵 밝기의 기준은 **"지금 말해도 되는가"**다. 예전에는 `recording`(마이크를
///   눌러 녹음 중인가)을 봤는데, 마이크가 세션 내내 열려 있는 지금은 그런
///   순간이 따로 없다. 아래 마이크 상태등과 같은 값을 받아 화면 전체가 한
///   가지 대답만 하게 한다.
class DuoInterpreterStage extends StatelessWidget {
  const DuoInterpreterStage({
    super.key,
    required this.ready,
    required this.partnerSpeaking,
  });

  /// 게이트가 열려 있어 지금 말하면 전사로 들어간다.
  final bool ready;

  /// 상대 말을 통역해 들려주는 중 — 내 차례가 아니다.
  final bool partnerSpeaking;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: partnerSpeaking ? 0.82 : (ready ? 1 : 0.6),
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

// ============================================================================
// 📡 [DUO-WAITING] 상대를 기다리는 동안의 무대.
//
// 이 자리에는 유저가 할 일이 없다. 초대는 이미 보냈고, 상대가 들어오면
// 마이크가 알아서 열린다. 그래서 화면이 해야 할 일은 하나뿐이다 —
// **멈춰 있지 않다는 것을 보여 주는 것.** 정지 화면은 몇 초만 지나도
// "고장 났나"로 읽힌다.
//
// 움직이는 것은 셋뿐이고 전부 같은 시계(2초)를 쓴다. 제각각 돌면 화면이
// 부산해지고, 부산한 화면은 기다림을 더 길게 느끼게 한다.
//   · 퍼지는 고리 둘 — 신호를 내보내는 중
//   · 진행 막대 — 아직 진행 중
//   · 그 밖은 전부 정지 (아래 통화 버튼들은 **그림**이다, 누를 수 없다)
// ============================================================================

const Color _kDuoBlue = Color(0xFF3B82F6);
const Color _kDuoSurface = Color(0xFF1C1C1E);
const Color _kDuoSurfaceBright = Color(0xFF393939);
const Color _kDuoOutline = Color(0xFF424754);
const Color _kDuoWarning = Color(0xFFFF5252);

class DuoWaitingStage extends StatefulWidget {
  const DuoWaitingStage({super.key, required this.backdropAsset});

  /// 뒤에 아주 옅게 깔리는 통화 그림. 대기가 끝나면 이 그림이 그대로
  /// 선명해지므로, 기다리는 동안에도 같은 그림을 보여 화면이 이어져 보인다.
  final String backdropAsset;

  @override
  State<DuoWaitingStage> createState() => _DuoWaitingStageState();
}

class _DuoWaitingStageState extends State<DuoWaitingStage>
    with SingleTickerProviderStateMixin {
  /// 하나뿐인 시계. 고리도 막대도 여기서 위상만 달리 읽는다.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 뒤에 깔리는 푸른 번짐. blur는 비싸서 방사형 그라디언트로 낸다 —
        // 어차피 아주 옅어 가장자리 차이가 보이지 않는다.
        IgnorePointer(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _kDuoBlue.withValues(alpha: 0.18),
                  _kDuoBlue.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Container(
                decoration: BoxDecoration(
                  color: _kDuoSurface,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  boxShadow: [
                    BoxShadow(
                      color: _kDuoBlue.withValues(alpha: 0.10),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: 0.18,
                      child: Image.asset(widget.backdropAsset,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium),
                    ),
                    _buildCardBody(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          _buildBeacon(),
          const SizedBox(height: 26),
          _buildProgressBar(),
          const SizedBox(height: 12),
          Container(
            width: 96,
            height: 8,
            decoration: BoxDecoration(
              color: _kDuoSurfaceBright,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const Spacer(),
          _buildMockControls(),
        ],
      ),
    );
  }

  /// 신호를 내보내는 표시. 고리 둘이 반 바퀴 어긋나 번갈아 퍼진다.
  Widget _buildBeacon() {
    return SizedBox(
      width: 96,
      height: 96,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          Widget ring(double phase) {
            // 0 → 1 동안 0.8배에서 1.5배로 퍼지며 사라진다.
            final double t = (_c.value + phase) % 1.0;
            return Transform.scale(
              scale: 0.8 + t * 0.7,
              child: Opacity(
                opacity: (0.5 * (1 - t)).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _kDuoBlue, width: 2),
                  ),
                ),
              ),
            );
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: ring(0.0)),
              Positioned.fill(child: ring(0.5)),
              child!,
            ],
          );
        },
        // 가운데 원은 안 움직인다 — 움직이면 아이콘이 흔들려 읽기 어렵다.
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kDuoSurfaceBright,
            border: Border.all(color: _kDuoOutline),
          ),
          child: const Icon(Icons.satellite_alt_rounded,
              color: _kDuoBlue, size: 34),
        ),
      ),
    );
  }

  /// 진행 막대. **끝나지 않는다** — 실제 진행률을 모르기 때문이다.
  /// 채운 길이를 거짓으로 늘리는 대신 밝기만 숨 쉬게 한다.
  Widget _buildProgressBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double full = constraints.maxWidth * 0.78;
        return SizedBox(
          width: full,
          height: 12,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _kDuoSurfaceBright,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  // 0.35 ↔ 1.0 사이를 오간다(사인 한 주기).
                  final double breath = 0.35 +
                      0.65 * (0.5 - 0.5 * math.cos(_c.value * 2 * math.pi));
                  return Container(
                    width: full * 0.5,
                    decoration: BoxDecoration(
                      color: _kDuoBlue.withValues(alpha: breath),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 통화 버튼 **그림**. 진짜 버튼은 화면 아래에 따로 있다 — 여기 것은
  /// 이 카드가 무엇이 될 자리인지 알려 주는 미리보기라 눌리지 않는다.
  Widget _buildMockControls() {
    Widget round(IconData icon, double size, Color bg, Color fg,
        {bool outlined = true}) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          border: outlined ? Border.all(color: _kDuoOutline) : null,
        ),
        child: Icon(icon, color: fg, size: size * 0.42),
      );
    }

    return IgnorePointer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: 0.5,
            child: round(Icons.mic_off_rounded, 44, _kDuoSurfaceBright,
                const Color(0xFFC2C6D6)),
          ),
          const SizedBox(width: 14),
          round(Icons.call_end_rounded, 52, _kDuoWarning, Colors.white,
              outlined: false),
          const SizedBox(width: 14),
          Opacity(
            opacity: 0.5,
            child: round(Icons.videocam_off_rounded, 44, _kDuoSurfaceBright,
                const Color(0xFFC2C6D6)),
          ),
        ],
      ),
    );
  }
}
