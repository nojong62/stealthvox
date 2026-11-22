import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_segment_split.dart';

List<DuoSplitRow> _rows(List<int> minutes) => [
      for (var i = 0; i < minutes.length; i++)
        DuoSplitRow(id: 'r$i', createdAtMs: 1000000 + minutes[i] * 60000)
    ];

void main() {
  group('duoSegmentBoundsMs', () {
    test('a call under 10 minutes is one segment', () {
      expect(duoSegmentBoundsMs(_rows([0, 3, 9])), isEmpty);
    });

    test('26 minutes make three segments', () {
      final bounds = duoSegmentBoundsMs(_rows([0, 4, 11, 15, 22, 26]));
      expect(bounds, [1000000 + 10 * 60000, 1000000 + 20 * 60000]);
      expect(duoSegmentIndexOf(1000000 + 4 * 60000, bounds), 0);
      expect(duoSegmentIndexOf(1000000 + 11 * 60000, bounds), 1);
      expect(duoSegmentIndexOf(1000000 + 26 * 60000, bounds), 2);
    });

    test('a segment with no lines is skipped, not made empty', () {
      final bounds = duoSegmentBoundsMs(_rows([0, 2, 31]));
      expect(bounds.length, 1);
      expect(duoSegmentIndexOf(1000000 + 31 * 60000, bounds), 1);
    });

    test('the same canonical times give the same cut on both phones', () {
      final a = duoSegmentBoundsMs(_rows([0, 12, 25]));
      final b = duoSegmentBoundsMs(_rows([25, 0, 12]));
      expect(a, b);
    });

    test('empty input', () {
      expect(duoSegmentBoundsMs(const <DuoSplitRow>[]), isEmpty);
    });
  });

  group('shouldSplitDuoHistory', () {
    Map<String, dynamic> ready() => {
          'duo_room_id': 'room1',
          'duo_mode': 'direct',
          'history_state': 'draft',
          'duo_canonical_applied_at': 1,
          'duo_final_completed_at': 1,
          'duo_final_success_count': 5,
        };

    test('off by default', () {
      expect(shouldSplitDuoHistory(ready(), enabled: false), isFalse);
      expect(kDuoSegmentSplit, isFalse);
    });

    test('splits only a finished direct draft that was not split yet', () {
      expect(shouldSplitDuoHistory(ready(), enabled: true), isTrue);
      expect(
          shouldSplitDuoHistory({...ready(), 'duo_mode': 'interpreter'},
              enabled: true),
          isFalse);
      expect(
          shouldSplitDuoHistory({...ready(), 'history_state': 'finalized'},
              enabled: true),
          isFalse);
      expect(
          shouldSplitDuoHistory({...ready(), 'duo_segment_split_at': 1},
              enabled: true),
          isFalse);
      expect(
          shouldSplitDuoHistory({...ready()}..remove('duo_canonical_applied_at'),
              enabled: true),
          isFalse);
    });
  });
}
