// 🔁 [RECONNECT] STT 소켓이 끊겨도 통역 마이크는 죽지 않는다
//
// 예전 구조는 이랬다:
//
//   재연결 5회 실패(0.5+1+2+4+8 = 15.5초)
//     → onGaveUp / onFatalError
//     → 통역의 onFatalError가 `_stopInterpreterCapture('stt_fatal')`
//     → 마이크·MicTap·WebRTC 통화까지 접힘 → **통역 영구 정지**
//
// 셀룰러로 이동하면서 15초 흔들리면 반드시 걸린다. 유저는 방에 그대로
// 있는데 마이크만 잠겨 있고, 스스로 돌아오지 않는다.
//
// 이제 끝내는 것은 **횟수가 아니라 `shouldReconnect` 게이트**다. 게이트는
// 방을 나갔거나 세대가 바뀌었을 때만 닫힌다. 그 사이에는 10초마다 계속
// 붙어 보고, 붙는 순간 오디오 게이트가 다시 열려 파이프라인이 살아난다.
//
// 🚫 다만 **재시도로 안 풀리는 실패**는 갈라 둔다. 401·403·빈 열쇠는
//   영원히 두드려도 그대로이므로 기존 fatal 정책으로 보낸다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/openai_streaming_transcribe_session.dart';

const String _stt = 'lib/custom_code/services/openai_streaming_transcribe_session.dart';
const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';
const String _call = 'lib/custom_code/services/duo_webrtc_call.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// [start]부터 [end] 직전까지의 소스 조각.
String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 자리: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 자리: $end');
  return src.substring(a, b);
}

/// 주석을 걷어낸 실행되는 줄만. 주석에 적힌 낱말이 판정을 흐리지 않게.
String _code(String src) => src
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///');
    })
    .join('\n');

void main() {
  final String stt = _read(_stt);
  final String duo = _read(_duo);
  final String call = _read(_call);

  /// 통역이 전사 세션을 만들고 콜백을 다는 구역.
  String interpSession() => _region(
      duo,
      'session.shouldReconnect = () =>\n'
          '        !_isExiting && _isConversationActive',
      'final ok = await session.connect();');

  /// 직접 대화 쪽의 같은 구역.
  String directSession() => _region(
      duo,
      'session.shouldReconnect = () => _isDirectGenerationCurrent(generation);',
      'final ok = await session.connect();');

  // ── ③ 횟수로 포기하지 않는다 ────────────────────────────────────────
  group('③ 5회 이상 실패해도 세션이 죽지 않는다', () {
    test('횟수 상한 상수가 사라졌다', () {
      expect(stt, isNot(contains('kStreamingSttMaxRetries')),
          reason: '15.5초 뒤 영구 포기하던 그 상수다');
    });

    test('재연결 구역에 횟수 비교가 없다', () {
      final String body =
          _code(_region(stt, 'Future<void> _reconnect(String reason) async {',
              'Future<void> _teardownSocket() async {'));
      for (final String cmp in <String>[
        '_retryCount >=',
        '_retryCount >',
        '_retryCount ==',
      ]) {
        expect(body, isNot(contains(cmp)),
            reason: '$cmp — 횟수가 다시 종료 조건이 됐다');
      }
    });

    test('끝내는 것은 게이트뿐이다', () {
      final String body =
          _region(stt, 'Future<void> _reconnect(String reason) async {',
              'Future<void> _teardownSocket() async {');
      // 늦게 닫히는 경우까지 보려면 지연 전후로 두 번 물어야 한다.
      expect('gate_closed'.allMatchesIn(body), 2,
          reason: '지연 전과 후, 두 번 확인해야 방을 나간 즉시 멈춘다');
    });

    test('로그만 줄이고 재시도는 계속한다', () {
      expect(stt, contains('kStreamingSttQuietLogAfter'));
      expect(stt, contains('**포기하는 횟수가 아니다.**'),
          reason: '다음 사람이 이 상수를 다시 상한으로 오해한다');
    });
  });

  // ── 백오프 사다리 (순수 함수) ───────────────────────────────────────
  group('백오프는 늘다가 상한에서 멈춘다', () {
    test('0.5 → 1 → 2 → 4 → 8 → 10 → 10초', () {
      expect(
          <int>[1, 2, 3, 4, 5, 6, 7]
              .map((n) => streamingSttBackoff(n).inMilliseconds)
              .toList(),
          <int>[500, 1000, 2000, 4000, 8000, 10000, 10000]);
    });

    test('아무리 오래 끊겨도 10초를 넘지 않는다', () {
      for (final int n in <int>[8, 20, 31, 32, 100, 100000]) {
        expect(streamingSttBackoff(n), kStreamingSttBackoffCeiling,
            reason: 'attempt=$n');
      }
    });

    test('큰 횟수에서 int가 넘치지 않는다', () {
      // 1 << 62 는 음수가 된다. 그러면 delay가 음수가 되어 재시도가
      // 폭주한다 — 상한 밖으로 새는 값이 하나도 없어야 한다.
      for (final int n in <int>[62, 63, 64, 1 << 20]) {
        expect(streamingSttBackoff(n).inMilliseconds, 10000, reason: 'n=$n');
        expect(streamingSttBackoff(n).isNegative, isFalse);
      }
    });

    test('첫 시도는 0.5초, 0이나 음수도 안전하다', () {
      expect(streamingSttBackoff(1).inMilliseconds, 500);
      expect(streamingSttBackoff(0).inMilliseconds, 500);
      expect(streamingSttBackoff(-3).inMilliseconds, 500);
    });
  });

  // ── 일시적 오류 vs 재시도로 안 풀리는 오류 ──────────────────────────
  group('재시도로 풀릴 실패와 아닌 실패를 가른다', () {
    test('401·403만 영구 실패다', () {
      expect(streamingSttPermanentReason(const WebSocketException('x', 401)),
          'auth_401');
      expect(streamingSttPermanentReason(const WebSocketException('x', 403)),
          'auth_403');
    });

    test('끊김·서버 흔들림·한도는 계속 붙어 본다', () {
      expect(streamingSttPermanentReason(const SocketException('unreachable')),
          isNull);
      expect(streamingSttPermanentReason(const WebSocketException('x', 429)),
          isNull,
          reason: '한도는 기다리면 풀린다');
      for (final int code in <int>[500, 502, 503, 504, 408]) {
        expect(streamingSttPermanentReason(WebSocketException('x', code)),
            isNull,
            reason: 'HTTP $code 는 서버가 흔들린 것이다');
      }
    });

    test('상태 코드가 없는 실패는 일시적으로 본다', () {
      // 핸드셰이크 전에 끊기면 코드가 없다. 모를 때는 붙어 보는 쪽이 낫다.
      expect(streamingSttPermanentReason(const WebSocketException('closed')),
          isNull);
      expect(streamingSttPermanentReason(TimeoutException_()), isNull);
    });

    test('빈 열쇠는 붙어 볼 것도 없다', () {
      expect(stt, contains("_permanentFailure = 'no_api_key';"));
    });

    test('영구 실패에서만 fatal로 넘어간다', () {
      final String end = _region(stt, 'void _endReconnectLoop() {',
          'Future<void> _teardownSocket() async {');
      expect(end, contains('onGaveUp?.call();'));
      expect(end, contains('onFatalError?.call(why);'));
      // 부르는 자리는 둘 — 지연 전 확인과, connect 실패 직후.
      expect('_endReconnectLoop();'.allMatchesIn(stt), 2);
    });

    test('붙는 순간 영구 실패 기록을 지운다', () {
      expect(stt, contains('_permanentFailure = null;'),
          reason: '지우지 않으면 한 번 401이 난 세션은 영영 안 붙는다');
    });
  });

  // ── ①④ 끊겼다 붙으면 스스로 돌아온다 ───────────────────────────────
  group('①④ 복구되면 파이프라인이 자동으로 살아난다', () {
    test('붙어 있던 게이트는 다시 열린다', () {
      final String body =
          _region(stt, 'Future<void> _reconnect(String reason) async {',
              'Future<void> _teardownSocket() async {');
      expect(body, contains('if (_audioGateOpen) _reopenGateAfterReconnect = true;'));
      expect(body, contains("openAudioGate(reason: 'reconnected');"));
    });

    // 실기기 2026-10-13: 첫 시도가 실패하면 다음 시도가 이미 닫힌 게이트를
    // 다시 읽어 "안 듣고 있었다"로 기억했다. 1초 넘는 끊김마다 다시 붙어도
    // 마이크가 영영 안 열렸다("통역 준비 중"에서 멈춤).
    test('여러 번 실패한 뒤 붙어도 게이트가 열린다 — 의도를 사슬 끝까지 들고 간다', () {
      final String body =
          _region(stt, 'Future<void> _reconnect(String reason) async {',
              'Future<void> _teardownSocket() async {');
      expect(body, isNot(contains('wasGateOpen')),
          reason: '시도마다 지역 변수로 읽으면 두 번째 시도부터 false가 된다');
      expect(body, contains('if (ok && _reopenGateAfterReconnect) {'));
    });

    test('끊긴 동안 호출부가 닫으면 다시 붙어도 열지 않는다', () {
      final String close = _region(stt, 'void closeAudioGate({required String reason}) {',
          'void appendAudio(');
      expect(close.indexOf('_reopenGateAfterReconnect = false;'),
          lessThan(close.indexOf('if (!_audioGateOpen) return;')),
          reason: '이미 닫힌 상태에서 일찍 돌아가면 의도가 남아 TTS 중에 열린다');
    });

    test('방 재입장 없이 같은 세션이 이어진다', () {
      // 통역은 세션을 다시 만들지 않는다. 소켓만 갈아 끼운다.
      expect(interpSession(), isNot(contains('OpenAiStreamingTranscribeSession(')),
          reason: '재연결이 새 세션을 만들면 콜백과 세대가 다 끊긴다');
    });

    test('화면은 붙는 순간 스스로 돌아온다', () {
      expect(interpSession(), contains('session.onConnected = () {'));
      expect(interpSession(), contains('_interpSttReconnecting = false'));
    });
  });

  // ── ② 끊긴 동안 마이크와 MicTap은 그대로 ────────────────────────────
  group('② 소켓이 끊겨도 마이크·MicTap을 닫지 않는다', () {
    test('재연결 핸들러는 마이크를 건드리지 않는다', () {
      final String body = _region(interpSession(),
          'session.onReconnecting = (attempt) {', 'session.onConnected = () {');
      for (final String forbidden in <String>[
        '_stopInterpreterCapture',
        '_interpMicTap',
        'InterpMicPhase.preparing',
        'InterpMicPhase.ended',
        '.dispose()',
      ]) {
        expect(body, isNot(contains(forbidden)),
            reason: '$forbidden — 끊김이 마이크를 닫으면 스스로 안 돌아온다');
      }
    });

    test('끊김은 "실패"가 아니라 "다시 잇는 중"이다', () {
      final String body = _region(interpSession(),
          'session.onReconnecting = (attempt) {', 'session.onConnected = () {');
      expect(body, contains('_interpSttReconnecting = true'));
      expect(body, isNot(contains('_interpStartFailed = true')));
    });

    test('끊긴 동안 미뤄 둔 상대 음성이 갇히지 않는다', () {
      final String body = _region(interpSession(),
          'session.onReconnecting = (attempt) {', 'session.onConnected = () {');
      expect(body, contains('_drainIncoming()'),
          reason: 'isUserSpeaking이 참으로 굳으면 상대 말이 영영 안 나온다');
    });

    test('끊김 로그가 마이크 종료를 말하지 않는다', () {
      expect(duo, isNot(contains('마이크를 닫고 대기로 돌린다')));
    });
  });

  // ── 끊긴 동안의 소리는 쌓지도 몰아 보내지도 않는다 ──────────────────
  group('끊긴 동안의 오디오는 버린다', () {
    test('재연결이 시작되면 오디오 게이트부터 닫는다', () {
      final String body =
          _region(stt, 'Future<void> _reconnect(String reason) async {',
              'Future<void> _teardownSocket() async {');
      expect(body, contains('_audioGateOpen = false;'));
    });

    test('게이트가 닫혔거나 안 붙었으면 그 자리에서 버린다', () {
      final String append =
          _region(stt, 'void appendAudio(Uint8List pcm) {', 'void _send(');
      expect(append, contains('if (_disposed || !_audioGateOpen || pcm.isEmpty) return;'));
      expect(append, contains('if (!isConnected) return;'));
      // 큐가 없다 = 나중에 몰아서 전사할 방법 자체가 없다.
      for (final String buffered in <String>[
        '_pendingAudio',
        '_audioBuffer',
        '.add(pcm)',
      ]) {
        expect(append, isNot(contains(buffered)),
            reason: '$buffered — 끊긴 동안의 소리를 쌓으면 나중에 몰아서 전사된다');
      }
    });

    test('왜 복구하지 않는지 코드 옆에 적어 뒀다', () {
      expect(stt, contains('있지도 않은 말을'));
    });
  });

  // ── ⑤ 방을 나가면 즉시 멈춘다 ───────────────────────────────────────
  group('⑤ 방 종료 시 재연결 루프가 즉시 멈춘다', () {
    test('통역 게이트는 세 조건을 다 본다', () {
      expect(
          duo,
          contains('session.shouldReconnect = () =>\n'
              '        !_isExiting && _isConversationActive && '
              'generation == _interpGeneration;'));
    });

    test('지연 뒤에도 다시 묻는다', () {
      final String body =
          _region(stt, 'Future<void> _reconnect(String reason) async {',
              'Future<void> _teardownSocket() async {');
      expect(body, contains('gate_closed_after_delay'),
          reason: '10초를 자는 동안 방을 나갈 수 있다');
    });

    test('게이트가 닫히면 조용히 멈춘다 — fatal이 아니다', () {
      final String body =
          _region(stt, "reconnect_skipped reason=gate_closed'", 'onReconnecting');
      expect(body, isNot(contains('onFatalError')),
          reason: '정상 종료를 실패로 올리면 화면이 "실패"로 남는다');
    });

    test('마이크를 접으면 "다시 잇는 중"도 지운다', () {
      final String body = _region(duo,
          'Future<void> _stopInterpreterCapture(String reason) async {',
          '/// 🔵 [INTERP-LIVE] 상대가 사라졌다.');
      expect(body, contains('_interpSttReconnecting = false'));
    });

    test('dispose는 재연결을 막는다', () {
      final String body =
          _region(stt, 'Future<void> _reconnect(String reason) async {',
              'Future<void> _teardownSocket() async {');
      expect('_disposed'.allMatchesIn(body), greaterThanOrEqualTo(2));
    });
  });

  // ── 화면 ────────────────────────────────────────────────────────────
  group('끊긴 동안 화면이 잠긴 것처럼 보이지 않는다', () {
    test('기존 상태 체계 안에서 한 줄만 얹었다', () {
      expect(duo, contains("if (_interpSttReconnecting) return '연결이 끊겨 다시 잇는 중';"));
    });

    test('"실패"보다 먼저 읽힌다', () {
      final int recon = duo.indexOf('if (_interpSttReconnecting) return');
      final int failed = duo.indexOf('if (_interpStartFailed) {');
      expect(recon, greaterThan(-1));
      expect(recon, lessThan(failed),
          reason: '순서가 뒤면 붙는 중에도 "마이크를 열지 못했습니다"가 뜬다');
    });

    test('새 UI 구조를 만들지 않았다', () {
      // 상태 하나만 늘렸다. 새 위젯·새 화면·새 단계는 없다.
      expect('bool _interpSttReconnecting'.allMatchesIn(duo), 1);
      expect(duo, isNot(contains('enum InterpSttPhase')));
    });
  });

  // ── ⑥⑦⑧ 건드리지 않기로 한 것 ──────────────────────────────────────
  group('⑥ 직접 대화의 오디오 경로는 그대로다', () {
    test('직접 대화의 fatal은 여전히 통화를 안 끊는다', () {
      final String all = directSession();
      // 이 구역의 마지막 블록이다. 끝까지 잘라 본다.
      final String body =
          all.substring(all.indexOf('session.onFatalError = (reason) {'));
      expect(body, contains('통화는 계속된다'));
      expect(body, contains('_sttActive = false'));
      expect(body, isNot(contains('_stopInterpreterCapture')));
      expect(body, isNot(contains('dispose')));
    });

    test('직접 대화의 게이트 조건은 안 바뀌었다', () {
      expect(duo,
          contains('session.shouldReconnect = () => _isDirectGenerationCurrent(generation);'));
    });

    test('직접 대화는 재연결 표시를 쓰지 않는다', () {
      expect(directSession(), isNot(contains('_interpSttReconnecting')));
    });
  });

  group('⑦ 통역은 여전히 원음을 상대에게 안 보낸다', () {
    test('트랙은 얹되 꺼 둔다', () {
      expect(call, contains('await pc.addTrack(_localAudioTrack!, stream);'));
      expect(call, contains('if (!sendAudio) {'));
      expect(call, contains('_localAudioTrack!.enabled = false;'));
    });

    test('음소거 해제 요청은 통역에서 무시된다', () {
      expect(call, contains('mute_ignored reason=interpreter_never_sends_origin'));
    });
  });

  group('⑧ 에코 가드·양보·MicTap 경로는 안 건드렸다', () {
    test('ECHO-GUARD가 살아 있다', () {
      expect(duo, contains('[ECHO-GUARD]'));
    });

    test('INTERP-YIELD 훅이 살아 있다', () {
      expect(duo, contains('[INTERP-YIELD]'));
      expect(duo, contains("reason=utterance_committed"));
    });

    test('MicTap PCM 경로가 그대로다', () {
      expect(duo, contains('_interpMicTap'));
      expect(duo, contains('DuoWebrtcMicTap'));
    });

    test('admission 문턱은 손대지 않았다', () {
      expect(duo, contains('kDuoMinVoicedMs'));
      expect(duo, contains('kDuoMinUtteranceRmsDbfs'));
    });
  });
}

/// 상태 코드가 없는 임의의 예외.
class TimeoutException_ implements Exception {}

extension on String {
  int allMatchesIn(String haystack) =>
      RegExp(RegExp.escape(this)).allMatches(haystack).length;
}
