// 🗣️ [INTERP-YIELD] 내가 말하는 중에는 상대 음성을 틀지 않는다.
//
// 왜 필요한가 — 2026-09-03 실기기 로그가 그 순간을 그대로 담고 있다:
//   11:48:12  speech_started            내가 영어로 말하기 시작
//   11:48:15  partner=playing           상대 번역 재생 시작
//   11:48:18  flush_on_close            말하던 중에 마이크가 닫힘
//   → 한 문장이 74자 + 57자 + 5자로 찢어져 각각 따로 번역됐다.
//
// 재생이 시작되면 게이트가 닫히고(`_closeInterpGate`), 그때 진행 중이던
// 발화가 강제 확정된다. 그 구조 자체는 옳다 — 안 그러면 서버가 발화를
// 영영 확정 못 해 과금이 안 멈춘다. 고칠 곳은 **재생을 시작하는 시점**이다.
//
// 상대 음성이 조금 늦게 들리는 편이, 내 문장이 세 조각으로 찢어지는 것보다
// 훨씬 낫다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';

void main() {
  final String duo = File(_duo).readAsStringSync().replaceAll('\r\n', '\n');

  /// `_drainIncoming`의 몸통만 잘라 본다.
  String drainBody() {
    final int start = duo.indexOf('Future<void> _drainIncoming() async {');
    expect(start, greaterThan(-1));
    final int end = duo.indexOf('String _resolvePartnerSrcLang(', start);
    expect(end, greaterThan(start),
        reason: '구역 경계를 못 잡았다 — 함수 순서가 바뀌었는지 확인할 것');
    return duo.substring(start, end);
  }

  group('내가 말하는 중이면 재생하지 않는다', () {
    test('큐에서 꺼내기 **전에** 판단한다', () {
      // 꺼낸 뒤 판단하면 그 메시지가 큐 밖으로 나가 순서가 깨지거나 사라진다.
      final body = drainBody();
      final int guard = body.indexOf('_shouldYieldIncomingToMySpeech');
      final int take = body.indexOf('_incomingQueue.removeAt(0)');
      expect(guard, greaterThan(-1), reason: '미루는 판단이 없다');
      expect(take, greaterThan(-1));
      expect(guard, lessThan(take),
          reason: '메시지를 꺼낸 뒤에 미루면 그 메시지가 큐 밖에서 사라진다');
    });

    test('break로 멈춘다 — 큐를 비우지 않는다', () {
      expect(drainBody(), contains('break;'));
    });

    test('판단은 isUserSpeaking 하나만 본다', () {
      final int at = duo.indexOf('bool get _shouldYieldIncomingToMySpeech');
      expect(at, greaterThan(-1));
      final String body = duo.substring(at, at + 300);
      expect(body, contains('stt.isUserSpeaking'));
      // `hasPendingUtterance`는 "전사 대기 중"까지 포함해서, 이미 말을 마친
      // 뒤에도 참이다. 그걸 쓰면 상대 음성이 필요 이상으로 늦어진다.
      expect(body, isNot(contains('hasPendingUtterance')),
          reason: '전사 대기까지 기다리면 상대 음성이 불필요하게 늦어진다');
    });

    test('직접 대화에는 걸지 않는다', () {
      final int at = duo.indexOf('bool get _shouldYieldIncomingToMySpeech');
      final String body = duo.substring(at, at + 300);
      expect(body, contains('if (_isDirectMode) return false;'),
          reason: '직접 대화는 소리를 안 내므로 미룰 이유가 없다');
    });
  });

  group('내 발화가 끝나면 다시 깨운다', () {
    test('onUtteranceCommitted가 깨우는 훅이다', () {
      // 새 폴링 타이머를 만들지 않는 근거 — 말이 끝나는 순간을 서버가 알려 준다.
      final int at = duo.indexOf('session.onUtteranceCommitted =',
          duo.indexOf('Future<bool> _ensureInterpreterStt('));
      expect(at, greaterThan(-1));
      final String body = duo.substring(at, at + 700);
      expect(body, contains('_drainIncoming()'));
      expect(body, contains('utterance_committed'));
    });

    test('소켓 재접속 때도 깨운다 — 큐가 영영 막히지 않게', () {
      final int at = duo.indexOf('session.onReconnecting =',
          duo.indexOf('Future<bool> _ensureInterpreterStt('));
      expect(at, greaterThan(-1));
      expect(duo.substring(at, at + 400), contains('_drainIncoming()'));
    });

    test('큐를 들여다보는 폴링 타이머를 만들지 않았다', () {
      // 파일에 `Timer.periodic`은 이미 있다(맛보기 1분 타이머, 통계 주기 등).
      // 여기서 막는 것은 **큐를 주기적으로 훑는** 타이머다 — 깨우는 신호가
      // 이미 있는데 폴링을 얹으면 배터리와 복잡도만 늘어난다.
      for (final m in RegExp(r'Timer\.periodic').allMatches(duo)) {
        final String near =
            duo.substring(m.start, (m.start + 400).clamp(0, duo.length));
        expect(near, isNot(contains('_incomingQueue')),
            reason: '큐를 폴링하는 타이머가 생겼다');
        expect(near, isNot(contains('_drainIncoming')),
            reason: 'drain을 폴링하는 타이머가 생겼다');
      }
    });

    test('버린 발화에서도 깨운다 (기존 경로 유지)', () {
      // 게이트에 걸려 버려진 발화 뒤에도 큐가 풀려야 한다.
      final n = RegExp(r'if \(_incomingQueue\.isNotEmpty\)').allMatches(duo).length;
      expect(n, greaterThanOrEqualTo(6),
          reason: '깨우는 자리가 줄었다 — 큐가 막히는 경로가 생겼는지 확인할 것');
    });
  });

  group('순서와 내용을 잃지 않는다', () {
    test('큐는 앞에서 꺼내고 뒤에 넣는다 (FIFO)', () {
      expect(duo, contains('_incomingQueue.add(data)'));
      expect(drainBody(), contains('_incomingQueue.removeAt(0)'));
    });

    test('한 번에 하나씩 처리한다 (직렬)', () {
      expect(drainBody(), contains('await _handleIncomingMessage(data)'));
    });

    test('재진입을 막는다', () {
      final body = drainBody();
      expect(body, contains('if (_isDrainingIncoming) return;'));
      expect(body, contains('_isDrainingIncoming = false;'));
    });

    test('미룬 사실이 로그에 남는다', () {
      expect(duo, contains("'[INTERP-YIELD]'"));
      expect(duo, contains('deferred queued='));
      expect(duo, contains('resume queued='));
    });
  });

  group('③ 조기 재생은 꺼져 있다', () {
    test('기본값이 false다', () {
      expect(
          duo,
          contains("bool.fromEnvironment('DUO_INTERP_STREAM_TTS', "
              "defaultValue: false)"),
          reason: '실기기에서 효과가 없었고 긴 문장에서는 더 느렸다');
    });

    test('코드는 지우지 않았다 — 다시 켤 수 있다', () {
      expect(duo, contains('_handleIncomingStreaming'));
      expect(duo, contains('translateForSpeechStreaming'));
    });
  });
}
