// 🔵 [INTERP-LIVE] 만능 통역 무대 그림의 밝기 계약.
//
// 마이크가 세션 내내 열려 있게 되면서 "녹음 중인가"라는 순간이 사라졌다.
// 이제 화면이 대답해야 하는 질문은 하나뿐이다 — **지금 말해도 되는가.**
// 무대 그림과 마이크 상태등이 그 대답을 따로 하면 안 되므로, 그림 쪽 규칙을
// 여기에 못 박아 둔다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth_vox/custom_code/widgets/duo_stage.dart';

double _stageOpacity(WidgetTester tester) {
  final AnimatedOpacity widget = tester.widget<AnimatedOpacity>(
    find.descendant(
      of: find.byType(DuoInterpreterStage),
      matching: find.byType(AnimatedOpacity),
    ),
  );
  return widget.opacity;
}

Future<void> _pump(
  WidgetTester tester, {
  required bool ready,
  required bool partnerSpeaking,
}) {
  return tester.pumpWidget(MaterialApp(
    home: DuoInterpreterStage(
      ready: ready,
      partnerSpeaking: partnerSpeaking,
    ),
  ));
}

void main() {
  group('DuoInterpreterStage 밝기', () {
    testWidgets('준비 완료면 가장 밝다 — 지금 말하면 된다', (tester) async {
      await _pump(tester, ready: true, partnerSpeaking: false);
      expect(_stageOpacity(tester), 1.0);
    });

    testWidgets('준비 전에는 어둡다 — 말해도 전사로 가지 않는다', (tester) async {
      await _pump(tester, ready: false, partnerSpeaking: false);
      expect(_stageOpacity(tester), lessThan(1.0));
    });

    testWidgets('상대 말이 나가는 동안은 중간 밝기 — 내 차례가 아니다', (tester) async {
      await _pump(tester, ready: false, partnerSpeaking: true);
      final double playing = _stageOpacity(tester);

      await _pump(tester, ready: false, partnerSpeaking: false);
      final double waiting = _stageOpacity(tester);

      await _pump(tester, ready: true, partnerSpeaking: false);
      final double live = _stageOpacity(tester);

      // 대기 < 상대 재생 < 내 차례. 세 상태가 눈으로 구분돼야 한다.
      expect(waiting, lessThan(playing));
      expect(playing, lessThan(live));
    });

    testWidgets('재생 중에는 ready가 참이어도 내 차례로 보이지 않는다', (tester) async {
      // 게이트가 닫히기 직전/직후의 한 프레임에서도 화면이 "말하세요"로
      // 보이면 안 된다. 재생 표시가 ready보다 우선한다.
      await _pump(tester, ready: true, partnerSpeaking: true);
      expect(_stageOpacity(tester), lessThan(1.0));
    });
  });
}
