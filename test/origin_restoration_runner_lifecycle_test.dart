// ====================================================================
// 🔒 [ORIGIN-RUNNER] 복원 한 판의 수명 — 되살아나면 안 되는 결함의 자리
// --------------------------------------------------------------------
// 2026-09-10 실기기에서, 통화를 끝내고 공부방을 처음 열면 3분을 멈춰 있다가
// "대화 정리가 예상보다 오래 걸리고 있습니다"로 떨어졌다. 복원은 3초 만에
// 정상으로 끝나 있었고, 맵에서도 지워져 있었다. **기다리는 쪽만 안 풀렸다.**
//
// 원인은 한 줄이었다.
//
//     final task = _run(...).whenComplete(() => _running.remove(id));
//     _running[id] = task;
//
// `Map.remove`는 지운 값을 돌려준다. 그 값이 곧 `task`고, `whenComplete`는
// 콜백이 Future를 돌려주면 그것이 끝날 때까지 자기 완료를 미룬다. task가
// 자기 자신을 기다린 것이다.
//
// 아래 시험은 그 모양을 **실행해서** 잡는다. 주석은 지워질 수 있어도 이건
// 빨간불이 된다.
// ====================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// 줄 주석을 걷어 낸다. 경고 주석에 적어 둔 나쁜 모양을 코드로 세지 않는다.
String stripComments(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// 고친 뒤의 등록 모양. `start()`가 하는 일과 같다.
Future<void> registerFixed(
  Map<String, Future<void>> running,
  String id,
  Future<void> raw,
) {
  late final Future<void> task;
  void cleanup() {
    // 내 판이 아직 등록돼 있을 때만 지운다.
    if (identical(running[id], task)) running.remove(id);
  }

  task = raw.whenComplete(cleanup);
  running[id] = task;
  return task;
}

/// 고치기 전의 등록 모양. **제품 코드로 되돌리면 안 된다** — 이 파일 안에서
/// 그 결함이 실제로 어떤 모습인지 보여 주기 위해서만 남긴다.
Future<void> registerSelfWaiting(
  Map<String, Future<void>> running,
  String id,
  Future<void> raw,
) {
  final task = raw.whenComplete(() => running.remove(id));
  running[id] = task;
  return task;
}

/// 짧은 상한을 두고 기다린다. 안 풀리면 `timedOut`이다.
Future<String> settle(Future<void> task,
    {Duration limit = const Duration(milliseconds: 300)}) async {
  try {
    await task.timeout(limit);
    return 'completed';
  } on TimeoutException {
    return 'timedOut';
  } catch (error) {
    return 'failed:${error.runtimeType}';
  }
}

void main() {
  group('판 하나의 수명', () {
    test('일이 끝나면 감싼 판도 곧바로 끝난다', () async {
      final running = <String, Future<void>>{};
      final task = registerFixed(
        running,
        'room',
        Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      expect(await settle(task), 'completed');
    });

    test('끝난 뒤에는 돌고 있지 않다', () async {
      final running = <String, Future<void>>{};
      final task = registerFixed(
        running,
        'room',
        Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      expect(running.containsKey('room'), isTrue);
      await settle(task);
      expect(running.containsKey('room'), isFalse);
    });

    test('일이 실패해도 정리는 돌고, 오류는 가려지지 않는다', () async {
      final running = <String, Future<void>>{};
      final task = registerFixed(
        running,
        'room',
        Future<void>.delayed(
          const Duration(milliseconds: 10),
          () => throw StateError('boom'),
        ),
      );
      expect(await settle(task), 'failed:StateError');
      expect(running.containsKey('room'), isFalse);
    });
  });

  group('되살리면 안 되는 모양', () {
    test('정리가 지운 판을 돌려주면 자기 자신을 기다린다', () async {
      final running = <String, Future<void>>{};
      final task = registerSelfWaiting(
        running,
        'room',
        Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      // 맵에서는 지워진다 — 실기기에서 runnerRunning=false로 보이던 것이다.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(running.containsKey('room'), isFalse);
      // 그런데 기다리는 쪽은 영영 안 풀린다. **이것이 그 결함이다.**
      expect(await settle(task), 'timedOut');
    });
  });

  group('늦게 도착한 정리', () {
    test('옛 판의 정리가 새 판을 지우지 않는다', () async {
      final running = <String, Future<void>>{};
      final slow = Completer<void>();
      final first = registerFixed(running, 'room', slow.future);

      // 첫 판이 끝나기 전에 새 판이 올라온 상황을 만든다.
      final second = Future<void>.value();
      running['room'] = second;

      slow.complete();
      await settle(first);

      expect(identical(running['room'], second), isTrue,
          reason: '늦게 온 정리가 남의 판을 지우면, 기다리는 쪽은 '
              '시작된 적 없는 판을 기다리게 된다');
    });
  });

  group('제품 코드가 그 모양으로 돌아가지 않았는가', () {
    // 그 나쁜 모양은 경고 주석 안에도 적혀 있다. 코드만 본다.
    final runner = stripComments(
        read('lib/custom_code/services/origin_restoration_runner.dart'));

    test('정리를 화살표 본문으로 줄이지 않았다', () {
      expect(runner, isNot(contains('whenComplete(() => _running.remove')));
      expect(runner, isNot(contains('whenComplete(() => _registeredRunId')));
    });

    test('정리는 반환형이 void인 이름 붙은 함수다', () {
      expect(runner, contains('void cleanup() {'));
      expect(runner, contains('task = raw.whenComplete(cleanup);'));
    });

    test('내 판일 때만 지운다', () {
      final cleanup = runner.indexOf('void cleanup() {');
      final guard = runner.indexOf('identical(_running[id], task)', cleanup);
      final remove = runner.indexOf('_running.remove(id);', cleanup);
      expect(cleanup, greaterThanOrEqualTo(0));
      expect(guard, greaterThan(cleanup));
      expect(remove, greaterThan(guard));
    });
  });
}
