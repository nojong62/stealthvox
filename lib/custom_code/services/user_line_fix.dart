// ====================================================================
// 🩹 [USER_FIX] 직전 유저 발화의 전사 오류를 AI 답변과 **한 호출에서** 되살린다.
// --------------------------------------------------------------------
// 2026-09-12 실기기: "회원 아닌 사람" → "피는 아닌 사람", "비회원도" → "비위원도"
// 로 전사됐는데 Luna는 뜻을 잡고 답했다. 그 이해를 버리지 않고 직전 유저
// 말풍선·대화 문맥·저장 줄에 되돌려 넣는다. 추가 호출은 없다 — 답변 앞에
// 제어 줄 두 개가 붙을 뿐이다.
//
//   [USER_FIX]
//   <잘못 잡힌 낱말만 바꾼 유저 문장>
//   [REPLY]
//   <평소 답변>
//
// 원칙(실장님 확정):
//   - "잘못 들은 글자 복원"과 "더 자연스럽게 고치기"를 철저히 가른다. 말투·
//     문법·어순·어미는 손대지 않는다. 확신이 없으면 안 쓴다.
//   - 대화 중 고친 문장은 **교정 후보**다. 방을 나갈 때 원문 복원기가 PCM과
//     전체 문맥으로 한 번 더 확인해 최종 확정한다. 원 전사는 `stt_text`로
//     같이 남겨 그 검증의 근거가 되게 한다.
//   - 공부방은 이 대화방의 최종 대화를 그대로 받는다.
// ====================================================================

const String kUserFixTag = '[USER_FIX]';
const String kUserFixReplyTag = '[REPLY]';

/// 시스템 프롬프트에 붙는 규칙. Step 1·2 공통 — 유저 줄은 언제나 대화 언어다.
String buildUserFixPolicy({required String nativeLang}) {
  return '''[USER_FIX — RESTORE A MISRECOGNIZED USER LINE, NEVER REWRITE IT]
The user's line is speech-recognition text. Sometimes one word is caught wrong — a sound-alike word, a name, a particle, a dropped syllable — while the conversation makes the intended word certain.
Only when you are certain from context what the user actually said, output exactly:
$kUserFixTag
<the user's latest line with ONLY the misrecognized part replaced, in $nativeLang>
$kUserFixReplyTag
<your normal reply>
Rules for the $kUserFixTag line:
- Keep every other word, the word order, the grammar, the sentence ending and the speech level exactly as the user said them. This is restoration, not polishing.
- Replace only what the recognizer got wrong. If the line is fine, or you are not certain, do not use $kUserFixTag — reply normally with no tags.
- Never use it for a line you merely disagree with, or whose meaning is unclear. Unclear is a different case, handled by the ask-back rule.
- Never combine it with any other control format.
- Without the tags, everything you output IS your reply. Never output a restated, corrected or rewritten user line on its own — that is not a reply.''';
}

class UserLineFix {
  const UserLineFix({required this.userLine, required this.reply});

  /// 되살린 유저 문장(대화 언어).
  final String userLine;

  /// 그 뒤에 이어지는 평소 답변.
  final String reply;
}

String _stripQuotes(String s) =>
    s.trim().replaceAll(RegExp(r'^["“”\s]+|["“”\s]+$'), '');

/// 답변 전체에서 `[USER_FIX] … [REPLY] …`를 갈라낸다. 형식이 아니면 null.
UserLineFix? parseUserLineFix(String output) {
  final match = RegExp(
    r'^\[USER_FIX\]\s*([\s\S]*?)\s*\[REPLY\]\s*([\s\S]+)$',
    caseSensitive: false,
  ).firstMatch(output.trim());
  if (match == null) return null;
  final userLine = _stripQuotes(match.group(1) ?? '');
  final reply = _stripQuotes(match.group(2) ?? '');
  if (userLine.isEmpty || reply.isEmpty) return null;
  return UserLineFix(userLine: userLine, reply: reply);
}

/// 스트리밍 도중, 지금까지 온 글자가 아직 `[USER_FIX]`의 앞부분일 수 있는가.
/// 그동안은 화면·TTS에 한 글자도 내보내지 않는다.
bool userLineFixMayBeControlSignal(String partial) {
  final leading = partial.trimLeft();
  if (leading.isEmpty) return true;
  return kUserFixTag.startsWith(leading) || leading.startsWith(kUserFixTag);
}

/// 모델이 "복원"이 아니라 "다시 쓰기"를 했는지 거르는 마지막 안전선.
///
/// 글자 수가 절반 아래로 줄거나 두 배 넘게 늘면 낱말 하나를 바꾼 것이 아니다.
/// 원문과 똑같으면 고칠 것이 없었던 것이다.
bool userLineFixIsPlausible({
  required String original,
  required String fixed,
}) {
  final a = original.trim();
  final b = fixed.trim();
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return false;
  final ratio = b.length / a.length;
  return ratio >= 0.5 && ratio <= 2.0;
}

/// 저장 줄에 얹는 필드. 원 전사를 `stt_text`로 남긴다 — 원문 복원기의 근거이고
/// 화면·공부방에는 나오지 않는다.
Map<String, dynamic> userLineFixFields({required String sttText}) {
  return <String, dynamic>{
    'stt_text': sttText.trim(),
    'user_fix': true,
  };
}
