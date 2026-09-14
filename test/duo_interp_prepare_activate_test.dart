// 🎙️ [PREPARE/ACTIVATE] 마이크를 상대보다 **먼저** 돌린다.
//
// 게스트가 들어오자마자 호스트가 말하는 일은 흔하다. 예전에는 마이크가 상대
// 입장 **뒤에** 켜져서, 그 순간에 한 말은 소리 자체가 존재하지 않았다 —
// 앞 여유 고리를 아무리 길게 잡아도 담을 것이 없었다.
//
// 이 판이 가르는 것은 둘이다.
//
//   prepare   송신 경로를 **실제로 세운다**(PC·트랙·MicTap·SDP까지)
//   activate  상대가 들어왔다. 전사·번역·문을 연다
//
// 🔄 2026-09-14 실기기에서 원칙이 한 번 바뀌었다. 처음에는 prepare를 "로컬
//   미디어만"으로 잡고 SDP를 activate로 미뤘는데, **그러면 마이크가 안 돈다** —
//   libwebrtc의 ADM은 송신 트랙이 실제로 활성화돼야 AudioRecord를 시작한다
//   (`[DUO-MIC-TAP] stopped frames=0 bytes=0`). 그래서 prepare의 뜻을 바꿨다.
//
//   > 상대 입장 전에도 SDP·ICE 같은 연결 정보는 만들어질 수 있다.
//   > 하지만 사용자 음성은 STT·번역·상대 서비스 로직으로 절대 흘리지 않는다.
//
// 실기기 성공 기준(2026-09-14 개정):
//   ① first_frame_bytes < partner_joined   (필수)
//   ② offer_sent < partner_joined          (이제 허용된다)
//   ③ STT socket open > partner_joined     (필수)
//   ④ audio_gate=open > partner_joined     (필수)
//   ⑤ 상대 미입장 이탈 시 offer·ICE·PC·MicTap 전부 정리
//   ⑥ 과금은 prepare 구간에서 시작하지 않는다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// [start] 선언부터 [end] 선언 직전까지.
///
/// ⚠️ `expect`를 쓰지 않는다. 이 함수는 group 본문에서도 불리는데, 거기서는
/// `expect`가 `OutsideTestException`으로 죽는다. 앵커가 틀리면 그 사실이
/// 그대로 드러나야 하므로 던진다.
String _region(String src, String start, String end) {
  final from = src.indexOf(start);
  if (from < 0) throw StateError('missing start: $start');
  final to = src.indexOf(end, from + start.length);
  if (to <= from) throw StateError('missing end: $end');
  return src.substring(from, to);
}

void main() {
  final String duo = _read('lib/custom_code/widgets/routine_mode_duo.dart');
  final String call = _read('lib/custom_code/services/duo_webrtc_call.dart');

  group('①② prepare는 상대를 기다리지 않고, 밖으로 나가지 않는다', () {
    final String prepare =
        _region(duo, 'void _maybePrepareInterpreter(String reason)', '/// 📞 [ACTIVATE] 상대가 들어왔다. 신호·전사·문을');

    test('상대 조건이 prepare에 없다', () {
      expect(prepare.contains('_hasConversationPartner'), isFalse,
          reason: '상대를 기다리면 입장 순간의 말을 또 잃는다');
    });

    test('activate 쪽에는 상대 조건이 그대로 있다', () {
      final String activate = _region(duo,
          'void _maybeAutoStartInterpreter(String reason)', 'Future<void> _startInterpreterCapture');
      expect(activate, contains('if (!_hasConversationPartner) return;'));
    });

    test('prepare 본문은 전사·번역·전송을 시작하지 않는다', () {
      final String body = _region(duo,
          'Future<void> _startInterpreterCapture(String reason) async {',
          'Future<bool> _startInterpreterWebrtc(');
      for (final gone in <String>[
        '_ensureInterpreterStt(',
        '_openInterpGate(',
        '_uploadMyMessage(',
        '_processRelayPipeline(',
      ]) {
        expect(body.contains(gone), isFalse,
            reason: 'prepare가 $gone 를 부른다 — 상대 없이 밖으로 나간다');
      }
    });

    test('WebRTC prepare는 SDP까지 세운다 — 그래야 마이크가 돈다', () {
      final String body = _region(duo,
          'Future<bool> _startInterpreterWebrtc(', '/// 📞 [ACTIVATE] 상대가 들어왔다.');
      expect(body, contains('call.prepareLocalMedia()'));
      expect(body, contains('call.startSignaling()'),
          reason: 'SDP가 없으면 ADM이 녹음을 시작하지 않는다(frames=0)');
      // 다만 기다리지 않는다 — 기다리면 상대 입장 전까지 prepare가 안 끝난다.
      expect(body, contains('unawaited(call.startSignaling()'),
          reason: 'await하면 prepare가 상대를 기다리게 된다');
      // 문은 여전히 안 연다.
      expect(body.contains('_openInterpGate('), isFalse);
    });
  });

  group('③ activate에서만 신호·전사·문이 열린다', () {
    final String activate = _region(
        duo, 'Future<void> _activateInterpreter(String reason) async {', '/// 🔊 [INTERP-WEBRTC] 번역 음성이');

    test('전사와 문이 여기 있다', () {
      expect(activate, contains('_ensureInterpreterStt()'));
      expect(activate, contains("_openInterpGate('capture_started')"));
    });

    test('신호는 여기서 다시 하지 않는다', () {
      // 준비 단계가 이미 태웠다. 여기서 또 부르면 방금 올린 신호를 덮는다.
      expect(activate.contains('startSignaling()'), isFalse);
    });

    test('문이 마지막이다', () {
      final int stt = activate.indexOf('_ensureInterpreterStt()');
      final int gate = activate.indexOf("_openInterpGate('capture_started')");
      expect(stt, greaterThan(0));
      expect(gate, greaterThan(stt),
          reason: '문이 먼저 열리면 그 사이 말이 갈 곳이 없다');
    });
  });

  group('②-b connect()의 바깥 의미는 그대로다', () {
    test('connect = prepareLocalMedia + startSignaling', () {
      expect(call, contains('Future<bool> connect() async {'));
      expect(call, contains('if (!await prepareLocalMedia()) return false;'));
      expect(call, contains('return startSignaling();'));
    });

    test('addTrack은 prepare 쪽에 있다 — ADM을 깨우는 일이다', () {
      final String prep = _region(call,
          'Future<bool> prepareLocalMedia() async {', 'Future<bool> startSignaling() async {');
      expect(prep, contains('pc.addTrack('));
      expect(prep, contains('getUserMedia'));
      // 신호는 한 줄도 없어야 한다.
      for (final gone in <String>['sendOffer(', 'createOffer(', 'sendCandidate(']) {
        expect(prep.contains(gone), isFalse, reason: 'prepare에 $gone 가 있다');
      }
    });

    test('ICE 후보 전송은 signaling 쪽이다', () {
      final String sig = _region(call,
          'Future<bool> startSignaling() async {', 'void _wireConnectionState(');
      expect(sig, contains('signaling.sendCandidate('));
      expect(sig, contains('pc.setLocalDescription(offer)'));
    });
  });

  group('④ 상대 없이 끝나도 전부 정리된다', () {
    test('background로 가면 준비 구간을 놓는다', () {
      final String life = _region(duo,
          'void didChangeAppLifecycleState(AppLifecycleState state)', 'Future<void> _fetchKeys()');
      expect(life, contains('InterpLifecycle.preparing'));
      expect(life, contains('InterpLifecycle.transportReady'));
      expect(life, contains('_stopInterpreterCapture('));
      // 이미 선 통화는 건드리지 않는다.
      expect(life.contains('InterpLifecycle.active'), isFalse,
          reason: '통화 중에 백그라운드로 갔다고 마이크를 접으면 안 된다');
    });

    test('정리가 MicTap·PC·오디오 모드·상태를 모두 되돌린다', () {
      final String stop = _region(duo,
          'Future<void> _stopInterpreterCapture(String reason) async {', '/// 🔵 [INTERP-LIVE] 상대가 사라졌다.');
      expect(stop, contains('tap.stop()'));
      expect(stop, contains('call.dispose()'));
      expect(stop, contains('_restoreInterpreterAudioOut()'));
      expect(stop, contains('_interpSocketPcm?.reset()'));
      expect(stop, contains('InterpLifecycle.idle'));
      expect(stop, contains('_interpAutoStartAttempted = false'),
          reason: '다음 상대를 위해 다시 준비할 수 있어야 한다');
    });

    test('탭을 통화보다 먼저 접는다', () {
      final String stop = _region(duo,
          'Future<void> _stopInterpreterCapture(String reason) async {', '/// 🔵 [INTERP-LIVE] 상대가 사라졌다.');
      expect(stop.indexOf('tap.stop()'), lessThan(stop.indexOf('call.dispose()')),
          reason: '통화를 먼저 닫으면 탭이 사라진 트랙을 붙든다');
    });

    test('오디오 모드 복구가 통화 dispose 안에 있다', () {
      expect(call, contains('Helper.clearAndroidCommunicationDevice()'));
      expect(call, contains('AndroidAudioConfiguration.media'));
    });
  });

  group('⑤ 과금은 준비 구간에서 시작하지 않는다', () {
    test('prepare 본문에 과금 호출이 없다', () {
      final String body = _region(duo,
          'Future<void> _startInterpreterCapture(String reason) async {',
          'Future<bool> _startInterpreterWebrtc(');
      expect(body.contains('BillingTicker'), isFalse,
          reason: '혼자 기다리는 시간이 과금된다');
    });

    test('과금 시작은 게스트 입장 자리 그대로다', () {
      expect(duo, contains('void _startDuoBilling()'));
      final String joined = _region(duo,
          '// 🆕 [과금정책] 게스트 입장 확정 시 과금 시작 / 퇴장 시 정지', '// 🔴 [DUO-LIVE]');
      expect(joined, contains('_startDuoBilling()'));
    });
  });

  group('🔄 lifecycle은 되돌아가지 않는다', () {
    test('전이는 한 곳에서만 한다', () {
      expect(duo, contains('bool _toInterpLifecycle(InterpLifecycle next, String reason)'));
      expect(duo, contains("'rejected \${prev.name}->\${next.name} reason=\$reason'"));
    });

    test('준비 완료는 함수 반환이 아니라 첫 프레임이다', () {
      final String feed = _region(duo,
          'void _feedInterpreterPcm(Uint8List bytes, int generation)',
          '마이크를 닫는다. **소켓은 그대로 둔다.**');
      expect(feed, contains("_toInterpLifecycle(InterpLifecycle.transportReady, 'first_frame')"),
          reason: '함수 성공만 보면 frames=0으로 죽은 마이크를 준비됐다고 한다');
      expect(feed, contains('InterpMicPhase.waitingPartner'),
          reason: '화면 상태가 내부 상태와 따로 논다');
    });

    test('waitingPartner의 뜻이 바뀐 것을 적어 뒀다', () {
      expect(duo, contains('마이크는 이미 돌고 있을 수 있다'));
    });
  });

  // 🔢 [GENERATION] 2026-09-14 실기기 회귀. 마이크가 상대보다 먼저 서면서
  //   세대의 주인이 바뀌어야 했는데 그대로 뒀다. `_ensureInterpreterStt`가
  //   activate에서 세대를 올리는 바람에, prepare에서 묶인 MicTap·WebRTC
  //   콜백이 전부 남의 세대가 됐다 — 마이크는 도는데 한 조각도 안 들어오고
  //   화면의 라이브가 안 살았다. 직접통화는 이 경로를 안 타서 멀쩡했다.
  group('🔢 세대의 주인은 prepare다', () {
    test('세대를 올리는 자리는 마이크 세션 시작 한 곳뿐이다', () {
      final int bumps = RegExp(r'\+\+_interpGeneration').allMatches(duo).length;
      // prepare 1 + 정리 2(dispose · _finalizeDuoSession). 그 이상이면
      // 통화 도중에 또 올리는 자리가 생긴 것이다.
      expect(bumps, lessThanOrEqualTo(3),
          reason: '세대를 여러 곳에서 올리면 앞에서 묶은 콜백이 죽는다');
      // 올리는 자리가 전부 "세션을 열거나 닫는" 자리여야 한다.
      for (final inside in <String>[
        'Future<bool> _ensureInterpreterStt',
        'Future<void> _activateInterpreter',
      ]) {
        final int at = duo.indexOf(inside);
        final int next = duo.indexOf('\n  ///', at + inside.length);
        final int end = next > at ? next : duo.length;
        expect(duo.substring(at, end).contains('++_interpGeneration'), isFalse,
            reason: '\$inside 안에서 세대를 올린다 — 마이크가 죽는다');
      }
    });

    test('prepare가 세대를 올린다', () {
      final String body = _region(duo,
          'Future<void> _startInterpreterCapture(String reason) async {',
          'Future<bool> _startInterpreterWebrtc(');
      expect(body, contains('final int generation = ++_interpGeneration;'));
    });

    test('_ensureInterpreterStt는 읽기만 한다', () {
      final String body = _region(
          duo, 'Future<bool> _ensureInterpreterStt() async {', 'if (kDuoInterpUseSocketStt) {');
      expect(body, contains('final int generation = _interpGeneration;'));
      expect(body.contains('++_interpGeneration'), isFalse,
          reason: 'activate에서 세대를 올리면 prepare의 마이크가 죽는다');
    });
  });

  group('🔁 재시도는 실패한 단계에서만 다시 시작한다', () {
    test('마이크가 이미 섰으면 activate부터 다시 한다', () {
      final String body = _region(duo,
          'void _scheduleInterpRetry(int generation)', '/// 예약을 접는다.');
      expect(body, contains('stage=activate'));
      expect(body, contains("_activateInterpreter('retry_"));
      expect(body, contains('stage=prepare'));
      // 예전 가드를 그대로 두면 activate 실패 뒤 영영 안 붙는다.
      expect(body.contains("dropped reason=already_live"), isFalse,
          reason: '마이크가 살아 있다는 이유로 재시도를 통째로 버린다');
    });

    test('수동 재시도도 같은 규칙이다', () {
      final String body =
          _region(duo, 'void _retryInterpreterNow()', '/// 🔵 [INTERP-LIVE] 상대가 방에 있으면');
      expect(body, contains("_activateInterpreter('manual_retry')"));
      expect(body, contains("_startInterpreterCapture('manual_retry')"));
    });
  });

  // ⏳ [PREPARE-GUARD] 방을 켜 둔 채 방치된 경우만 잡는 마지막 안전장치.
  //   방 이탈·백그라운드 즉시 종료가 1순위이고, 이건 그 둘이 다 안 일어난
  //   경우만이다. **통화가 선 뒤에는 절대 안 걸린다.**
  group('⏳ 준비 상태 안전망', () {
    final String guard =
        _region(duo, 'void _armInterpPrepareGuard(String reason)', 'void _cancelInterpPrepareGuard(');

    test('준비 단계에서만 작동한다', () {
      expect(guard, contains('InterpLifecycle.preparing'));
      expect(guard, contains('InterpLifecycle.transportReady'));
      // 통화 중에 마이크를 접으면 대화가 끊긴다.
      expect(guard, contains("_lgDuo('[PREPARE-GUARD]', 'skipped stage="),
          reason: '다른 단계에서 불려도 아무것도 안 해야 한다');
    });

    test('상대가 있으면 안 건다 · 붙은 뒤엔 안 쏜다', () {
      expect(guard, contains('if (_hasConversationPartner) return;'),
          reason: '상대가 이미 있으면 곧 activate로 간다');
      expect(guard, contains("skipped reason=partner_online"),
          reason: '시계가 울릴 때 상대가 와 있으면 접어야 한다');
    });

    test('activate로 넘어가면 시계를 접는다', () {
      final String act = _region(duo,
          'Future<void> _activateInterpreter(String reason) async {', '/// 🔊 [INTERP-WEBRTC] 번역 음성이');
      expect(act, contains("_cancelInterpPrepareGuard('activating')"));
    });

    test('정리에서도 접는다', () {
      final String stop = _region(duo,
          'Future<void> _stopInterpreterCapture(String reason) async {', '/// 🔵 [INTERP-LIVE] 상대가 사라졌다.');
      expect(stop, contains('_cancelInterpPrepareGuard(reason)'));
    });

    test('10분은 UX가 아니라 안전망이라고 적어 뒀다', () {
      expect(duo, contains('const Duration kDuoInterpPrepareMaxWait = Duration(minutes: 10);'));
      expect(duo, contains('UX 정책이 아니라 안전망이다'));
    });
  });
}
