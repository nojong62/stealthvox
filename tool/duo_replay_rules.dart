// ====================================================================
// 🎬 [REPLAY-RULES] "두 사람이 실제로 나눈 대화를, 읽고 공부할 수 있는
// 대화로 다시 세운 것."
// --------------------------------------------------------------------
// **아직 앱에 붙이지 않는다.** 실제 통화 몇 건에 돌려 보고 눈으로 정한 뒤에
// 옮긴다. (`tool/replay_probe.dart`가 이 파일을 쓴다)
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

/// 원본 한 줄. canonical의 줄이든 채널 원문이든 이 모양으로 넣는다.
class ReplaySourceLine {
  const ReplaySourceLine({
    required this.id,
    required this.role,
    required this.text,
  });

  final String id;

  /// 'HOST' 또는 'GUEST'. 통화에서의 역할이다.
  final String role;
  final String text;
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
  }

  return ReplayVerdict(reasons.isEmpty, reasons);
}

/// 원본과 글자가 달라진 줄. **A(의미 보존)를 볼 때 여기만 읽으면 된다** —
/// 나머지 줄은 손대지 않은 것이므로 의미가 바뀔 수 없다.
class ReplayEdit {
  const ReplayEdit({required this.before, required this.after, required this.ids});

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
// 프롬프트
// ====================================================================

/// 모델에게 주는 권한은 **좁게** 잡는다. 첫 버전에서 넓히면 무엇이 지나쳤는지
/// 가릴 수 없다. 애매하면 그대로 두는 쪽이 언제나 기본이다.
const String kReplayPrompt =
    '''You are given ONE phone call between two people, already transcribed. Each line came from that speaker's own phone, so it carries everything a real call carries: noise, half-words, repeats, and sounds that were never really speech.

Write the call out as a conversation someone can actually read and study.

Read the WHOLE call first. Work out what the two people were doing together - what was asked, what was answered, what was agreed, what was left open. Then write that same conversation the way it would read if the recognizer had not mangled it: the important exchanges, in the order they happened, in clean sentences.

LANGUAGE RULE - absolute: every turn stays in the language that speaker actually used. If one spoke Korean and the other English, your version keeps both, exactly as they were. Never translate a turn, not even one word inside a sentence.

KEEP:
- What each person actually meant, and how strongly they meant it.
- Who said what. Never move a line from one speaker to the other.
- The order of the conversation, and the exchanges that carry it.
- Names, places, numbers, times and dates exactly as spoken.

DROP without hesitation:
- Sounds that were never speech, and words the recognizer clearly invented.
- Fillers and false starts that carry nothing.
- The same thing stored twice.
- Back-and-forth that only exists because the line was bad ("뭐라고?", "안 들려", "여보세요?").

JOIN AND SMOOTH:
- Put a broken-up sentence back together as one sentence.
- Finish a turn that is obviously unfinished, using only what the call itself already settles.
- Write natural, complete sentences instead of transcript fragments.

NEVER:
- Add a fact, a plan, a reason or a feeling that the two never touched.
- Decide something they left undecided, or make an answer more certain than it was.
- Turn a short exchange into a long one, or a long call into a summary of itself.
- Translate.

If the call is too broken to make sense of, return the lines as they are rather than guessing what the people meant.

Return strict JSON only:
{"turns":[{"ids":["<source id>"],"role":"HOST","text":"..."}],
 "dropped":[{"id":"<source id>","reason":"noise|filler|duplicate"}]}

"ids" lists the source lines that turn came from, in order - your best mapping, several ids for a turn you joined. Put ids you left out in "dropped".''';

Map<String, dynamic> buildReplayPayload(List<ReplaySourceLine> source) =>
    <String, dynamic>{
      'turns': <Map<String, String>>[
        for (final line in source)
          <String, String>{
            'id': line.id,
            'role': line.role,
            'text': line.text,
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
      warnings.add(ReplayWarning('expanded',
          '원본 $sourceLen자 → ${text.length}자: "$text"'));
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
      warnings.add(ReplayWarning('unknown_reason', '"$reason"로 지운 줄을 되살렸다: $id'));
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
    warnings.add(
        ReplayWarning('unlisted', '$unlisted줄이 응답에 안 실렸다 — 뺀 것으로 본다'));
  }

  return ReplayResult(turns: turns, dropped: dropped, warnings: warnings);
}
