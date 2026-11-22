import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/chunked_write_batch.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_origin_corrector.dart';

DuoSourceUtterance _u(int i, int ms) => DuoSourceUtterance(
      id: 'u$i',
      role: i.isEven ? 'HOST' : 'GUEST',
      text: 'line $i',
      spokenAtMs: ms,
      seq: i,
      srcLang: 'ko',
    );

void main() {
  group('splitDuoSourceIntoChunks', () {
    test('a short call stays one chunk (same as before)', () {
      final src = [for (var i = 0; i < 39; i++) _u(i, i * 15000)]; // ~9.7min
      final chunks = splitDuoSourceIntoChunks(src);
      expect(chunks.length, 1);
      expect(chunks.first.length, 39);
    });

    test('splits by 10 minutes of speaking time', () {
      final src = [for (var i = 0; i < 80; i++) _u(i, i * 20000)]; // 26min
      final chunks = splitDuoSourceIntoChunks(src, maxLines: 1000);
      expect(chunks.length, 3);
      expect(chunks.expand((c) => c).map((u) => u.id).toList(),
          src.map((u) => u.id).toList());
    });

    test('splits when a chunk would exceed the line cap', () {
      final src = [for (var i = 0; i < 200; i++) _u(i, i * 1000)]; // 3.3min
      final chunks = splitDuoSourceIntoChunks(src);
      expect(chunks.map((c) => c.length).toList(), [80, 80, 40]);
    });

    test('empty input gives no chunks', () {
      expect(splitDuoSourceIntoChunks(const <DuoSourceUtterance>[]), isEmpty);
    });
  });

  group('mergeDuoOriginCorrectionResults', () {
    test('keeps corrections of chunks that did not overflow', () {
      final merged = mergeDuoOriginCorrectionResults([
        const DuoOriginCorrectionResult(
            corrections: {'a': 'A'}, proposed: 1, overflow: false),
        const DuoOriginCorrectionResult(
            corrections: {}, proposed: 9, overflow: true),
        const DuoOriginCorrectionResult(
            corrections: {'b': 'B'}, proposed: 1, overflow: false),
      ]);
      expect(merged.corrections, {'a': 'A', 'b': 'B'});
      expect(merged.proposed, 11);
      expect(merged.overflow, isTrue);
    });

    test('nothing to merge gives the empty result', () {
      final merged = mergeDuoOriginCorrectionResults(const []);
      expect(merged.corrections, isEmpty);
      expect(merged.overflow, isFalse);
    });
  });

  test('ChunkedWriteBatch stays under the 500 write limit', () {
    expect(ChunkedWriteBatch.commitsFor(0, 400), 0);
    expect(ChunkedWriteBatch.commitsFor(400, 400), 1);
    expect(ChunkedWriteBatch.commitsFor(401, 400), 2);
    expect(ChunkedWriteBatch.commitsFor(1000, 400), 3);
  });
}
