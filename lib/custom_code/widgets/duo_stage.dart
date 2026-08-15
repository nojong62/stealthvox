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
const Color kDuoStageLive = Color(0xFF34D399);
const Color kDuoStageBlue = Color(0xFF2563EB);
const Color kDuoStageMine = Color(0xFF93C5FD);
const Color kDuoStageTheirs = Color(0xFF4ADE80);

/// 직접 대화 — 제공된 직접 통화 이미지를 화면 중앙에 표시한다.
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

    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 260),
          opacity: opacity,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * 0.72,
              maxHeight: constraints.maxHeight * 0.82,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/images/duo_direct_call.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
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

/// 만능 통역 — 제공된 통역기 이미지를 화면 중앙에 표시한다.
class DuoInterpreterStage extends StatelessWidget {
  const DuoInterpreterStage({super.key, required this.recording});

  final bool recording;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 260),
          opacity: recording ? 1 : 0.72,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * 0.72,
              maxHeight: constraints.maxHeight * 0.82,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/images/duo_interpreter.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
