// 🔀 [INTERP-TRANSPORT] 만능 통역의 글자 통로를 런타임에 되돌린다
//
// `DUO_INTERP_WEBRTC`는 빌드에 박히는 값이라, 배포한 뒤 문제가 나면 되돌리는 데
// 스토어 새 빌드가 필요했다. `DuoInterpreterTransport` Remote Config가 그
// 손잡이다 — 직접 대화의 `DuoDirectTransport`와 같은 모양이다.
//
// 이 파일이 막는 사고는 다섯이고, 다섯 중 넷은 **조용히** 일어난다:
//   ① 캡처는 WebRTC인데 Firestore 스냅샷도 읽어 한 발화를 두 번 번역·재생
//   ② 캡처는 Firestore인데 스냅샷을 건너뛰어 상대 발화를 아예 못 받음
//   ③ 통화 중에 Remote Config가 바뀌어 통로가 중간에 갈아 끼워짐
//   ④ Remote Config를 못 읽어 통역 자체가 시작되지 않음
//   ⑤ 모르는 문자열이 들어와 아무 갈래도 안 골라짐
//
// ①②는 같은 뿌리다 — **판단하는 자리마다 값을 따로 읽으면** 언젠가 어긋난다.
// 그래서 통로를 묻는 자리를 게터 하나로 좁히고, 그 게터가 보는 값은 통화가
// 시작될 때 한 번 박은 `_interpTransport` 하나뿐이게 한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// [start] 선언부터 [end] 직전까지의 소스 조각.
String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 선언: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 선언: $end');
  return src.substring(a, b);
}

void main() {
  final String duo = _read(_duo);

  // ==========================================================================
  group('통로를 묻는 자리는 하나뿐이다', () {
    test('두 값만 알아듣는 상수가 있다', () {
      expect(duo, contains("const String kDuoInterpTransportWebrtc = 'webrtc';"));
      expect(duo,
          contains("const String kDuoInterpTransportFirestore = 'firestore';"));
      expect(
          duo,
          contains("const String kDuoInterpTransportRemoteConfigKey = "
              "'DuoInterpreterTransport';"));
    });

    test('판단은 게터 하나가 한다', () {
      expect(duo, contains('bool get _useInterpWebrtc'));
      final String body = _region(
          duo, 'bool get _useInterpWebrtc', 'void _pinInterpTransport(');
      // 게터가 보는 것은 박아 둔 값과 빌드 타임 폴백 둘뿐이다.
      expect(body, contains('_interpTransport ?? _fallbackInterpTransport'));
      expect(body, isNot(contains('FirebaseRemoteConfig')),
          reason: '판단하는 자리에서 Remote Config를 다시 읽으면 안 된다');
    });

    test('분기 세 자리가 모두 그 게터를 본다', () {
      // 캡처 선택 / 실시간 전송 / Firestore 스킵.
      expect(duo, contains('if (_useInterpWebrtc) {'));
      expect(duo, contains('_useInterpWebrtc && !_isDirectMode'));
      expect(RegExp(r'_useInterpWebrtc').allMatches(duo).length,
          greaterThanOrEqualTo(4),
          reason: '게터를 보는 자리가 줄었다 — 어디가 상수로 돌아갔는지 확인할 것');
    });

    test('상수를 직접 보는 자리는 폴백 게터 하나뿐이다', () {
      // 주석은 세지 않는다. 실행되는 줄만 본다.
      final List<String> code = duo
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .where((l) => l.contains('kDuoInterpWebrtc'))
          .toList();
      // 선언 1줄(`const bool kDuoInterpWebrtc =`) + 폴백 게터 1줄.
      expect(code.length, 2,
          reason: '상수를 직접 읽는 자리가 늘었다: ${code.join(" | ")}');
      expect(code.any((l) => l.contains('_fallbackInterpTransport')), isTrue);
    });
  });

  // ==========================================================================
  group('① 캡처와 Firestore 가드가 같은 값을 본다', () {
    test('두 자리가 같은 게터를 쓴다 — 상수를 섞어 쓰지 않는다', () {
      final String capture = _region(duo,
          'Future<void> _startInterpreterCapture(', 'Future<bool> _startInterpreterWebrtc(');
      final String listen =
          _region(duo, 'void _listenForMessages()', 'void _enqueueIncoming(');
      expect(capture, contains('_useInterpWebrtc'));
      expect(listen, contains('_useInterpWebrtc'));
      expect(capture, isNot(contains('kDuoInterpWebrtc')),
          reason: '캡처가 상수를 직접 본다 — 가드와 어긋날 수 있다');
      expect(listen, isNot(contains('kDuoInterpWebrtc')),
          reason: '가드가 상수를 직접 본다 — 캡처와 어긋날 수 있다');
    });

    test('건너뛴 사실이 로그에 남는다', () {
      final String listen =
          _region(duo, 'void _listenForMessages()', 'void _enqueueIncoming(');
      expect(listen, contains('firestore_skipped'));
    });
  });

  // ==========================================================================
  group('② 리스너가 스냅샷을 보기 전에 값이 박힌다', () {
    test('_listenForMessages 첫머리에서 박는다', () {
      final String listen =
          _region(duo, 'void _listenForMessages()', 'void _enqueueIncoming(');
      final int pin = listen.indexOf("_pinInterpTransport('listen_messages')");
      final int guard = listen.indexOf('_useInterpWebrtc && !_isDirectMode');
      expect(pin, greaterThan(-1), reason: '리스너가 통로를 안 박는다');
      expect(guard, greaterThan(pin),
          reason: '가드가 먼저면 첫 상대 발화를 빌드 타임 기본값으로 판단한다');
    });

    test('마이크를 열 때도 박는다 — 리스너보다 먼저 올 수 있다', () {
      final String capture = _region(duo,
          'Future<void> _startInterpreterCapture(', 'Future<bool> _startInterpreterWebrtc(');
      final int pin = capture.indexOf("_pinInterpTransport('interp_capture')");
      final int branch = capture.indexOf('if (_useInterpWebrtc) {');
      expect(pin, greaterThan(-1));
      expect(branch, greaterThan(pin), reason: '박기 전에 갈라지면 안 된다');
    });
  });

  // ==========================================================================
  group('③ 통화 중에는 값이 바뀌지 않는다', () {
    test('한 번 박히면 다시 박지 않는다', () {
      final String body =
          _region(duo, 'void _pinInterpTransport(String reason)', '  /// 📚');
      expect(body, contains('if (_interpTransport != null) return;'),
          reason: '두 번째 호출이 값을 갈아 끼우면 캡처와 가드가 어긋난다');
    });

    test('Remote Config 갱신이 박힌 값을 덮지 않는다', () {
      // `_fetchKeys`는 원문만 갈아 둔다. 판단값은 `_interpTransport`다.
      final String fetch =
          _region(duo, 'Future<void> _fetchKeys() async {', "  void _lgDuo(String tag, String msg)");
      expect(fetch, contains('_interpTransportRaw = interpTransport;'));
      expect(fetch, isNot(contains('_interpTransport =')),
          reason: 'Remote Config가 통화 중인 통로를 갈아 끼운다');
    });

    test('원문과 판단값이 다른 필드다', () {
      expect(duo, contains("String _interpTransportRaw = '';"));
      expect(duo, contains('String? _interpTransport;'));
    });
  });

  // ==========================================================================
  group('④ Remote Config를 못 읽어도 통역은 시작된다', () {
    test('빈 값이면 빌드 타임 기본값으로 떨어진다', () {
      final String body =
          _region(duo, 'void _pinInterpTransport(String reason)', '  /// 📚');
      expect(body, contains('_fallbackInterpTransport'),
          reason: '못 읽었을 때 떨어질 자리가 없으면 통역이 안 켜진다');
      // 못 읽었다고 예외를 던지거나 일찍 빠져나가지 않는다.
      expect(body, isNot(contains('throw')));
      expect(body, isNot(contains('_interpStartFailed')));
    });

    test('폴백은 빌드 타임 상수가 정한다', () {
      final String body = _region(
          duo, 'String get _fallbackInterpTransport', 'bool get _useInterpWebrtc');
      expect(body, contains('kDuoInterpWebrtc'));
      expect(body, contains('kDuoInterpTransportWebrtc'));
      expect(body, contains('kDuoInterpTransportFirestore'));
    });

    test('fetch 실패 경로가 통로를 건드리지 않는다', () {
      // `_fetchKeys`가 예외로 빠져도 `_interpTransportRaw`는 빈 문자열 그대로다.
      expect(duo, contains("String _interpTransportRaw = '';"),
          reason: '초기값이 없으면 fetch 실패가 null 참조가 된다');
    });
  });

  // ==========================================================================
  group('⑤ 모르는 문자열은 기본값으로 떨어진다', () {
    test('두 값과 정확히 같을 때만 채택한다', () {
      final String body =
          _region(duo, 'void _pinInterpTransport(String reason)', '  /// 📚');
      expect(
          body,
          contains('(raw == kDuoInterpTransportWebrtc || '
              'raw == kDuoInterpTransportFirestore)'),
          reason: '부분 일치로 고르면 "webrtc2" 같은 오타가 통과한다');
    });

    test('Remote Config 원문을 소문자·공백 정리해서 받는다', () {
      final String fetch =
          _region(duo, 'Future<void> _fetchKeys() async {', "  void _lgDuo(String tag, String msg)");
      final int at = fetch.indexOf('kDuoInterpTransportRemoteConfigKey');
      final String tail = fetch.substring(at, at + 120);
      expect(tail, contains('.trim()'));
      expect(tail, contains('.toLowerCase()'));
    });

    test('무엇으로 박혔는지 로그에 남는다', () {
      final String body =
          _region(duo, 'void _pinInterpTransport(String reason)', '  /// 📚');
      expect(body, contains('[INTERP-TRANSPORT]'));
      expect(body, contains('pinned='));
      expect(body, contains('raw='), reason: '오타가 들어왔을 때 그 값이 안 보이면 못 고친다');
    });
  });

  // ==========================================================================
  group('직접 대화는 건드리지 않았다', () {
    test('DuoDirectTransport는 그대로다', () {
      expect(duo,
          contains("const String kDuoTransportRemoteConfigKey = 'DuoDirectTransport';"));
      expect(duo, contains('_directTransport = transport == kDuoTransportRelay'));
    });

    test('두 손잡이가 서로 다른 필드를 본다', () {
      expect(duo, contains('bool get _useWebrtcTransport =>'));
      final String direct =
          _region(duo, 'bool get _useWebrtcTransport =>', 'String get _directSttSource');
      expect(direct, isNot(contains('_interpTransport')),
          reason: '축이 다르다 — 소리 통로와 글자 통로를 한 값으로 묶으면 안 된다');
    });
  });
}
