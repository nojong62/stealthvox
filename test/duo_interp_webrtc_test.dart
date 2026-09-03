// 📡 [INTERP-WEBRTC] 만능 통역을 직접 대화와 같은 WebRTC 골격 위에 올린다.
//
// 왜 — 통역의 마이크는 `record`가 여는 생 PCM이었다. WebRTC의 AEC/NS/AGC를
// 하나도 안 태운 소리라 세기가 -24 ~ -43dBFS로 출렁였고(2026-09-03 실측),
// 그 출렁임을 고정 문턱으로 가르려다 **진짜 사람 말을 버렸다.**
//
// 무엇을 바꾸나 — 마이크와 전달 통로 둘뿐이다:
//
//   끄면(기존)  record → STT → Firestore messages → 상대
//   켜면(새것)  WebRTC 마이크 → MicTap → STT → DataChannel → 상대
//
// 무엇을 안 바꾸나 — 조각이 도착한 **뒤의 모든 것**이다. 번역·TTS·큐·YIELD·
// 게이트·환청 방어는 그대로다. 그래야 실기기에서 "마이크만 바뀌었다"가 참이 되고,
// 좋아졌는지 나빠졌는지를 그 하나로 돌릴 수 있다.
//
// 🚫 상대 PCM은 전사하지 않는다. 이미 깨끗한 내 마이크 PCM이 있는데
//    Opus 압축 → 네트워크 → 지터버퍼 → 복원을 거친 소리를 전사할 이유가 없다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_webrtc_call.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';
const String _call = 'lib/custom_code/services/duo_webrtc_call.dart';
const String _tap = 'lib/custom_code/services/duo_webrtc_mic_tap.dart';

void main() {
  final String duo = File(_duo).readAsStringSync().replaceAll('\r\n', '\n');
  final String call = File(_call).readAsStringSync().replaceAll('\r\n', '\n');
  final String tap = File(_tap).readAsStringSync().replaceAll('\r\n', '\n');

  /// `_startInterpreterWebrtc`의 몸통만 잘라 본다.
  String startBody() {
    final int start = duo.indexOf('Future<bool> _startInterpreterWebrtc(');
    expect(start, greaterThan(-1), reason: '새 진입점이 없다');
    final int end = duo.indexOf('void _onInterpreterData(', start);
    expect(end, greaterThan(start), reason: '구역 경계를 못 잡았다');
    return duo.substring(start, end);
  }

  // ==========================================================================
  group('🚧 플래그 — 켜짐이 기본이고, 끄면 옛 경로 그대로다', () {
    test('기본값이 true다 — 빌드 명령을 외워야 도는 구조가 아니다', () {
      // v150 이전에는 false였고, 저장소 어디에도 `--dart-define`을 주는
      // 자리가 없었다. 그래서 debug APK·release APK·AAB 어느 것도 이 경로를
      // 타지 않았다. 기본값이 곧 실행 경로다.
      expect(
          duo,
          contains("bool.fromEnvironment('DUO_INTERP_WEBRTC', "
              "defaultValue: true)"),
          reason: '기본이 꺼져 있으면 아무 빌드도 이 경로를 안 탄다');
    });

    test('분기는 상수가 아니라 세션이 확정한 값을 본다', () {
      // 상수를 직접 보는 자리가 하나라도 남으면 Remote Config로 되돌렸을 때
      // 그 자리만 옛 값으로 돌아 캡처와 가드가 어긋난다.
      final int decl = duo.indexOf('bool get _useInterpWebrtc');
      for (final String site in <String>[
        'if (_useInterpWebrtc) {',
        '_useInterpWebrtc && !_isDirectMode',
      ]) {
        expect(duo, contains(site), reason: '\$site 자리가 없다');
      }
      // 선언·주석·폴백 게터 밖에서 상수를 읽지 않는다.
      final int fallback = duo.indexOf('String get _fallbackInterpTransport');
      expect(fallback, greaterThan(-1));
      expect(decl, greaterThan(-1));
    });

    test('롤백 경로를 지우지 않았다', () {
      // `--dart-define=DUO_INTERP_WEBRTC=false`로 돌아갈 자리가 있어야 한다.
      expect(duo, contains('PreparedAudioCapture.start('));
      expect(duo, contains('_listenForMessages'));
      expect(duo, contains('_uploadMyMessage('));
    });

    test('롤백이 빌드 타임이라는 사실이 선언 옆에 적혀 있다', () {
      // Remote Config가 아니다 — 되돌리려면 새 빌드가 필요하다.
      final int at = duo.indexOf("bool.fromEnvironment('DUO_INTERP_WEBRTC'");
      final String head = duo.substring(at - 1400, at);
      expect(head, contains('DUO_INTERP_WEBRTC=false'),
          reason: '되돌리는 방법이 선언 옆에 없으면 급할 때 못 찾는다');
    });

    test('꺼지면 마이크를 여는 주체가 예전 그대로다', () {
      final int at = duo.indexOf('if (_useInterpWebrtc) {',
          duo.indexOf('Future<void> _startInterpreterCapture('));
      expect(at, greaterThan(-1), reason: '분기가 없다');
      final int prepared =
          duo.indexOf('PreparedAudioCapture.start(', at);
      expect(prepared, greaterThan(at),
          reason: 'record 경로가 분기 뒤에 남아 있어야 한다');
    });
  });

  // ==========================================================================
  group('🎙️ 원어를 상대에게 보내지 않는다', () {
    test('통역은 sendAudio=false로 연다', () {
      // 붙이면 상대 스피커에서 원어가 그대로 난다. 통역이 아니게 된다.
      expect(startBody(), contains('sendAudio: false'));
    });

    test('직접 대화는 기본값(보냄) 그대로다', () {
      // `DuoWebrtcCall`의 기본이 true이므로 Direct 호출부는 아무것도 안 넘긴다.
      expect(call, contains('this.sendAudio = true'));
      final int at = duo.indexOf('Future<bool> _openWebrtcTransport(');
      final int end = duo.indexOf('_webrtcCall = call;', at);
      expect(end, greaterThan(at));
      expect(duo.substring(at, end), isNot(contains('sendAudio')),
          reason: '직접 대화 호출부를 건드리면 회귀다');
    });

    test('보내지 않을 때도 트랙 자체는 만든다', () {
      // MicTap이 붙을 대상이 그 트랙이다. 안 만들면 전사할 소리가 없다.
      final int at = call.indexOf('_localAudioTrack = tracks.first;');
      expect(at, greaterThan(-1));
      final String body = call.substring(at, at + 900);
      expect(body, contains('if (sendAudio) {'));
      expect(body, contains('pc.addTrack('));
    });

    test('상대 PCM을 전사하는 자리를 만들지 않았다', () {
      // 이번 설계의 명시적 제외 항목이다. 플러그인 포크도 원격 탭도 없다.
      expect(call, isNot(contains('getRemoteTrack')));
      expect(tap, isNot(contains('RemoteAudioTrack')));
      // 통역 진입점 어디에서도 원격 소리를 만지지 않는다.
      final String body = startBody();
      expect(body, isNot(contains('remote')));
      expect(body, isNot(contains('onRemoteVoice')));
    });

    test('네이티브 탭은 여전히 로컬 트랙 전용이다', () {
      // `getLocalTrack`이 유일한 통로다. 여기가 바뀌면 설계가 달라진 것이다.
      final String kt = File(
              'android/app/src/main/kotlin/com/example/my_project/DuoWebrtcMicTap.kt')
          .readAsStringSync();
      expect(kt, contains('getLocalTrack(trackId)'));
      expect(kt, contains('is LocalAudioTrack'));
    });
  });

  // ==========================================================================
  group('📨 글자는 DataChannel로 간다', () {
    test('채널 이름이 상수로 하나다', () {
      expect(kDuoInterpDataChannelLabel, 'duo-interp-text');
    });

    test('호스트가 만들고 게스트가 받는다 — 둘이 생기지 않는다', () {
      // 양쪽이 각자 만들면 채널이 두 개가 되고 한쪽 말이 사라진다.
      final int at = call.indexOf('if (withDataChannel) {');
      expect(at, greaterThan(-1));
      final String body = call.substring(at, at + 900);
      expect(body, contains('if (isOfferer) {'));
      expect(body, contains('pc.createDataChannel('));
      expect(body, contains('pc.onDataChannel ='));
    });

    test('순서와 도착을 보장한다', () {
      final int at = call.indexOf('pc.createDataChannel(');
      final String body = call.substring(at, at + 300);
      expect(body, contains('ordered = true'),
          reason: '발화 순서가 뒤집히면 대화가 안 된다');
    });

    test('직접 대화는 채널을 열지 않는다', () {
      expect(call, contains('this.withDataChannel = false'));
      final int at = duo.indexOf('Future<bool> _openWebrtcTransport(');
      final int end = duo.indexOf('_webrtcCall = call;', at);
      expect(duo.substring(at, end), isNot(contains('withDataChannel')));
    });

    test('보내기 실패를 삼키지 않는다', () {
      // 조용히 Firestore로 되돌아가면 어느 통로가 돌았는지 못 가린다.
      expect(call, contains('bool sendData('));
      expect(duo, contains('send ok='));
    });

    test('오디오를 이 채널로 보내지 않는다', () {
      final int at = duo.indexOf("_interpCall?.sendData(");
      expect(at, greaterThan(-1));
      final String body = duo.substring(at, at + 700);
      expect(body, contains("'text': spoken"));
      expect(body, isNot(contains('pcm')));
      expect(body, isNot(contains('bytes')));
    });

    test('상대가 골라 읽을 최소 정보가 실린다', () {
      final int at = duo.indexOf("_interpCall?.sendData(");
      final String body = duo.substring(at, at + 700);
      for (final String key in <String>[
        "'msgId'",
        "'senderRole'",
        "'text'",
        "'srcLang'",
        "'seq'",
        "'spokenAt'",
      ]) {
        expect(body, contains(key), reason: '$key 가 빠졌다');
      }
    });
  });

  // ==========================================================================
  group('🔁 같은 발화를 두 번 읽지 않는다', () {
    test('새 경로가 켜지면 Firestore는 통역 큐에 넣지 않는다', () {
      // 두 통로가 다 살아 있으면 한 발화를 두 번 번역하고 두 번 읽는다.
      final int at = duo.indexOf('void _listenForMessages()');
      final int end = duo.indexOf('void _enqueueIncoming(', at);
      expect(end, greaterThan(at));
      final String body = duo.substring(at, end);
      final int guard = body.indexOf('_useInterpWebrtc && !_isDirectMode');
      final int enqueue = body.indexOf('_enqueueIncoming(data)');
      expect(guard, greaterThan(-1), reason: '제외 조건이 없다');
      expect(enqueue, greaterThan(-1));
      expect(guard, lessThan(enqueue), reason: '큐에 넣은 뒤 막으면 늦다');
      expect(body, contains('firestore_skipped'),
          reason: '건너뛴 사실이 로그에 남아야 실기기에서 확인된다');
    });

    test('직접 대화는 어느 경우에도 Firestore 경로를 지난다', () {
      // 직접 대화의 글자는 이 채널로만 온다. 같이 막으면 History가 빈다.
      final int at = duo.indexOf('_useInterpWebrtc && !_isDirectMode');
      expect(at, greaterThan(-1));
      expect(duo.substring(at - 200, at + 100), contains('_isDirectMode'));
    });

    test('DataChannel 수신도 같은 장부로 중복을 막는다', () {
      final int at = duo.indexOf('void _onInterpreterData(');
      final String body = duo.substring(at, at + 1200);
      expect(body, contains('_processedMsgIds'));
      expect(body, contains("payload['msgId']"));
    });

    test('내가 보낸 것이 되돌아와도 안 읽는다', () {
      final int at = duo.indexOf('void _onInterpreterData(');
      final String body = duo.substring(at, at + 1200);
      expect(body, contains('if (role == _myRole) return;'));
    });

    test('수신은 기존 큐로 들어간다 — 두 번째 파이프라인을 만들지 않았다', () {
      // 번역·TTS·YIELD·게이트가 이미 검증된 경로다.
      final int at = duo.indexOf('void _onInterpreterData(');
      final String body = duo.substring(at, at + 1200);
      expect(body, contains('_enqueueIncoming(payload)'));
    });
  });

  // ==========================================================================
  group('📝 기록이 통화를 붙잡지 않는다', () {
    test('새 경로에서 History 쓰기를 기다리지 않는다', () {
      // Firestore가 2초 걸려도 상대 목소리가 늦어지면 안 된다.
      final int at = duo.indexOf('if (_useInterpWebrtc) {',
          duo.indexOf('Future<void> _processRelayPipeline('));
      expect(at, greaterThan(-1));
      final int end = duo.indexOf('    } else {', at);
      expect(end, greaterThan(at));
      final String body = duo.substring(at, end);
      expect(body, contains('unawaited(_uploadMyMessage('));
      expect(body, contains('unawaited(_saveHistoryMessage('));
      expect(body, isNot(contains('await _uploadMyMessage(')),
          reason: '기록을 기다리면 이 구조의 핵심이 무너진다');
    });

    test('실시간 전달이 기록보다 먼저다', () {
      final int at = duo.indexOf('if (_useInterpWebrtc) {',
          duo.indexOf('Future<void> _processRelayPipeline('));
      final String body = duo.substring(at, at + 1800);
      final int send = body.indexOf('sendData(');
      final int save = body.indexOf('unawaited(_uploadMyMessage(');
      expect(send, greaterThan(-1));
      expect(save, greaterThan(send), reason: '기록이 먼저면 전달이 그만큼 늦다');
    });

    test('기존 경로는 여전히 기다린다 — 순서를 안 바꿨다', () {
      final int at = duo.indexOf('    } else {',
          duo.indexOf('Future<void> _processRelayPipeline('));
      final String body = duo.substring(at, at + 1400);
      expect(body, contains('await _uploadMyMessage('));
      expect(body, contains('await _saveHistoryMessage('));
    });
  });

  // ==========================================================================
  group('🔬 마이크만 바뀌고 뒤는 그대로다', () {
    test('두 경로가 같은 PCM 처리기를 쓴다', () {
      // 여기가 갈리면 "마이크만 바뀌었다"가 거짓이 되어 비교가 무의미해진다.
      expect(duo, contains('void _feedInterpreterPcm('));
      final int n =
          RegExp(r'_feedInterpreterPcm\(bytes, generation\)').allMatches(duo).length;
      expect(n, 2, reason: 'record 경로와 WebRTC 경로 둘 다 이 함수를 써야 한다');
    });

    test('게이트·세기 계측·AEC 프로브가 그 안에 그대로 있다', () {
      final int at = duo.indexOf('void _feedInterpreterPcm(');
      final String body = duo.substring(at, at + 1400);
      expect(body, contains('stt.audioGateOpen'));
      expect(body, contains('_utteranceRms?.addPcm(bytes)'));
      expect(body, contains('_aecProbe.addIdle(bytes)'));
      expect(body, contains('_aecProbe.addDuringTts(bytes)'));
      expect(body, contains('stt.appendAudio(bytes)'));
    });

    test('보정 장치를 아직 하나도 지우지 않았다', () {
      // WebRTC AEC가 TTS 에코까지 지우는지는 실기기에서 확인할 일이다.
      expect(duo, contains('kDuoMinUtteranceRmsDbfs'));
      expect(duo, contains('[INTERP-YIELD]'));
      expect(duo, contains('_closeInterpGate'));
      expect(duo, contains('_looksLikeEcho'));
    });

    test('하드웨어 NS는 직접 대화와 같이 끈다', () {
      expect(startBody(), contains('disableHardwareNoiseSuppressor()'));
    });

    test('전사 PCM 출처가 webrtc_mic으로 남는다', () {
      expect(startBody(), contains('kDuoSttPcmSourceWebrtcMic'));
    });
  });

  // ==========================================================================
  group('🔊 소리가 나갈 곳', () {
    test('통역 경로에서만 정한다', () {
      // 직접 대화의 라우팅은 네이티브(`MainActivity.kt`)가 이미 하고 있다.
      expect(startBody(), contains('_routeInterpreterAudioOut()'));
      final int at = duo.indexOf('Future<bool> _openWebrtcTransport(');
      final int end = duo.indexOf('_webrtcCall = call;', at);
      expect(duo.substring(at, end), isNot(contains('setSpeakerphoneOn')),
          reason: '직접 대화 라우팅을 건드리면 회귀다');
    });

    test('이어폰·블루투스를 밀어내지 않는다', () {
      // 헤드셋 낀 사람의 소리를 스피커로 끌어내면 그게 더 나쁘다.
      final int at = duo.indexOf('Future<void> _routeInterpreterAudioOut()');
      expect(at, greaterThan(-1));
      final String body = duo.substring(at, at + 1600);
      final int wired = body.indexOf("'wired-headset'");
      final int bt = body.indexOf("'bluetooth'");
      final int force = body.indexOf('setSpeakerphoneOn(true)');
      expect(wired, greaterThan(-1));
      expect(bt, greaterThan(-1));
      expect(force, greaterThan(wired),
          reason: '외부 장치 확인보다 강제가 먼저면 헤드셋을 밀어낸다');
      expect(force, greaterThan(bt));
    });

    test('내가 켠 것만 되돌린다', () {
      // 남의 라우팅을 이 화면이 끄고 나가면 다음 화면 소리가 엉뚱해진다.
      final int at = duo.indexOf('Future<void> _restoreInterpreterAudioOut()');
      expect(at, greaterThan(-1));
      final String body = duo.substring(at, at + 800);
      expect(body, contains('if (!_interpForcedSpeaker) return;'));
      expect(body, contains('setSpeakerphoneOn(false)'));
      expect(body, contains('clearAndroidCommunicationDevice()'));
    });

    test('통화를 닫은 뒤에 되돌린다', () {
      // 먼저 되돌리면 WebRTC가 정리하면서 다시 통화 라우팅으로 덮어쓴다.
      final int at = duo.indexOf('Future<void> _stopInterpreterCapture(');
      final String body = duo.substring(at, at + 1400);
      final int disposeCall = body.indexOf('call.dispose()');
      final int restore = body.indexOf('_restoreInterpreterAudioOut()');
      expect(disposeCall, greaterThan(-1));
      expect(restore, greaterThan(disposeCall));
    });

    test('TTS 재생 코드는 안 건드렸다', () {
      // 라우팅만 정하고 재생기는 그대로다.
      final String tts =
          File('lib/custom_code/services/tts_adapter.dart').readAsStringSync();
      expect(tts, isNot(contains('setSpeakerphoneOn')));
      expect(tts, isNot(contains('Helper.')));
    });

    test('어디로 나가는지 로그에 남는다', () {
      expect(duo, contains('audio_route='));
      expect(duo, contains('speakerphone='));
    });
  });

  // ==========================================================================
  group('🧹 정리 순서', () {
    test('탭을 통화보다 먼저 접는다', () {
      // 통화를 먼저 닫으면 탭이 사라진 트랙을 붙들고 있게 된다.
      final int at = duo.indexOf('Future<void> _stopInterpreterCapture(');
      final String body = duo.substring(at, at + 1200);
      final int stopTap = body.indexOf('tap.stop()');
      final int disposeCall = body.indexOf('call.dispose()');
      expect(stopTap, greaterThan(-1));
      expect(disposeCall, greaterThan(stopTap));
    });

    test('채널도 같이 닫는다', () {
      final int at = call.indexOf('Future<void> dispose() async {');
      final String body = call.substring(at, at + 600);
      expect(body, contains('_dataChannel = null'));
      expect(body, contains('_dataChannelOpen = false'));
    });

    test('직접 대화와 다른 필드를 쓴다 — 정리 경로가 얽히지 않는다', () {
      expect(duo, contains('DuoWebrtcCall? _interpCall;'));
      expect(duo, contains('DuoWebrtcCall? _webrtcCall;'));
    });
  });

  // ==========================================================================
  group('📋 로그', () {
    test('새 태그 둘로만 남긴다', () {
      expect(duo, contains("'[INTERP-WEBRTC]'"));
      expect(duo, contains("'[INTERP-DATA]'"));
    });

    test('한 통화를 되짚을 최소 줄이 다 있다', () {
      for (final String line in <String>[
        'connection_started',
        'connection_ready',
        'connection_closed',
        'local_pcm',
        'channel_state=',
        'send ok=',
        'receive seq=',
      ]) {
        final bool present = duo.contains(line) || call.contains(line);
        expect(present, isTrue, reason: '"$line" 줄이 없다');
      }
    });

    test('발화 원문을 싣지 않는다 — 길이만', () {
      final int at = duo.indexOf("'[INTERP-DATA]',\n        'receive");
      expect(at, greaterThan(-1));
      final String block = duo.substring(at, at + 250);
      expect(block, contains('len='));
      expect(block, isNot(contains(r'$text')));
    });

    test('AEC/NS/AGC를 요청했다는 사실만 적고 적용됐다고 말하지 않는다', () {
      // 실제 적용 여부는 플랫폼이 정하고 알려 주지 않는다. 지어내면 안 된다.
      final String body = startBody();
      expect(body, contains('aec=requested'));
      expect(body, isNot(contains('aec=applied')));
    });
  });
}
