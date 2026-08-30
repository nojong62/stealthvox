// 🚫 [NO-STT-FROM-REMOTE] 릴레이에서 받은 PCM이 전사로 새지 않는지 지킨다.
//
// 이건 단위 시험으로는 잡히지 않는다. `DuoMicPcmFanout`은 무엇을 물리든
// 두 갈래로 나눠 줄 뿐이라, 잘못된 것은 **무엇을 물렸는가**이기 때문이다.
// 그래서 배선 자체를 원문에서 읽어 확인한다.
//
// 이 시험이 깨지면 먼저 배선을 의심할 것. 이름만 바꿨다면 아래 상수를 고친다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _duoWidget = 'lib/custom_code/widgets/routine_mode_duo.dart';

/// `relay.inbound.listen((pcm) { … });` 의 본문만 떼어 온다.
String _inboundListenerBody(String source) {
  const String marker = 'relay.inbound.listen(';
  final int start = source.indexOf(marker);
  expect(start, greaterThan(-1),
      reason: '릴레이 수신 구독을 찾지 못했다 — 배선이 바뀌었다면 이 시험도 같이 고칠 것');
  var depth = 0;
  for (var i = start + marker.length - 1; i < source.length; i++) {
    final String c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('릴레이 수신 구독의 끝을 찾지 못했다');
}

void main() {
  final String source = File(_duoWidget).readAsStringSync();

  group('릴레이 수신 PCM의 종착지', () {
    test('수신 구독은 재생기와 계측기 말고 아무 데도 넘기지 않는다', () {
      final String body = _inboundListenerBody(source);

      // 가야 할 곳
      expect(body, contains('_jitterPlayer?.add(pcm)'));
      expect(body, contains('_remotePcmMeter?.note(pcm)'));

      // 가면 안 되는 곳 — 전사 입력의 모든 이름.
      expect(body, isNot(contains('appendAudio')));
      expect(body, isNot(contains('_directStt')));
      expect(body, isNot(contains('_directFanout')));
      expect(body, isNot(contains('fanout.add')));
      expect(body, isNot(contains('openai')));
      // 진단 비교기도 마찬가지다. 상대 소리를 A/B에 넣으면 "내 마이크가
      // 어떤가"를 묻는 자리에 남의 소리가 섞인다.
      expect(body, isNot(contains('_sttAbProbe')));
    });

    test('A/B 진단기에 PCM을 넣는 자리도 로컬 마이크 하나뿐이다', () {
      final Iterable<Match> feeds =
          RegExp(r'_sttAbProbe\?\.addPcm\(').allMatches(source);
      expect(feeds.length, 1,
          reason: '진단기에 두 곳에서 소리를 넣으면 비교 대상이 뒤섞인다');
      // 그 한 곳은 팬아웃의 세 번째 갈래다 = 마이크 스트림에서만 온다.
      final int at = feeds.single.start;
      final String around = source.substring(at - 200, at + 60);
      expect(around, contains('toProbe:'));
    });

    test('전사 팬아웃에 물리는 스트림은 로컬 마이크 캡처 하나뿐이다', () {
      // 팬아웃에 조각을 넣는 자리는 마이크 캡처 구독 안에만 있어야 한다.
      final Iterable<Match> feeds = RegExp(r'fanout\.add\(').allMatches(source);
      expect(feeds.length, 1, reason: '팬아웃에 PCM을 넣는 자리가 둘 이상이면 출처가 섞일 수 있다');

      final int captureSub = source.indexOf('capture.stream.listen(');
      expect(captureSub, greaterThan(-1));
      expect(feeds.single.start, greaterThan(captureSub),
          reason: 'fanout.add는 마이크 캡처 구독 안에서만 불려야 한다');
    });

    test('전사 세션에 넣는 PCM은 팬아웃을 거쳐서만 들어간다', () {
      // 직접 대화 경로에서 appendAudio를 직접 부르는 자리가 없어야 한다.
      // (만능 통역은 릴레이를 쓰지 않으므로 이 규칙 밖이다)
      final int directStart = source.indexOf('Future<void> _startDirectCall(');
      final int directEnd = source.indexOf('Future<void> _stopDirectCall(');
      expect(directStart, greaterThan(-1));
      expect(directEnd, greaterThan(directStart));
      final String directRegion = source.substring(directStart, directEnd);

      final Iterable<Match> appends =
          RegExp(r'appendAudio\(').allMatches(directRegion);
      expect(appends.length, 1,
          reason: '직접 대화에서 전사에 PCM을 넣는 자리는 팬아웃의 toStt 하나뿐이다');
      expect(directRegion.substring(0, appends.single.start),
          contains('toStt: (bytes) =>'));
    });
  });
}
