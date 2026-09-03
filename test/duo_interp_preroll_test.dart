// 🎚️ [INTERP-PREROLL] 만능 통역 상대 음성의 재생 시작 대기를 줄인다.
//
// 왜 여기인가 — 2026-09-03 실기기 10턴 실측:
//   toPlaybackMs 2.4~3.3초 중 **754ms가 프리롤**이었다. 매 턴에 붙는 고정
//   비용이라, 문장을 조각내는 것(조기 TTS)보다 효과가 확실하다. 실제로
//   조기 TTS는 같은 검증에서 10/10턴 `overlapped=false`로 효과가 없었다.
//
// 왜 24,000B인가 — 새로 지어낸 숫자가 아니다. 같은 64KB 링버퍼 위에서
// 첫 턴 유저 번역(`fastFirstTurnPrerollBytes`)이 이미 쓰던 값이다.
//
// 줄이면 무엇이 위험한가 — 언더런("몇 단어 하고 약간 쉬는" 증상)이다.
// 그래서 값만 줄이지 않고 **언더런을 세어 로그로 낸다.** 다음에 더 줄일지는
// 실기기 `underruns=` 숫자를 보고 정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';
import 'package:stealth_vox/custom_code/services/tts_adapter.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';
const String _tts = 'lib/custom_code/services/tts_adapter.dart';

void main() {
  final String duo = File(_duo).readAsStringSync().replaceAll('\r\n', '\n');
  final String tts = File(_tts).readAsStringSync().replaceAll('\r\n', '\n');

  int ms(int bytes) =>
      pcm16DurationMs(bytes, sampleRate: TtsAdapterConfig.sampleRate);

  group('값 — 754ms에서 500ms로', () {
    test('상대 음성 프리롤은 0.5초다', () {
      expect(TtsAdapterConfig.duoPartnerPrerollBytes, 24000);
      expect(ms(TtsAdapterConfig.duoPartnerPrerollBytes), 500);
    });

    test('기존 값(0.75초)에서 250ms를 아낀다', () {
      final int saved = ms(TtsAdapterConfig.prerollBytes) -
          ms(TtsAdapterConfig.duoPartnerPrerollBytes);
      expect(saved, 250);
    });

    test('이미 검증된 값을 그대로 쓴다 — 새 숫자를 지어내지 않았다', () {
      expect(TtsAdapterConfig.duoPartnerPrerollBytes,
          TtsAdapterConfig.fastFirstTurnPrerollBytes,
          reason: '같은 링버퍼 위에서 이미 쓰이던 값이어야 근거가 있다');
    });

    test('공용 기본값은 안 건드렸다 — 다른 경로는 그대로 0.75초다', () {
      // 서클톡·시나리오톡·AI 음성이 이 값을 쓴다. 이번 변경은 듀오 전용이다.
      expect(TtsAdapterConfig.prerollBytes, 36000);
      expect(ms(TtsAdapterConfig.prerollBytes), 750);
    });

    test('링버퍼 안에 들어간다', () {
      // 프리롤은 한 번에 밀어넣으므로 링버퍼보다 크면 그 자리에서 잘린다.
      expect(TtsAdapterConfig.duoPartnerPrerollBytes,
          lessThan(TtsAdapterConfig.playerBufferSize));
      expect(tts, contains('bufferSize: TtsAdapterConfig.playerBufferSize'),
          reason: '플레이어가 이 링버퍼로 열리지 않으면 위 비교가 헛것이다');
    });
  });

  group('실제로 걸려 있다', () {
    test('상대 음성 요청 두 곳 모두 이 값을 넘긴다', () {
      // `_speakPartner`(상시 경로)와 `_handleIncomingStreaming`(조기 TTS,
      // 지금은 꺼져 있음) 둘 다다. 한쪽만 걸면 플래그를 켰을 때 값이 달라져
      // 실기기 숫자를 비교할 수 없게 된다.
      final int partnerRequests =
          RegExp(r"playbackCategory: 'duo_partner'").allMatches(duo).length;
      final int withPreroll =
          RegExp(r'prerollBytes: TtsAdapterConfig\.duoPartnerPrerollBytes')
              .allMatches(duo)
              .length;
      expect(partnerRequests, 2);
      expect(withPreroll, partnerRequests,
          reason: '상대 음성 요청 중 프리롤을 안 넘기는 자리가 남았다');
    });

    test('상대 음성 요청에만 걸었다', () {
      // 직접 대화는 TTS를 쓰지 않는다(상대 목소리를 그대로 듣는다).
      // 다른 카테고리에 섞여 들어갔는지 본다.
      for (final m
          in RegExp(r'prerollBytes: TtsAdapterConfig\.duoPartnerPrerollBytes')
              .allMatches(duo)) {
        final String near =
            duo.substring((m.start - 600).clamp(0, duo.length), m.end);
        expect(near, contains("playbackCategory: 'duo_partner'"));
      }
    });

    test('요청별 프리롤을 받는 자리가 살아 있다', () {
      expect(tts,
          contains('request.prerollBytes ?? TtsAdapterConfig.prerollBytes'),
          reason: '요청값이 무시되면 상수만 바꾼 셈이 된다');
    });
  });

  group('언더런 방어 — 값만 줄이지 않는다', () {
    test('버퍼가 마른 것을 센다', () {
      expect(tts, contains('void noteBufferHealth()'));
      expect(tts, contains('underrunCount++'));
      expect(tts, contains('recoveryCount++'));
    });

    test('판정 잣대는 remainingPlaybackMs다 — 프리롤을 처음 정할 때와 같다', () {
      final int at = tts.indexOf('void noteBufferHealth()');
      expect(at, greaterThan(-1));
      expect(tts.substring(at, at + 600),
          contains('_pcmPlayer.remainingPlaybackMs()'));
    });

    test('먹이기 전후로 본다 — 가장 얇을 때와 가장 두꺼울 때', () {
      // 먹인 뒤에만 보면 짧은 결핍이 새 청크에 가려 안 보인다.
      final int feed = tts.indexOf('await _pcmPlayer.feed(chunk);');
      expect(feed, greaterThan(-1));
      final String before = tts.substring((feed - 400).clamp(0, tts.length), feed);
      final String after = tts.substring(feed, feed + 200);
      expect(before, contains('noteBufferHealth();'), reason: '먹이기 직전 확인이 없다');
      expect(after, contains('noteBufferHealth();'), reason: '먹인 직후 확인이 없다');
    });

    test('마를 때마다 세지 않는다 — 한 번 마른 구간은 한 번이다', () {
      // 청크마다 세면 한 번 끊긴 것이 수십 번으로 부풀어 판단을 그르친다.
      final int at = tts.indexOf('void noteBufferHealth()');
      final String body = tts.substring(at, at + 600);
      expect(body, contains('if (!wasDry)'));
      expect(body, contains('wasDry = true'));
      expect(body, contains('wasDry = false'));
    });

    test('언더런은 그 자리에서 한 줄 남는다', () {
      expect(tts, contains('UNDERRUN turnId='));
    });
  });

  group('성적표', () {
    test('실기기에서 볼 값이 다 들어 있다', () {
      const List<String> fields = <String>[
        'turnId',
        'targetPrerollMs',
        'actualPrerollMs',
        'bufferedMsAtStart',
        'ttsTtfbMs',
        'playbackStartMs',
        'underrunCount',
        'recoveryCount',
      ];
      for (final String f in fields) {
        expect(tts, contains('this.$f'), reason: '$f 이(가) 성적표에 없다');
      }
    });

    test('bufferedMsAtStart는 플레이어에게 직접 물어본다', () {
      // 프리롤 바이트를 ms로 환산한 값과 같아야 정상이다. 같은 값을 두 번
      // 적으면 어긋남을 영영 못 본다.
      expect(tts,
          contains('bufferedMsAtStart = _pcmPlayer.remainingPlaybackMs()'));
      expect(
          tts,
          isNot(contains(
              'bufferedMsAtStart: pcm16DurationMs(prerollActualBytes')),
          reason: '실측이 아니라 되풀이라면 검증 가치가 없다');
    });

    test('이어붙인 조각에서는 내지 않는다', () {
      // 이어붙임은 프리롤을 쌓지 않는다. 0으로 찍히면 "0이어도 됐다"로 읽힌다.
      expect(tts, contains('if (!continuing && onPrerollReport != null)'));
    });

    test('짧은 음성(목표 미달)에서도 재생하고 성적표를 낸다', () {
      // 스트림이 목표량 전에 끝나는 경우. 여기서 안 틀면 소리가 통째로 사라진다.
      final int end = tts.indexOf('reason=stream_end');
      final int report = tts.indexOf('onPrerollReport!(TtsPrerollReport(');
      expect(end, greaterThan(-1));
      expect(report, greaterThan(end),
          reason: '짧은 음성 경로가 성적표보다 뒤에 있으면 보고를 건너뛴다');
    });

    test('듀오가 성적표를 [INTERP-PREROLL]로 찍는다', () {
      expect(duo, contains("'[INTERP-PREROLL]'"));
      final int at = duo.indexOf("'[INTERP-PREROLL]'");
      final String block = duo.substring(at, at + 500);
      for (final String key in <String>[
        'turn=',
        'targetMs=',
        'actualMs=',
        'bufferedMs=',
        'ttsTtfbMs=',
        'playbackStartMs=',
        'underruns=',
        'recoveries=',
      ]) {
        expect(block, contains(key), reason: '$key 가 로그에 없다');
      }
    });
  });

  group('기존 동작을 깨지 않는다', () {
    test('재생 시작 알림(에코 게이트)은 프리롤을 채운 뒤다', () {
      // 게이트를 여기서 닫는다. 순서가 바뀌면 자기 목소리를 다시 듣는다.
      final int at = tts.indexOf('onPlaybackStart?.call(request);');
      expect(at, greaterThan(-1));
      final String before = tts.substring((at - 500).clamp(0, tts.length), at);
      expect(before, contains('_pcmPlayer.begin('));
    });

    test('조기 TTS는 여전히 꺼져 있다 — 이번 변경과 섞지 않는다', () {
      expect(
          duo,
          contains("bool.fromEnvironment('DUO_INTERP_STREAM_TTS', "
              "defaultValue: false)"));
    });
  });
}
