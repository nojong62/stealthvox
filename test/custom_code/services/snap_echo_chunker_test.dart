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

    test('markup puts the pause tag between every unit', () {
      expect(
        SnapEchoChunker.markup(
            <String>['I went', 'to the store.'], ChirpPause.short),
        'I went [pause short] to the store.',
      );
    });
  });
}
