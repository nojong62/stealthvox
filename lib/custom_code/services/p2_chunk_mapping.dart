/// Step Expand P2에서 Part1 → Part2 변화를 표현하는 의미 청크.
class P2Chunk {
  const P2Chunk({
    required this.text,
    required this.type,
    this.from,
    this.fromStart,
    this.fromEnd,
  });

  final String text;
  final String type;
  final String? from;
  final int? fromStart;
  final int? fromEnd;

  bool get referencesPart1 =>
      (type == 'kept' || type == 'evolved') &&
      (from?.trim().isNotEmpty ?? false);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'type': type,
        if (referencesPart1) 'from': from!.trim(),
      };
}

const Set<String> _p2ChunkTypes = <String>{'kept', 'evolved', 'new'};

List<P2Chunk> fallbackP2Chunks(String expandedText) {
  final text = expandedText.trim();
  if (text.isEmpty) return const <P2Chunk>[];
  return <P2Chunk>[P2Chunk(text: text, type: 'kept')];
}

/// GPT/Firestore의 chunks 배열을 검증한다.
///
/// 청크를 순서대로 이어 붙인 문장이 [expandedText]와 달라지면 일부 문구가
/// 빠졌거나 새로 생긴 것이므로 전체 문장 kept fallback으로 돌아간다.
List<P2Chunk> parseP2Chunks(
  dynamic raw,
  String expandedText, {
  required String part1Text,
}) {
  final expanded = expandedText.trim();
  if (expanded.isEmpty || raw is! List) return fallbackP2Chunks(expanded);
  final chunks = <P2Chunk>[];
  for (final item in raw) {
    if (item is! Map) return fallbackP2Chunks(expanded);
    final text = (item['text'] ?? '').toString().trim();
    final type = (item['type'] ?? '').toString().trim().toLowerCase();
    final rawFrom = (item['from'] ?? '').toString().trim();
    final from = type == 'new' ? '' : rawFrom;
    if (text.isEmpty || !_p2ChunkTypes.contains(type)) {
      return fallbackP2Chunks(expanded);
    }
    if ((type == 'kept' || type == 'evolved') && from.isEmpty) {
      return fallbackP2Chunks(expanded);
    }
    final sourceRange = type == 'kept' || type == 'evolved'
        ? findP2SourceRange(part1Text, from)
        : null;
    if ((type == 'kept' || type == 'evolved') && sourceRange == null) {
      return fallbackP2Chunks(expanded);
    }
    chunks.add(P2Chunk(
      text: text,
      type: type,
      from: from.isEmpty ? null : from,
      fromStart: sourceRange?.start,
      fromEnd: sourceRange?.end,
    ));
  }
  if (chunks.isEmpty ||
      _normalizeP2Text(chunks.map((chunk) => chunk.text).join(' ')) !=
          _normalizeP2Text(expanded)) {
    return fallbackP2Chunks(expanded);
  }
  return chunks;
}

String _normalizeP2Text(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]+'), '');

/// 실제 음성 timestamp가 없으므로 청크 단어 수 비율로 현재 청크를 추정한다.
/// 이 값은 시각 연출용이며 ±1~2단어 오차를 허용한다.
int p2ChunkIndexAtPosition(
  List<P2Chunk> chunks, {
  required int positionMs,
  required int totalMs,
}) {
  if (chunks.isEmpty || totalMs <= 0) return -1;
  final weights = chunks
      .map(
          (chunk) => RegExp(r'\S+').allMatches(chunk.text).length.clamp(1, 999))
      .toList(growable: false);
  final totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight);
  final progress = positionMs.clamp(0, totalMs) / totalMs;
  final target = progress * totalWeight;
  var cumulative = 0;
  for (var index = 0; index < weights.length; index++) {
    cumulative += weights[index];
    if (target < cumulative || index == weights.length - 1) return index;
  }
  return chunks.length - 1;
}

/// GPT의 from은 Part1에 실제 존재하는 문구여야 한다. 대소문자만 무시한다.
({int start, int end})? findP2SourceRange(String part1, String? from) {
  final phrase = from?.trim() ?? '';
  if (part1.isEmpty || phrase.isEmpty) return null;
  final start = part1.toLowerCase().indexOf(phrase.toLowerCase());
  if (start < 0) return null;
  return (start: start, end: start + phrase.length);
}
