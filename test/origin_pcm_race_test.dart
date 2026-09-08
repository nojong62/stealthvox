// 💾 [ORIGIN-PCM] 복원이 시작될 때 필요한 파일이 이미 다 써져 있는가.
//
// 대화 중의 `put`은 `unawaited`다 — 전사를 한 밀리초도 늦추지 않기 위해서다.
// 그 대가로 **마지막 발화에서 지는 경주**가 생긴다.
//
//   turn_100 쓰기가 큐에 있는 채로 사용자가 대화를 끝낸다
//   → 복원이 곧바로 turn_100을 의심한다
//   → read가 null
//   → 소리가 있는데도 "PCM 없음"으로 강등된다
//
// 고칠 수 있었던 낱말이 그대로 남는다. `flush`가 그 한 걸음을 막는다.
//
// 두 번째 위험은 **호출부가 넘긴 바이트를 되쓰는 것**이다. 쓰기가 큐를 거쳐
// 나중에 일어나므로, 그 사이 원본이 바뀌면 전사에 올린 소리와 파일에 남는
// 소리가 갈린다.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_pcm_store.dart';

Uint8List filled(int bytes, int value) =>
    Uint8List.fromList(List<int>.filled(bytes, value));

void main() {
  late Directory root;
  final store = OriginPcmStore.instance;

  setUp(() {
    root = Directory.systemTemp.createTempSync('origin_pcm_race');
    OriginPcmStore.debugRootOverride = root;
    OriginPcmStore.enabled = true;
    store.resetForTest();
  });

  tearDown(() {
    OriginPcmStore.debugRootOverride = null;
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('flush — 복원 시작 직전의 문', () {
    test('기다리지 않으면 마지막 발화를 놓칠 수 있다', () async {
      // 대화 중처럼 기다리지 않고 넣는다.
      for (var i = 1; i <= 20; i++) {
        // ignore: unawaited_futures
        store.put('roomA', i, filled(2048, i));
      }

      // 여기서 곧바로 복원을 시작하면 뒤쪽이 비어 있을 수 있다.
      await store.flush('roomA');

      // flush 뒤에는 전부 있어야 한다.
      for (var i = 1; i <= 20; i++) {
        final back = await store.read('roomA', i);
        expect(back, isNotNull, reason: 'turn $i');
        expect(back!.first, i);
      }
    });

    test('flush 뒤 매니페스트가 실제 파일과 맞는다', () async {
      for (var i = 1; i <= 12; i++) {
        // ignore: unawaited_futures
        store.put('roomA', i, filled(1024, i));
      }
      await store.flush('roomA');

      final m = await store.manifest('roomA');
      expect(m.turns.length, 12);
      expect(m.turns.map((t) => t.seq), List<int>.generate(12, (i) => i + 1));
    });

    test('flush 중에 붙은 쓰기도 기다린다', () async {
      // ignore: unawaited_futures
      store.put('roomA', 1, filled(1024, 1));
      final pending = store.flush('roomA');
      // 문이 닫히는 중에 한 발 더 들어온다.
      // ignore: unawaited_futures
      store.put('roomA', 2, filled(1024, 2));
      await pending;

      expect(await store.read('roomA', 2), isNotNull);
    });

    test('쓴 것이 없는 방은 즉시 돌아온다', () async {
      await store.flush('empty');
      await store.flush('');
    });

    test('flush는 파일을 지우지 않는다', () async {
      await store.put('roomA', 1, filled(1024, 7));
      await store.flush('roomA');
      await store.flush('roomA');

      expect(await store.read('roomA', 1), isNotNull);
    });

    test('_pending에도 문이 있다', () async {
      // ignore: unawaited_futures
      store.put('', 1, filled(1024, 3));
      await store.flush('');

      expect(
        File('${root.path}/$kOriginPcmDirName/$kOriginPcmPendingDir/turn_001.wav')
            .existsSync(),
        isTrue,
      );
    });
  });

  group('넘긴 바이트가 나중에 바뀌어도', () {
    test('저장되는 것은 put을 부른 순간의 소리다', () async {
      // 대화방의 `_snapshotTurnPcm()`은 실제로 독립 사본을 만들지만, 창고가
      // 그 계약에 기대면 안 된다. 쓰기가 큐를 거쳐 나중에 일어나므로 넘긴
      // 배열을 되쓰는 호출부가 생기면 전사에 올린 소리와 파일이 갈린다.
      final bytes = filled(2048, 0xAA);

      // ignore: unawaited_futures
      store.put('roomA', 1, bytes);
      // 쓰기가 아직 큐에 있는 동안 원본을 통째로 덮는다.
      bytes.fillRange(0, bytes.length, 0xBB);

      await store.flush('roomA');

      final back = await store.read('roomA', 1);
      expect(back, isNotNull);
      expect(back!.every((b) => b == 0xAA), isTrue,
          reason: 'put을 부른 순간의 소리가 남아야 한다');
    });

    test('여러 발화가 서로 섞이지 않는다', () async {
      final buffer = filled(1024, 1);
      // ignore: unawaited_futures
      store.put('roomA', 1, buffer);
      buffer.fillRange(0, buffer.length, 2);
      // ignore: unawaited_futures
      store.put('roomA', 2, buffer);
      buffer.fillRange(0, buffer.length, 3);

      await store.flush('roomA');

      expect((await store.read('roomA', 1))!.first, 1);
      expect((await store.read('roomA', 2))!.first, 2);
    });
  });
}
