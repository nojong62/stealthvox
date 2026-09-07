// 🚨 [INTERP-GATE] 게이트를 닫기 **전에** 말을 확정한다 — 순서가 전부다
//
// 통역은 상대 목소리가 재생되는 동안 마이크 게이트를 닫는다(`tts_playing`).
// 그 소리를 되받아 전사하지 않기 위해서다.
//
// 그런데 `closeAudioGate`는 안에서 `_capture.abort()`를 부른다. 닫고 나서
// flush하면 **이미 버려진 뒤라 아무것도 못 살린다.** 로그에는
// `flush_on_close … 말하던 중이었다`가 남는데 정작 저장되는 것이 없다.
//
// 2026-09-07 실기기 통역에서 그 일이 났다.
//
//   21:49:08  utt_1 speech_started              게스트가 말하기 시작
//   21:49:11  [INTERP-DATA] receive seq=1       호스트 메시지 도착
//   21:49:14  audio_gate=close reason=tts_playing
//   21:49:14  [INTERP-GATE] flush_on_close — 말하던 중이었다   ← 사라짐
//   …
//   closing started=2 ended=1                   두 번 열렸는데 한 번만 닫힘
//
// 호스트에는 게스트 말이 **한 글자도** 안 갔다. 게스트는 호스트 말을 듣고 바로
// 대답하니 재생 구간과 정확히 겹친다 — 구조적으로 게스트 대답이 잘 사라진다.
//
// 위젯 안 메서드라 단위 테스트로 못 돌린다. 다른 흐름 시험과 같은 방식으로
// **순서가 그 자리에 있는지**를 소스에서 지킨다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// `_closeInterpGate` 본문만 떼어 낸다. 다음 메서드 선언 앞까지다.
String _closeInterpGateBody(String duo) {
  final int start = duo.indexOf('void _closeInterpGate(String reason) {');
  final int end = duo.indexOf('\n  /// item_id 없이 온 전사문이', start);
  if (start < 0 || end <= start) return '';
  return duo.substring(start, end);
}

void main() {
  final String duo = _read(_duo);
  final String body = _closeInterpGateBody(duo);

  group('🚨 확정이 먼저, 닫는 것이 나중이다', () {
    test('본문을 찾을 수 있다 — 못 찾으면 아래 검사가 무의미하다', () {
      expect(body, isNotEmpty, reason: '_closeInterpGate 본문을 못 떼어 냈다');
    });

    test('두 호출이 다 있다', () {
      expect(body, contains('flushPendingUtterance'));
      expect(body, contains('stt.closeAudioGate(reason: reason)'));
    });

    test('flush가 closeAudioGate보다 앞에 온다', () {
      final int flushAt = body.indexOf('flushPendingUtterance');
      final int closeAt = body.indexOf('stt.closeAudioGate(reason: reason)');
      expect(flushAt, greaterThan(0));
      expect(closeAt, greaterThan(0));
      expect(flushAt, lessThan(closeAt),
          reason: '닫고 나서 flush하면 이미 버려진 뒤라 아무것도 못 살린다');
    });

    test('닫기는 말하던 중이 아니어도 반드시 돈다', () {
      // flush는 말하던 중일 때만이지만, 닫기는 조건 밖에 있어야 한다.
      // 안 그러면 조용할 때 게이트가 안 닫혀 상대 목소리를 되받아 전사한다.
      final int ifAt = body.indexOf('if (wasSpeaking) {');
      final int closeAt = body.indexOf('stt.closeAudioGate(reason: reason)');
      expect(ifAt, greaterThan(0));
      expect(closeAt, greaterThan(ifAt),
          reason: '닫기는 if 블록 뒤에 있어야 한다');
    });

    test('이미 닫혀 있으면 flush하지 않는다', () {
      // 상대 메시지가 연달아 오면 재생마다 이 함수가 불린다. 앞 재생이
      // 닫아 둔 상태에서 또 확정하면 같은 버퍼를 두 번 확정하려 든다.
      expect(body, contains('final bool wasOpen = stt.audioGateOpen;'));
      expect(body,
          contains('final bool wasSpeaking = wasOpen && stt.hasPendingUtterance;'));
    });

    test('기다리지 않는다 — 재생이 flush를 붙들면 안 된다', () {
      expect(body, contains('unawaited('));
    });
  });

  group('📌 왜 이 순서인지 코드에 적혀 있다', () {
    test('closeAudioGate가 버린다는 사실을 적어 뒀다', () {
      expect(duo, contains('`closeAudioGate`는 안에서 `_capture.abort()`를 부른다'));
    });

    test('실기기 사례를 남겨 뒀다 — 되돌리려는 사람이 읽게', () {
      expect(duo, contains('2026-09-07 실기기 통역에서 그 일이 났다'));
      expect(duo, contains('started=2 ended=1'));
    });
  });
}
