// 🔤 [THOUGHT-EXPANSION] 이전 생각 → 다음 생각의 변화를 찾는다.
//
//   P2가 쓰는 물건이다. 사용자에게 문법을 설명하지 않고, 문장이 자라면서
//   어디가 바뀌었는지만 눈과 귀로 느끼게 한다.
//
//   ⚠️ **단순 suffix diff가 아니다.** 뒤에 말이 붙기만 하는 게 아니라
//   `didn't like` → `wasn't sure I liked`처럼 표현이 통째로 바뀌기도 한다.
//   그래서 LCS로 두 문장을 맞춰 보고 **현재 문장 쪽에서 바뀐 토큰의 연속
//   구간**을 낸다.
//
//   순수 함수만 둔다. 새 dependency 없음.

import 'dart:math' as math;

/// 강조 구간. UTF-16 문자 오프셋이라 `TextSpan`이 그대로 쓴다.
class MorphRange {
  const MorphRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is MorphRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start-$end';
}

/// 여러 changed region 가운데 다음 생각으로 넘어가는 핵심 하나.
///
/// UI·TTS·cache는 [MorphChange.ranges]를 직접 고르지 않고 이 객체만 쓴다.
/// UTF-16 offset은 [MorphChange.text] 기준이다.
class PrimaryMorph {
  const PrimaryMorph({
    required this.start,
    required this.end,
    required this.phrase,
  });

  final int start;
  final int end;
  final String phrase;

  int get length => end - start;
  String get identity => '$start-$end';
  MorphRange get range => MorphRange(start, end);

  @override
  bool operator ==(Object other) =>
      other is PrimaryMorph &&
      other.start == start &&
      other.end == end &&
      other.phrase == phrase;

  @override
  int get hashCode => Object.hash(start, end, phrase);

  @override
  String toString() => '$identity "$phrase"';
}

/// 한 문장의 변화 한 벌.
///
/// **화면 강조·TTS 강조 지시문·캐시 identity가 전부 이 객체 하나에서 나온다.**
/// 각자 diff를 다시 계산하는 경로를 만들지 않는다 — 그러면 눈에 보이는 자리와
/// 귀에 들리는 자리가 어긋난다.
class MorphChange {
  const MorphChange({
    required this.text,
    required this.ranges,
    this.primary,
  });

  final String text;

  /// LCS가 찾은 changed regions. 분석·debug용이며 제품 강조에는 쓰지 않는다.
  final List<MorphRange> ranges;
  final PrimaryMorph? primary;

  bool get isEmpty => primary == null;

  /// 강조할 실제 문구들. TTS 지시문이 이걸 그대로 인용한다.
  List<String> get phrases =>
      ranges.map((r) => text.substring(r.start, r.end)).toList();

  /// 캐시 지문. all changes가 같아도 primary가 다르면 다른 소리다.
  String get identity => primary?.identity ?? 'none';

  static const MorphChange none = MorphChange(text: '', ranges: <MorphRange>[]);
}

/// 🚧 조정 가능한 값들. **실제 History ladder로 검증하기 전까지 제품 최종
/// 정책값이 아니다.** 합성/구조변형 예문 11개에서 기대대로 동작하는 것까지만
/// 확인됐다.
class MorphConfig {
  const MorphConfig({
    this.maxRegions = 3,
    this.mergeGapTokens = 0,
    this.floodRatio = 0.75,
    this.suppressRatio = 0.80,
  });

  /// 한 문장에서 강조할 구간 수 상한. 시선이 흩어지지 않게 한다.
  final int maxRegions;

  /// 이만큼 이하로 떨어진 두 구간은 합친다. 0이면 합치지 않는다 —
  /// 올리면 사이에 낀 **안 바뀐 단어까지 삼킨다.**
  final int mergeGapTokens;

  /// 이 비율 넘게 바뀌면 가장 큰 구간 하나만 남긴다.
  final double floodRatio;

  /// 이 비율 넘게 바뀌면 **강조를 아예 생략한다.** 문장이 통째로 다시 쓰인
  /// 경우 전부 노랗게 칠하면 아무 정보도 주지 못한다.
  final double suppressRatio;
}

class _Tok {
  _Tok(this.raw, this.start, this.end);

  final String raw;
  final int start;
  final int end;

  /// 비교용. 소문자 + 앞뒤 구두점 제거. **아포스트로피는 남긴다** —
  /// `wasn't`가 `was` + `n't`로 쪼개지면 강조가 글자 단위로 부서진다.
  String get norm =>
      raw.toLowerCase().replaceAll(RegExp(r"^[^\w']+|[^\w']+$"), '');
}

List<_Tok> _tokenize(String s) {
  final out = <_Tok>[];
  for (final m in RegExp(r'\S+').allMatches(s)) {
    out.add(_Tok(m.group(0)!, m.start, m.end));
  }
  return out;
}

class _Region {
  _Region(
    this.start,
    this.end,
    this.tokenStart,
    this.tokenEnd,
    this.tokenCount,
  );

  int start;
  int end;
  int tokenStart;
  int tokenEnd;
  int tokenCount;
}

/// [previous]와 [current]를 견주어 현재 문장에서 강조할 자리를 낸다.
///
/// [previous]가 비어 있으면(첫 문장) 강조하지 않는다.
MorphChange computeMorph(
  String previous,
  String current, {
  MorphConfig config = const MorphConfig(),
}) {
  final text = current;
  if (previous.trim().isEmpty || text.trim().isEmpty) {
    return MorphChange(text: text, ranges: const <MorphRange>[]);
  }

  final a = _tokenize(previous);
  final b = _tokenize(text);
  if (a.isEmpty || b.isEmpty) {
    return MorphChange(text: text, ranges: const <MorphRange>[]);
  }
  final n = a.length;
  final m = b.length;

  // LCS 길이표. 문장 길이가 수십 토큰이라 O(n·m)으로 충분하다.
  final dp = List<List<int>>.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
    growable: false,
  );
  for (int i = n - 1; i >= 0; i--) {
    for (int j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i].norm == b[j].norm
          ? dp[i + 1][j + 1] + 1
          : math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }

  // 현재 토큰이 이전 문장에 그대로 남아 있는가.
  final kept = List<bool>.filled(m, false);
  final matchedOld = List<int>.filled(m, -1);
  int i = 0;
  int j = 0;
  while (i < n && j < m) {
    if (a[i].norm == b[j].norm) {
      kept[j] = true;
      matchedOld[j] = i;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }

  // 바뀐 토큰의 연속 구간
  final regions = <_Region>[];
  int k = 0;
  while (k < m) {
    if (kept[k]) {
      k++;
      continue;
    }
    final int s = k;
    while (k < m && !kept[k]) {
      k++;
    }
    regions.add(_Region(b[s].start, b[k - 1].end, s, k - 1, k - s));
  }
  if (regions.isEmpty) {
    return MorphChange(text: text, ranges: const <MorphRange>[]);
  }

  // 가까운 구간 병합
  final merged = <_Region>[regions.first];
  for (int r = 1; r < regions.length; r++) {
    final last = merged.last;
    int between = 0;
    for (final tok in b) {
      if (tok.start > last.end && tok.end < regions[r].start) between++;
    }
    if (between <= config.mergeGapTokens) {
      last.end = regions[r].end;
      last.tokenEnd = regions[r].tokenEnd;
      last.tokenCount += regions[r].tokenCount + between;
    } else {
      merged.add(regions[r]);
    }
  }

  final int changed = merged.fold<int>(0, (sum, r) => sum + r.tokenCount);
  final double ratio = changed / m;

  // 문장이 통째로 다시 쓰였다 → 강조 생략
  if (ratio > config.suppressRatio) {
    return MorphChange(text: text, ranges: const <MorphRange>[]);
  }
  List<_Region> picked = merged;
  if (ratio > config.floodRatio) {
    picked = _largest(merged, 1);
  } else if (merged.length > config.maxRegions) {
    picked = _largest(merged, config.maxRegions);
  }

  final ranges = picked
      .map((r) => MorphRange(
            r.start.clamp(0, text.length),
            r.end.clamp(0, text.length),
          ))
      .where((r) => r.end > r.start)
      .toList()
    ..sort((x, y) => x.start.compareTo(y.start));

  final primary = _selectPrimaryMorph(
    text: text,
    previousTokens: a,
    currentTokens: b,
    matchedOld: matchedOld,
    candidates: merged,
    changedRatio: ratio,
    config: config,
  );

  return MorphChange(text: text, ranges: ranges, primary: primary);
}

List<_Region> _largest(List<_Region> regions, int count) {
  final sorted = List<_Region>.from(regions)
    ..sort((x, y) => y.tokenCount.compareTo(x.tokenCount));
  final top = sorted.take(count).toList()
    ..sort((x, y) => x.start.compareTo(y.start));
  return top;
}

class _ScoredPrimary {
  const _ScoredPrimary({
    required this.range,
    required this.score,
    required this.tokenCount,
  });

  final MorphRange range;
  final int score;
  final int tokenCount;
}

/// LCS 결과 위의 가벼운 local selector. API 호출 없이 항상 결정적이다.
PrimaryMorph? _selectPrimaryMorph({
  required String text,
  required List<_Tok> previousTokens,
  required List<_Tok> currentTokens,
  required List<int> matchedOld,
  required List<_Region> candidates,
  required double changedRatio,
  required MorphConfig config,
}) {
  if (candidates.isEmpty) return null;

  final scored = <_ScoredPrimary>[];
  for (final region in candidates) {
    final raw = text.substring(region.start, region.end);
    final lower = raw.toLowerCase();
    final int replacedOld = _replacedOldTokenCount(
      region,
      matchedOld,
      previousTokens.length,
    );
    final bool replacement = replacedOld > 0;
    final int direction = _directionScore(lower);
    final bool atStart = region.tokenStart == 0;
    final bool atEnd = region.tokenEnd == currentTokens.length - 1;

    // 우선 2: 기존 핵심 표현 교체. 단순 삽입보다 확실히 높게 둔다.
    int score = replacement ? 110 + math.min(replacedOld, 6) * 3 : 0;

    // 우선 1: 방향을 만드는 표현. 특정 단어 하나만 보지 않고, 절 길이와
    // 위치도 함께 본다. suffix의 새 절은 다음 생각일 가능성이 높다.
    score += direction;
    if (direction > 0 && region.tokenCount >= 3) score += 10;
    if (direction > 0 && atEnd) score += 8;

    // 우선 3: 새 의미 덩어리. 긴 구간을 무조건 이기게 하지는 않는다.
    score += math.min(region.tokenCount, 7) * 4;
    if (!replacement && atEnd && region.tokenCount >= 3) score += 14;
    if (!replacement && atStart && region.tokenCount == 1) score -= 4;

    final refined = _refinePrimaryRange(text, region, direction > 0);
    if (refined.end <= refined.start) continue;
    scored.add(_ScoredPrimary(
      range: refined,
      score: score,
      tokenCount: region.tokenCount,
    ));
  }
  if (scored.isEmpty) return null;

  // 거의 전면 재작성인데 의미 방향 anchor도 교체 anchor도 없다면 억지로
  // 하나를 고르지 않는다. suppressRatio 직전의 경계 사례를 위한 안전망이다.
  if (changedRatio >= config.floodRatio && scored.every((c) => c.score < 80)) {
    return null;
  }

  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byTokens = b.tokenCount.compareTo(a.tokenCount);
    if (byTokens != 0) return byTokens;
    return a.range.start.compareTo(b.range.start);
  });
  final picked = scored.first.range;
  return PrimaryMorph(
    start: picked.start,
    end: picked.end,
    phrase: text.substring(picked.start, picked.end),
  );
}

int _replacedOldTokenCount(
  _Region region,
  List<int> matchedOld,
  int previousLength,
) {
  int leftOld = -1;
  for (int i = region.tokenStart - 1; i >= 0; i--) {
    if (matchedOld[i] >= 0) {
      leftOld = matchedOld[i];
      break;
    }
  }
  int rightOld = previousLength;
  for (int i = region.tokenEnd + 1; i < matchedOld.length; i++) {
    if (matchedOld[i] >= 0) {
      rightOld = matchedOld[i];
      break;
    }
  }
  return math.max(0, rightOld - leftOld - 1);
}

int _directionScore(String phrase) {
  final normalized =
      phrase.replaceAll(RegExp(r"[^a-z0-9']+"), ' ').trim().toLowerCase();
  if (normalized.isEmpty) return 0;

  // 대조·결과·이유는 다음 생각의 방향을 가장 강하게 바꾼다.
  if (RegExp(r'^(but|so|because|instead|actually|then)\b')
      .hasMatch(normalized)) {
    return 88;
  }
  // 시간·관점 frame. 문장 어디에 있든 덩어리 단위로 판정한다.
  if (RegExp(
          r'(^|\b)(at first|in the end|for a moment|after|before|eventually|meanwhile)(\b|$)')
      .hasMatch(normalized)) {
    return 72;
  }
  // 연결어가 새 절의 첫머리라면 약한 방향 anchor로 본다.
  if (RegExp(r'^(and|or|yet)\b').hasMatch(normalized)) return 54;
  return 0;
}

MorphRange _refinePrimaryRange(
  String text,
  _Region region,
  bool directional,
) {
  int start = region.start;
  int end = region.end;

  // `but after ..., I started ...`처럼 한 changed region 안에 두 생각이 붙으면
  // 방향을 여는 첫 phrase 하나만 남긴다. 별도 문법 parser는 쓰지 않는다.
  if (directional) {
    final comma = text.indexOf(',', start);
    if (comma >= start && comma < end - 1) end = comma;
  }

  // 구두점은 변화의 의미가 아니므로 글자 강조에서 제외한다.
  while (start < end && RegExp(r'\s').hasMatch(text[start])) {
    start++;
  }
  while (end > start && RegExp(r'''[\s,.;:!?]''').hasMatch(text[end - 1])) {
    end--;
  }
  return MorphRange(start, end);
}

/// 변화 부분을 **살짝만** 살려 읽으라는 지시문을 만든다.
///
/// 기본 스타일(Smooth Jazz) 위에 얹는 한 겹이다. 과장하면 실패다 —
/// 강조 부분이 문장에서 따로 떨어져 들리면 안 된다.
String morphEmphasisInstruction(MorphChange morph) {
  if (morph.isEmpty) return '';
  final phrase = morph.primary!.phrase.trim();
  return '''

Read the entire sentence naturally and smoothly, keeping the same Smooth Jazz
delivery. Give the phrase "$phrase" slightly stronger stress and a subtle
pitch lift or change so it is noticeable but understated. Do not isolate the
phrase, pause around it, exaggerate it, or slow down unnaturally. Keep the
whole sentence connected as one soft, conversational utterance.''';
}
