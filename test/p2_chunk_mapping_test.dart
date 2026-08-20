import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/p2_chunk_mapping.dart';

void main() {
  test('kept/evolved/new JSON을 순서대로 파싱한다', () {
    final chunks = parseP2Chunks(<Map<String, String>>[
      <String, String>{
        'text': 'I really like coffee',
        'type': 'evolved',
        'from': 'I like coffee',
      },
      <String, String>{'text': 'in the morning', 'type': 'new'},
    ], 'I really like coffee in the morning.', part1Text: 'I like coffee.');

    expect(chunks.length, 2);
    expect(chunks.first.type, 'evolved');
    expect(chunks.first.from, 'I like coffee');
    expect(chunks.first.fromStart, 0);
    expect(chunks.first.fromEnd, 13);
    expect(chunks.last.type, 'new');
  });

  test('kept에도 from이 없으면 전체 kept fallback을 사용한다', () {
    final chunks = parseP2Chunks(<Map<String, String>>[
      <String, String>{'text': 'I like coffee', 'type': 'kept'},
    ], 'I like coffee.', part1Text: 'I like coffee.');

    expect(chunks, hasLength(1));
    expect(chunks.single.text, 'I like coffee.');
    expect(chunks.single.type, 'kept');
    expect(chunks.single.from, isNull);
  });

  test('kept의 from 범위를 Part1에서 계산한다', () {
    final chunks = parseP2Chunks(<Map<String, String>>[
      <String, String>{
        'text': 'I like coffee',
        'type': 'kept',
        'from': 'I like coffee',
      },
    ], 'I like coffee.', part1Text: 'I like coffee.');

    expect(chunks.single.type, 'kept');
    expect(chunks.single.fromStart, 0);
    expect(chunks.single.fromEnd, 13);
  });

  test('new 청크에 잘못 온 from은 저장하지 않는다', () {
    final chunks = parseP2Chunks(<Map<String, String>>[
      <String, String>{
        'text': 'especially today',
        'type': 'new',
        'from': 'I like coffee',
      },
    ], 'especially today', part1Text: 'I like coffee.');

    expect(chunks.single.from, isNull);
    expect(chunks.single.toJson().containsKey('from'), isFalse);
  });

  test('청크가 Part2 전체를 덮지 않으면 fallback한다', () {
    final chunks = parseP2Chunks(<Map<String, String>>[
      <String, String>{'text': 'I like', 'type': 'new'},
    ], 'I like coffee.', part1Text: 'I like coffee.');

    expect(chunks.single.text, 'I like coffee.');
    expect(chunks.single.type, 'kept');
  });

  test('from이 Part1의 실제 substring이 아니면 fallback한다', () {
    final chunks = parseP2Chunks(<Map<String, String>>[
      <String, String>{
        'text': 'I love coffee',
        'type': 'evolved',
        'from': 'I drink tea',
      },
    ], 'I love coffee.', part1Text: 'I like coffee.');

    expect(chunks.single.text, 'I love coffee.');
    expect(chunks.single.type, 'kept');
  });

  test('단어 비율로 재생 위치의 활성 청크를 정한다', () {
    const chunks = <P2Chunk>[
      P2Chunk(text: 'one two', type: 'new'),
      P2Chunk(text: 'three four five six', type: 'new'),
    ];

    expect(p2ChunkIndexAtPosition(chunks, positionMs: 100, totalMs: 600), 0);
    expect(p2ChunkIndexAtPosition(chunks, positionMs: 300, totalMs: 600), 1);
    expect(p2ChunkIndexAtPosition(chunks, positionMs: 600, totalMs: 600), 1);
  });

  test('Part1 from 범위는 대소문자를 무시해 찾는다', () {
    final range =
        findP2SourceRange('I Like Coffee every day.', 'i like coffee');
    expect(range, isNotNull);
    expect(range!.start, 0);
    expect(range.end, 13);
  });
}
