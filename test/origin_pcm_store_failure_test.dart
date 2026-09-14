// 🔔 [STORE-FAIL] 소리를 못 담았다는 사실이 조용히 사라지면 안 된다.
//
// 지금은 못 담아도 글자가 이미 있어서 "재검증 불가"로 끝난다. 통화 후 일괄
// 전사로 넘어가면 PCM이 **원본**이라, 못 담은 발화는 글자 자체가 안 생긴다.
// 그때 어느 발화였는지 모르면 무엇이 사라졌는지도 알 수 없다.
//
// ⚠️ 이 알림은 **통화 오디오 경로를 기다리게 하지 않는다.** `putKeyed`의
//    계약이 "던지지 않는다 · 호출부는 unawaited"라서, 알림이 한 번이라도
//    기다리면 그 지연이 마이크 갈래에 실린다.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_pcm_store.dart';

void main() {
  late Directory root;
  final store = OriginPcmStore.instance;

  setUp(() {
    root = Directory.systemTemp.createTempSync('origin_pcm_fail');
    OriginPcmStore.debugRootOverride = root;
    OriginPcmStore.enabled = true;
    store.resetForTest();
    store.onStoreFailed = null;
  });

  tearDown(() {
    store.onStoreFailed = null;
    OriginPcmStore.debugRootOverride = null;
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('21 · capacity 초과는 silent failure가 아니다', () {
    test('상한을 넘은 발화마다 호출자에게 알린다', () async {
      final seen = <OriginPcmStoreFailure>[];
      store.onStoreFailed = seen.add;

      // 4MB씩 12개 = 48MB. 40MB를 넘는 뒤쪽이 버려진다.
      for (var i = 1; i <= 12; i++) {
        await store.putKeyed('roomA', 'utt_$i', Uint8List(4 * 1024 * 1024));
      }

      expect(seen, isNotEmpty,
          reason: '못 담은 발화가 있는데 아무도 그 사실을 듣지 못했다');
      expect(seen.every((f) => f.reason == kOriginPcmFailCapacity), isTrue);
      expect(seen.every((f) => f.roomId == 'roomA'), isTrue);
      // **발화 열쇠가 실려야 한다.** 방 이름만 알면 어느 말이 사라졌는지 모른다.
      expect(seen.first.pcmKey, startsWith('utt_'));
      expect(seen.first.bytes, greaterThan(0));
    });

    test('버려진 발화 수만큼 알림이 온다(첫 한 번이 아니다)', () async {
      var count = 0;
      store.onStoreFailed = (_) => count++;
      for (var i = 1; i <= 12; i++) {
        await store.putKeyed('roomA', 'utt_$i', Uint8List(4 * 1024 * 1024));
      }
      final dropped = store.droppedKeysOf('roomA');
      expect(dropped.length, greaterThan(1));
      expect(count, dropped.length);
    });

    test('호출자가 통화 뒤에 직접 물어볼 수도 있다', () async {
      expect(store.isRoomPcmComplete('roomA'), isTrue);
      for (var i = 1; i <= 12; i++) {
        await store.putKeyed('roomA', 'utt_$i', Uint8List(4 * 1024 * 1024));
      }
      expect(store.isRoomPcmComplete('roomA'), isFalse);
      expect(store.droppedKeysOf('roomA'), isNotEmpty);
    });

    test('정상 보존에는 알림이 없다', () async {
      var count = 0;
      store.onStoreFailed = (_) => count++;
      await store.putKeyed('roomA', 'utt_1', Uint8List(1024));
      expect(count, 0);
      expect(store.isRoomPcmComplete('roomA'), isTrue);
    });

    test('듣는 쪽이 터져도 창고는 계속 돈다', () async {
      store.onStoreFailed = (_) => throw StateError('listener exploded');
      for (var i = 1; i <= 12; i++) {
        await store.putKeyed('roomA', 'utt_$i', Uint8List(4 * 1024 * 1024));
      }
      // 앞쪽 발화는 멀쩡히 남아야 한다.
      expect(await store.readKeyed('roomA', 'utt_1'), isNotNull);
    });
  });

  group('알림은 통화 경로를 붙잡지 않는다', () {
    test('콜백 타입이 동기다 — Future를 돌려줄 수 없다', () {
      // 이 한 줄이 방어선이다. 반환형이 void라 구현자가 `await`를 심으려면
      // 타입을 먼저 바꿔야 하고, 그 변경은 리뷰에서 보인다.
      expect(store.onStoreFailed, isNull);
      void sink(OriginPcmStoreFailure f) {}
      store.onStoreFailed = sink;
      expect(store.onStoreFailed, isNotNull);
    });

    test('저장 경로에 새 await가 들어가지 않았다(소스 확인)', () {
      final String source =
          File('lib/custom_code/services/origin_pcm_store.dart')
              .readAsStringSync()
              .replaceAll('\r\n', '\n');
      final int start = source.indexOf('void _noteFailure(');
      expect(start, greaterThan(0));
      final String body = source.substring(start, start + 700);
      expect(body, isNot(contains('await')));
      expect(body, contains('[DUO-PCM] store_failed'));
    });
  });

  group('방 단위 전사 상태 — 다음 판이 쓸 이름', () {
    test('전사가 남았으면 pending', () {
      expect(
        resolveRoomTranscriptionState(captured: 10, transcribed: 4, lost: 0),
        kRoomTranscriptionPending,
      );
    });

    test('다 전사했고 잃은 소리도 없으면 complete', () {
      expect(
        resolveRoomTranscriptionState(captured: 10, transcribed: 10, lost: 0),
        kRoomTranscriptionComplete,
      );
    });

    test('소리를 못 남긴 발화가 있으면 다 전사해도 incomplete', () {
      expect(
        resolveRoomTranscriptionState(captured: 10, transcribed: 10, lost: 2),
        kRoomTranscriptionIncomplete,
      );
    });

    test('아무것도 안 담은 방은 complete다(빈 통화)', () {
      expect(
        resolveRoomTranscriptionState(captured: 0, transcribed: 0, lost: 0),
        kRoomTranscriptionComplete,
      );
    });
  });
}
