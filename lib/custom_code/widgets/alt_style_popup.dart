// ════════════════════════════════════════════════════════════════════
// 🔀 [ALT-STYLE] "다른 표현 보기" 버튼과 팝업
// --------------------------------------------------------------------
// 히스토리 말풍선과 Keepers 카드가 이 한 벌을 함께 쓴다. 화면마다 따로
// 그리면 같은 이름의 팝업이 서로 다르게 생기고, 무엇보다 스타일 목록이
// 갈라진다. 생성 규칙은 `services/alt_style.dart`에 있다.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '/custom_code/services/ai_style.dart';
import '/custom_code/services/alt_style.dart';

const Color kAltStyleAccent = Color(0xFF38BDF8);
const Color kAltStyleNameColor = Color(0xFFB46CFF);

/// 말풍선·카드 옆에 붙는 버튼.
///
/// translate 아이콘은 글리프에 한자(文)가 들어 있어 쓰지 않는다. 글자 없는
/// 교체 화살표로 "같은 뜻 다른 표현"을 나타낸다.
Widget buildAltStyleButton({
  required VoidCallback onPressed,
  double size = 26,
  EdgeInsets padding = const EdgeInsets.all(8),
  double minTouchSize = 44,
}) {
  return IconButton(
    padding: padding,
    constraints:
        BoxConstraints(minWidth: minTouchSize, minHeight: minTouchSize),
    icon: Icon(Icons.swap_horiz_rounded, color: kAltStyleAccent, size: size),
    onPressed: onPressed,
    tooltip: '다른 표현 보기',
  );
}

/// 같은 뜻을 스타일별로 늘어놓는 팝업.
///
/// 맨 위는 **지금 설정된 스타일과 원래 문장**이다. 그 아래로 나머지가 온다 —
/// 무엇과 견주는지가 먼저 보여야 나머지가 읽힌다.
///
/// 팝업 아무 곳이나 눌러도 닫힌다(실장님 요청). 바깥을 눌러도 닫힌다.
void showAltStylePopup({
  required BuildContext context,
  required String apiKey,
  required String baseText,
  required String targetLang,
}) {
  final styles = otherAiStyles(targetLang);
  if (styles.isEmpty) return;
  final future = fetchAltStyleSentences(
    apiKey: apiKey,
    baseText: baseText,
    styles: styles,
    targetLang: targetLang,
  );
  final currentStyle = effectiveAiStyle(targetLang: targetLang);

  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(dialogContext).pop(),
      child: Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        // 문장이 길면 4개가 화면을 넘긴다. 높이를 화면의 75%로 묶고
        // 안쪽을 스크롤시켜 마지막 스타일까지 볼 수 있게 한다.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: FutureBuilder<Map<String, String>>(
              future: future,
              builder: (ctx, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 90,
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kAltStyleAccent),
                    ),
                  );
                }
                final data = snapshot.data ?? <String, String>{};
                final entries = <MapEntry<String, String>>[
                  MapEntry(currentStyle, baseText.trim()),
                  ...styles
                      .where(data.containsKey)
                      .map((s) => MapEntry(s, data[s]!)),
                ];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '다른 표현 보기',
                      style: TextStyle(
                        color: kAltStyleAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (data.isEmpty)
                      const Text(
                        '표현을 불러오지 못했습니다. 다시 시도해 주세요.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            // 스타일 이름 한 줄, 다음 줄에 문장.
                            children: entries
                                .map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.key,
                                          style: const TextStyle(
                                            color: kAltStyleNameColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          e.value,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    const Center(
                      child: Text(
                        '탭하면 닫힙니다',
                        style: TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
