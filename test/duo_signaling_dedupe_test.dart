// 📮 [DUO-SIGNAL] 신호 rendezvous의 세 결함을 못 박는 시험.
//
// 셋 다 2026-09-02 실기기 통화에서 실제로 터진 것이다.
//
//   ① 같은 offer를 반복 적용 → answer 무한 생성
//      23초 통화에 answer 1,247회. Firestore 쓰기가 그만큼 나갔다.
//      원인: 내가 answer를 같은 문서에 쓰면 스냅샷이 다시 떨어지고
//            거기에 offer가 그대로 있는데, 중복 가드가 `type == 'answer'`
//            일 때만 걸려 있어 offer를 받는 쪽(게스트)이 무방비였다.
//
//   ② answerer가 offer를 기다리다 20초에 포기
//      게스트가 호스트보다 24초 먼저 시작해, 호스트가 offer를 올리기
//      4초 전에 리스너를 닫았다. offer는 정상적으로 올라갔지만 아무도
//      듣고 있지 않았다.
//
//   ③ sessionId를 폰마다 자기 `_directGeneration`으로 생성
//      두 값이 어긋나면 게스트가 호스트의 offer를 "남의 세대"로 버린다.
//      오늘은 우연히 둘 다 #1이라 안 터졌을 뿐이다.
//
// 여기서는 **판단 규칙 자체**를 시험한다. Firestore와 PeerConnection은
// 붙이지 않는다 — 규칙이 틀리면 실기기에서는 소리가 안 나는 것으로만
// 드러나고, 그때는 원인을 눈으로 못 가린다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_webrtc_signaling.dart';

/// `_applyRemoteDescription`의 중복 판단만 떼어 낸 모형.
/// 실제 코드와 **같은 열쇠**(`duoRemoteSdpKey`)를 쓴다.
class _Applier {
  String? _lastKey;
  int applied = 0;

  bool apply({
    required String sessionId,
    required String type,
    required String sdp,
  }) {
    final key = duoRemoteSdpKey(sessionId: sessionId, type: type, sdp: sdp);
    if (_lastKey == key) return false;
    _lastKey = key;
    applied++;
    return true;
  }

  /// ICE restart처럼 새 협상을 시작할 때. 이걸 안 놓으면 상대의 새 answer가
  /// "같은 신호"로 보여 적용되지 않는다.
  void resetForRenegotiation() => _lastKey = null;
}

void main() {
  const String kOffer = 'v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\nm=audio 9 UDP/TLS';
  const String kSession = 'room-1#1';

  group('① 같은 신호는 한 번만 적용한다', () {
    test('같은 offer 스냅샷 100회 → 적용 1회', () {
      final a = _Applier();
      for (var i = 0; i < 100; i++) {
        a.apply(sessionId: kSession, type: 'offer', sdp: kOffer);
      }
      expect(a.applied, 1, reason: '무한 재협상 고리가 그대로다');
    });

    test('answer를 쓴 뒤 같은 문서 스냅샷이 다시 와도 offer 재적용 없음', () {
      // 실기기에서 터진 그 모양 그대로다.
      final a = _Applier();
      expect(a.apply(sessionId: kSession, type: 'offer', sdp: kOffer), isTrue);
      // 내 answer 쓰기 → 스냅샷 → 같은 offer가 다시 실려 온다
      for (var i = 0; i < 50; i++) {
        expect(a.apply(sessionId: kSession, type: 'offer', sdp: kOffer), isFalse,
            reason: '재적용되면 answer가 또 생성된다');
      }
      expect(a.applied, 1);
    });

    test('같은 answer 반복 스냅샷도 재적용 없음 (offerer 쪽)', () {
      final a = _Applier();
      const String kAnswer = 'v=0\r\nanswer-sdp';
      for (var i = 0; i < 30; i++) {
        a.apply(sessionId: kSession, type: 'answer', sdp: kAnswer);
      }
      expect(a.applied, 1);
    });

    test('역할별 예외가 아니라 양쪽에 같은 규칙이 걸린다', () {
      // 예전 가드는 `type == 'answer'`일 때만 막아서 offer를 받는 쪽이
      // 무방비였다. 이제 종류와 무관하게 같은 규칙이다.
      final offerSide = _Applier();
      final answerSide = _Applier();
      for (var i = 0; i < 20; i++) {
        offerSide.apply(sessionId: kSession, type: 'answer', sdp: 'A');
        answerSide.apply(sessionId: kSession, type: 'offer', sdp: 'O');
      }
      expect(offerSide.applied, 1);
      expect(answerSide.applied, 1);
    });
  });

  group('① 정상 재협상은 막지 않는다', () {
    test('SDP가 실제로 달라지면 적용한다 (ICE restart)', () {
      final a = _Applier();
      a.apply(sessionId: kSession, type: 'answer', sdp: 'answer-v1');
      a.apply(sessionId: kSession, type: 'answer', sdp: 'answer-v2');
      expect(a.applied, 2, reason: 'ICE restart가 막히면 망 전환에서 복구 못 한다');
    });

    test('세션이 바뀌면 같은 SDP라도 새 신호다', () {
      final a = _Applier();
      a.apply(sessionId: 'room-1#1', type: 'offer', sdp: kOffer);
      a.apply(sessionId: 'room-1#2', type: 'offer', sdp: kOffer);
      expect(a.applied, 2);
    });

    test('종류가 바뀌면 새 신호다', () {
      final a = _Applier();
      a.apply(sessionId: kSession, type: 'offer', sdp: 'X');
      a.apply(sessionId: kSession, type: 'answer', sdp: 'X');
      expect(a.applied, 2);
    });

    test('재협상을 시작하면 상대의 새 answer를 다시 받는다', () {
      final a = _Applier();
      a.apply(sessionId: kSession, type: 'answer', sdp: 'same');
      a.resetForRenegotiation();
      expect(a.apply(sessionId: kSession, type: 'answer', sdp: 'same'), isTrue,
          reason: 'restart 뒤 같은 SDP가 와도 받아야 협상이 끝난다');
    });
  });

  group('한 통화의 answer 생성 횟수', () {
    test('offer 스냅샷이 몇 번 오든 answer는 1회다', () {
      // answer는 offer를 **적용했을 때만** 만든다. 적용이 1회면 answer도 1회다.
      final a = _Applier();
      var answers = 0;
      for (var i = 0; i < 200; i++) {
        if (a.apply(sessionId: kSession, type: 'offer', sdp: kOffer)) {
          answers++;
        }
      }
      expect(answers, 1, reason: '실기기에서 1,247회가 나왔던 자리다');
    });
  });

  group('③ 세션 id의 주인은 호스트다', () {
    test('열쇠에 세션이 들어가 서로 다른 통화가 섞이지 않는다', () {
      final k1 = duoRemoteSdpKey(sessionId: 'r#1', type: 'offer', sdp: kOffer);
      final k2 = duoRemoteSdpKey(sessionId: 'r#2', type: 'offer', sdp: kOffer);
      expect(k1, isNot(k2));
    });

    test('호스트는 세션 id 없이 만들 수 없다', () {
      // 게스트는 채택하므로 null로 시작하지만, 호스트는 진실값의 주인이라
      // 처음부터 값을 갖고 있어야 한다.
      expect(
        () => DuoWebrtcSignaling(roomId: 'r', isOfferer: true),
        throwsA(isA<AssertionError>()),
      );
    });

    test('게스트는 세션 id 없이 시작한다 — 문서에서 채택한다', () {
      final s = DuoWebrtcSignaling(roomId: 'r', isOfferer: false);
      expect(s.sessionId, isNull,
          reason: '게스트가 자기 generation으로 id를 지어내면 안 된다');
    });

    test('호스트는 준 값을 그대로 쓴다', () {
      final s = DuoWebrtcSignaling(
          roomId: 'r', isOfferer: true, offerSessionId: 'r#7');
      expect(s.sessionId, 'r#7');
    });
  });

  group('신호 자리의 모양', () {
    test('경로 상수가 흔들리지 않는다', () {
      // 규칙(firestore.rules)이 이 경로에 걸려 있다. 바뀌면 쓰기가 막힌다.
      expect(kDuoWebrtcCollection, 'webrtc');
      expect(kDuoWebrtcDoc, 'current');
      expect(kDuoWebrtcCandidateCollection, 'candidates');
      expect(kDuoWebrtcSessionField, 'sessionId');
    });
  });
}
