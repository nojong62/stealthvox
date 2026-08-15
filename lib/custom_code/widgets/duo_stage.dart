import 'package:flutter/material.dart';

// ============================================================================
// 🖼️ [DUO-STAGE] 말풍선이 없을 때 화면 가운데를 채우는 그림들.
//
// 예전에는 두 방식 모두 안내 문장 한 줄이었다. 직접 대화는 양쪽이 들어오면
// 마이크가 자동으로 켜지므로 시킬 일이 없고, 만능 통역은 "무슨 언어가 오가는지"가
// 문장보다 훨씬 중요한 정보였다. 그래서 문장을 걷어내고 각자에게 맞는 그림을 둔다.
//
// **이 파일은 Firebase도 앱 상태도 모른다.** 필요한 값만 인자로 받는다.
// 화면 없이 띄워 보고 눈으로 확인할 수 있어야 해서 일부러 갈라놨다.
// ============================================================================

const Color kDuoStageBg = Color(0xFF121212);
const Color kDuoStagePanel = Color(0xFF1C1C1E);
const Color kDuoStageIdle = Color(0xFF445066);
const Color kDuoStageLive = Color(0xFF34D399);
const Color kDuoStageMuted = Color(0xFFF59E0B);
const Color kDuoStageBlue = Color(0xFF2563EB);
const Color kDuoStageMine = Color(0xFF93C5FD);
const Color kDuoStageTheirs = Color(0xFF4ADE80);

/// 직접 대화 — 두 폰이 붙어 있는 그림.
///
/// 상태는 색과 가운데 연결점으로만 말한다. "왜 소리가 안 가는지"의 정확한
/// 이유는 버튼 옆 라벨이 이미 말하고 있으므로 여기서 겹쳐 적지 않는다.
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
    final Color accent = live
        ? kDuoStageLive
        : (callActive && muted)
            ? kDuoStageMuted
            : kDuoStageIdle;

    return Center(
      // 가로 화면처럼 높이가 짧을 때 줄무늬(overflow)가 뜨지 않게 감싼다.
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PhoneGlyph(accent: accent, active: callActive),
                _LinkDots(
                    accent: accent, live: live, muted: callActive && muted),
                _PhoneGlyph(
                    accent: partnerOnline ? accent : kDuoStageIdle,
                    active: partnerOnline && callActive),
              ],
            ),
            const SizedBox(height: 28),
            // 사람 표시는 남긴다 — 폰 그림만으로는 상대가 방에 있는지 알 수 없다.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person,
                    size: 15,
                    color: partnerOnline ? kDuoStageLive : Colors.white24),
                const SizedBox(width: 6),
                Icon(Icons.person,
                    size: 15,
                    color: partnerOnline ? kDuoStageLive : Colors.white24),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 폰 한 대. 화면 부분이 켜지면 통화가 붙은 것이다.
class _PhoneGlyph extends StatelessWidget {
  const _PhoneGlyph({required this.accent, required this.active});

  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: 74,
      height: 132,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: kDuoStagePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent, width: active ? 2.0 : 1.2),
        boxShadow: active
            ? [
                BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 22,
                    spreadRadius: 1),
              ]
            : null,
      ),
      child: Column(
        children: [
          // 스피커 슬릿
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: active ? 0.9 : 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              width: double.infinity,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: active ? 0.16 : 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.graphic_eq,
                  size: 22,
                  color: accent.withValues(alpha: active ? 0.95 : 0.35)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 두 폰 사이의 연결. 붙어 있으면 채워진 점, 아니면 빈 점.
class _LinkDots extends StatelessWidget {
  const _LinkDots(
      {required this.accent, required this.live, required this.muted});

  final Color accent;
  final bool live;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (muted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Icon(Icons.mic_off_rounded, size: 18, color: accent),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(3, (i) {
              return AnimatedContainer(
                duration: Duration(milliseconds: 220 + i * 90),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: live ? 7 : 5,
                height: live ? 7 : 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: live ? accent : Colors.transparent,
                  border: Border.all(
                      color: accent.withValues(alpha: live ? 1 : 0.5),
                      width: 1.2),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// 만능 통역 — 무슨 언어가 어디로 가는지.
///
/// 상대 언어는 세션 문서에서 받는다. 아직 모르면 `—`로 둔다 — 아무거나 채워
/// 넣으면 사용자가 잘못된 언어쌍을 믿는다.
class DuoLangPairBar extends StatelessWidget {
  const DuoLangPairBar({super.key, required this.mine, this.theirs});

  final String mine;
  final String? theirs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Expanded(
              child: _LangChip(
                  lang: mine, who: '나', color: kDuoStageMine, known: true)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child:
                Icon(Icons.swap_horiz_rounded, color: Colors.white38, size: 22),
          ),
          Expanded(
            child: _LangChip(
                lang: theirs ?? '—',
                who: '상대',
                color: kDuoStageTheirs,
                known: theirs != null),
          ),
        ],
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip(
      {required this.lang,
      required this.who,
      required this.color,
      required this.known});

  final String lang;
  final String who;
  final Color color;
  final bool known;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: kDuoStagePanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: known
                ? color.withValues(alpha: 0.45)
                : const Color(0xFF33384A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(who,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 2),
          Text(lang,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: known ? color : Colors.white38,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// 만능 통역 — 아직 오간 말이 없을 때 가운데 그림.
class DuoInterpreterStage extends StatelessWidget {
  const DuoInterpreterStage({super.key, required this.recording});

  final bool recording;

  @override
  Widget build(BuildContext context) {
    final Color accent = recording ? kDuoStageLive : kDuoStageBlue;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: 116,
        height: 116,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: recording ? 0.18 : 0.10),
          shape: BoxShape.circle,
          border: Border.all(
              color: accent.withValues(alpha: recording ? 0.9 : 0.45),
              width: recording ? 2.0 : 1.2),
        ),
        child: Icon(Icons.g_translate_rounded,
            size: 48, color: accent.withValues(alpha: 0.95)),
      ),
    );
  }
}
