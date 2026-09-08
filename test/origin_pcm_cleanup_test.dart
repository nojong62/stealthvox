// 💾 [ORIGIN-PCM] 창고가 새지 않는가.
//
// 이 저장소에는 **하위 폴더를 못 보던 청소기가 릴리스에 그대로 들어간
// 전례가 있다.** 그래서 여기서 가장 중요한 단언은 하나다 — 방 폴더 안의
// 파일까지 실제로 세는가.
//
// 나이는 파일 mtime을 직접 세팅해 만든다. 24시간을 기다릴 수는 없다.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_pcm_store.dart';

Uint8List fakePcm(int bytes) => Uint8List(bytes);

void main() {
  late Directory root;
  late Directory store;
  final s = OriginPcmStore.instance;

  /// 방 하나를 손으로 만든다. 나이를 직접 정해야 해서 `put`을 쓰지 않는다.
  Directory makeRoom(String id, {required int fileCount, required int bytes, Duration age = Duration.zero}) {
    final dir = Directory('${store.path}/$id')..createSync(recursive: true);
    final when = DateTime.now().subtract(age);
    for (var i = 1; i <= fileCount; i++) {
      final f = File('${dir.path}/turn_${i.toString().padLeft(3, '0')}.wav')
        ..writeAsBytesSync(Uint8List(bytes));
      f.setLastModifiedSync(when);
    }
    return dir;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('origin_pcm_cleanup');
    OriginPcmStore.debugRootOverride = root;
    OriginPcmStore.enabled = true;
    store = Directory('${root.path}/$kOriginPcmDirName')..createSync(recursive: true);
    s.resetForTest();
  });

  tearDown(() {
    OriginPcmStore.debugRootOverride = null;
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('나이', () {
    test('24시간 경계 — 23시간은 남고 25시간은 지워진다', () async {
      makeRoom('young', fileCount: 2, bytes: 1000, age: const Duration(hours: 23));
      makeRoom('old', fileCount: 2, bytes: 1000, age: const Duration(hours: 25));

      await s.cleanup();

      expect(Directory('${store.path}/young').existsSync(), isTrue);
      expect(Directory('${store.path}/old').existsSync(), isFalse);
    });

    test('폴더는 늙었지만 안의 파일이 새것이면 살린다', () async {
      // 폴더 mtime은 플랫폼마다 갱신 시점이 다르다. 그것만 믿으면 지금
      // 쓰고 있는 방을 늙었다고 지운다.
      final dir = makeRoom('active', fileCount: 1, bytes: 1000, age: const Duration(hours: 30));
      File('${dir.path}/turn_002.wav')
        ..writeAsBytesSync(Uint8List(1000))
        ..setLastModifiedSync(DateTime.now());

      await s.cleanup();

      expect(dir.existsSync(), isTrue);
    });

    test('_pending도 나이로 회수된다', () async {
      makeRoom(kOriginPcmPendingDir, fileCount: 1, bytes: 500, age: const Duration(hours: 40));
      await s.cleanup();
      expect(Directory('${store.path}/$kOriginPcmPendingDir').existsSync(), isFalse);
    });
  });

  group('전역 상한', () {
    test('넘치면 오래된 방부터 통째로 지운다', () async {
      makeRoom('a', fileCount: 1, bytes: 4000, age: const Duration(hours: 3));
      makeRoom('b', fileCount: 1, bytes: 4000, age: const Duration(hours: 2));
      makeRoom('c', fileCount: 1, bytes: 4000, age: const Duration(hours: 1));

      await s.cleanup(maxBytes: 9000);

      // 12000 → 9000 이하가 될 때까지 오래된 것부터. a가 먼저 나간다.
      expect(Directory('${store.path}/a').existsSync(), isFalse);
      expect(Directory('${store.path}/b').existsSync(), isTrue);
      expect(Directory('${store.path}/c').existsSync(), isTrue);
    });

    test('상한 안이면 아무것도 지우지 않는다', () async {
      makeRoom('a', fileCount: 2, bytes: 1000);
      makeRoom('b', fileCount: 2, bytes: 1000);

      await s.cleanup(maxBytes: 100000);

      expect(Directory('${store.path}/a').existsSync(), isTrue);
      expect(Directory('${store.path}/b').existsSync(), isTrue);
    });

    test('방 안에서 골라내지 않는다 — 통째로 나가거나 통째로 남는다', () async {
      makeRoom('a', fileCount: 5, bytes: 2000, age: const Duration(hours: 5));
      makeRoom('b', fileCount: 1, bytes: 2000, age: const Duration(hours: 1));

      await s.cleanup(maxBytes: 3000);

      expect(Directory('${store.path}/a').existsSync(), isFalse);
      // 남은 방은 파일이 하나도 빠지지 않았다.
      expect(Directory('${store.path}/b').listSync().length, 1);
    });
  });

  group('안전', () {
    test('하위 파일까지 실제로 센다', () async {
      // 폴더만 세고 안을 안 보면 크기가 0이라 상한에 절대 안 걸린다.
      makeRoom('big', fileCount: 10, bytes: 5000, age: const Duration(hours: 2));
      makeRoom('small', fileCount: 1, bytes: 100, age: const Duration(hours: 1));

      await s.cleanup(maxBytes: 1000);

      expect(Directory('${store.path}/big').existsSync(), isFalse,
          reason: '50,000바이트를 0으로 셌다면 이 방은 살아남는다');
    });

    test('창고 루트가 없어도 던지지 않는다', () async {
      store.deleteSync(recursive: true);
      await s.cleanup();
    });

    test('빈 창고에서도 던지지 않는다', () async {
      await s.cleanup();
      expect(store.existsSync(), isTrue);
    });

    test('폴더가 아닌 것이 루트에 있어도 넘어간다', () async {
      File('${store.path}/stray.txt').writeAsStringSync('x');
      makeRoom('a', fileCount: 1, bytes: 100, age: const Duration(hours: 40));

      await s.cleanup();

      expect(Directory('${store.path}/a').existsSync(), isFalse);
      expect(File('${store.path}/stray.txt').existsSync(), isTrue);
    });

    test('cleanupOnce는 앱 실행당 한 번이다', () async {
      makeRoom('old', fileCount: 1, bytes: 100, age: const Duration(hours: 40));
      await OriginPcmStore.cleanupOnce();
      expect(Directory('${store.path}/old').existsSync(), isFalse);

      // 두 번째 방은 두 번째 호출이 무시되므로 남는다.
      makeRoom('old2', fileCount: 1, bytes: 100, age: const Duration(hours: 40));
      await OriginPcmStore.cleanupOnce();
      expect(Directory('${store.path}/old2').existsSync(), isTrue);
    });
  });
}
