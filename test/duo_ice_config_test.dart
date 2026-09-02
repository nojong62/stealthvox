// 🧊 [DUO-ICE] ICE 설정이 무엇을 믿고 무엇을 지어내지 않는가를 지키는 시험.
//
// 여기서 지키는 한 문장:
//   "TURN 주소나 비밀번호를 앱이 지어내지 않는다. 서버가 준 것만 쓰고,
//    못 받으면 STUN만으로 붙되 그 사실을 숨기지 않는다."
//
// `hasTurn`이 조용히 true가 되는 순간 대칭 NAT 실패의 유일한 단서가 사라진다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_ice_config.dart';

void main() {
  group('DuoIceConfig.stunOnly — TURN이 없을 때', () {
    test('STUN만 들어 있고 hasTurn은 거짓이다', () {
      final config = DuoIceConfig.stunOnly();
      expect(config.hasTurn, isFalse);
      expect(config.turnSource, 'none');
      expect(config.iceServers, isNotEmpty);
      final urls = config.iceServers.first['urls'] as List;
      expect(urls.every((u) => (u as String).startsWith('stun:')), isTrue);
    });

    test('turn: 주소를 지어내지 않는다', () {
      final config = DuoIceConfig.stunOnly();
      final everyUrl = config.iceServers
          .expand((s) => (s['urls'] as List).cast<String>())
          .toList();
      expect(everyUrl.any((u) => u.startsWith('turn:')), isFalse);
      expect(everyUrl.any((u) => u.startsWith('turns:')), isFalse);
    });

    test('username/credential을 만들어 넣지 않는다', () {
      final config = DuoIceConfig.stunOnly();
      for (final server in config.iceServers) {
        expect(server.containsKey('username'), isFalse);
        expect(server.containsKey('credential'), isFalse);
      }
    });
  });

  group('PeerConnection 설정', () {
    test('unified-plan과 계속 수집(continual gathering)을 켠다', () {
      // 통화 중 Wi-Fi ↔ LTE가 바뀌어도 새 후보를 찾을 수 있어야 한다.
      final map = DuoIceConfig.stunOnly().toPeerConnectionConfig();
      expect(map['sdpSemantics'], 'unified-plan');
      expect(map['continualGatheringPolicy'], 'gather_continually');
      expect(map['iceServers'], isNotEmpty);
    });
  });

  group('describe() — 실기기 로그에서 읽을 한 줄', () {
    test('TURN 유무가 문자열에 드러난다', () {
      // 이 한 줄이 "왜 소리가 안 났는가"를 가르는 근거가 된다.
      expect(DuoIceConfig.stunOnly().describe(), contains('turn=false'));
    });
  });
}
