// ✂️ [DUO-CHUNK-SIM] 첫 조각 문턱을 숫자로 비교한다.
//
//   dart run tool/duo_chunk_sim.dart
//
// 문턱을 감으로 정하면 "짧은 말이 쪼개진다" 또는 "조기 재생이 안 걸린다"
// 둘 중 하나가 실기기에서야 드러난다. 그 전에 여기서 본다.
//
// ⚠️ **말뭉치의 한계를 먼저 밝힌다.**
//   진짜 실측은 2026-09-03 실기기 로그의 발화 3건뿐이다(한국어). 나머지는
//   지시문에 적힌 시험 문장과, 그 길이대에 맞춰 지어낸 문장이다. 그러므로
//   아래 표는 **경향을 보는 재료**이지 결론이 아니다. 실기기에서 실제
//   번역문이 쌓이면 그 값을 넣고 다시 돌릴 것.

import 'package:stealth_vox/custom_code/services/duo_speech_chunker.dart';

/// 실측 3건 — 2026-09-03 SM-S931N/M336K 로그의 전사문을 영어로 옮긴 것.
const List<String> realSamples = <String>[
  'In this test', // "이번 테스트에서"
  "It's the 144th test now.", // "지금은 144번째 테스트입니다."
  'I hope we get a good result.', // "좋은 결과가 나오기를 기대합니다."
];

/// 지시문 18번의 시험 문장(짧은 말).
const List<String> shortSamples = <String>[
  'Hello.',
  'Where are you going?',
  'Just a moment.',
  'Really?',
  'Sounds good.',
  'Yes, of course.',
  'I see. Thanks.',
  'Sounds good. Thanks a lot.',
];

/// 중간 길이 — 쉼표가 하나 있는 실제 대화체.
const List<String> mediumSamples = <String>[
  "If you're free this afternoon, do you want to grab a coffee together?",
  'I finished the report, so I can help you now.',
  'When you get there, please give me a call.',
  'It was raining hard, but we went anyway.',
  "Since you're already here, let's start early.",
];

/// 긴 문장 — 구절이 두세 개로 나뉘는 것.
const List<String> longSamples = <String>[
  "I stopped by the store on the way home, picked up some vegetables, "
      "and started cooking dinner right away.",
  "If the weather is nice tomorrow morning, we could walk along the river, "
      "and then have lunch at that place you mentioned.",
  "She said the meeting was moved to three o'clock, so we have some extra "
      "time before it starts, which is a relief.",
];

List<String> get corpus =>
    <String>[...realSamples, ...shortSamples, ...mediumSamples, ...longSamples];

/// 델타를 조금씩 흘려 넣어 실제 스트리밍을 흉내 낸다.
List<String> runChunker(String text, int firstChunkFloor, {int step = 3}) {
  final c = DuoSpeechChunker(minFirstChunkChars: firstChunkFloor);
  final out = <String>[];
  for (var i = 0; i < text.length; i += step) {
    final end = (i + step > text.length) ? text.length : i + step;
    out.addAll(c.add(text.substring(i, end)));
  }
  final tail = c.flush();
  if (tail != null) out.add(tail);
  return out;
}

/// 조각 끝에 붙는 닫는 부호. 이걸 벗겨야 진짜 마지막 글자가 보인다.
const String closers = '”"\')]』」';

bool endsAtBoundary(String s) {
  var last = s.trimRight();
  while (last.isNotEmpty && closers.contains(last[last.length - 1])) {
    last = last.substring(0, last.length - 1);
  }
  if (last.isEmpty) return false;
  final ch = last[last.length - 1];
  return kDuoSentenceEnders.contains(ch) || kDuoClauseEnders.contains(ch);
}

int wordCount(String s) =>
    s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

void report(int floor) {
  int split = 0;
  int totalChunks = 0;
  int firstLenSum = 0;
  int naturalBoundary = 0;
  int splitCount = 0;
  final tinyTails = <String>[];

  for (final text in corpus) {
    final chunks = runChunker(text, floor);
    totalChunks += chunks.length;
    firstLenSum += chunks.first.length;
    if (chunks.length > 1) {
      split++;
      // 마지막을 뺀 조각들이 경계에서 끝났는가.
      for (final c in chunks.take(chunks.length - 1)) {
        splitCount++;
        if (endsAtBoundary(c)) naturalBoundary++;
      }
      // 1~2 단어짜리 꼬리.
      final tail = chunks.last;
      if (wordCount(tail) <= 2) tinyTails.add('"$tail"  ← $text');
    }
  }

  final n = corpus.length;
  String pct(int a, int b) =>
      b == 0 ? '  n/a' : '${(a * 100 / b).toStringAsFixed(0).padLeft(3)}%';

  print('┌─ 첫 조각 문턱 ${floor.toString().padLeft(2)}자 '
      '${'─' * 46}');
  print('│ ① 쪼개진 turn 비율      ${pct(split, n)}  ($split/$n)');
  print('│ ② 평균 TTS chunk 수     ${(totalChunks / n).toStringAsFixed(2)}');
  print('│ ③ 첫 조각 평균 길이     ${(firstLenSum / n).toStringAsFixed(1)}자');
  print('│ ④ 자연 경계에서 끊김    ${pct(naturalBoundary, splitCount)}  '
      '($naturalBoundary/$splitCount)');
  print('│ ⑤ 1~2단어 꼬리          ${tinyTails.length}건');
  for (final t in tinyTails) {
    print('│      $t');
  }
  print('└${'─' * 62}');
  print('');
}

/// 길이대별로 쪼개짐이 어떻게 갈리는지 — 이게 정책의 핵심이다.
void byLength(int floor) {
  print('── 문턱 ${floor}자 — 길이대별 조각 수 ${'─' * 30}');
  void group(String label, List<String> items) {
    final counts = items.map((t) => runChunker(t, floor).length).toList();
    final avg = counts.reduce((a, b) => a + b) / counts.length;
    final splitRatio = counts.where((c) => c > 1).length;
    print('  $label  평균 ${avg.toStringAsFixed(2)}조각, '
        '쪼개짐 $splitRatio/${items.length}');
  }

  group('실측+짧은 말', <String>[...realSamples, ...shortSamples]);
  group('중간 문장   ', mediumSamples);
  group('긴 문장     ', longSamples);
  print('');
}

void main() {
  print('');
  print('말뭉치 ${corpus.length}건 '
      '(실측 ${realSamples.length} / 짧은 ${shortSamples.length} / '
      '중간 ${mediumSamples.length} / 긴 ${longSamples.length})');
  print('⚠️ 실측은 3건뿐이다. 나머지는 지어낸 문장이므로 경향만 본다.');
  print('');

  for (final floor in <int>[12, 16, 20, 24, 28, 40, 60]) {
    report(floor);
  }
  for (final floor in <int>[16, 20, 24, 28]) {
    byLength(floor);
  }

  // 대표 문장이 문턱마다 어떻게 갈리는지 눈으로 본다.
  print('── 대표 문장의 실제 조각 ${'─' * 38}');
  const probes = <String>[
    'Sounds good. Thanks a lot.',
    "If you're free this afternoon, do you want to grab a coffee together?",
  ];
  for (final text in probes) {
    print('  "$text"');
    for (final floor in <int>[20, 28, 40, 60]) {
      final chunks = runChunker(text, floor);
      print('    ${floor.toString().padLeft(2)}자 → ${chunks.length}조각  '
          '${chunks.map((c) => '「$c」').join(' ')}');
    }
    print('');
  }
}
