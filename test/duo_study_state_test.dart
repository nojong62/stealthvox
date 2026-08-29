import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

Uint8List frame(double amplitude, {int ms = 80}) {
  final int samples = ms * kStealthVoxSttBytesPerMs ~/ 2;
  final bytes = Uint8List(samples * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    final double v = math.sin(i * 0.05) * amplitude;
    view.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return bytes;
}

void main() {
  group('isStudyVisible', () {
    test('값이 없으면 보인다 — 옛 문서를 숨기지 않는다', () {
      expect(isStudyVisible(null), isTrue);
      expect(isStudyVisible(''), isTrue);
      expect(isStudyVisible('   '), isTrue);
    });

    test('included는 보인다', () {
      expect(isStudyVisible(kStudyStateIncluded), isTrue);
    });

    test('기술적 찌꺼기만 안 보인다 — 그래도 문서는 남아 있다', () {
      expect(isStudyVisible(kStudyStateHiddenEcho), isFalse);
      expect(isStudyVisible(kStudyStateHiddenHesitation), isFalse);
      expect(isStudyVisible(kStudyStateHiddenDuplicate), isFalse);
      expect(isStudyVisible(kStudyStateHiddenArtifact), isFalse);
      expect(isStudyVisible(kStudyStateMerged), isFalse);
    });

    test('숨김 상태는 전부 기술적 사유다 — 중요도로 숨기는 상태가 없다', () {
      for (final state in kStudyStateHidden) {
        expect(state.contains('value'), isFalse,
            reason: '$state — 말의 가치로 숨기는 상태를 만들면 안 된다');
        expect(state.contains('important'), isFalse, reason: state);
        expect(state.contains('key'), isFalse, reason: state);
      }
    });

    test('말 고르는 소리는 잡음과 다른 상태다 — 실제 음성이기 때문', () {
      expect(kStudyStateHiddenHesitation, isNot(kStudyStateHiddenArtifact));
    });

    test('모르는 상태는 보인다 — 옛 앱이 대화를 통째로 비우면 안 된다', () {
      expect(isStudyVisible('hidden_something_new'), isTrue);
    });
  });

  group('pcm16Rms', () {
    test('무음은 0이다', () {
      expect(pcm16Rms(frame(0.0)), 0.0);
    });

    test('사인파의 RMS는 진폭의 약 0.707배다', () {
      expect(pcm16Rms(frame(0.5)), closeTo(0.5 / math.sqrt2, 0.02));
    });

    test('빈 조각도 터지지 않는다', () {
      expect(pcm16Rms(Uint8List(0)), 0.0);
    });
  });
}
