// 🌬️ [BREATH] 한 호흡 구간.
//
//   **텍스트가 아니라 실제 PCM에서 나온 값이다.** 문법·단어 수·쉼표는 이
//   경계를 만드는 데 전혀 쓰이지 않는다 — AI가 실제로 어디서 쉬었는지가
//   유일한 기준이다.

/// 재생 구간 하나.
///
/// [startMs]/[endMs]는 padding까지 포함한 **재생 범위**이고,
/// [speechStartMs]/[speechEndMs]는 padding을 뺀 **실제 발성 범위**다.
/// 둘을 함께 들고 있어야 관리자가 "무음을 얼마나 남겼는지"를 보고 padding을
/// 판단할 수 있다.
class BreathSegment {
  const BreathSegment({
    required this.startMs,
    required this.endMs,
    required this.speechStartMs,
    required this.speechEndMs,
  });

  final int startMs;
  final int endMs;
  final int speechStartMs;
  final int speechEndMs;

  int get durationMs => endMs - startMs;
  int get speechDurationMs => speechEndMs - speechStartMs;

  /// Phase 2의 Breath metadata cache가 쓸 직렬화.
  Map<String, int> toJson() => <String, int>{
        's': startMs,
        'e': endMs,
        'ss': speechStartMs,
        'se': speechEndMs,
      };

  static BreathSegment fromJson(Map<String, dynamic> json) => BreathSegment(
        startMs: json['s'] as int,
        endMs: json['e'] as int,
        speechStartMs: json['ss'] as int,
        speechEndMs: json['se'] as int,
      );

  @override
  String toString() =>
      'BreathSegment($startMs~$endMs, speech $speechStartMs~$speechEndMs)';
}
