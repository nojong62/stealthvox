// ====================================================================
// 🎬 [REPLAY-RULES] "두 사람이 실제로 나눈 대화를, 읽고 공부할 수 있는
// 대화로 다시 세운 것."
// --------------------------------------------------------------------
// 규칙·프롬프트·빗장만 둔다. **네트워크도 Firestore도 모른다** — 그래야
// `tool/replay_probe.dart`가 실기기 없이 같은 규칙을 돌려 볼 수 있고,
// 시험도 모델 없이 빗장만 따로 검사할 수 있다.
// 실제 호출과 저장은 `duo_replay.dart`가 맡는다.
//
// 2026-08-29 방향 조정: 조건을 잘게 달아 두니 결과가 부자연스러웠다. 이제
// 모델에게 **통화 전체를 먼저 읽고 맥락과 중요한 주고받기 중심으로** 쓰게
// 한다. 잘라내는 판단은 열되, **없던 사실을 만드는 것만 닫는다.**
//
// CANONICAL과 무엇이 다른가.
//
//   CANONICAL  줄을 **가린다**. 원문 글자는 그대로 두고 study_state만 바꾼다.
//              지운 것이 없으므로 언제나 되돌아갈 자리가 된다.
//   REPLAY     대화를 **다시 세운다**. 중요하지 않은 주고받기는 빠지고,
//              토막은 문장이 되고, 읽히는 대화가 남는다.
//
// 그래서 Replay가 줄을 버려도 안전하다 — 실제로 한 말은 canonical과 원본
// 메시지에 그대로 있고, 화면은 그 둘을 오갈 수 있어야 한다(Original Call).
//
// ⚠️ **직접 대화 전용이다.** 만능 통역에는 Replay를 걸지 않는다 — 그쪽은
// 서클톡과 같은 STT→번역→TTS 경로라 상대에게 들린 것이 이미 번역문이고,
// 통화가 끝나면 세션 문서도 지운다. 되살릴 원본 통화가 없다.
//
// 그래서 Replay는 canonical을 덮지 않고 그 위에 따로 산다. 덮으면 "내가 실제로
// 한 말"이 사라지고, 그건 Duo의 장점 자체를 지우는 일이다.
//
// 🔒 **번역이 아니다.** 각 발화는 그 사람이 실제로 쓴 언어 그대로 남는다.
// 한쪽이 한국어, 한쪽이 영어로 말했으면 Replay도 그대로 섞여 있다. 배울
// 언어로 옮기는 일은 공부방이 줄 단위로 따로 한다 — 책임을 섞지 않는다.
// ====================================================================

import 'dart:convert';

/// 원본 한 줄. **canonical의 줄을 넣는다** — raw transcript가 아니다.
///
/// 뒤의 값들은 **보조 신호**다. 있으면 모델에게 같이 주고, 없으면 없는 대로
/// 돈다. 어느 하나도 그것만으로 줄을 지우는 근거가 되지 않는다 — 지우는 판단은
/// 언제나 앞뒤 맥락이 한다.
class ReplaySourceLine {
  const ReplaySourceLine({
    required this.id,
    required this.role,
    required this.text,
    this.spokenAtMs,
    this.seq,
    this.state,
    this.rmsDbfs,
    this.sttSource,
  });

  final String id;

  /// 'HOST' 또는 'GUEST'. 통화에서의 역할이다.
  final String role;
  final String text;

  /// 말을 시작한 시각. 앞뒤 줄과의 간격이 맥락 판단의 재료가 된다.
  final int? spokenAtMs;

  /// 화자별 일련번호.
  final int? seq;

  /// canonical이 붙인 표시(`included` 등). [prepareReplaySource]가 본다.
  final String? state;

  /// 그 발화 구간의 평균 세기. **낮다고 지우지 않는다** — 맥락이 이미 튄다고
  /// 볼 때 그 판단을 거드는 정도로만 쓴다. 낮은 세기 자체는
  /// `low_level` 게이트가 저장 전에 이미 걸렀다.
  final double? rmsDbfs;

  /// 이 글자를 만든 소리의 출처(`local_mic`). 다른 값이면 마이크가 아닌 소리다.
  final String? sttSource;
}

/// 복원된 한 줄.
class ReplayTurn {
  const ReplayTurn({
    required this.role,
    required this.text,
    required this.sourceIds,
  });

  final String role;
  final String text;

  /// 이 줄이 어느 원본에서 나왔는가. **추적의 핵심이다** — 이 고리가 있어야
  /// Original Call과 나란히 놓고 무엇이 어떻게 바뀌었는지 볼 수 있다.
  final List<String> sourceIds;
}

/// 걷어낸 줄과 그 이유.
class ReplayDrop {
  const ReplayDrop({required this.id, required this.reason});

  final String id;

  /// 셋뿐이다. 모르는 이유로는 아무것도 지우지 않는다.
  final String reason;
}

const Set<String> kReplayDropReasons = <String>{
  'noise', // 사람이 낸 소리가 아닌 것을 전사기가 글로 만든 줄
  'filler', // 자기 차례를 붙들고 말을 고르던 발성("음…", "uh")
  'duplicate', // 같은 순간이 두 번 저장된 줄
  // 글자는 멀쩡한데 앞뒤 대화와 이어지지 않는 줄. **모양이 아니라 자리로**
  // 가린다 — "안녕하세요."는 대화 한복판에서는 튀고, 통화 첫머리에서는
  // 정상이다. 낱말 목록으로는 절대 못 가르는 종류다.
  'context',
  // 응답 어디에도 안 적힌 줄. 모델이 대화에 넣지 않기로 한 것으로 본다.
  // **원본은 canonical에 그대로 있다** — 그래서 여기서 버려도 잃지 않는다.
  'unlisted',
};

/// 검토용 경고. **자동으로 막지 않는다** — 사람이 결과를 보고 판단할 재료다.
class ReplayWarning {
  const ReplayWarning(this.kind, this.detail);

  final String kind;
  final String detail;

  @override
  String toString() => '[$kind] $detail';
}

class ReplayResult {
  const ReplayResult({
    required this.turns,
    required this.dropped,
    required this.warnings,
  });

  final List<ReplayTurn> turns;
  final List<ReplayDrop> dropped;
  final List<ReplayWarning> warnings;
}

// ====================================================================
// 🛟 [FALLBACK] Replay는 **개선 계층이지 원본을 대신하는 계층이 아니다.**
// --------------------------------------------------------------------
// 앱에 붙일 때도 이 원칙은 그대로 간다. Replay가 미덥지 않으면 canonical을
// 그대로 보여준다 — 조금 지저분한 대화가, 없던 말이 섞인 매끈한 대화보다
// 언제나 낫다.
//
// 되돌리는 이유도 **닫아 둔다.** "AI가 보기에 이상해서"로는 되돌리지 않는다.
//   · 응답을 읽지 못했다
//   · 남은 대화가 없다
//   · 원본에 없는 줄을 지어냈다      — 잘라내는 것은 열되 만드는 것은 닫는다
//   · 한 사람 말만 남았다            — 대화가 아니게 됐다
//   · 원본보다 줄이 늘었다           — 없던 주고받기를 만든 것이다
//
// **줄을 많이 지운 것은 더 이상 되돌릴 이유가 아니다.** 중요하지 않은
// 주고받기를 걷어내는 것이 이제 이 계층이 하는 일이고, 원본은 canonical에
// 그대로 남아 있다.
// ====================================================================

/// 원본보다 줄이 이 배수를 넘게 늘면 되돌린다. 줄이는 계층이 늘렸다는 것은
/// 없던 주고받기를 만들었다는 뜻이다.
const double kReplayMaxTurnInflation = 1.15;

/// 대화가 남아 있다고 볼 최소 줄 수. **이보다 적으면 대화가 아니다.**
///
/// ⚠️ 이건 "원본이 짧으면 만들지 않는다"가 아니다. **결과**가 이보다 적을
/// 때만 되돌린다. 두 줄짜리 통화는 두 줄짜리 Replay로 성립한다.
const int kReplayMinTurns = 2;

class ReplayVerdict {
  const ReplayVerdict(this.useReplay, this.reasons);

  final bool useReplay;

  /// 되돌린 이유. 비어 있으면 Replay를 쓴다.
  final List<String> reasons;

  bool get fallsBack => !useReplay;
}

/// 이 판을 쓸 것인가, canonical로 되돌릴 것인가.
ReplayVerdict judgeReplay({
  required ReplayResult result,
  required int sourceCount,
  int sourceSpeakers = 2,
}) {
  final reasons = <String>[];
  final kinds = result.warnings.map((w) => w.kind).toSet();

  if (kinds.contains('parse')) reasons.add('parse_failed');
  if (kinds.contains('invented')) reasons.add('invented_turn');
  if (result.turns.isEmpty) {
    reasons.add('empty');
  } else {
    if (sourceSpeakers > 1 &&
        result.turns.map((t) => t.role).toSet().length < 2) {
      reasons.add('speaker_collapsed');
    }
    if (sourceCount > 0 &&
        result.turns.length > sourceCount * kReplayMaxTurnInflation) {
      reasons.add('turn_inflation');
    }
    // 🧭 **줄을 많이 지운 것은 되돌릴 이유가 아니다.** 문맥에서 튄 줄을
    //   걷어내는 것이 이 계층이 하는 일이고, 원본은 canonical에 그대로 있다.
    //   대화라고 부를 수 없을 만큼 남지 않았을 때만 되돌린다.
    if (result.turns.length < kReplayMinTurns &&
        sourceCount >= kReplayMinTurns) {
      reasons.add('too_few_turns');
    }
  }

  return ReplayVerdict(reasons.isEmpty, reasons);
}

/// 원본과 글자가 달라진 줄. **A(의미 보존)를 볼 때 여기만 읽으면 된다** —
/// 나머지 줄은 손대지 않은 것이므로 의미가 바뀔 수 없다.
class ReplayEdit {
  const ReplayEdit(
      {required this.before, required this.after, required this.ids});

  final String before;
  final String after;
  final List<String> ids;
}

List<ReplayEdit> replayEdits({
  required ReplayResult result,
  required List<ReplaySourceLine> source,
}) {
  final byId = <String, ReplaySourceLine>{for (final s in source) s.id: s};
  final edits = <ReplayEdit>[];
  for (final turn in result.turns) {
    final before =
        turn.sourceIds.map((id) => byId[id]?.text.trim() ?? '').join(' ');
    if (before == turn.text.trim()) continue;
    edits.add(ReplayEdit(
        before: before, after: turn.text.trim(), ids: turn.sourceIds));
  }
  return edits;
}

// ====================================================================
// ① 결정적 입력 정리 — 모델에게 넘기기 전에 기계가 먼저 치운다
// ====================================================================

/// canonical이 이미 판단해 둔 것을 걸러 낸다. **여기서는 맥락을 보지 않는다.**
///
/// 모델에게 물어볼 필요가 없는 줄을 먼저 빼는 것이 목적이다.
///   · `merged`      — 이웃 줄에 흡수됐다. 넣으면 같은 말이 두 번 실린다.
///   · `hidden_echo` — 스피커로 나간 상대 목소리가 되돌아온 줄.
///   · `hidden_duplicate` — 같은 순간이 두 번 저장된 줄.
///   · 빈 줄
///
/// `hidden_hesitation`은 **넣는다.** 사람이 낸 소리이고, 뺄지 말지는 앞뒤를
/// 보고 모델이 정할 일이다. 여기서 미리 지우면 맥락 판단의 재료가 준다.
///
/// ⚠️ `low_level`로 걸린 발화는 **애초에 저장되지 않았으므로** 여기 오지
/// 않는다(`kDuoMinUtteranceRmsDbfs` 게이트). 이 함수가 따로 거를 것이 없다.
List<ReplaySourceLine> prepareReplaySource(List<ReplaySourceLine> source) {
  const Set<String> skip = <String>{
    'merged',
    'hidden_echo',
    'hidden_duplicate',
  };
  final out = <ReplaySourceLine>[];
  final seenIds = <String>{};
  for (final line in source) {
    if (line.text.trim().isEmpty) continue;
    if (skip.contains((line.state ?? '').trim())) continue;
    if (!seenIds.add(line.id)) continue;
    out.add(line);
  }
  return out;
}

// ====================================================================
// ② 프롬프트 — 맥락으로 판단한다
// ====================================================================

/// 권한의 방향은 **자리(fit)에만** 넓다. 문맥에 얹히지 않는 줄은 뺀다 —
/// 실장님 지시(2026-08-31). 첫 판은 "애매하면 남긴다"였는데, 그러면 전사가
/// 지어낸 문장이 학습용 대본에 그대로 남아 대본이 대본 구실을 못 했다.
///
/// **이 권한이 안전한 이유는 하나뿐이다.** 실제로 한 말은 canonical
/// (Original Call)에 통째로 남아 있고 이 계층은 거기에 손대지 않는다. 여기서
/// 뺀 줄은 잃은 줄이 아니라 **이 대본에만 안 실린 줄**이다.
///
/// ⚠️ 넓힌 것은 **자리**뿐이고 **값어치**가 아니다. 짧다고, 평범하다고,
/// 안 중요해 보인다고 빼는 것은 여전히 금지다. 그 판단은 이 계층의 일이
/// 아니다([[duo-history-cleanup-principle]]와 같은 선).
const String kReplayPrompt =
    '''You are given ONE phone call between two people, already transcribed. Each line came from that speaker's own phone, so it carries everything a real call carries: noise, half-words, repeats, and sounds that were never really speech.

Write the call out as a conversation someone can actually read and study, built ONLY from the lines that belong to it.

READ THE WHOLE CALL FIRST, before you judge any single line. Work out what the two people were doing together - what was asked, what was answered, what was agreed, what was left open. That through-line is the script. Then write it the way it would read if the recognizer had not mangled it, and leave out whatever sits outside it.

HOW TO JUDGE A LINE - by its PLACE IN THE CONVERSATION, never by how it looks on its own.

A line can be perfect Korean, perfect English, a perfectly ordinary sentence, and still be something nobody said. The recognizer invents fluent sentences out of silence. The only way to tell is to read the lines around it.

For every line, look at the two or three turns before it and the two or three turns after it, and ask:
- Does it answer, react to, or follow from what was just said?
- Does the next turn treat it as something that was actually said?
- Does the topic, or the language, jump for this one line and jump back right after?
- Read the same speaker's turns before and after it with this line taken out. Does the conversation read better without it?
- Is this line the only one in the call that nobody engages with?

If a line is stranded - nothing leads into it and nothing follows from it - it is almost certainly something the recognizer invented. Drop it as "context". Half-belonging is not belonging: if you have to argue for a line's place, it does not have one.

  A: 오늘 뭐 먹을까?
  B: 김치찌개 어때?
  A: 안녕하세요.          <- stranded. nobody greets mid-meal-decision. DROP as context.
  B: 좋아. 그거 먹자.      <- answers B's own suggestion, not the greeting.

But the same words can be perfectly real somewhere else:

  A: 러시아 가 본 적 있어?
  B: 아니, 아직 없어.      <- "러시아" is what the call is ABOUT. KEEP. Never drop it.

NEVER keep a list of suspicious words. "안녕하세요", "검은색", "그녀는", "러시아" are all ordinary things people say. What decides is whether the conversation around them makes sense with them in it.

WHEN A LINE DOES NOT FIT, LEAVE IT OUT. What you are writing is a STUDY SCRIPT, not a record of the call. The record is kept whole somewhere else and you are not touching it, so nothing a person said is lost by leaving it out of this script. Build the script ONLY from the lines that hold together as one conversation. If you cannot place a line in that conversation, drop it as "context" - do not keep it "just in case". One stranded line teaches the learner a sentence nobody said.

That licence is about FIT, not about WORTH. Never leave a line out because it is short, plain, or looks unimportant. A line that answers, asks, reacts, agrees, or refuses belongs in the script however small it is - "응.", "아니.", "왜?", "그래." are the conversation. Deciding which real remarks matter is not your job; deciding which lines belong to the conversation is.

LANGUAGE RULE - absolute: every turn stays in the language that speaker actually used. If one spoke Korean and the other English, your version keeps both, exactly as they were. Never translate a turn, not even one word inside a sentence.

KEEP:
- What each person actually meant, and how strongly they meant it.
- Who said what. Never move a line from one speaker to the other.
- The order of the conversation, and the exchanges that carry it.
- Names, places, numbers, times and dates exactly as spoken.
- Short real replies. "응." "아니." "왜?" "그래." are real conversation when something leads into them.

DROP:
- Lines stranded from the conversation around them (reason: context).
- Sounds that were never speech (reason: noise).
- Fillers and false starts that carry nothing (reason: filler).
- The same thing stored twice (reason: duplicate).
- Back-and-forth that only exists because the line was bad ("뭐라고?", "안 들려", "여보세요?") (reason: noise).

JOIN AND SMOOTH:
- Put a broken-up sentence back together as one sentence, when the pieces are the SAME speaker in a row and read as one thought.
  "오늘 저녁에" + "집에 갈 거예요." -> "오늘 저녁에 집에 갈 거예요."
- Finish a turn that is obviously unfinished, using only what the call itself already settles.
- Write natural, complete sentences instead of transcript fragments.

NEVER:
- Add a fact, a plan, a reason or a feeling that the two never touched.
- Add a question nobody asked.
- Decide something they left undecided, or make an answer more certain than it was.
- Turn a short exchange into a long one, or a long call into a summary of itself.
- Translate.

YOU DO NOT NEED A CLEAN TRANSCRIPT. Most calls arrive with some lines mangled. If the through-line of the conversation is there, write it out and drop the few lines that are not part of it. Do not refuse, do not return the input unchanged, and do not give up because some lines are uncertain. Only when the call has no through-line at all - when you cannot tell what the two were talking about - return the lines as they are.

SIGNALS you may be given per line, when the app has them. Use them ONLY to support a decision the context already points to; never drop a line on a signal alone:
- "rms_dbfs": how loud that utterance was. Very low means the recognizer may have had almost no speech to work with.
- "state": what the preservation layer marked it as.
- "stt_source": where the audio came from. Anything other than "local_mic" did not come from that speaker's own microphone.

Return strict JSON only:
{"turns":[{"ids":["<source id>"],"role":"HOST","text":"..."}],
 "dropped":[{"id":"<source id>","reason":"context|noise|filler|duplicate"}]}

"ids" lists the source lines that turn came from, in order - your best mapping, several ids for a turn you joined. Put every id you left out in "dropped", with the reason that fits.''';

/// 모델에게 넘길 몸통. **통화 전체를 한 번에 준다** — 앞뒤를 보고 판단하라고
/// 시켰으니 줄을 따로따로 보내면 그 지시가 성립하지 않는다.
///
/// 보조 신호는 **있을 때만** 싣는다. 빈 값을 채워 보내면 모델이 그 빈 값을
/// 근거로 읽는다.
Map<String, dynamic> buildReplayPayload(List<ReplaySourceLine> source) =>
    <String, dynamic>{
      'turns': <Map<String, dynamic>>[
        for (final line in source)
          <String, dynamic>{
            'id': line.id,
            'role': line.role,
            'text': line.text,
            if (line.spokenAtMs != null) 'spoken_at_ms': line.spokenAtMs,
            if (line.seq != null) 'seq': line.seq,
            if (line.state != null && line.state!.isNotEmpty)
              'state': line.state,
            if (line.rmsDbfs != null)
              'rms_dbfs': double.parse(line.rmsDbfs!.toStringAsFixed(1)),
            if (line.sttSource != null && line.sttSource!.isNotEmpty)
              'stt_source': line.sttSource,
          }
      ]
    };

// ====================================================================
// 응답 읽기 + 빗장
// ====================================================================

/// 모델 응답을 읽고 **규칙을 지켰는지 같이 본다.**
///
/// 빗장은 둘이고, 남는 것은 전부 검토용 기록이다.
///   · 화자를 옮긴 줄은 원본 화자로 되돌린다 — 남의 말이 내 말이 되면 안 된다.
///   · 원본 없는 줄은 버린다 — 잘라내는 것은 열되 만드는 것은 닫는다.
///
/// 막지 않고 적어만 두는 것: 응답에 안 실린 줄, 원본보다 훨씬 길어진 줄,
/// 서로 다른 화자를 한 줄로 묶은 것.
ReplayResult parseReplayResponse({
  required String content,
  required List<ReplaySourceLine> source,
}) {
  final warnings = <ReplayWarning>[];
  final byId = <String, ReplaySourceLine>{for (final s in source) s.id: s};
  final seen = <String>{};
  final turns = <ReplayTurn>[];
  final dropped = <ReplayDrop>[];

  Map<String, dynamic>? decoded;
  try {
    final raw = jsonDecode(content);
    if (raw is Map<String, dynamic>) decoded = raw;
  } catch (_) {}
  if (decoded == null) {
    warnings.add(const ReplayWarning('parse', 'JSON이 아니다 — 원본을 그대로 쓴다'));
    return ReplayResult(
      turns: <ReplayTurn>[
        for (final s in source)
          ReplayTurn(role: s.role, text: s.text, sourceIds: <String>[s.id])
      ],
      dropped: const <ReplayDrop>[],
      warnings: warnings,
    );
  }

  for (final item in (decoded['turns'] as List? ?? const <dynamic>[])) {
    if (item is! Map) continue;
    final ids = <String>[
      for (final id in (item['ids'] as List? ?? const <dynamic>[]))
        if (byId.containsKey(id.toString())) id.toString()
    ];
    final text = (item['text'] ?? '').toString().trim();
    if (ids.isEmpty) {
      if (text.isNotEmpty) {
        warnings.add(ReplayWarning('invented', '원본 없는 줄을 지어냈다: "$text"'));
      }
      continue;
    }
    if (text.isEmpty) continue;

    // 화자는 원본이 정한다. 모델이 옮겼으면 되돌리고 적어 둔다.
    final roles = <String>{for (final id in ids) byId[id]!.role};
    if (roles.length > 1) {
      warnings.add(ReplayWarning(
          'speaker_merge', '서로 다른 화자를 한 줄로 묶었다: ${ids.join(",")}'));
    }
    final sourceRole = byId[ids.first]!.role;
    final claimed = (item['role'] ?? sourceRole).toString();
    if (claimed != sourceRole) {
      warnings.add(ReplayWarning(
          'speaker_moved', '$claimed로 옮긴 줄을 $sourceRole로 되돌렸다: ${ids.first}'));
    }

    // 원본보다 크게 길어졌다 = 없던 말이 붙었을 수 있다.
    final int sourceLen =
        ids.fold<int>(0, (n, id) => n + byId[id]!.text.trim().length);
    // 토막을 문장으로 세우면 길어지는 것이 정상이라 창을 넓게 둔다.
    // **막지 않는다** — 사람이 보고 판단할 재료다.
    if (sourceLen > 0 && text.length > sourceLen * 2.5) {
      warnings.add(ReplayWarning(
          'expanded', '원본 $sourceLen자 → ${text.length}자: "$text"'));
    }

    seen.addAll(ids);
    turns.add(ReplayTurn(role: sourceRole, text: text, sourceIds: ids));
  }

  for (final item in (decoded['dropped'] as List? ?? const <dynamic>[])) {
    if (item is! Map) continue;
    final id = (item['id'] ?? '').toString();
    if (!byId.containsKey(id) || seen.contains(id)) continue;
    final reason = (item['reason'] ?? '').toString().trim().toLowerCase();
    if (!kReplayDropReasons.contains(reason)) {
      warnings
          .add(ReplayWarning('unknown_reason', '"$reason"로 지운 줄을 되살렸다: $id'));
      continue; // seen에 넣지 않는다 → 아래에서 원문 그대로 되살아난다
    }
    seen.add(id);
    dropped.add(ReplayDrop(id: id, reason: reason));
  }

  // 어디에도 안 적힌 원본은 **대화에서 뺀 것으로 본다.**
  //
  //   예전에는 여기서 원문 그대로 되살렸다. 정돈만 하던 시절에는 그게 맞았다
  //   — 빠진 줄은 실수일 가능성이 컸으니까. 지금은 중요하지 않은 주고받기를
  //   걷어내는 것이 이 계층이 하는 일이라, 되살리면 그 일을 무르는 셈이 된다.
  //   **실제로 한 말은 canonical과 원본 메시지에 그대로 있다.**
  var unlisted = 0;
  for (final s in source) {
    if (seen.contains(s.id)) continue;
    dropped.add(ReplayDrop(id: s.id, reason: 'unlisted'));
    unlisted++;
  }
  if (unlisted > 0) {
    warnings.add(ReplayWarning('unlisted', '$unlisted줄이 응답에 안 실렸다 — 뺀 것으로 본다'));
  }

  return ReplayResult(turns: turns, dropped: dropped, warnings: warnings);
}
