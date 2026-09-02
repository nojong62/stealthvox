// 🛣️ [DUO-RTC] "지금 P2P인가 TURN인가"를 읽어 내는 규칙의 시험.
//
// 이 함수가 틀리면 로그가 거짓말을 하고, **그 거짓말은 실기기에서 눈으로
// 못 잡는다.** 소리는 똑같이 잘 들리기 때문이다. TURN을 붙이지 않은 지금
// 단계에서 `P2P(...)`가 아닌 값이 나오면 곧바로 조사해야 하므로, 판정
// 규칙만큼은 실기기 없이 여기서 못 박는다.
//
// 표준 RTCIceCandidatePairStats에는 후보 **종류**가 없다. localCandidateId /
// remoteCandidateId로 후보 보고서를 가리킬 뿐이다. 그 간접 참조를 제대로
// 푸는지가 이 시험의 핵심이다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_webrtc_call.dart';
import 'package:webrtc_interface/webrtc_interface.dart' show StatsReport;

StatsReport _r(String id, String type, Map<String, dynamic> values) =>
    StatsReport(id, type, 0, values);

StatsReport _localCand(String id, String type) =>
    _r(id, 'local-candidate', <String, dynamic>{'candidateType': type});

StatsReport _remoteCand(String id, String type) =>
    _r(id, 'remote-candidate', <String, dynamic>{'candidateType': type});

StatsReport _pair(
  String id, {
  required String local,
  required String remote,
  String state = 'succeeded',
  bool? nominated,
  bool? selected,
}) =>
    _r(id, 'candidate-pair', <String, dynamic>{
      'localCandidateId': local,
      'remoteCandidateId': remote,
      'state': state,
      if (nominated != null) 'nominated': nominated,
      if (selected != null) 'selected': selected,
    });

void main() {
  group('후보 id → 종류를 풀어서 길을 읽는다', () {
    test('srflx 쌍이면 P2P다 — TURN 없는 지금 단계의 정답', () {
      final path = resolveDuoIcePath(<StatsReport>[
        _localCand('L1', 'srflx'),
        _remoteCand('R1', 'srflx'),
        _pair('P1', local: 'L1', remote: 'R1', nominated: true),
      ]);
      expect(path, 'P2P(srflx/srflx)');
    });

    test('같은 망(host 후보)도 P2P다', () {
      final path = resolveDuoIcePath(<StatsReport>[
        _localCand('L1', 'host'),
        _remoteCand('R1', 'host'),
        _pair('P1', local: 'L1', remote: 'R1', nominated: true),
      ]);
      expect(path, 'P2P(host/host)');
    });

    test('내 쪽이 relay면 TURN이다', () {
      final path = resolveDuoIcePath(<StatsReport>[
        _localCand('L1', 'relay'),
        _remoteCand('R1', 'srflx'),
        _pair('P1', local: 'L1', remote: 'R1', nominated: true),
      ]);
      expect(path, startsWith('TURN'));
    });

    test('상대 쪽만 relay여도 TURN이다 — 한쪽만 봐서는 안 된다', () {
      final path = resolveDuoIcePath(<StatsReport>[
        _localCand('L1', 'srflx'),
        _remoteCand('R1', 'relay'),
        _pair('P1', local: 'L1', remote: 'R1', nominated: true),
      ]);
      expect(path, startsWith('TURN'));
    });
  });

  group('어느 쌍을 고를 것인가', () {
    test('transport가 가리키는 쌍이 1순위다', () {
      // succeeded 쌍이 여럿일 때 아무거나 고르면 길을 잘못 읽는다.
      final path = resolveDuoIcePath(<StatsReport>[
        _r('T1', 'transport', <String, dynamic>{'selectedCandidatePairId': 'P2'}),
        _localCand('L1', 'relay'),
        _remoteCand('R1', 'relay'),
        _pair('P1', local: 'L1', remote: 'R1'),
        _localCand('L2', 'srflx'),
        _remoteCand('R2', 'srflx'),
        _pair('P2', local: 'L2', remote: 'R2'),
      ]);
      expect(path, 'P2P(srflx/srflx)');
    });

    test('transport가 없으면 nominated 쌍을 고른다', () {
      final path = resolveDuoIcePath(<StatsReport>[
        _localCand('L1', 'relay'),
        _remoteCand('R1', 'relay'),
        _pair('P1', local: 'L1', remote: 'R1'),
        _localCand('L2', 'host'),
        _remoteCand('R2', 'host'),
        _pair('P2', local: 'L2', remote: 'R2', nominated: true),
      ]);
      expect(path, 'P2P(host/host)');
    });

    test('실패한 쌍은 고르지 않는다', () {
      final path = resolveDuoIcePath(<StatsReport>[
        _localCand('L1', 'host'),
        _remoteCand('R1', 'host'),
        _pair('P1', local: 'L1', remote: 'R1', state: 'failed'),
      ]);
      expect(path, 'not-selected-yet');
    });

    test('아직 아무 쌍도 없으면 그렇다고 말한다 — P2P라고 넘겨짚지 않는다', () {
      expect(resolveDuoIcePath(<StatsReport>[]), 'not-selected-yet');
      expect(
          resolveDuoIcePath(<StatsReport>[_localCand('L1', 'srflx')]),
          'not-selected-yet');
    });
  });

  group('구현마다 다른 모양을 견딘다', () {
    test('종류를 쌍에 직접 실어 보내는 구현도 읽는다', () {
      // 일부 구현은 localCandidateType을 쌍에 바로 넣는다. 간접 참조가
      // 없어도 길을 읽을 수 있어야 한다.
      final path = resolveDuoIcePath(<StatsReport>[
        _r('P1', 'candidate-pair', <String, dynamic>{
          'state': 'succeeded',
          'nominated': true,
          'localCandidateType': 'srflx',
          'remoteCandidateType': 'host',
        }),
      ]);
      expect(path, 'P2P(srflx/host)');
    });

    test('후보 보고서가 없으면 물음표로 남긴다 — 지어내지 않는다', () {
      final path = resolveDuoIcePath(<StatsReport>[
        _pair('P1', local: 'L1', remote: 'R1', nominated: true),
      ]);
      // 길을 못 읽었다는 사실이 로그에 드러나야 한다.
      expect(path, 'P2P(?/?)');
    });
  });
}
