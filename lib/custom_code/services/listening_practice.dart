// ====================================================================
// 🎧 [LISTENING PRACTICE] 서클톡·시나리오톡 안의 Step 1 ↔ Step 2 전환.
// --------------------------------------------------------------------
// 새 모드도, 새 세션도 아니다. 한 대화방 안에서 스위치 하나로 **AI가 말하는
// 언어만** 바꾼다.
//
//   Step 1  지금까지의 대화방 그대로. AI는 유저의 대화 언어(ORIGIN)로 말한다.
//   Step 2  유저는 계속 자기 언어로 말하고, AI만 로비의 배울 언어(TARGET)로
//           답한다. 듣기 훈련이다 — 번역 모드가 아니다.
//
// 전환해도 STT·문맥·TTS 세션·과금·유휴 타이머는 아무것도 재시작하지 않는다.
// 프롬프트는 매 턴 새로 조립되므로, 바뀐 Step은 **다음 유저 턴의 AI 응답**부터
// 적용된다. 말하고 있는 AI 음성은 끊지 않는다.
//
// Step 1 경로의 프롬프트 문자열은 이 파일이 생기기 전과 한 글자도 다르지
// 않아야 한다. 여기 함수들은 Step 2일 때만 호출된다.
// ====================================================================

import 'package:flutter/material.dart';

import 'origin_language_session.dart'
    show detectOriginScript, textContradictsLanguage;

enum ListeningStep {
  step1,
  step2;

  /// History에 남기는 값. 1 / 2.
  int get value => this == ListeningStep.step1 ? 1 : 2;

  ListeningStep get toggled =>
      this == ListeningStep.step1 ? ListeningStep.step2 : ListeningStep.step1;
}

/// 배울 언어가 대화 언어와 같으면 Step 2는 의미가 없다. 스위치를 잠근다.
bool listeningStep2Available({
  required String nativeLang,
  required String targetLang,
}) {
  final n = nativeLang.trim().toLowerCase();
  final t = targetLang.trim().toLowerCase();
  return n.isNotEmpty && t.isNotEmpty && n != t;
}

/// Step 2의 출력 언어 규칙. [buildNativeOutputLanguagePolicy]의 자리에 들어간다.
///
/// 유저 말은 여전히 ORIGIN이라는 것을 못 박는다 — 모델이 "영어로 말하라"를
/// "유저도 영어로 말한다"로 읽고 유저 문장을 오해하는 일을 막는다.
String buildTargetOutputLanguagePolicy({
  required String nativeLang,
  required String targetLang,
}) {
  return '''OUTPUT LANGUAGE: Natural spoken $targetLang only.
- The user speaks $nativeLang. Treat every incoming text as their actual $nativeLang utterance and understand it fully.
- You reply in $targetLang only. Never switch back to $nativeLang, never translate the user's words, never place a second language beside yours.
- This is listening practice for the user: they listen to your $targetLang and answer in $nativeLang. That is normal — keep the conversation going in $targetLang.''';
}

/// Step 2의 말투 규칙. [kKoreanPoliteSpeechPolicy] 자리에 들어간다.
String buildTargetRegisterPolicy(String targetLang) {
  return 'Use the everyday polite spoken register of $targetLang. Keep it warm and spoken, never stiff or written.';
}

/// Step 2의 이해 확인 규칙. 시험이 아니라 대화 안에서 자연스럽게 되묻는다.
String buildListeningPracticePolicy({
  required String nativeLang,
  required String targetLang,
}) {
  return '''[LISTENING PRACTICE — CHECK UNDERSTANDING INSIDE THE CONVERSATION]
The user hears your $targetLang and answers in $nativeLang. Read their answer against what you just said.
- If it fits what you said: simply continue the conversation. Do not add a comprehension check.
- If it only partly fits: do not repeat yourself word for word. Ask again in shorter, plainer $targetLang, once.
- If it misses the point of your question: do not ignore their answer and do not just agree. Acknowledge what they said, then naturally bring the focus back in $targetLang.
Never test, grade, or correct the user. Never say they were wrong, never mention understanding or listening. Never press the same question more than once. Respect what they actually said and clarify only when the conversation needs it. It must feel like real talk.''';
}

/// History 줄에 얹는 Step 정보.
///
/// Step 2의 AI 줄은 AI가 실제로 한 배울 언어 문장이 `original_text`로 남는다.
/// `source_lang`을 같이 적어야 History가 그 줄을 "유저가 배울 언어로 말한
/// 원문"으로 착각하지 않고, 배울글은 복사로 끝낸다(`_sourceLangForMessage`).
/// HOST 줄은 언제나 유저의 ORIGIN이므로 `step`만 남긴다.
Map<String, dynamic> listeningStepFields(
  ListeningStep step, {
  required bool isAi,
  required String targetLang,
}) {
  return <String, dynamic>{
    'step': step.value,
    if (isAi && step == ListeningStep.step2) 'source_lang': targetLang.trim(),
  };
}

/// 고유 문자로 적는 언어. 이 언어를 기대하는데 답이 라틴 문자뿐이면 어긋난 것이다.
const Set<String> _kNonLatinScriptLanguages = <String>{
  'korean',
  'japanese',
  'chinese',
  'russian',
  'hindi',
};

/// AI 답변이 그 Step의 언어로 나왔는지. 글자로 확정될 때만 false다 — 라틴
/// 문자끼리(영어·프랑스어…)는 가릴 수 없어 true로 둔다. 재요청은 하지 않고
/// 로그만 남긴다.
bool replyMatchesListeningStep(
  String reply, {
  required ListeningStep step,
  required String nativeLang,
  required String targetLang,
}) {
  final expected = step == ListeningStep.step2 ? targetLang : nativeLang;
  if (textContradictsLanguage(reply, expected)) return false;
  // 한국어를 기대하는데 라틴 문자뿐이다 — 어느 라틴 언어인지는 몰라도
  // 한국어가 아닌 것은 분명하다.
  final verdict = detectOriginScript(reply);
  if (verdict.reason == 'latin_needs_judge' &&
      _kNonLatinScriptLanguages.contains(expected.trim().toLowerCase())) {
    return false;
  }
  return true;
}

/// 마이크 표시등 옆의 `Step 1 | Step 2` 스위치. 두 대화방이 같이 쓴다.
class ListeningStepSwitch extends StatelessWidget {
  const ListeningStepSwitch({
    super.key,
    required this.step,
    required this.enabled,
    required this.onChanged,
    this.activeColor = const Color(0xFFFBBF24),
  });

  final ListeningStep step;

  /// false면 배울 언어 == 대화 언어. 눌러도 아무 일도 없다.
  final bool enabled;
  final ValueChanged<ListeningStep> onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Container(
        height: 32,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _segment(ListeningStep.step1, 'Step 1'),
            _segment(ListeningStep.step2, 'Step 2'),
          ],
        ),
      ),
    );
  }

  Widget _segment(ListeningStep value, String label) {
    final bool active = step == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !enabled || active ? null : () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
