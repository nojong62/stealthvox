// 🎙️ [CAPTURE-PREDICATE] "캡처가 살아 있나"를 묻는 곳은 한 군데뿐이다
//
// 통역에는 캡처 경로가 둘이다:
//   · 옛 경로  — `record` 레코더를 `_interpCapture`에 담는다
//   · WebRTC   — `_interpMicTap`에 담고 `_interpCapture`는 **null로 둔다**
//
// WebRTC가 기본이 된 뒤에도 몇 자리가 `_interpCapture != null`만 봤다.
// 그래서 2026-09-04 실기기에서 이렇게 됐다:
//
//   [DUO-MIC-TAP] started              ← 탭은 멀쩡히 돈다
//   _openInterpGate('capture_started') ← _interpCapture == null 로 조기 return
//   → 게이트가 영영 안 열림 → PCM 전부 버려짐
//   → [INTERP-PHASE] mic=preparing 에서 멈춤 → 화면에 마이크가 잠겨 보임
//
// 로그에는 `mic_closed`도 `socket_lost`도 없었다. 아무것도 실패하지 않았고,
// 살아 있는 마이크를 **물어보는 쪽이 못 알아본 것**이다.
//
// 그래서 판정은 `_interpCaptureLive` 하나로만 한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final String duo = _read(_duo);

  group('두 경로를 다 보는 판정 하나만 쓴다', () {
    test('_interpCaptureLive가 둘 다 본다', () {
      expect(
          duo,
          contains('bool get _interpCaptureLive =>\n'
              '      _interpCapture != null || _interpMicTap != null;'));
    });

    test('그 정의 말고는 어디에도 직접 비교가 없다', () {
      final Iterable<RegExpMatch> hits =
          RegExp(r'_interpCapture\s*[!=]=\s*null').allMatches(duo);
      // 정의 안의 `_interpCapture != null` 하나만 남아야 한다.
      expect(hits.length, 1,
          reason: '살아 있는 WebRTC 캡처를 못 알아보는 자리가 ${hits.length - 1}군데 남았다');
      final int only = hits.first.start;
      final int defAt = duo.indexOf('bool get _interpCaptureLive =>');
      expect(only, greaterThan(defAt));
      expect(only - defAt, lessThan(120), reason: '남은 하나는 정의 안의 그것이어야 한다');
    });
  });

  group('마이크를 잠그던 두 자리', () {
    test('준비 판정이 탭도 센다', () {
      expect(
          duo,
          contains('      _interpCaptureLive &&\n'
              '      (_interpStt?.audioGateOpen ?? false);'));
    });

    test('게이트를 여는 조건이 탭도 센다', () {
      expect(
          duo,
          contains(
              'if (stt == null || !stt.isConnected || !_interpCaptureLive) return;'));
    });

    test('왜 그런지 두 자리 옆에 적어 뒀다', () {
      expect(duo, contains('WebRTC 경로는 `_interpCapture`를 안 채운다'));
      expect(duo, contains('게이트가 영영 안 열린다'));
    });
  });

  group('나머지 두 자리', () {
    test('게이트가 닫히면 화면도 따라 닫힌다', () {
      expect(
          duo,
          contains('if (!_isDirectMode && _interpCaptureLive) {\n'
              '      _setInterpMicPhase(InterpMicPhase.gated);'));
    });

    test('이중 시작 방어가 WebRTC에서도 먹는다', () {
      // 자동 시작과 캡처 시작, 두 자리 다.
      expect(
          RegExp(r'if \(_interpCaptureLive \|\| _interpStarting\) return;')
              .allMatches(duo)
              .length,
          2,
          reason: '한쪽만 보면 도는 통역 위에 두 번째 캡처가 얹힌다');
    });
  });

  group('건드리지 않은 것', () {
    // 🔄 2026-09-14에 자리가 옮겨졌다. 마이크는 상대보다 **먼저** 서고
    //   (prepare), 문은 상대가 들어온 뒤 activate의 마지막 줄에서 열린다.
    //   규칙 자체는 그대로다 — 문이 열리는 순간이 곧 "지금 말하면 들어간다"다.
    test('게이트를 여는 자리는 activate의 마지막 줄이다', () {
      final int act = duo.indexOf(
          'Future<void> _activateInterpreter(String reason) async {');
      expect(act, greaterThan(-1));
      final int gate = duo.indexOf("_openInterpGate('capture_started')", act);
      final int stt = duo.indexOf('_ensureInterpreterStt()', act);
      final int signaling = duo.indexOf('_activateInterpreterWebrtc(', act);
      expect(gate, greaterThan(-1),
          reason: '문을 여는 자리가 activate에 없다');
      expect(gate, greaterThan(stt),
          reason: '전사 소켓보다 문이 먼저 열리면 그 사이 말이 갈 곳이 없다');
      expect(gate, greaterThan(signaling),
          reason: '신호보다 문이 먼저 열리면 상대에게 보낼 통로가 없다');
    });

    test('prepare 단계에서는 문을 열지 않는다', () {
      final int prep = duo.indexOf(
          'Future<void> _startInterpreterCapture(String reason) async {');
      final int end =
          duo.indexOf('Future<bool> _startInterpreterWebrtc(', prep);
      expect(prep, greaterThan(-1));
      expect(duo.substring(prep, end).contains('_openInterpGate('), isFalse,
          reason: '상대가 없는데 문이 열리면 무음이 전사로 올라간다');
    });

    test('탭과 게이트의 역할 분담은 그대로다', () {
      // 게이트가 닫혀도 캡처는 돈다. always-on의 전부가 이것이다.
      expect(duo, contains('게이트가 닫혀 있으면 조각을 그냥 버린다'));
      expect(duo, contains('**캡처는 계속 돈다**'));
    });
  });
}
