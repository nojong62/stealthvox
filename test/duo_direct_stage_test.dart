// 🔴 [DUO-LIVE] 직접 대화 불빛은 "상대가 입장했다"가 아니라
// "지금 말하면 원음 전달·녹음·글자 저장이 모두 된다"를 뜻한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stealth_vox/custom_code/widgets/duo_stage.dart';

Map<String, bool> _allReady() => <String, bool>{
  'partnerOnline': true,
  'callActive': true,
  'muted': false,
  'transportConnected': true,
  'partnerAudioConnected': true,
  'micActive': true,
  'pcmFlowing': true,
  'sttActive': true,
  'sttConnected': true,
  'audioGateOpen': true,
};

bool _ready(Map<String, bool> s) => duoDirectReadyToTalk(
  partnerOnline: s['partnerOnline']!,
  callActive: s['callActive']!,
  muted: s['muted']!,
  transportConnected: s['transportConnected']!,
  partnerAudioConnected: s['partnerAudioConnected']!,
  micActive: s['micActive']!,
  pcmFlowing: s['pcmFlowing']!,
  sttActive: s['sttActive']!,
  sttConnected: s['sttConnected']!,
  audioGateOpen: s['audioGateOpen']!,
);

double _stageOpacity(WidgetTester tester) {
  return tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
}

void main() {
  group('duoDirectReadyToTalk', () {
    test('원음·PCM·STT·게이트가 모두 준비된 때만 true', () {
      expect(_ready(_allReady()), isTrue);
    });

    for (final blocker in <String>[
      'partnerOnline',
      'callActive',
      'transportConnected',
      'partnerAudioConnected',
      'micActive',
      'pcmFlowing',
      'sttActive',
      'sttConnected',
      'audioGateOpen',
    ]) {
      test('$blocker가 아직이면 false', () {
        final state = _allReady()..[blocker] = false;
        expect(_ready(state), isFalse);
      });
    }

    test('음소거중이면 false', () {
      final state = _allReady()..['muted'] = true;
      expect(_ready(state), isFalse);
    });
  });

  group('DuoDirectStage 밝기', () {
    testWidgets('실제 대화 준비 완료 후에만 가장 밝다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DuoDirectStage(ready: true, partnerOnline: true),
        ),
      );
      expect(_stageOpacity(tester), 1.0);
    });

    testWidgets('상대가 입장해도 녹음 준비 전이면 어둡다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DuoDirectStage(ready: false, partnerOnline: true),
        ),
      );
      expect(_stageOpacity(tester), lessThan(1.0));
    });
  });
}
