// 💾 [ORIGIN-PCM] 방 하나가 디스크를 독식하지 않는가.
//
// 10분 세션이 약 8.6MB이므로 정상 대화는 40MB에 닿지 않는다. **닿았다면
// 그것은 비정상 신호다** — 세션 종료 처리가 깨졌거나 창고가 새는 것이다.
// 그때 하는 일은 하나다: 더 쓰지 않는다. 이미 확보한 소리를 지워 자리를
// 내주면, 비정상 상황에서 멀쩡한 근거까지 잃는다.
//
// 그리고 **막히는 것은 보존뿐이다.** 전사도 대화도 그대로 간다.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_pcm_store.dart';

void main() {
  late Directory root;
  final store = OriginPcmStore.instance;

  /// 상한 근처까지 채운다. 40MB를 진짜로 쓰면 테스트가 느려지므로, 큰 덩이
  /// 몇 개로 경계를 만든다.
  Future<void> fill(String room, int chunks, int bytes) async {
    for (var i = 1; i <= chunks; i++) {
      await store.put(room, i, Uint8List(bytes));
    }
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('origin_pcm_quota');
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

  test('상한 아래에서는 전부 보존된다', () async {
    // 4MB씩 9개 = 36MB < 40MB
    await fill('roomA', 9, 4 * 1024 * 1024);

    final m = await store.manifest('roomA');
    expect(m.turns.length, 9);
    expect(m.dropped, isEmpty);
  });

  test('상한을 넘으면 그 뒤로 보존하지 않는다', () async {
    // 4MB씩 12개 = 48MB. 10번째에서 40MB를 넘는다.
    await fill('roomA', 12, 4 * 1024 * 1024);

    final m = await store.manifest('roomA');
    expect(m.turns.length, lessThan(12));
    expect(m.dropped, isNotEmpty);
    // 못 쓴 것은 뒤쪽 번호다.
    expect(m.dropped.first.compareTo(m.turns.last.key), greaterThan(0));
  });

  test('이미 써 둔 발화는 지우지 않는다', () async {
    await fill('roomA', 12, 4 * 1024 * 1024);

    // 앞쪽은 전부 살아 있어야 한다. 자리를 내주려고 오래된 것을 버리면
    // 비정상 상황에서 멀쩡한 근거까지 잃는다.
    final first = await store.read('roomA', 1);
    expect(first, isNotNull);
    expect(first!.lengthInBytes, 4 * 1024 * 1024);
  });

  test('못 쓴 번호는 dropped에 남는다', () async {
    await fill('roomA', 12, 4 * 1024 * 1024);

    final m = await store.manifest('roomA');
    for (final key in m.dropped) {
      // dropped에 있는데 파일도 있으면 둘 중 하나가 거짓말이다.
      expect(m.turnOf(key), isNull);
      expect(await store.readKeyed('roomA', key), isNull);
    }
  });

  test('"우리가 안 쓴 것"과 "OS가 지운 것"이 갈린다', () async {
    await store.put('roomA', 1, Uint8List(1024));
    await store.put('roomA', 2, Uint8List(1024));
    // OS가 하나를 걷어간 상황.
    File('${root.path}/$kOriginPcmDirName/roomA/turn_002.wav').deleteSync();

    final m = await store.manifest('roomA');
    // 매니페스트는 2번을 알고 있지만 파일이 없다 → OS가 지운 것.
    expect(m.dropped.contains(2), isFalse);
    expect(await store.read('roomA', 2), isNull);
  });

  test('방이 다르면 상한도 따로다', () async {
    await fill('roomA', 12, 4 * 1024 * 1024);
    await store.put('roomB', 1, Uint8List(1024));

    expect(await store.read('roomB', 1), isNotNull,
        reason: '남의 방이 넘쳤다고 이 방이 막히면 안 된다');
  });

  test('discard 뒤에는 상한이 초기화된다', () async {
    await fill('roomA', 12, 4 * 1024 * 1024);
    await store.discard('roomA');

    await store.put('roomA', 1, Uint8List(1024));
    expect(await store.read('roomA', 1), isNotNull);
  });
}
