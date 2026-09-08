// ====================================================================
// 🔍 [ORIGIN-RESTORE] 사람이 실제로 말한 것을 되살린다
// --------------------------------------------------------------------
// 대화방은 속도가 전부라 발화 하나를 그 자리에서 전사하고 넘어간다. 그때는
// 앞뒤에 무슨 말이 오갔는지 아직 없다. 대화가 끝나고 나면 전부 있다 —
// 그래서 여기서 한 번 더 본다.
//
//   flush → 전체 Origin 훑기 → 의심점만 추출 → 그 발화의 PCM만 다시 듣기
//   → Origin 복원 → Target 관점에서 한 번 더 → 새 의심점만 다시 듣기
//   → Final Canonical Origin → discard → Final Target
//
// ⚠️ **문장을 다듬는 자리가 아니다.** 잘못 들은 낱말 하나를 되살리는 일이고,
//    그 외에는 전부 금지다. 사람의 말은 비문일 수 있고, 어색하다는 이유는
//    고칠 근거가 못 된다.
//
// 🚫 **Target은 Origin을 고치지 못한다.** 영어로 옮겼을 때 주어가 뒤집혀
//    보이면 그것은 "여기를 다시 들어 보라"는 신호일 뿐이다. Target을 고쳐
//    거꾸로 번역해 Origin에 덮는 길은 만들지 않는다 — 그 길이 있으면 말투와
//    뉘앙스가 갈리고, 하지 않은 말이 학습 자료로 남는다.
//
// 🚫 **PCM이 없으면 고치지 않는다.** 문맥만으로 고치는 것은 "문맥상 조금
//    이상하다"로 원문을 바꾸는 일과 구분되지 않는다. 소리가 없으면 원문이
//    남는다.
//
// **판정은 전부 이 파일의 순수 함수에 있다.** 모델 호출은 주입받으므로
// ([OriginRestorationEngine]), 테스트가 네트워크 없이 모든 갈래를 태운다.
// ====================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'transcript_repair_guard.dart';

/// 의심을 부른 까닭. 로그와 감사 기록이 이 값으로 갈린다.
enum SuspectReason {
  /// 이 줄의 행위자가 앞뒤 발화와 어긋난다(내가↔네가).
  speakerConflict,

  /// 대명사가 다른 사람을 가리킨다.
  pronounConflict,

  /// 숫자·시간·날짜·단위가 앞뒤 정보와 부딪힌다.
  numberConflict,

  /// 이름·지명·회사·제품이 다른 대상이 된다.
  properNounConflict,

  /// 긍정과 부정이 뒤집혔다.
  negationConflict,

  /// 시제 때문에 사건 순서가 어긋난다.
  tenseConflict,

  /// 소유주가 바뀐다.
  possessionConflict,

  /// 발음이 비슷한 다른 낱말로 들렸다.
  soundAlike,

  other,
}

/// 얼마나 확실한가. **[high]만 원문을 고친다.**
enum SuspectConfidence {
  /// PCM과 문맥이 같은 후보를 함께 지지한다.
  high,

  /// 문맥은 가리키지만 소리가 분명하지 않다. 원문을 지킨다.
  medium,

  /// 문법이 어색하다는 정도. **사람의 말은 비문일 수 있다.**
  low,
}

/// 소리가 무엇을 지지하는가.
enum AcousticVerdict {
  /// 다시 들어 보니 후보가 들린다.
  supportsCandidate,

  /// 다시 들어도 원문이 들린다. **고치지 않는다.**
  supportsOriginal,

  /// 둘 다 들리거나 둘 다 없다.
  unclear,

  /// 소리가 없다 — 파일 없음·손상·전사 실패·상한으로 못 씀.
  unavailable,
}

/// 복원이 보는 발화 하나.
@immutable
class RestorationTurn {
  const RestorationTurn({
    required this.id,
    required this.isUser,
    required this.text,
    this.pcmSeq,
    this.subjectHint = '',
  });

  final String id;
  final bool isUser;
  final String text;

  /// 이 발화의 소리를 가리키는 번호. **AI 줄과 상한에 걸린 줄은 null이다.**
  final int? pcmSeq;

  /// 이 줄이 누구 얘기인지 이미 정해져 있으면 그 값. 3자가 나오는 줄에만 있다.
  final String subjectHint;

  RestorationTurn withText(String next) => RestorationTurn(
        id: id,
        isUser: isUser,
        text: next,
        pcmSeq: pcmSeq,
        subjectHint: subjectHint,
      );
}

/// 다시 봐야 할 자리 하나.
///
/// **낱말쌍만 담는다.** 문장 전체를 담을 칸이 없으므로 모델이 구조적으로
/// 재작성을 할 수 없다 — 이것이 과수정을 막는 첫 번째 겹이다.
@immutable
class OriginSuspect {
  const OriginSuspect({
    required this.turnId,
    required this.span,
    required this.candidate,
    required this.reason,
    this.confidence = SuspectConfidence.medium,
    this.targetEvidence = '',
  });

  final String turnId;

  /// 원문에서 의심되는 조각.
  final String span;

  /// 그 자리에 들어갈 후보.
  final String candidate;

  final SuspectReason reason;

  /// 모델이 매긴 문맥 쪽 확신. 최종 판정은 소리와 함께 [resolveConfidence]가 한다.
  final SuspectConfidence confidence;

  /// Target 검사에서 온 의심일 때, 모델이 실제로 그 관점에서 읽었다는 근거.
  ///
  /// **번역을 건너뛰면 채울 수 없는 칸이다.** 한 번의 호출로 번역과 검사를
  /// 함께 시키면서도 모델이 정말 Target으로 해석했는지를 이 값으로 확인한다.
  final String targetEvidence;

  /// 같은 소리를 같은 까닭으로 두 번 보내지 않기 위한 열쇠.
  String cacheKey(String roomId) => '$roomId|$turnId|$span|$candidate';

  @override
  String toString() =>
      'OriginSuspect(turn=$turnId, reason=${reason.name}, conf=${confidence.name})';
}

/// 복원이 끝나고 남는 것.
@immutable
class RestorationOutcome {
  const RestorationOutcome({
    required this.turns,
    required this.corrections,
    required this.stats,
    this.abandoned = false,
  });

  /// 확정된 Final Canonical Origin.
  final List<RestorationTurn> turns;

  /// turnId → 고쳐진 글. **바뀐 줄만 들어 있다.**
  final Map<String, String> corrections;

  final RestorationStats stats;

  /// 복원을 포기했는가. 그래도 [turns]는 원문 그대로 채워져 있다.
  final bool abandoned;

  bool get changed => corrections.isNotEmpty;
}

/// 실기기에서 값을 조정할 근거.
///
/// **발화 내용은 담지 않는다.** 세는 것만 센다.
@immutable
class RestorationStats {
  const RestorationStats({
    this.turns = 0,
    this.suspects = 0,
    this.pcmRechecked = 0,
    this.pcmMissing = 0,
    this.corrected = 0,
    this.rejected = 0,
    this.targetSuspects = 0,
    this.secondRecheck = 0,
    this.cacheHit = 0,
    this.overflow = false,
  });

  final int turns;
  final int suspects;
  final int pcmRechecked;
  final int pcmMissing;
  final int corrected;
  final int rejected;
  final int targetSuspects;
  final int secondRecheck;
  final int cacheHit;
  final bool overflow;

  RestorationStats copyWith({
    int? turns,
    int? suspects,
    int? pcmRechecked,
    int? pcmMissing,
    int? corrected,
    int? rejected,
    int? targetSuspects,
    int? secondRecheck,
    int? cacheHit,
    bool? overflow,
  }) =>
      RestorationStats(
        turns: turns ?? this.turns,
        suspects: suspects ?? this.suspects,
        pcmRechecked: pcmRechecked ?? this.pcmRechecked,
        pcmMissing: pcmMissing ?? this.pcmMissing,
        corrected: corrected ?? this.corrected,
        rejected: rejected ?? this.rejected,
        targetSuspects: targetSuspects ?? this.targetSuspects,
        secondRecheck: secondRecheck ?? this.secondRecheck,
        cacheHit: cacheHit ?? this.cacheHit,
        overflow: overflow ?? this.overflow,
      );
}

// ══════════════════════════════════════════════════════════════════════
// 판정 — 전부 순수 함수다
// ══════════════════════════════════════════════════════════════════════

/// 비정상 응답을 막는 빗장. **정확도 정책이 아니다.**
///
/// 100줄 중 20줄이 의심스럽다면 그만큼 틀린 것이 아니라 모델이 폭주했거나
/// 전사가 통째로 무너진 것이다. 그런 응답을 반영하면 대화가 다른 대화가 된다.
///
/// ⚠️ **이 값을 정확도의 기준으로 쓰지 말 것.** 실기기 20~30 세션의 suspect
/// 비율을 재기 전까지는 무엇이 정상인지 아무도 모른다. 지금은 폭주만 막는다.
const double kSuspectSafetyCapRatio = 0.15;

/// 줄이 아주 적은 방에서 비율만으로 자르면 한 건도 못 고친다. 이만큼까지는
/// 비율과 무관하게 통과시킨다.
const int kSuspectSafetyCapFloor = 3;

/// 비정상적으로 많은가.
bool isSuspectOverflow(int suspects, int turns) {
  if (suspects <= kSuspectSafetyCapFloor) return false;
  if (turns <= 0) return true;
  return suspects > (turns * kSuspectSafetyCapRatio);
}

/// 원문의 [span]을 [candidate]로 바꾼 글. 바꿀 수 없으면 **null**이다.
///
/// 거절하는 경우와 그 까닭:
///   · [span]이 원문에 없다 — 모델이 지어낸 자리다.
///   · [span]이 원문에 두 번 이상 있다 — **어느 것인지 알 수 없다.** 첫 번째를
///     고르면 엉뚱한 자리를 고치게 된다.
///   · 바꾼 결과가 [isMinimalTranscriptRepair]를 통과하지 못한다 — 교정이
///     아니라 다시 쓴 문장이다. 그 가드를 우회하지 않는다.
String? applySpanPatch(String raw, String span, String candidate) {
  final from = span.trim();
  final to = candidate.trim();
  if (from.isEmpty || to.isEmpty || from == to) return null;
  final first = raw.indexOf(from);
  if (first < 0) return null;
  if (raw.indexOf(from, first + from.length) >= 0) return null;
  final patched = raw.replaceRange(first, first + from.length, to);
  if (patched.trim() == raw.trim()) return null;
  if (!isMinimalTranscriptRepair(raw, patched)) return null;
  return patched;
}

/// 다시 들은 글이 무엇을 지지하는가.
///
/// 판정은 **글자 비교**다. 재전사문에 후보가 들어 있고 원문 조각이 없으면
/// 후보를 지지한 것이고, 그 반대면 원문을 지킨 것이다. 둘 다 있거나 둘 다
/// 없으면 알 수 없다 — 그때는 고치지 않는다.
AcousticVerdict judgeAcoustic(String? rechecked, String span, String candidate) {
  final heard = (rechecked ?? '').replaceAll(RegExp(r'\s+'), '');
  if (heard.isEmpty) return AcousticVerdict.unavailable;
  final from = span.replaceAll(RegExp(r'\s+'), '');
  final to = candidate.replaceAll(RegExp(r'\s+'), '');
  if (from.isEmpty || to.isEmpty) return AcousticVerdict.unclear;
  final hasFrom = heard.contains(from);
  final hasTo = heard.contains(to);
  if (hasTo && !hasFrom) return AcousticVerdict.supportsCandidate;
  if (hasFrom && !hasTo) return AcousticVerdict.supportsOriginal;
  return AcousticVerdict.unclear;
}

/// 소리와 문맥을 합쳐 최종 등급을 낸다.
///
/// **[SuspectConfidence.high]는 소리가 후보를 지지할 때만 나온다.** 문맥이
/// 아무리 강해도 소리가 없으면 high가 될 수 없고, 그래서 PCM 없이 고치는
/// 길이 열리지 않는다.
SuspectConfidence resolveConfidence(
  AcousticVerdict verdict,
  SuspectConfidence contextConfidence,
) {
  switch (verdict) {
    case AcousticVerdict.supportsCandidate:
      // 문맥이 "문법이 어색하다" 정도면 소리가 맞아도 올리지 않는다.
      return contextConfidence == SuspectConfidence.low
          ? SuspectConfidence.low
          : SuspectConfidence.high;
    case AcousticVerdict.supportsOriginal:
      return SuspectConfidence.low;
    case AcousticVerdict.unclear:
    case AcousticVerdict.unavailable:
      return SuspectConfidence.medium;
  }
}

/// 이 의심을 실제로 반영하는가. **high 하나뿐이다.**
bool shouldApply(SuspectConfidence resolved) =>
    resolved == SuspectConfidence.high;

// ══════════════════════════════════════════════════════════════════════
// 모델 응답 읽기
// ══════════════════════════════════════════════════════════════════════

SuspectReason _reasonOf(Object? raw) {
  final v = (raw ?? '').toString().trim().toLowerCase();
  for (final r in SuspectReason.values) {
    if (r.name.toLowerCase() == v) return r;
  }
  // 스네이크로 오는 경우를 받아 준다("speaker_conflict").
  const map = <String, SuspectReason>{
    'speaker_conflict': SuspectReason.speakerConflict,
    'speaker_context_conflict': SuspectReason.speakerConflict,
    'subject_conflict': SuspectReason.speakerConflict,
    'pronoun_conflict': SuspectReason.pronounConflict,
    'number_conflict': SuspectReason.numberConflict,
    'numeric_conflict': SuspectReason.numberConflict,
    'proper_noun_conflict': SuspectReason.properNounConflict,
    'negation_conflict': SuspectReason.negationConflict,
    'tense_conflict': SuspectReason.tenseConflict,
    'possession_conflict': SuspectReason.possessionConflict,
    'sound_alike': SuspectReason.soundAlike,
    'acoustic_match': SuspectReason.soundAlike,
  };
  return map[v] ?? SuspectReason.other;
}

SuspectConfidence _confidenceOf(Object? raw) {
  switch ((raw ?? '').toString().trim().toLowerCase()) {
    case 'high':
      return SuspectConfidence.high;
    case 'low':
      return SuspectConfidence.low;
    default:
      return SuspectConfidence.medium;
  }
}

/// 모델이 준 JSON에서 의심점을 읽는다. **모르는 줄은 버린다.**
///
/// 깨진 응답이나 지어낸 turn id를 그대로 태우면 엉뚱한 줄을 고친다. 읽을 수
/// 없으면 빈 목록이고, 그러면 복원은 아무것도 하지 않은 채 끝난다 — 그것이
/// 잘못 고치는 것보다 낫다.
List<OriginSuspect> parseOriginSuspects(
  String content, {
  required Set<String> knownTurnIds,
  bool requireTargetEvidence = false,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return const <OriginSuspect>[];
  }
  final list = decoded is Map ? decoded['suspects'] : decoded;
  if (list is! List) return const <OriginSuspect>[];

  final out = <OriginSuspect>[];
  final seen = <String>{};
  for (final raw in list) {
    if (raw is! Map) continue;
    final turnId = (raw['turn_id'] ?? '').toString().trim();
    final span = (raw['span'] ?? raw['origin_span'] ?? '').toString().trim();
    final candidate =
        (raw['candidate'] ?? raw['candidate_origin'] ?? '').toString().trim();
    if (turnId.isEmpty || span.isEmpty || candidate.isEmpty) continue;
    if (!knownTurnIds.contains(turnId)) continue;
    if (span == candidate) continue;
    final evidence =
        (raw['target_evidence'] ?? raw['evidence_target'] ?? '').toString().trim();
    // Target 검사에서 온 것은 근거가 있어야 한다. 없으면 모델이 번역을
    // 건너뛰고 원문만 보고 답한 것이라, Target 관점의 의심이 아니다.
    if (requireTargetEvidence && evidence.isEmpty) continue;
    // 같은 자리에 같은 후보가 두 번 오면 하나만 본다.
    final key = '$turnId|$span|$candidate';
    if (!seen.add(key)) continue;
    out.add(OriginSuspect(
      turnId: turnId,
      span: span,
      candidate: candidate,
      reason: _reasonOf(raw['reason'] ?? raw['issue']),
      confidence: _confidenceOf(raw['confidence'] ?? raw['priority']),
      targetEvidence: evidence,
    ));
  }
  return out;
}

// ══════════════════════════════════════════════════════════════════════
// 지시문
// ══════════════════════════════════════════════════════════════════════

/// 전사 원문을 시간순으로 훑어 **의심점만** 되돌려 받는 지시문.
String buildOriginSuspectInstructions({required String sourceName}) =>
    '''You are auditing a speech-recognition transcript of a real conversation.

Your ONLY job is to point at words that speech recognition probably got wrong.
You are NOT editing, rewriting, improving, or translating anything.

WHAT COUNTS AS A SUSPECT
A word or short phrase that contradicts what the conversation itself establishes:
- The wrong person is doing the action ($sourceName drops subjects constantly, so this is the most common error of all).
- A pronoun points at someone the surrounding turns rule out.
- A possessor changes without the conversation saying so.
- A number, time, date, amount, or unit fights information given elsewhere.
- A negation is flipped: the turn says the opposite of what follows from the conversation.
- A tense puts events in an impossible order.
- A name, place, company, or product becomes a different one.
- A word that sounds like another word and only the other one makes sense here.

WHAT IS NOT A SUSPECT
- Awkward grammar. Real speech is often ungrammatical, and that is not an error.
- Informal, broken, or repeated speech. People talk that way.
- Anything you would merely phrase better.
- A word that is simply unusual but does not contradict anything.
If your reason is "this reads oddly", it is not a suspect. Say nothing.

THIRD PARTIES
Do not assume every subject is one of the two speakers. A conversation can bring in
a third person, and more than one. Follow who the conversation actually names, and
who the pronouns have been pointing at up to this line. When a SUBJECT is given for
a line, that line is already settled — do not contradict it.

OUTPUT
Return JSON only: {"suspects": [...]}. Each entry:
  "turn_id"    the id exactly as given
  "span"       the exact substring from that line, copied character for character
  "candidate"  what you believe was actually said, same length in words
  "reason"     one of: speakerConflict, pronounConflict, numberConflict, properNounConflict, negationConflict, tenseConflict, possessionConflict, soundAlike
  "confidence" high | medium | low
Rules for "span" and "candidate": both must be short — a word or two. Never return a
whole sentence. The span must appear in that line exactly once; if the word you suspect
appears more than once in the line, skip it. Never change the number of words.
Return {"suspects": []} when nothing contradicts anything. That is a normal answer and
often the correct one.''';

/// 복원된 Origin을 Target 관점에서 읽어 **다시 볼 자리만** 되돌려 받는 지시문.
///
/// 한 번의 호출로 번역과 검사를 함께 시킨다. 임시 Target을 통째로 받지 않으므로
/// 출력이 의심 건수에만 비례하고, `target_evidence`가 모델이 실제로 그 관점에서
/// 읽었다는 근거가 된다.
String buildTargetValidationInstructions({
  required String sourceName,
  required String targetLanguage,
}) =>
    '''You are checking a $sourceName transcript for recognition errors that only become visible in $targetLanguage.

Silently render each line into natural $targetLanguage in your head. Do not output the
translation. $sourceName leaves out subjects and objects; $targetLanguage cannot. That is
exactly why this pass exists — when you are forced to name who did what, a misheard
subject stops making sense.

REPORT A LINE WHEN, IN $targetLanguage:
- "I" and "you" come out swapped relative to what the conversation establishes.
- A third person gets attached to the wrong someone, or becomes "I" or "you".
- The actor of the sentence contradicts the surrounding turns.
- Possession moves to the wrong person.
- A negation is inverted.
- A number, time, or date fights other lines.
- A tense reverses the order events must have happened in.

YOU ARE A DETECTOR, NOT AN EDITOR.
You never fix the $targetLanguage. You never hand back a corrected translation. You point
at the $sourceName span that should be listened to again, and nothing else. The original
audio decides what was said — not you, and not the translation.

Do not report a line for reading awkwardly in $targetLanguage. Awkward is not wrong.

OUTPUT
Return JSON only: {"suspects": [...]}. Each entry:
  "turn_id"          the id exactly as given
  "origin_span"      the exact $sourceName substring to re-examine, appearing once in that line
  "candidate_origin" the $sourceName wording you believe was actually said
  "target_evidence"  the short $targetLanguage phrase that shows the problem
  "issue"            one of: speakerConflict, pronounConflict, numberConflict, properNounConflict, negationConflict, tenseConflict, possessionConflict
"target_evidence" is required. It is how we know you actually read this in $targetLanguage.
Return {"suspects": []} when nothing contradicts anything.''';

/// 모델에게 보여 줄 대화록 한 벌.
///
/// **turn id를 함께 싣는다** — 모델이 그 값을 그대로 돌려주어야 어느 줄인지
/// 알 수 있다. 화자는 이름이 아니라 역할로 적는다.
String formatRestorationTranscript(List<RestorationTurn> turns) {
  final buffer = StringBuffer();
  for (final t in turns) {
    buffer.writeln('[${t.id}] ${t.isUser ? 'USER' : 'OTHER'}: ${t.text}');
    if (t.subjectHint.trim().isNotEmpty) {
      buffer.writeln('    (SUBJECT: ${t.subjectHint.trim()})');
    }
  }
  return buffer.toString().trimRight();
}

// ══════════════════════════════════════════════════════════════════════
// 엔진
// ══════════════════════════════════════════════════════════════════════

/// 전체 대화를 훑어 의심점만 돌려준다.
typedef SuspectDetector = Future<List<OriginSuspect>> Function(
    List<RestorationTurn> turns);

/// 그 발화의 소리를 다시 들어 글로 돌려준다. 못 들으면 null.
typedef AcousticRechecker = Future<String?> Function(int pcmSeq);

/// 복원 한 판. **모델 호출을 주입받는다** — 판정은 전부 여기 있고 네트워크는
/// 바깥에 있어서, 테스트가 모든 갈래를 실제로 태울 수 있다.
class OriginRestorationEngine {
  const OriginRestorationEngine({
    required this.roomId,
    required this.detectSuspects,
    required this.recheckAcoustic,
    required this.validateTarget,
    this.log,
  });

  final String roomId;
  final SuspectDetector detectSuspects;
  final AcousticRechecker recheckAcoustic;
  final SuspectDetector validateTarget;
  final void Function(String message)? log;

  Future<RestorationOutcome> run(List<RestorationTurn> input) async {
    final turns = List<RestorationTurn>.of(input);
    var stats = RestorationStats(turns: turns.length);
    final corrections = <String, String>{};
    // 같은 소리를 같은 까닭으로 두 번 보내지 않는다. 세션 후처리 동안만 산다.
    final acoustic = <String, String?>{};

    if (turns.isEmpty) {
      _emit(stats);
      return RestorationOutcome(
          turns: turns, corrections: corrections, stats: stats);
    }

    // ── STEP 2 · 3 · 4 ────────────────────────────────────────────
    List<OriginSuspect> first;
    try {
      first = await detectSuspects(turns);
    } catch (error) {
      log?.call('[ORIGIN-RESTORE] detect_failed reason=${error.runtimeType}');
      _emit(stats);
      return RestorationOutcome(
          turns: turns, corrections: corrections, stats: stats, abandoned: true);
    }
    stats = stats.copyWith(suspects: first.length);

    if (isSuspectOverflow(first.length, turns.length)) {
      // 🚧 폭주. 그만큼 틀린 것이 아니라 응답이 무너진 것이다.
      log?.call('[ORIGIN-RESTORE] overflow suspects=${first.length} '
          'turns=${turns.length} — 전량 기각');
      stats = stats.copyWith(overflow: true, rejected: first.length);
      _emit(stats);
      return RestorationOutcome(
          turns: turns, corrections: corrections, stats: stats, abandoned: true);
    }

    stats = await _applyAll(first, turns, corrections, acoustic, stats,
        second: false);

    // ── STEP 5 · 6 · 7 · 8 ────────────────────────────────────────
    List<OriginSuspect> second;
    try {
      second = await validateTarget(turns);
    } catch (error) {
      // Target 검사가 죽어도 여기까지의 복원은 살린다.
      log?.call('[ORIGIN-RESTORE] target_failed reason=${error.runtimeType}');
      _emit(stats);
      return RestorationOutcome(
          turns: turns, corrections: corrections, stats: stats);
    }
    stats = stats.copyWith(targetSuspects: second.length);

    if (isSuspectOverflow(second.length, turns.length)) {
      log?.call('[ORIGIN-RESTORE] target_overflow suspects=${second.length} '
          'turns=${turns.length} — 2차는 전량 기각');
      stats = stats.copyWith(
          overflow: true, rejected: stats.rejected + second.length);
      _emit(stats);
      return RestorationOutcome(
          turns: turns, corrections: corrections, stats: stats);
    }

    stats = await _applyAll(second, turns, corrections, acoustic, stats,
        second: true);

    _emit(stats);
    return RestorationOutcome(
        turns: turns, corrections: corrections, stats: stats);
  }

  /// 의심 목록 하나를 소리에 물어보고, 통과한 것만 반영한다.
  Future<RestorationStats> _applyAll(
    List<OriginSuspect> suspects,
    List<RestorationTurn> turns,
    Map<String, String> corrections,
    Map<String, String?> acoustic,
    RestorationStats stats, {
    required bool second,
  }) async {
    var out = stats;
    for (final s in suspects) {
      final idx = turns.indexWhere((t) => t.id == s.turnId);
      if (idx < 0) {
        out = out.copyWith(rejected: out.rejected + 1);
        continue;
      }
      final turn = turns[idx];

      // 먼저 패치가 성립하는지 본다. 성립하지 않으면 소리를 물어볼 이유가
      // 없다 — 그 호출은 통째로 낭비다.
      final patched = applySpanPatch(turn.text, s.span, s.candidate);
      if (patched == null) {
        out = out.copyWith(rejected: out.rejected + 1);
        continue;
      }

      // 🚫 소리가 없으면 고치지 않는다. 문맥만으로 고치는 것은 "조금
      //   이상하다"로 원문을 바꾸는 일과 구분되지 않는다.
      final seq = turn.pcmSeq;
      if (seq == null) {
        out = out.copyWith(
            pcmMissing: out.pcmMissing + 1, rejected: out.rejected + 1);
        continue;
      }

      final key = s.cacheKey(roomId);
      String? heard;
      if (acoustic.containsKey(key)) {
        heard = acoustic[key];
        out = out.copyWith(cacheHit: out.cacheHit + 1);
      } else {
        try {
          heard = await recheckAcoustic(seq);
        } catch (error) {
          log?.call('[ORIGIN-RESTORE] recheck_failed '
              'reason=${error.runtimeType}');
          heard = null;
        }
        acoustic[key] = heard;
        out = out.copyWith(
          pcmRechecked: out.pcmRechecked + 1,
          secondRecheck: second ? out.secondRecheck + 1 : out.secondRecheck,
        );
      }

      final verdict = judgeAcoustic(heard, s.span, s.candidate);
      if (verdict == AcousticVerdict.unavailable) {
        out = out.copyWith(pcmMissing: out.pcmMissing + 1);
      }
      if (!shouldApply(resolveConfidence(verdict, s.confidence))) {
        out = out.copyWith(rejected: out.rejected + 1);
        continue;
      }

      turns[idx] = turn.withText(patched);
      corrections[turn.id] = patched;
      out = out.copyWith(corrected: out.corrected + 1);
    }
    return out;
  }

  void _emit(RestorationStats s) {
    // 🔇 발화 내용은 남기지 않는다. 세는 것만 센다.
    log?.call('[ORIGIN-RESTORE] turns=${s.turns} suspects=${s.suspects} '
        'pcm_rechecked=${s.pcmRechecked} pcm_missing=${s.pcmMissing} '
        'corrected=${s.corrected} rejected=${s.rejected} '
        'target_suspects=${s.targetSuspects} second_recheck=${s.secondRecheck} '
        'cache_hit=${s.cacheHit} overflow=${s.overflow}');
  }
}
