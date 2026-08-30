// 🎬 [DUO-REPLAY] 늦게 만들어진 Replay를 열린 화면이 알아차리는가.
//
// 성공 기준 한 문장:
//   "통화 종료 직후 공부방에 들어가 Replay가 아직 없어도, 나갔다 다시 들어올
//    필요 없이 생성 완료 순간 Conversation Replay 선택지가 나타난다."
//
// 화면 규칙은 위젯이 아니라 [DuoReplayViewState]가 쥔다 — setState 사이에
// 숨어 있으면 시험으로 고정할 수가 없다. 여기서 그 규칙을 못 박는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_replay.dart';

/// `replay/current` 문서 한 벌.
Map<String, dynamic> replayDoc({
  String status = kReplayReady,
  int version = 100,
  int dropped = 3,
  List<String> texts = const <String>['오늘 뭐 먹을까?', '김치찌개 어때?'],
}) =>
    <String, dynamic>{
      'status': status,
      kDuoReplayCanonicalVersionField: version,
      'dropped_count': dropped,
      'turns': <Map<String, dynamic>>[
        for (var i = 0; i < texts.length; i++)
          <String, dynamic>{
            'role': i.isEven ? 'HOST' : 'GUEST',
            'text': texts[i],
            'source_ids': <String>['s$i'],
          }
      ],
    };

void main() {
  group('문서 읽기 — 쓸 수 없는 것은 전부 null이다 (fail-open)', () {
    test('ready 문서는 읽힌다', () {
      final script = parseDuoReplayDoc(replayDoc());
      expect(script, isNotNull);
      expect(script!.lines.length, 2);
      expect(script.canonicalVersion, 100);
      expect(script.droppedCount, 3);
      expect(script.isUsable, isTrue);
    });

    test('문서가 없으면 null', () {
      expect(parseDuoReplayDoc(null), isNull);
    });

    test('status=failed면 null — 화면에 오류를 띄우지 않는다', () {
      expect(parseDuoReplayDoc(replayDoc(status: kReplayFailed)), isNull);
    });

    test('모양이 깨져도 null — 예외를 던지지 않는다', () {
      expect(parseDuoReplayDoc(<String, dynamic>{'status': kReplayReady}), isNull);
      expect(
          parseDuoReplayDoc(<String, dynamic>{
            'status': kReplayReady,
            'turns': 'not a list',
          }),
          isNull);
      expect(
          parseDuoReplayDoc(<String, dynamic>{
            'status': kReplayReady,
            'turns': <dynamic>[],
          }),
          isNull);
      // 줄은 있는데 글자가 전부 빈 경우.
      expect(
          parseDuoReplayDoc(<String, dynamic>{
            'status': kReplayReady,
            'turns': <dynamic>[
              <String, dynamic>{'role': 'HOST', 'text': '   '}
            ],
          }),
          isNull);
    });

    test('status가 아예 없으면 null', () {
      expect(parseDuoReplayDoc(<String, dynamic>{'turns': <dynamic>[]}), isNull);
    });
  });

  group('열린 화면이 늦게 온 Replay를 잡는다', () {
    test('진입 시 없으면 Original만 — 전환 줄이 안 뜬다', () {
      final view = DuoReplayViewState();
      expect(view.apply(null), isFalse, reason: '없던 것이 계속 없으면 다시 그릴 이유가 없다');
      expect(view.hasReplay, isFalse);
      expect(view.showReplay, isFalse);
    });

    test('★ 화면이 열린 채로 Replay가 생기면 전환 줄이 나타난다', () {
      final view = DuoReplayViewState();
      view.apply(null); // 진입 시 첫 조회 — 아직 없다

      // …통화 뒤 canonical → Replay가 만들어지고 구독이 잡는다.
      final changed = view.apply(parseDuoReplayDoc(replayDoc()));

      expect(changed, isTrue, reason: '다시 그려야 전환 줄이 뜬다');
      expect(view.hasReplay, isTrue);
    });

    test('생겨도 보고 있던 화면을 바꾸지 않는다 — 선택지만 늘어난다', () {
      final view = DuoReplayViewState();
      view.apply(null);
      view.apply(parseDuoReplayDoc(replayDoc()));
      expect(view.showReplay, isFalse,
          reason: 'Original을 보고 있던 사람을 Replay로 끌고 가면 안 된다');
    });

    test('Replay를 보고 있는 중에 갱신되면 새 내용으로 바뀐다', () {
      final view = DuoReplayViewState();
      view.apply(parseDuoReplayDoc(replayDoc(version: 100)));
      view.select(replay: true);
      expect(view.showReplay, isTrue);

      final changed = view.apply(parseDuoReplayDoc(
          replayDoc(version: 200, texts: <String>['새 판1', '새 판2', '새 판3'])));

      expect(changed, isTrue);
      expect(view.showReplay, isTrue, reason: '보던 탭에 그대로 머문다');
      expect(view.script!.lines.length, 3);
      expect(view.script!.lines.first.text, '새 판1');
    });
  });

  group('같은 판이 여러 번 와도 화면은 가만히 있는다', () {
    test('같은 canonical_version은 다시 그리지 않는다', () {
      final view = DuoReplayViewState();
      expect(view.apply(parseDuoReplayDoc(replayDoc(version: 100))), isTrue);
      for (var i = 0; i < 5; i++) {
        expect(view.apply(parseDuoReplayDoc(replayDoc(version: 100))), isFalse,
            reason: '같은 판이 반복되면 rebuild 폭주가 된다');
      }
      expect(view.hasReplay, isTrue);
    });

    test('판이 바뀌면 다시 그린다', () {
      final view = DuoReplayViewState();
      view.apply(parseDuoReplayDoc(replayDoc(version: 100)));
      expect(view.apply(parseDuoReplayDoc(replayDoc(version: 101))), isTrue);
      expect(view.script!.canonicalVersion, 101);
    });

    test('없는 상태가 반복돼도 다시 그리지 않는다', () {
      final view = DuoReplayViewState();
      expect(view.apply(null), isFalse);
      expect(view.apply(null), isFalse);
      expect(view.apply(parseDuoReplayDoc(replayDoc(status: kReplayFailed))),
          isFalse);
    });
  });

  group('Replay가 사라지면 원본으로 되돌아간다', () {
    test('failed로 바뀌면 전환 줄이 없어진다', () {
      final view = DuoReplayViewState();
      view.apply(parseDuoReplayDoc(replayDoc()));
      expect(view.hasReplay, isTrue);

      expect(view.apply(parseDuoReplayDoc(replayDoc(status: kReplayFailed))),
          isTrue);
      expect(view.hasReplay, isFalse);
    });

    test('Replay를 보던 중에 사라지면 Original로 되돌린다 — 빈 화면을 안 남긴다', () {
      final view = DuoReplayViewState();
      view.apply(parseDuoReplayDoc(replayDoc()));
      view.select(replay: true);
      expect(view.showReplay, isTrue);

      view.apply(null);
      expect(view.showReplay, isFalse);
      expect(view.hasReplay, isFalse);
    });

    test('사라졌다 다시 생기면 다시 잡는다', () {
      final view = DuoReplayViewState();
      view.apply(parseDuoReplayDoc(replayDoc(version: 100)));
      view.apply(null);
      expect(view.hasReplay, isFalse);
      // 같은 판이 다시 와도 이번엔 새로 반영돼야 한다(장부가 비워졌으므로).
      expect(view.apply(parseDuoReplayDoc(replayDoc(version: 100))), isTrue);
      expect(view.hasReplay, isTrue);
    });
  });

  group('사용자 선택', () {
    test('Replay가 없으면 그 탭으로 갈 수 없다', () {
      final view = DuoReplayViewState();
      view.select(replay: true);
      expect(view.showReplay, isFalse);
    });

    test('있으면 오갈 수 있다', () {
      final view = DuoReplayViewState();
      view.apply(parseDuoReplayDoc(replayDoc()));
      view.select(replay: true);
      expect(view.showReplay, isTrue);
      view.select(replay: false);
      expect(view.showReplay, isFalse);
    });
  });

  group('구독은 Replay가 걸리는 방에만 붙는다', () {
    test('직접 통화 방에만 참이다', () {
      expect(
          duoRoomHasReplay(<String, dynamic>{
            kDuoModeField: 'direct',
            kDuoRoomIdField: 'room1',
          }),
          isTrue);
    });

    test('만능 통역·일반 방에는 안 붙는다', () {
      for (final Map<String, dynamic> room in <Map<String, dynamic>>[
        <String, dynamic>{kDuoModeField: 'interpreter', kDuoRoomIdField: 'r'},
        <String, dynamic>{}, // Circle Talk / Scenario Talk / 일반 히스토리
        <String, dynamic>{kDuoModeField: 'direct'}, // 공유 고리 없는 옛 방
        <String, dynamic>{kDuoRoomIdField: 'r'},
      ]) {
        expect(duoRoomHasReplay(room), isFalse, reason: '$room');
      }
    });

    test('빈 roomId로는 지켜보지 않는다', () {
      expect(watchDuoReplay(''), emitsDone);
    });
  });

  group('학습 상태를 건드리지 않는다', () {
    test('뷰 상태가 쥔 것은 대본과 탭 선택뿐이다', () {
      // 이 클래스에는 히스토리·배울글·연습에 손댈 방법이 아예 없다.
      // 필드가 늘면 이 시험이 깨지고, 그때 다시 생각하게 된다.
      final view = DuoReplayViewState();
      view.apply(parseDuoReplayDoc(replayDoc()));
      view.select(replay: true);
      expect(view.script, isNotNull);
      expect(view.showReplay, isTrue);
      expect(view.hasReplay, isTrue);
      // 되돌려도 대본은 그대로 남는다 — 다시 조회할 이유를 만들지 않는다.
      view.select(replay: false);
      expect(view.script, isNotNull);
    });
  });

  // ── 배선 확인 ────────────────────────────────────────────────────
  // 구독의 수명은 위젯 안에 있어 단위 시험으로 못 잡는다. 원문에서 읽어
  // 못 박는다 — 이 셋이 깨지면 구독이 새거나 죽은 화면을 두드린다.
  group('구독 수명', () {
    final String room = File('lib/custom_code/widgets/chat_history_master.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('dispose에서 반드시 끊는다', () {
      final int at = room.indexOf('void dispose() {');
      expect(at, greaterThan(-1));
      final String block = room.substring(at, at + 400);
      expect(block, contains('_stopReplayListener();'));
      // 곁가지를 가장 먼저 접는다 — 늦게 온 이벤트가 setState를 부르면 안 된다.
      expect(block.indexOf('_stopReplayListener();'),
          lessThan(block.indexOf('BillingTicker')));
    });

    test('같은 방이면 구독을 새로 만들지 않는다', () {
      expect(
          room,
          contains('if (_replaySub != null && _replayRoomId == roomId) return;'));
    });

    test('방이 바뀌면 이전 구독을 끊고 새로 건다', () {
      final int at = room.indexOf('void _startReplayListener(String roomId) {');
      expect(at, greaterThan(-1));
      final String block = room.substring(at, at + 700);
      expect(block, contains('_stopReplayListener();'));
      expect(block.indexOf('_stopReplayListener();'),
          lessThan(block.indexOf('_replaySub = watchDuoReplay')));
    });

    test('화면이 내려간 뒤 온 이벤트는 setState를 부르지 않는다', () {
      final int at = room.indexOf('_replaySub = watchDuoReplay(roomId).listen(');
      expect(at, greaterThan(-1));
      final String block = room.substring(at, at + 500);
      expect(block, contains('if (!mounted || _replayRoomId != roomId) return;'));
      // 같은 판이면 setState 자체를 건너뛴다.
      expect(block, contains('if (!_replayView.apply(script)) return;'));
    });

    test('구독 오류가 스트림을 죽이지 않는다', () {
      final int at = room.indexOf('_replaySub = watchDuoReplay(roomId).listen(');
      final String block = room.substring(at, at + 900);
      expect(block, contains('cancelOnError: false'));
      expect(block, contains('replay_listener_error'));
    });

    test('진단 로그에 전사문이 실리지 않는다', () {
      for (final String needle in <String>[
        'replay_listener_started room=',
        'replay_waiting room=',
        'replay_ready room=',
        'replay_failed room=',
        'replay_listener_stopped room=',
      ]) {
        expect(room, contains(needle), reason: '$needle 로그가 없다');
      }
      final int at = room.indexOf("'[HISTORY] replay_ready room=");
      final String block = room.substring(at, at + 200);
      expect(block, contains('lines='));
      expect(block, contains('version='));
      expect(block, isNot(contains('.text')));
    });

    test('첫 1회 조회는 그대로 남아 있고, 그 뒤에 구독이 붙는다', () {
      final int read = room.indexOf('await readDuoReplay(roomId)');
      final int watch = room.indexOf('_startReplayListener(roomId);');
      expect(read, greaterThan(-1), reason: '진입 시 1회 조회는 유지한다');
      expect(watch, greaterThan(read), reason: '조회 뒤에 구독을 건다');
      // 둘 다 직접 통화 방 확인 뒤에 있어야 한다.
      final int gate = room.indexOf('if (!duoRoomHasReplay(room)) return;');
      expect(gate, greaterThan(-1));
      expect(read, greaterThan(gate));
      expect(watch, greaterThan(gate));
    });

    test('구독은 Replay 상태만 갱신한다 — 재조회·재적용을 부르지 않는다', () {
      final int at = room.indexOf('void _startReplayListener(String roomId) {');
      final int end = room.indexOf('void _stopReplayListener()');
      expect(end, greaterThan(at));
      final String block = room.substring(at, end);
      for (final String forbidden in <String>[
        '_fetchRoomData',
        'applyDuoCanonicalToHistory',
        '_syncDuoCanonical',
        '_ensureHistoryTargets',
        '_scheduleMissingTargetGeneration',
      ]) {
        expect(block, isNot(contains(forbidden)),
            reason: '$forbidden 이 구독 안에서 불리면 학습 상태가 초기화된다');
      }
    });
  });
}
