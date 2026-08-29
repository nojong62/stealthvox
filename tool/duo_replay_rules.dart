// ====================================================================
// 🎬 [REPLAY-RULES] "실제로 나눈 대화의 의미는 그대로 두고, 통화 잡음만
// 걷어내 사람이 다시 읽고 공부할 수 있는 대화로 복원한 것."
// --------------------------------------------------------------------
// **아직 앱에 붙이지 않는다.** 규칙을 실제 통화 몇 건에 돌려 보고, ④ 끊어진
// 발화 복원과 ⑤ 맥락 연결을 어디까지 열지 눈으로 정한 뒤에 옮긴다.
// (`tool/replay_probe.dart`가 이 파일을 쓴다)
//
// CANONICAL과 무엇이 다른가.
//
//   CANONICAL  줄을 **가린다**. 원문 글자는 그대로 두고 study_state만 바꾼다.
//   REPLAY     줄을 **세운다**. 토막을 잇고 명백한 것만 되살려 읽히게 만든다.
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
// 앱에 붙일 때도 이 원칙은 그대로 간다. Replay가 실패하거나 미덥지 않으면
// canonical을 그대로 보여준다 — 조금 지저분한 대화가, 의미가 바뀐 매끈한
// 대화보다 언제나 낫다.
//
// 무엇이 fallback을 부르는가는 **닫아 둔다.** "AI가 보기에 이상해서"로는
// 되돌리지 않는다. 셋뿐이다.
//   · 응답을 읽지 못했다
//   · 원본 없는 줄을 지어냈다        — 한 줄이라도 용납하지 않는다
//   · 너무 많이 지웠다·빠뜨렸다      — 남은 것이 원본보다 나을 수 없다
//
// 아래는 fallback을 부르지 **않는다.** 코드가 이미 안전한 쪽으로 되돌려
// 놓았거나(화자 이동), 정상 복원에서도 흔히 나올 값이기 때문이다(길어짐).
// 임계값은 실제 통화를 넣어 보고 정한다 — 지금 값은 잠정이다.
// ====================================================================

/// 원본의 이 비율을 넘게 지우면 되돌린다.
///
/// ⚠️ **아직 손대지 않는다.** 실제 통화 5~10건의 분포를 보기 전에 만지면
/// 무엇에 맞춘 값인지 알 수 없게 된다.
///
/// 이미 보이는 구멍 하나: **짧은 통화에서 비율은 거칠다.** 네 줄짜리 통화에서
/// 진짜 잡음 두 줄을 지우면 50%가 되어, 정상 Replay가 되돌아간다. 실제
/// 분포를 본 뒤 "비율 **또는** 절대 줄 수" 중 무엇으로 갈지 정한다
/// (예: 비율을 넘더라도 지운 줄이 2줄 이하면 통과).
const double kReplayMaxDropRatio = 0.4;

/// 모델이 이 비율을 넘게 빠뜨리면(fail-open으로 되살아나도) 되돌린다.
/// 절반을 흘린 응답은 정돈이 아니라 사고다. 위와 같은 이유로 잠정치다.
const double kReplayMaxLostRatio = 0.3;

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
}) {
  final reasons = <String>[];
  final kinds = result.warnings.map((w) => w.kind).toSet();

  if (kinds.contains('parse')) reasons.add('parse_failed');
  if (kinds.contains('invented')) reasons.add('invented_turn');
  if (result.turns.isEmpty) reasons.add('empty');

  if (sourceCount > 0) {
    if (result.dropped.length / sourceCount > kReplayMaxDropRatio) {
      reasons.add('too_much_dropped');
    }
    final lost = result.warnings
        .where((w) => w.kind == 'restored_missing')
        .map((w) => int.tryParse(RegExp(r'\d+').firstMatch(w.detail)?.group(0) ?? '0') ?? 0)
        .fold<int>(0, (a, b) => a + b);
    if (lost / sourceCount > kReplayMaxLostRatio) {
      reasons.add('model_lost_lines');
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
    '''You are restoring ONE phone call between two people so that it can be read and studied afterwards. Each line was transcribed from that speaker's own phone.

This is NOT translation, NOT summarisation, NOT rewriting.

LANGUAGE RULE — absolute: every turn stays in the language the speaker actually used. If one speaker spoke Korean and the other English, the restored call keeps both, exactly as they were. Never translate a turn, not even partially.

Your only job is to take out what the phone call and the recognizer added, so that what the two people actually said reads as a conversation.

YOU MAY:
1. Drop a line that is recognizer noise rather than speech.
2. Drop a sound that only held the speaker's own turn while they searched for words ("음...", "uh"), when it is not an answer, a question, a reaction or an agreement.
3. Drop a line the recognizer stored twice for the same moment. Matching words alone never justify this - a person genuinely repeating themselves is not a duplicate.
4. Join fragments of ONE sentence by the SAME speaker into that sentence, when no real turn by the other speaker sits between them.
5. Restore a word the surrounding turns make unmistakable - a mis-heard word that the reply plainly settles.

YOU MAY NOT:
- Translate anything.
- Improve the wording, fix the speaker's grammar, or make a turn sound more natural, more fluent or more native.
- Add a reason, a feeling, a detail or a politeness that was not spoken.
- Summarise, shorten or compress the call.
- Move words from one speaker to the other, or merge turns by different speakers.
- Invent a turn that has no source line.
- Guess at something ambiguous. WHEN IN DOUBT, KEEP THE LINE EXACTLY AS IT IS.

Keep both speakers in the order they actually spoke. Keep every turn that carries meaning, however short or ordinary: questions, answers, agreements, refusals, reactions, greetings.

Return strict JSON only:
{"turns":[{"ids":["<source id>"],"role":"HOST","text":"..."}],
 "dropped":[{"id":"<source id>","reason":"noise|filler|duplicate"}]}

"ids" lists every source line that became this turn, in order. Every source id must appear exactly once across "turns" and "dropped".''';

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
/// 빗장은 셋이고, 전부 "잃지 않는 쪽"으로 기운다.
///   · 빠뜨린 원본은 원문 그대로 되살린다 — 근거 없이 사람 말을 지우지 않는다.
///   · 화자를 옮긴 줄은 원본 화자로 되돌린다 — 남의 말이 내 말이 되면 안 된다.
///   · 모르는 이유로 지운 줄은 되살린다.
///
/// 막지는 않되 눈에 띄게 적어 두는 것: 원본보다 훨씬 길어진 줄(지어냈을 수
/// 있다), 서로 다른 화자를 한 줄로 묶은 것.
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
    if (sourceLen > 0 && text.length > sourceLen * 1.6) {
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

  // 🧭 [FAIL-OPEN] 어디에도 안 적힌 원본은 원문 그대로 되살린다. 판단인지
  //   실수인지 알 수 없고, 근거 없이 사람 말을 감추지 않는다.
  final missing = <ReplayTurn>[];
  for (final s in source) {
    if (seen.contains(s.id)) continue;
    missing.add(
        ReplayTurn(role: s.role, text: s.text, sourceIds: <String>[s.id]));
  }
  if (missing.isNotEmpty) {
    warnings.add(ReplayWarning(
        'restored_missing', '${missing.length}줄이 응답에서 빠져 원문으로 되살렸다'));
    turns.addAll(missing);
  }

  return ReplayResult(turns: turns, dropped: dropped, warnings: warnings);
}
