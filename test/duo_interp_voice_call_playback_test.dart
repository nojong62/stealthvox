// 🔊 [INTERP-PLAY] 통역 TTS는 통화 경로로 나간다 — 볼륨 키가 닿게
//
// 2026-09-11 실기기(SM-S931N). 통역 중 물리 볼륨 키가 통역 음량을 못 바꿨다.
//
//   dumpsys  STREAM_MUSIC speaker=0 / STREAM_VOICE_CALL speaker=5
//   재생기   usage=USAGE_MEDIA content=CONTENT_TYPE_MUSIC
//   볼륨키 10회 → VOICE_CALL 5→15, MUSIC 0 그대로
//
// 통화 중에는 볼륨 키가 STREAM_VOICE_CALL을 잡는데 통역 TTS는 미디어로
// 나가고 있었다. 미디어가 0이면 무음, 크면 줄일 방법이 없었다.
//
// 이 시험이 지키는 것 셋.
//   ① 통역만 네이티브 통화 경로를 쓴다 — 서클톡·시나리오톡·로봇·Direct 불변
//   ② 통역 재생기는 오디오 세션(mode/focus/route)을 건드리지 않는다
//   ③ feed의 await가 실제 write를 기다린다 — 백프레셔가 이 작업의 관문이다

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_interp_pcm_player.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';
const String _adapter = 'lib/custom_code/services/tts_adapter.dart';
const String _native =
    'android/app/src/main/kotlin/com/example/my_project/MainActivity.kt';
const String _direct = 'lib/custom_code/services/duo_direct_audio.dart';
const String _circle = 'lib/custom_code/widgets/routine_mode_circle_talk.dart';
const String _scenario =
    'lib/custom_code/widgets/routine_mode_scenario_talk.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// 공백을 한 칸으로 눌러 비교한다 — 들여쓰기 바뀌었다고 시험이 깨지면 안 된다.
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 네이티브 채널을 가로채 호출을 기록한다.
class _FakeChannel {
  _FakeChannel() : channel = const MethodChannel(kDuoInterpPcmChannel);

  final MethodChannel channel;
  final List<MethodCall> calls = <MethodCall>[];
  bool startResult = true;
  Duration appendDelay = Duration.zero;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'start') return startResult;
      if (call.method == 'appendBlocking' && appendDelay > Duration.zero) {
        await Future<void>.delayed(appendDelay);
      }
      return null;
    });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  List<String> get methods => calls.map((MethodCall c) => c.method).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String duo = _read(_duo);
  final String adapter = _read(_adapter);
  final String native = _read(_native);
  final String flatNative = _flat(native);

  // ── ① 주입 경계 ────────────────────────────────────────────────
  group('① 주입 경계 — 기본값은 예전 그대로', () {
    test('TtsAdapter는 계약을 받고, 안 주면 flutter_sound 재생기다', () {
      expect(adapter, contains('TtsPcmSink? pcmSink,'));
      expect(_flat(adapter), contains('_pcmPlayer = pcmSink ?? PcmStreamPlayer()'));
    });

    test('PcmStreamPlayer가 그 계약을 구현한다', () {
      expect(adapter, contains('class PcmStreamPlayer implements TtsPcmSink'));
    });

    test('서클톡·시나리오톡은 주입하지 않는다 — 한 글자도 안 바뀐다', () {
      for (final String path in <String>[_circle, _scenario]) {
        final String src = _read(path);
        expect(src, isNot(contains('pcmSink')), reason: '$path');
        expect(src, isNot(contains('DuoInterpPcmPlayer')), reason: '$path');
      }
    });

    test('통역 재생 경로를 유지하고 로봇 재생 경로는 제거됐다', () {
      final int interp = duo.indexOf('TtsAdapter? _ensureInterpreterTts()');
      expect(interp, greaterThan(-1));
      final String interpBody =
          duo.substring(interp, duo.indexOf('return adapter;', interp));
      expect(interpBody, contains('pcmSink: sink'));
      expect(duo, isNot(contains('_ensureRobotTts')));
    });
  });

  // ── ② 세션 비개입 ──────────────────────────────────────────────
  group('② 오디오 세션을 건드리지 않는다', () {
    test('네이티브에 모드 셋이 이름으로 갈라져 있다', () {
      expect(native, contains('PLAYBACK_MEDIA = "media"'));
      expect(
          native, contains('PLAYBACK_VOICE_CALL_MANAGED = "voiceCallManaged"'));
      expect(native,
          contains('PLAYBACK_VOICE_COMM_TRACK_ONLY = "voiceCommTrackOnly"'));
    });

    test('mode·speakerphone·통화포커스는 managed 분기 안에만 있다', () {
      final int start = native.indexOf('private fun startPcmStream');
      final int end = native.indexOf('private fun appendPcm(');
      final String whole = native.substring(start, end);
      final int a = whole.indexOf('if (mode == PLAYBACK_VOICE_CALL_MANAGED) {');
      final int b = whole.indexOf('} else if (mode == PLAYBACK_MEDIA) {');
      expect(a, greaterThan(-1));
      expect(b, greaterThan(a));
      final String managed = whole.substring(a, b);
      for (final String call in <String>[
        'manager.mode = AudioManager.MODE_IN_COMMUNICATION',
        'manager.isSpeakerphoneOn = true',
        'AudioManager.STREAM_VOICE_CALL',
      ]) {
        expect(managed, contains(call));
        expect(whole.split(call).length - 1, 1,
            reason: '$call 이 managed 밖에도 있으면 통역이 세션을 건드린다');
      }
    });

    test('trackOnly는 usage만 통화용이다', () {
      expect(
          flatNative,
          contains('if (mode == PLAYBACK_MEDIA) { AudioAttributes.USAGE_MEDIA '
              '} else { AudioAttributes.USAGE_VOICE_COMMUNICATION'));
    });

    test('trackOnly에서는 AudioManager를 아예 잡지 않는다', () {
      // audioManager 가 null 로 남는 것이 곧 해제 분기의 표식이다.
      final int start = native.indexOf('private fun startPcmStream');
      final int end = native.indexOf('private fun appendPcm(');
      final String whole = native.substring(start, end);
      expect(whole.split('audioManager = manager').length - 1, 2,
          reason: 'managed 와 media 두 분기에서만 잡아야 한다');
    });
  });

  // ── ③ Direct 불변 ──────────────────────────────────────────────
  group('③ Direct 기존 경로 불변', () {
    test('Direct 호출부는 손대지 않았다', () {
      final String src = _read(_direct);
      expect(src, contains("'voiceCall': true"));
      expect(src, isNot(contains('playbackMode')));
      expect(src, contains("invokeMethod<void>('append', pcm)"),
          reason: 'Direct 는 즉시 반환하는 append 그대로여야 한다');
      expect(src, isNot(contains('appendBlocking')));
    });

    test('네이티브가 옛 voiceCall:true를 managed로 받는다', () {
      expect(
          flatNative,
          contains('?: if (legacyVoiceCall) { PLAYBACK_VOICE_CALL_MANAGED'));
    });

    test('append와 appendBlocking은 서로 다른 메서드다', () {
      expect(native, contains('"append" ->'));
      expect(native, contains('"appendBlocking" ->'));
      expect(native, contains('private fun appendPcm(bytes: ByteArray)'));
      expect(native, contains('private fun appendPcmBlocking('));
    });

    test('블로킹 write는 executor 위에서만 돈다 — 플랫폼 스레드를 막지 않는다', () {
      final int a = native.indexOf('private fun appendPcmBlocking(');
      final int b = native.indexOf('private fun setPcmVolume(', a);
      final String body = native.substring(a, b);
      expect(body, contains('pcmExecutor.execute {'));
      expect(body, contains('WRITE_BLOCKING'));
      expect(body, contains('runOnUiThread { result.success(null) }'));
      expect(body.indexOf('pcmExecutor.execute {'),
          lessThan(body.indexOf('WRITE_BLOCKING')),
          reason: 'write 가 executor 밖이면 플랫폼 스레드가 멈춘다');
    });

    test('abort가 오래 막히지 않게 조각내어 쓴다', () {
      final int a = native.indexOf('private fun appendPcmBlocking(');
      final int b = native.indexOf('private fun setPcmVolume(', a);
      final String body = native.substring(a, b);
      expect(body, contains('generation == pcmGeneration'),
          reason: '조각 사이에 중단을 확인해야 abort 가 즉시 먹는다');
      expect(body, contains('minOf(slice, bytes.size - offset)'));
    });
  });

  // ── ④ 재생기 계약 ──────────────────────────────────────────────
  group('④ 재생기 계약', () {
    late _FakeChannel fake;
    late DuoInterpPcmPlayer player;

    setUp(() {
      fake = _FakeChannel()..install();
      player = DuoInterpPcmPlayer(channel: fake.channel);
    });
    tearDown(() => fake.remove());

    test('begin은 trackOnly 모드와 음량을 함께 넘긴다', () async {
      await player.begin(sampleRate: 24000, volume: 0.8);
      expect(player.isSessionActive, isTrue);
      final MethodCall start = fake.calls.first;
      expect(start.method, 'start');
      final Map<Object?, Object?> args =
          start.arguments as Map<Object?, Object?>;
      expect(args['playbackMode'], kPlaybackVoiceCommTrackOnly);
      expect(args['sampleRate'], 24000);
      expect(args['volume'], 0.8);
    });

    test('start가 거절되면 세션을 열지 않는다', () async {
      fake.startResult = false;
      await player.begin(sampleRate: 24000, volume: 1.0);
      expect(player.isSessionActive, isFalse);
      await player.feed(Uint8List(100));
      expect(fake.methods, isNot(contains('appendBlocking')));
    });

    test('feed는 블로킹 메서드를 쓴다 — 백프레셔가 여기 달려 있다', () async {
      await player.begin(sampleRate: 24000, volume: 1.0);
      await player.feed(Uint8List(4800));
      expect(fake.methods, contains('appendBlocking'));
      expect(fake.methods, isNot(contains('append')));
    });

    test('feed의 await가 네이티브 write를 기다린다', () async {
      fake.appendDelay = const Duration(milliseconds: 60);
      await player.begin(sampleRate: 24000, volume: 1.0);
      final Stopwatch sw = Stopwatch()..start();
      await player.feed(Uint8List(4800));
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(50),
          reason: '즉시 돌아오면 버퍼가 무한히 앞서 나간다');
      expect(player.feedMaxMs, greaterThanOrEqualTo(50));
    });

    test('remainingPlaybackMs는 먹인 양으로 센다 — 기기에 묻지 않는다', () async {
      await player.begin(sampleRate: 24000, volume: 1.0);
      // 24000Hz mono 16-bit → 48000 bytes = 1000ms
      await player.feed(Uint8List(48000));
      expect(player.remainingPlaybackMs(), greaterThan(700));
      expect(player.bufferedPeakMs, greaterThan(700));
    });

    test('setVolume은 세션이 열렸을 때만 나간다', () async {
      await player.setVolume(0.5);
      expect(fake.methods, isEmpty);
      await player.begin(sampleRate: 24000, volume: 1.0);
      await player.setVolume(0.5);
      expect(fake.methods, contains('setVolume'));
      final Map<Object?, Object?> args =
          fake.calls.last.arguments as Map<Object?, Object?>;
      expect(args['volume'], 0.5);
    });

    test('finish는 꼬리 무음을 먹이고 닫는다', () async {
      await player.begin(sampleRate: 24000, volume: 1.0);
      await player.feed(Uint8List(4800));
      await player.finish();
      expect(player.isSessionActive, isFalse);
      expect(fake.methods.last, 'finish');
      expect(fake.methods.where((String m) => m == 'appendBlocking').length, 2,
          reason: '본문 한 번 + 꼬리 무음 한 번');
    });

    test('abort는 stop을 보내고 세션을 닫는다', () async {
      await player.begin(sampleRate: 24000, volume: 1.0);
      await player.abort();
      expect(player.isSessionActive, isFalse);
      expect(fake.methods, contains('stop'));
    });

    test('dispose는 여러 번 불러도 안전하다', () async {
      await player.begin(sampleRate: 24000, volume: 1.0);
      await player.dispose();
      final int after = fake.calls.length;
      await player.dispose();
      await player.dispose();
      expect(fake.calls.length, after, reason: '닫힌 세션에 또 보내지 않는다');
    });

    test('feed가 실패해도 예외를 밖으로 내지 않는다', () async {
      await player.begin(sampleRate: 24000, volume: 1.0);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fake.channel, (MethodCall call) async {
        throw PlatformException(code: 'PCM_WRITE');
      });
      await expectLater(player.feed(Uint8List(100)), completes);
    });

    test('begin을 다시 부르면 앞 세션을 먼저 닫는다', () async {
      await player.begin(sampleRate: 24000, volume: 1.0);
      await player.begin(sampleRate: 24000, volume: 1.0);
      expect(fake.methods, contains('stop'));
    });
  });

  // ── ⑤ 게이트와 계측 ────────────────────────────────────────────
  group('⑤ 게이트와 계측', () {
    test('게이트 개폐는 어댑터 계층 그대로다', () {
      expect(_flat(duo),
          contains("onPlaybackStart: (request) => _closeInterpGate('tts_playing')"));
      expect(duo, contains("_scheduleInterpGateReopen('tts_finished')"));
    });

    test('재생 실패·타임아웃에도 게이트가 열린다', () {
      final int a = duo.indexOf('Future<void> _speakPartner(');
      final String body = duo.substring(a, duo.indexOf('[INTERP-STREAM]', a));
      final int timeout = body.indexOf('on TimeoutException');
      final int reopen =
          body.indexOf("_scheduleInterpGateReopen('tts_finished')");
      expect(timeout, greaterThan(-1));
      expect(reopen, greaterThan(timeout),
          reason: '재개가 catch 바깥에 있어야 어떤 끝에서도 열린다');
    });

    test('프리롤 줄에 백프레셔 두 값이 붙는다', () {
      expect(duo, contains('feedMaxMs='));
      expect(duo, contains('bufferedPeakMs='));
    });

    test('네트워크 에코 상태를 새로 만들지 않는다', () {
      expect(duo, isNot(contains('playingTts')), reason: 'Echo Guard는 로컬이다');
    });
  });
}
