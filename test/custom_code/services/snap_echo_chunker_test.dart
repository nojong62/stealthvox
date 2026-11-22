import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/chirp_pause_markup.dart';
import 'package:stealth_vox/custom_code/services/snap_echo_chunker.dart';

String _reply(List<String> chunks) => jsonEncode(<String, dynamic>{
      'choices': <dynamic>[
        <String, dynamic>{
          'message': <String, dynamic>{
            'content': jsonEncode(<String, dynamic>{'chunks': chunks}),
          },
        },
      ],
    });

void main() {
  const original = 'I went to the store yesterday because I needed milk.';

  group('SnapEchoChunker', () {
    test('keeps chunks that preserve every character', () {
      final chunks = SnapEchoChunker.parseChunks(
        _reply(<String>[
          'I went',
          'to the store',
          'yesterday',
          'because I needed milk.',
        ]),
        original,
      );
      expect(chunks, hasLength(4));
    });

    test('rejects chunks that change a word', () {
      expect(
        SnapEchoChunker.parseChunks(
          _reply(<String>[
            'I went',
            'to the shop',
            'yesterday',
            'because I needed milk.'
          ]),
          original,
        ),
        isNull,
      );
    });

    test('rejects a single chunk and broken JSON', () {
      expect(SnapEchoChunker.parseChunks(_reply(<String>[original]), original),
          isNull);
      expect(SnapEchoChunker.parseChunks('not json', original), isNull);
    });

    test('languages without spaces compare the same way', () {
      expect(
        SnapEchoChunker.chunksPreserveText(
            <String>['昨日', '店に', '行きました。'], '昨日店に行きました。'),
        isTrue,
      );
    });

    test('only English uses the stress-beat rules and its own cache version', () {
      expect(SnapEchoChunker.isEnglish('English'), isTrue);
      expect(SnapEchoChunker.isEnglish(' english '), isTrue);
      expect(SnapEchoChunker.isEnglish('Korean'), isFalse);
      expect(SnapEchoChunker.isEnglish('Japanese'), isFalse);

      expect(SnapEchoChunker.instructions('English', SnapUnitSize.quick),
          contains('stress-timed'));
      expect(SnapEchoChunker.instructions('Spanish', SnapUnitSize.quick),
          isNot(contains('stress-timed')));

      expect(snapChunkVersionFor('English'), kSnapChunkEnglishStressVersion);
      expect(snapChunkVersionFor('Korean'), kSnapChunkVersion);
    });

    test('English quick and full state different beat counts', () {
      final quick =
          SnapEchoChunker.instructions('English', SnapUnitSize.quick);
      final full = SnapEchoChunker.instructions('English', SnapUnitSize.full);
      expect(quick, contains('Exactly 1 stressed beat'));
      expect(full, contains('Exactly 2 stressed beats'));
      expect(quick, isNot(equals(full)));
    });

    test('mergeOrphanTail folds a short last unit into the one before', () {
      expect(
        SnapEchoChunker.mergeOrphanTail(
            <String>['I went to the store', 'yesterday.']),
        <String>['I went to the store yesterday.'],
      );
      // 꼬리가 충분히 길면 그대로 둔다.
      expect(
        SnapEchoChunker.mergeOrphanTail(
            <String>['I went to the store', 'because I needed milk.']),
        <String>['I went to the store', 'because I needed milk.'],
      );
      // 합치면 11단어를 넘으면 그대로 둔다.
      expect(
        SnapEchoChunker.mergeOrphanTail(<String>[
          'one two three four five six seven eight nine ten',
          'eleven twelve',
        ]),
        <String>[
          'one two three four five six seven eight nine ten',
          'eleven twelve',
        ],
      );
    });

    test('Gemini style prompt asks for 99% pace and stress-centered rhythm', () {
      expect(kSnapGeminiStylePrompt, contains('99 percent'));
      expect(kSnapGeminiStylePrompt, isNot(contains('85 percent')));
      expect(kSnapGeminiStylePrompt, contains('stressed syllable'));
      expect(kSnapGeminiCacheTag, isNotEmpty);
    });

    test('markup puts the pause tag between every unit', () {
      expect(
        SnapEchoChunker.markup(
            <String>['I went', 'to the store.'], ChirpPause.short),
        'I went [pause short] to the store.',
      );
    });
  });
}
