// 💾 [ORIGIN-PCM] 창고가 소리를 잃지 않는가.
//
// 이 층에는 판정이 없다. 그래서 검증할 것도 하나다 — **넣은 바이트가 그대로
// 나오는가.** 여기서 한 바이트라도 어긋나면 복원은 사람이 하지 않은 말을
// 근거로 원문을 고치게 된다.
//
// 디렉터리를 주입할 수 있게 만들어 둔 덕에 `path_provider`를 흉내 내지 않고
// 실제 파일 입출력을 그대로 검증한다.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_pcm_store.dart';
import 'package:stealth_vox/custom_code/services/pcm_audio_utils.dart';

/// 길이만 맞춘 가짜 PCM. 값은 위치마다 달라야 한다 — 전부 0이면 잘못된
/// offset으로 읽어도 테스트가 통과한다.
Uint8List fakePcm(int bytes, {int seed = 0}) {
  final out = Uint8List(bytes);
  for (var i = 0; i < bytes; i++) {
    out[i] = (i * 7 + seed * 31) & 0xFF;
  }
  return out;
}

void main() {
  late Directory root;
  final store = OriginPcmStore.instance;

  setUp(() {
    root = Directory.systemTemp.createTempSync('origin_pcm_test');
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

  group('넣고 꺼내기', () {
    test('put한 바이트가 read에서 그대로 나온다', () async {
      final pcm = fakePcm(4800, seed: 3); // 100ms
      await store.put('roomA', 1, pcm);

      final back = await store.read('roomA', 1);
      expect(back, isNotNull);
      expect(back!.lengthInBytes, pcm.lengthInBytes);
      expect(back, orderedEquals(pcm));
    });

    test('파일은 재생 가능한 WAV로 쓰인다', () async {
      // 디버깅할 때 직접 들어볼 수 있어야 한다. 헤더 없이 쓰면 못 듣는다.
      await store.put('roomA', 2, fakePcm(960));

      final file = File('${root.path}/$kOriginPcmDirName/roomA/turn_002.wav');
      expect(file.existsSync(), isTrue);
      final raw = file.readAsBytesSync();
      expect(String.fromCharCodes(raw.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(raw.sublist(8, 12)), 'WAVE');
      expect(raw.lengthInBytes, 960 + 44);
    });

    test('번호는 세 자리로 채워진다', () async {
      await store.put('roomA', 7, fakePcm(480));
      expect(
        File('${root.path}/$kOriginPcmDirName/roomA/turn_007.wav').existsSync(),
        isTrue,
      );
    });

    test('없는 발화는 null이다', () async {
      await store.put('roomA', 1, fakePcm(480));
      expect(await store.read('roomA', 2), isNull);
      expect(await store.read('roomB', 1), isNull);
    });

    test('빈 PCM·잘못된 번호는 아무것도 쓰지 않는다', () async {
      await store.put('roomA', 1, Uint8List(0));
      await store.put('roomA', 0, fakePcm(480));
      await store.put('roomA', -3, fakePcm(480));
      expect(
        Directory('${root.path}/$kOriginPcmDirName/roomA').existsSync(),
        isFalse,
      );
    });

    test('같은 번호를 다시 쓰면 마지막 것이 남는다', () async {
      // 저신뢰 재전사로 같은 턴이 두 번 올라올 수 있다. 나중 것이 옳다.
      await store.put('roomA', 1, fakePcm(480, seed: 1));
      await store.put('roomA', 1, fakePcm(960, seed: 2));

      final back = await store.read('roomA', 1);
      expect(back!.lengthInBytes, 960);
      expect(back, orderedEquals(fakePcm(960, seed: 2)));
    });

    test('겹쳐 들어온 put이 서로를 덮지 않는다', () async {
      // 대화방은 `unawaited`로 부른다. 직렬화가 없으면 매니페스트가 서로를
      // 덮어써 마지막 하나만 남는다.
      final writes = <Future<void>>[
        for (var i = 1; i <= 8; i++) store.put('roomA', i, fakePcm(480, seed: i)),
      ];
      await Future.wait(writes);

      final m = await store.manifest('roomA');
      expect(m.turns.length, 8);
      for (var i = 1; i <= 8; i++) {
        expect(await store.read('roomA', i), orderedEquals(fakePcm(480, seed: i)));
      }
    });

    test('꺼지면 아무것도 쓰지 않는다', () async {
      OriginPcmStore.enabled = false;
      await store.put('roomA', 1, fakePcm(480));
      expect(
        Directory('${root.path}/$kOriginPcmDirName/roomA').existsSync(),
        isFalse,
      );
    });
  });

  group('버리기', () {
    test('discard가 방 폴더를 통째로 지운다', () async {
      await store.put('roomA', 1, fakePcm(480));
      await store.put('roomB', 1, fakePcm(480));

      await store.discard('roomA');

      expect(
        Directory('${root.path}/$kOriginPcmDirName/roomA').existsSync(),
        isFalse,
      );
      // 남의 방은 건드리지 않는다.
      expect(await store.read('roomB', 1), isNotNull);
    });

    test('없는 방을 지워도 던지지 않는다', () async {
      await store.discard('nope');
      await store.discard('');
    });
  });

  group('방보다 먼저 온 발화', () {
    test('adoptPending이 _pending을 방으로 옮긴다', () async {
      // 첫 발화는 이름·장소·주제처럼 뒤따르는 줄의 기준이 되는 내용이 많다.
      await store.put('', 1, fakePcm(480, seed: 9));
      expect(
        File('${root.path}/$kOriginPcmDirName/$kOriginPcmPendingDir/turn_001.wav')
            .existsSync(),
        isTrue,
      );

      await store.adoptPending('roomA');

      expect(await store.read('roomA', 1), orderedEquals(fakePcm(480, seed: 9)));
      expect(
        Directory('${root.path}/$kOriginPcmDirName/$kOriginPcmPendingDir')
            .existsSync(),
        isFalse,
      );
    });

    test('방이 이미 쓴 번호는 덮지 않는다', () async {
      await store.put('roomA', 1, fakePcm(480, seed: 1));
      await store.put('', 1, fakePcm(960, seed: 2));

      await store.adoptPending('roomA');

      final back = await store.read('roomA', 1);
      expect(back!.lengthInBytes, 480, reason: '방 것이 옳다');
    });

    test('옮길 것이 없으면 조용히 돌아온다', () async {
      await store.adoptPending('roomA');
      await store.adoptPending('');
    });
  });

  group('매니페스트', () {
    test('무엇이 있는지 적는다', () async {
      await store.put('roomA', 1, fakePcm(4800));
      await store.put('roomA', 3, fakePcm(2400));

      final m = await store.manifest('roomA');
      expect(m.turns.map((t) => t.seq), <int>[1, 3]);
      expect(m.turnOf(1)!.bytes, 4800 + 44);
      expect(m.turnOf(1)!.ms, 100, reason: '24kHz 16bit에서 4800바이트는 100ms');
      expect(m.turnOf(2), isNull);
      expect(m.dropped, isEmpty);
    });

    test('깨져 있으면 파일 목록으로 되돌아간다', () async {
      await store.put('roomA', 1, fakePcm(480));
      await store.put('roomA', 2, fakePcm(480));
      File('${root.path}/$kOriginPcmDirName/roomA/_manifest.json')
          .writeAsStringSync('{ 이건 JSON이 아니다');

      final m = await store.manifest('roomA');
      expect(m.turns.length, 2, reason: '매니페스트는 편의이지 진실의 근거가 아니다');
    });

    test('매니페스트가 없어도 읽힌다', () async {
      await store.put('roomA', 1, fakePcm(480));
      File('${root.path}/$kOriginPcmDirName/roomA/_manifest.json').deleteSync();

      final m = await store.manifest('roomA');
      expect(m.turns.single.seq, 1);
    });

    test('없는 방은 빈 매니페스트다', () async {
      final m = await store.manifest('nope');
      expect(m.isEmpty, isTrue);
      expect(m.totalBytes, 0);
    });

    test('turn 파일이 아닌 것은 세지 않는다', () async {
      await store.put('roomA', 1, fakePcm(480));
      final dir = Directory('${root.path}/$kOriginPcmDirName/roomA');
      File('${dir.path}/notes.txt').writeAsStringSync('x');
      File('${dir.path}/turn_bad.wav').writeAsStringSync('x');

      // 매니페스트 파일을 지워 실제 스캔 경로를 태운다.
      File('${dir.path}/_manifest.json').deleteSync();
      final m = await store.manifest('roomA');
      expect(m.turns.single.seq, 1);
    });

    test('디스크의 매니페스트가 실제 JSON이다', () async {
      await store.put('roomA', 1, fakePcm(480));
      final decoded = jsonDecode(
        File('${root.path}/$kOriginPcmDirName/roomA/_manifest.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(decoded['room_id'], 'roomA');
      expect(decoded['sample_rate'], kStealthVoxSttSampleRate);
      expect((decoded['turns'] as List).length, 1);
    });
  });
}
