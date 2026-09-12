// ====================================================================
// 🤖 [DUO-ROBOT] 실제 상대 없이 Duo를 연습하기 위한 대화 상대
// --------------------------------------------------------------------
// Duo를 시험하려면 폰 두 대와 사람 둘이 필요했다. 그래서 마이크·발화 경계·
// 전사를 한 번 확인하려 해도 매번 자리를 만들어야 했고, 그 번거로움 때문에
// 정작 가장 자주 봐야 할 STT를 자주 못 봤다.
//
// 이 파일은 그 자리에 앉을 상대를 만든다. **말을 만들 뿐이다** — 듣는 일도
// 소리를 내는 일도 지금 Duo가 쓰는 것을 그대로 쓴다.
//
//   내 마이크 → PCM → Deepgram 경계 → gpt-transcribe → 문장 확정
//                                                        ↓
//                                              여기서 이 파일이 불린다
//                                                        ↓
//                              답변 한 줄 → 기존 큐/TTS로 되돌아간다
//
// 이제는 Duo의 정식 혼자 연습 상대다. 실제 상대방과 연결하지 않고도 같은
// 마이크·전사·통역·히스토리 경로를 연습할 수 있다.
//
// 🚫 **이 파일이 검증하는 것과 아닌 것**
//    검증한다  — 실제 마이크, PCM, Deepgram 발화 경계, gpt-transcribe,
//                문장 확정, 연속 대화 문맥, 통역의 번역·TTS·재생
//    검증 못 한다 — 상대 WebRTC 인바운드 오디오, `DuoPcmJitterPlayer`의
//                지터 버퍼 경로. 그 둘은 폰 두 대로 봐야 한다.
// ====================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Duo Robot 혼자 연습을 제공할 것인가. **여기가 유일한 판단처다.**
///
/// 🤖 **2026-09-11: 다시 올렸다.** 만능 통역을 재생 경로까지 손보면서 한 판을
///   여러 번 돌려야 하는데, 그때마다 폰 두 대와 사람 둘을 붙이는 것이 검증
///   횟수를 줄이고 있었다. 로봇은 통역의 번역·TTS·재생까지 그대로 태우므로
///   그 반복에 맞는다(못 보는 것은 파일 머릿말의 두 가지).
///
/// 정식 혼자 연습 기능이므로 디버그·릴리스 모두 제공한다.
const bool kDuoRobotAvailable = true;

/// 로봇이 쓰는 가짜 발신자 id. 실제 사람의 uid와 절대 겹치지 않는 모양이다.
const String kDuoRobotSenderUid = 'duo_robot_debug';

/// 대화 문맥으로 들고 갈 턴 수. 통화 상대는 방금 한 말을 기억하면 되지,
/// 30분 전을 되짚을 필요가 없다.
const int kDuoRobotMemoryTurns = 12;

/// 로봇이 쓰는 모델. 통화 상대는 빨라야 하고, 길게 말할 필요가 없다.
const String kDuoRobotModel = 'gpt-4.1-mini';

const Duration kDuoRobotTimeout = Duration(seconds: 12);

/// 오간 말 한 줄.
@immutable
class DuoRobotTurn {
  const DuoRobotTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

/// 사용자가 말하면 사람처럼 답하는 혼자 연습 상대.
///
/// **대화 상태를 자기가 들고 있는다.** 위젯이 턴마다 문맥을 조립해 넘기게
/// 하면 그 조립 코드가 Direct와 Interpreter 두 벌로 갈린다.
class DuoRobot {
  DuoRobot({required this.apiKey, this.onLog});

  final String apiKey;
  final void Function(String tag, String message)? onLog;

  final List<DuoRobotTurn> _memory = <DuoRobotTurn>[];

  /// 몇 번째 발화인가. 실제 Peer 메시지의 `seq`와 같은 자리에 쓴다.
  int _seq = 0;

  int get turnCount => _memory.length;

  void reset() {
    _memory.clear();
    _seq = 0;
  }

  /// 다음 발화 번호. 큐에 넣을 payload와 로그가 같은 값을 본다.
  int nextSeq() => ++_seq;

  /// 사용자의 말에 대한 답 한 줄. **실패하면 null이다.**
  ///
  /// 던지지 않는다 — 로봇이 한 턴 말을 못 해도 통화는 이어져야 하고, 다음
  /// 발화는 정상으로 받아야 한다.
  Future<String?> reply({
    required String userText,
    required String language,
    required bool isDirect,
  }) async {
    final String said = userText.trim();
    if (apiKey.isEmpty || said.isEmpty) return null;
    _memory.add(DuoRobotTurn(fromUser: true, text: said));
    _trim();

    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': kDuoRobotModel,
              // 통화 상대는 매번 같은 말을 하면 안 된다. 그렇다고 엉뚱한 데로
              // 새면 대화가 이어지지 않는다.
              'temperature': 0.8,
              'max_tokens': 120,
              'messages': _messages(language: language, isDirect: isDirect),
            }),
          )
          .timeout(kDuoRobotTimeout);
      if (response.statusCode != 200) {
        onLog?.call('[DUO-ROBOT]', 'reply_status=${response.statusCode}');
        return null;
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choices = body['choices'] as List? ?? const <dynamic>[];
      if (choices.isEmpty) return null;
      final message = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      final text = (message?['content'] ?? '').toString().trim();
      if (text.isEmpty) return null;
      _memory.add(DuoRobotTurn(fromUser: false, text: text));
      _trim();
      return text;
    } catch (error) {
      onLog?.call('[DUO-ROBOT]', 'reply_failed=${error.runtimeType}');
      return null;
    }
  }

  List<Map<String, String>> _messages({
    required String language,
    required bool isDirect,
  }) {
    final out = <Map<String, String>>[
      <String, String>{
        'role': 'system',
        'content': _persona(language: language, isDirect: isDirect),
      },
    ];
    for (final t in _memory) {
      out.add(<String, String>{
        'role': t.fromUser ? 'user' : 'assistant',
        'content': t.text,
      });
    }
    return out;
  }

  /// 로봇의 성격. **평범한 통화 상대 하나면 된다.**
  ///
  /// 지금 목적은 화려한 상대를 만드는 것이 아니라, 개발자가 계속 말을 걸
  /// 이유를 주는 것이다. 답이 길거나 매번 질문으로 끝나면 시험이 피곤해진다.
  String _persona({required String language, required bool isDirect}) {
    final medium = isDirect
        ? 'You are on a normal phone call with them, speaking the same language.'
        : 'You are on a call where an interpreter relays between you. Speak only your own language and let the interpreter do its work.';
    return '''You are a person on the other end of a phone call. Reply in $language.

$medium

How you talk:
- One or two sentences. This is speech, not writing.
- React to what they actually said before adding anything of your own.
- Do not end every turn with a question. Sometimes just answer, or say what you think.
- Have ordinary things going on in your life, and mention them the way anyone would.
- Keep the thread of the call. What they told you three turns ago still happened.
- Speak the way people speak out loud: contractions, short turns, no bullet points, no lists, no headings, no emoji.
- Never mention that you are an AI, a test, or a robot. You are simply the person they called.
- Never repeat a canned test phrase. This is a real conversation.

Your reply is read aloud by a speech synthesizer, so write only the words you would say.''';
  }

  void _trim() {
    while (_memory.length > kDuoRobotMemoryTurns) {
      _memory.removeAt(0);
    }
  }

  /// 실제 Peer가 올리는 메시지와 **같은 모양**의 payload.
  ///
  /// 이 값이 `_incomingQueue`로 들어가면 그 아래는 로봇인지 사람인지 구분하지
  /// 못한다 — 그것이 이 설계의 요점이다. 기존 처리 경로를 한 줄도 복제하지
  /// 않고 그대로 태운다.
  ///
  /// ⚠️ **Firestore에 쓰지 않는다.** 서버에는 로봇 발화가 남지 않는다.
  static Map<String, dynamic> payload({
    required String text,
    required String srcLang,
    required String duoMode,
    required String myRole,
    required int seq,
  }) =>
      <String, dynamic>{
        'senderUid': kDuoRobotSenderUid,
        // 방에서의 자리는 내 반대편이다.
        'senderRole': myRole == 'HOST' ? 'GUEST' : 'HOST',
        'text': text,
        'srcLang': srcLang,
        'duoMode': duoMode,
        'seq': seq,
        'spokenAt': DateTime.now().millisecondsSinceEpoch,
        // 채널 문서가 없으므로 로봇임을 알아볼 수 있는 값을 둔다. 히스토리
        // 줄에 그대로 남아, 나중에 이 방이 로봇 시험이었음을 알 수 있다.
        '__channelMsgId': 'robot_$seq',
      };
}
