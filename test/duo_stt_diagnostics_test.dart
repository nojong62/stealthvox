// 🔬 [DUO-DIAG] 진단 로그가 (1) 세 칸 비교를 가능하게 하고 (2) release에는
// 한 글자도 안 나가는지 확인한다.
//
// 세 칸이란 이것이다.
//   ① 사람이 실제로 말한 문장 — 사람이 눈으로 확인
//   ② GPT raw transcript      — [DuoSTT-RAW] text=
//   ③ 최종 저장 transcript     — [DuoSTT-DECISION] finalText=

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_transcript_gate.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

void main() {
  final String duo =
      File(_duo).readAsStringSync().replaceAll('\r\n', '\n');

  group('전사문이 실린 로그는 개발 빌드에서만 나간다', () {
    test('_lgDuoDev는 진단이 꺼져 있으면 아무것도 찍지 않는다', () {
      expect(
          duo,
          contains('void _lgDuoDev(String tag, String msg) {\n'
              '    if (!_duoDiagOn) return;'));
    });

    test('진단 스위치는 한 곳에서만 판단한다', () {
      // 여기저기서 kDebugMode를 따로 물으면 나중에 한쪽만 바뀌어 반쪽만 켜진다.
      expect(
          duo,
          contains('static bool get _duoDiagOn => '
              'foundation.kDebugMode || kDuoSttDiagForced;'));
      // `_duoDiagOn` 정의 한 줄 말고는 kDebugMode를 직접 보는 곳이 없어야 한다.
      expect(RegExp('foundation.kDebugMode').allMatches(duo).length, 1);
    });

    test('release 강제 스위치의 기본값은 꺼짐이다', () {
      final String probe =
          File('lib/custom_code/services/duo_stt_ab_probe.dart')
              .readAsStringSync()
              .replaceAll('\r\n', '\n');
      expect(
          probe,
          contains("bool.fromEnvironment('DUO_STT_DIAG', defaultValue: false)"),
          reason: '기본값이 켜짐이면 평범한 배포 빌드가 전사문을 logcat에 흘린다');
    });

    test('전사문을 싣는 두 로그는 _lgDuoDev로만 나간다', () {
      // `text="`(raw)와 `finalText="`(decision)이 들어간 곳은 dev 로거뿐이어야 한다.
      for (final String needle in <String>['text="\${text.trim()}"']) {
        final int at = duo.indexOf(needle);
        expect(at, greaterThan(-1), reason: '$needle 로그가 사라졌다');
        // 그 로그를 감싸는 함수가 _lgDuoDev를 부르는지 앞쪽에서 확인한다.
        final String before = duo.substring(0, at);
        expect(before.lastIndexOf('_lgDuoDev('),
            greaterThan(before.lastIndexOf('void _lgDirectSttRaw')),
            reason: 'raw 로그가 dev 게이트를 지나지 않는다');
      }
    });

    test('release 로그(_lgDuo)에는 전사문이 실리지 않는다', () {
      // 버림 로그는 release에도 남지만 길이와 사유만 남긴다.
      expect(duo, contains("'noise_gate=\$noiseReason item=\$itemId len="));
      expect(duo, contains("'dropped item=\$itemId voicedMs=\$voicedMs"));
    });
  });

  group('게이트 순서 — 길이 → 세기 → 잡음 → 저장', () {
    test('세기 게이트가 길이 게이트 뒤, 잡음 필터 앞에 선다', () {
      final int voiced = duo.indexOf('belowVoicedGate(voicedMs');
      final int level = duo.indexOf('belowLevelGate(rmsDbfs');
      final int noise = duo.indexOf('noiseTranscriptReason(trimmed)');
      expect(voiced, greaterThan(-1));
      expect(level, greaterThan(voiced), reason: '길이 게이트가 먼저다');
      expect(noise, greaterThan(level), reason: '잡음 필터는 세기 뒤다');
    });

    test('세기는 진단기가 아니라 전용 계측기에서 읽는다', () {
      // 진단이 꺼진 release에서도 게이트가 살아야 한다.
      expect(duo, contains('_utteranceRms?.rmsDbfsOf(itemId)'));
      expect(duo, isNot(contains('_sttAbProbe?.rmsDbfsOf')));
    });

    test('계측기는 진단 스위치와 무관하게 만들어진다', () {
      final int at = duo.indexOf('_utteranceRms = DuoUtteranceRmsMeter();');
      expect(at, greaterThan(-1));
      // 그 줄이 _duoDiagOn 삼항 안에 들어가 있으면 release에서 null이 된다.
      final int lineStart = duo.lastIndexOf('\n', at) + 1;
      final String line = duo.substring(lineStart, at + 60);
      expect(line, isNot(contains('_duoDiagOn')));
    });

    test('마이크 조각은 진단 갈래와 별도로 계측 갈래에도 간다', () {
      expect(duo, contains('toLevel: (bytes) => _utteranceRms?.addPcm(bytes)'));
    });

    test('재접속과 통화 종료에 누적이 비워진다', () {
      expect(duo, contains('session.onReconnecting'));
      expect(duo, contains('_utteranceRms?.reset()'));
    });
  });

  group('모든 drop 지점이 사유를 남긴다', () {
    test('reason 상수가 전부 호출부에서 쓰인다', () {
      for (final String name in <String>[
        'DuoDropReason.staleGeneration',
        'DuoDropReason.voicedMs',
        'DuoDropReason.duplicateItem',
        'DuoDropReason.accepted',
        'DuoDropReason.historyWriteFailed',
        'DuoDropReason.lowLevel',
      ]) {
        expect(duo, contains(name), reason: '$name 을 남기는 자리가 없다');
      }
      // empty_text / empty_after_clean / hard_ghost 는 noiseTranscriptReason이
      // 돌려주는 값이 그대로 실린다.
      expect(duo, contains('reason: noiseReason'));
    });

    test('accepted 판정은 히스토리 저장 뒤에 찍힌다', () {
      final int save = duo.indexOf('channelMsgId: channelId,');
      final int accepted = duo.indexOf('accepted: true');
      expect(save, greaterThan(-1));
      expect(accepted, greaterThan(save),
          reason: '저장 전에 accepted를 찍으면 실패한 저장도 성공으로 보인다');
    });

    test('히스토리 쓰기 실패가 더는 빈 catch로 사라지지 않는다', () {
      expect(duo, contains("'save_failed(\${e.runtimeType}) role=\$role"));
    });
  });

  group('진단 로그 형식', () {
    test('[DuoSTT-RAW]에 화자·언어·voicedMs·원문이 다 있다', () {
      final int at = duo.indexOf("'[DuoSTT-RAW]'");
      expect(at, greaterThan(-1));
      final String block = duo.substring(at, at + 400);
      for (final String field in <String>[
        'speaker=',
        'language=',
        'voicedMs=',
        'voicedSrc=',
        'item=',
        'text="',
      ]) {
        expect(block, contains(field));
      }
      // 언어가 비어 있으면 'auto'로 적는다 — 빈칸은 로그에서 못 읽는다.
      expect(block, contains("languageCode.isEmpty ? 'auto' : languageCode"));
    });

    test('[DuoSTT-DECISION]에 accepted/reason/finalText가 다 있다', () {
      final int at = duo.indexOf("'[DuoSTT-DECISION]'");
      expect(at, greaterThan(-1));
      final String block = duo.substring(at, at + 300);
      for (final String field in <String>[
        'speaker=',
        'accepted=',
        'reason=',
        'finalText="',
      ]) {
        expect(block, contains(field));
      }
    });

    test('voiced_ms 사유에는 실제 값과 문턱이 같이 붙는다', () {
      expect(duo, contains('voicedMs=\$voicedMs '));
      expect(duo, contains('min=\$kDuoMinVoicedMs'));
    });

    test('low_level 로그는 release에도 남고 전사문은 싣지 않는다', () {
      // 문턱을 다시 잡을 근거가 이 숫자다. 원문은 필요 없다.
      final int at = duo.indexOf("reason=\${DuoDropReason.lowLevel} speaker=");
      expect(at, greaterThan(-1));
      final String block = duo.substring(at, at + 300);
      for (final String field in <String>[
        'speaker=',
        'item=',
        'rmsDbfs=',
        'threshold=',
        'voicedMs=',
      ]) {
        expect(block, contains(field));
      }
      expect(block, isNot(contains('text=')));
      expect(block, isNot(contains('finalText=')));
      // 진단 게이트(_lgDuoDev)가 아니라 release 로거로 나간다.
      final String before = duo.substring(0, at);
      expect(before.lastIndexOf('_lgDuo('),
          greaterThan(before.lastIndexOf('_lgDuoDev(')));
    });
  });

  group('필터는 옮기기만 했고 판정은 그대로다', () {
    test('_isNoiseTranscript는 noiseTranscriptReason의 얇은 껍데기다', () {
      expect(
          duo,
          contains('bool _isNoiseTranscript(String raw) => '
              'noiseTranscriptReason(raw) != null;'));
      // 옮긴 뒤에도 같은 문장을 같은 사유로 버린다.
      expect(noiseTranscriptReason('Thank you for watching'),
          DuoDropReason.hardGhost);
      expect(noiseTranscriptReason('네'), isNull);
    });
  });
}
