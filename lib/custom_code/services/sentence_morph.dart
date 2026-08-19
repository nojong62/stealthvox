// 🔤 [SENTENCE-MORPH] 이전 문장 → 현재 문장에서 **달라진 자리**를 찾는다.
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

/// 한 문장의 변화 한 벌.
///
/// **화면 강조·TTS 강조 지시문·캐시 identity가 전부 이 객체 하나에서 나온다.**
/// 각자 diff를 다시 계산하는 경로를 만들지 않는다 — 그러면 눈에 보이는 자리와
/// 귀에 들리는 자리가 어긋난다.
class MorphChange {
  const MorphChange({required this.text, required this.ranges});

  final String text;
  final List<MorphRange> ranges;

  bool get isEmpty => ranges.isEmpty;

  /// 강조할 실제 문구들. TTS 지시문이 이걸 그대로 인용한다.
  List<String> get phrases =>
      ranges.map((r) => text.substring(r.start, r.end)).toList();

  /// 캐시 지문. 같은 문장이라도 강조 자리가 다르면 다른 소리이므로 키가
  /// 달라야 한다. 범위만으로 만들어 **결정적**이다.
  String get identity =>
      ranges.isEmpty ? 'none' : ranges.map((r) => '${r.start}-${r.end}').join(',');

  static const MorphChange none =
      MorphChange(text: '', ranges: <MorphRange>[]);
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
  _Region(this.start, this.end, this.tokenCount);

  int start;
  int end;
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
  int i = 0;
  int j = 0;
  while (i < n && j < m) {
    if (a[i].norm == b[j].norm) {
      kept[j] = true;
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
    regions.add(_Region(b[s].start, b[k - 1].end, k - s));
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

  return MorphChange(text: text, ranges: ranges);
}

List<_Region> _largest(List<_Region> regions, int count) {
  final sorted = List<_Region>.from(regions)
    ..sort((x, y) => y.tokenCount.compareTo(x.tokenCount));
  final top = sorted.take(count).toList()
    ..sort((x, y) => x.start.compareTo(y.start));
  return top;
}

/// 변화 부분을 **살짝만** 살려 읽으라는 지시문을 만든다.
///
/// 기본 스타일(Smooth Jazz) 위에 얹는 한 겹이다. 과장하면 실패다 —
/// 강조 부분이 문장에서 따로 떨어져 들리면 안 된다.
String morphEmphasisInstruction(MorphChange morph) {
  if (morph.isEmpty) return '';
  final quoted = morph.phrases.map((p) => '"${p.trim()}"').join(', ');
  return '''

Within this sentence, give slightly stronger sentence stress and a subtle
pitch lift to: $quoted.
Keep it understated. Do not pause around these words, do not separate them
from the sentence, and do not slow down for them. The sentence must still
sound like one natural, connected utterance — the emphasis should be barely
noticeable, not a teaching demonstration.''';
}
