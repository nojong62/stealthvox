// 🔀 [INTERP-STT-KIND] 통역의 전사 엔진을 두 벌로 둔다
//
// 09-06 `8d5fb27c`가 통역을 직접 대화와 같은 길에 올렸다 — 경계는 Deepgram이,
// 글자는 gpt-transcribe가. 아키텍처는 하나가 됐지만 **판정자가 둘로 갈렸다.**
// 그전에는 소켓 한 벌이 경계와 글자를 같이 맡아서 어긋날 자리가 없었다.
//
// 2026-09-10 실기기에서 그 대가가 나왔다.
//
//   RETRANSCRIBE ok len=0                    API는 멀쩡했다
//   transcribe=failed reason=empty_text      7.56초·15.84초짜리 무음이 올라감
//   utterance_end voiced=0/89 avgDbfs=-65.9  그 구간에 목소리가 없었다
//   closing started=2 ended=2                3분 통화에 발화가 둘뿐
//
// **gpt-transcribe가 맞고 Deepgram이 틀렸다.** 그래서 통역만 옛 소켓으로
// 되돌리되, Deepgram 경로는 지우지 않고 플래그로 남긴다 — 견주려면 둘 다
// 있어야 한다.
//
// 🚫 **직접 대화는 이 값을 보지 않는다.** 그쪽은 09-06 구조로 잘 돌고, 오늘
//   실기기에서도 전사가 정상이었다. 이 시험이 지키는 것은 그 경계다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// 줄 주석을 걷는다. 경고 주석에 적어 둔 옛 모양을 코드로 세지 않는다.
String stripComments(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final duo = stripComments(read('lib/custom_code/widgets/routine_mode_duo.dart'));

  group('통역 전사 엔진 손잡이', () {
    test('기본은 소켓이다', () {
      expect(duo, contains('const bool kDuoInterpUseSocketStt ='));
      expect(duo, contains("bool.fromEnvironment('DUO_INTERP_SOCKET_STT'"));
      expect(duo, contains('defaultValue: true'));
    });

    test('Deepgram 경로를 지우지 않았다', () {
      expect(duo, contains('DuoSttPipeline('),
          reason: '견주려면 둘 다 남아 있어야 한다');
      expect(duo, contains("kind=deepgram"));
    });

    test('두 갈래가 어느 엔진인지 로그로 밝힌다', () {
      expect(duo, contains('kind=socket'));
      expect(duo, contains('kind=deepgram'));
    });
  });

  group('갈리는 자리는 한 곳뿐이다', () {
    test('소켓 갈래는 통역 세션 안에만 있다', () {
      final interp = duo.indexOf('Future<bool> _ensureInterpreterStt');
      final branch = duo.indexOf('if (kDuoInterpUseSocketStt) {');
      expect(interp, greaterThanOrEqualTo(0));
      expect(branch, greaterThan(interp),
          reason: '분기가 통역 세션 밖에 있으면 직접 대화가 휘말린다');
    });

    test('직접 대화는 그 플래그를 보지 않는다', () {
      final direct = duo.indexOf('Future<void> _startDirectStt');
      if (direct < 0) return; // 이름이 바뀌면 아래 총량 검사가 잡는다
      final interp = duo.indexOf('Future<bool> _ensureInterpreterStt');
      final firstUse = duo.indexOf('if (kDuoInterpUseSocketStt) {');
      expect(firstUse, greaterThan(interp));
      expect(duo.substring(direct, interp > direct ? interp : duo.length)
              .contains('kDuoInterpUseSocketStt'),
          isFalse,
          reason: '직접 대화 쪽에서 이 값을 읽으면 두 모드가 다시 묶인다');
    });

    test('플래그를 읽는 자리는 손에 꼽을 만큼만이다', () {
      final uses = 'kDuoInterpUseSocketStt'.allMatches(duo).length;
      expect(uses, lessThanOrEqualTo(4),
          reason: '여기저기서 읽으면 나중에 한쪽만 바뀌어 반쪽만 켜진다');
    });
  });

  group('어댑터', () {
    test('두 엔진을 같은 이름으로 감싼다', () {
      expect(duo, contains('class _InterpSttHandle'));
      expect(duo, contains('_InterpSttHandle.socket('));
      expect(duo, contains('_InterpSttHandle.pipeline('));
    });

    test('부르는 자리가 어느 엔진인지 묻지 않는다', () {
      expect(duo, contains('_InterpSttHandle? _interpStt;'),
          reason: '필드가 어댑터 타입이라 스무 곳이 그대로 간다');
    });

    test('소켓에 없는 것은 어댑터가 흡수한다', () {
      final handle = duo.indexOf('class _InterpSttHandle');
      final note = duo.indexOf('void noteAccepted(', handle);
      expect(note, greaterThan(handle),
          reason: 'noteAccepted는 소켓에 없다 — 여기서 삼켜야 호출부가 안 깨진다');
    });
  });

  // 🔄 2026-09-14에 뒤집혔다. 예전에는 "서버가 잘라 간 덩이라 앱에 없다"가
  //   전제였고, 그래서 이 갈래에는 PCM이 하나도 안 남았다. 그 대가로
  //   로비값 재확인(origin probe)도, 통화 후 History 재전사도 설 자리가
  //   없었다. 이제 `DuoSocketPcmCapture`가 서버 경계에 맞춰 그 덩이를 만든다.
  group('소켓 갈래도 발화 소리를 남긴다', () {
    String socketBranch() {
      final branch = duo.indexOf('if (kDuoInterpUseSocketStt) {');
      final end = duo.indexOf('final session = DuoSttPipeline(', branch);
      expect(branch, greaterThan(0));
      expect(end, greaterThan(branch));
      return duo.substring(branch, end);
    }

    test('item_id가 정해지는 자리에서 소리를 확정해 창고에 넣는다', () {
      final body = socketBranch();
      expect(body, contains('_interpSocketPcm?.commitSpeech(itemId)'),
          reason: 'item_id 자리에서 안 확정하면 창고 열쇠가 어긋난다');
      expect(body, contains('_stashDuoPcm'),
          reason: '소리를 담아 놓고 창고에 안 넣으면 통화가 끝나면 사라진다');
      expect(body, contains('_onInterpreterTranscript'),
          reason: '전사 뒤 번역·TTS·History는 그대로 탄다');
    });

    test('경계는 여전히 서버가 준다 — 앱이 새로 판정하지 않는다', () {
      final body = socketBranch();
      // 담기 시작·확정이 서버 콜백 안에서만 일어나야 한다.
      expect(body, contains('socket.onSpeechStarted'));
      expect(body, contains('socket.onUtteranceCommitted'));
      // 앱이 스스로 발화를 열고 닫는 길이 생기면 판정기가 둘이 된다.
      expect(body.contains('VoiceActivityDetector'), isFalse);
    });
  });
}
