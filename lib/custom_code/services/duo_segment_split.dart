import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'chunked_write_batch.dart';
import 'duo_canonical.dart'
    show kDuoCanonicalAppliedAtField, kDuoModeField, kDuoRoomIdField;
import 'duo_final_transcription.dart' show duoFinalSupersedesRestoration;
import 'duo_study_state.dart';
import 'history_finalize.dart' show kHistoryStateDraft, kHistoryStateField;

// ====================================================================
// ✂️ [DUO-SEGMENT] 긴 직접 통화를 공부방에서 10분 단위 기록으로 나눈다
// --------------------------------------------------------------------
// 통화는 끊지 않는다. **통화 중에는 아무것도 바뀌지 않는다.** 통화가 끝나고
// 공부방에 들어와 정돈(canonical)과 재전사가 끝난 뒤, 그 방의 줄을 10분 조각으로
// 갈라 `…_s1`, `…_s2` 같은 형제 기록으로 옮긴다.
//
// 경계는 줄의 `created_at`으로 정한다. 정돈이 이 값을 **공유 시간축**으로 다시
// 써 두었으므로, 두 폰이 같은 규칙을 쓰면 같은 자리에서 끊긴다(폰 시계 무관).
//
// ⚠️ **기본은 꺼져 있다.** `--dart-define=DUO_SEGMENT_SPLIT=true`인 시험 빌드에서만
// 돈다. 실기기에서 두 폰이 같은 조각을 만드는지 확인하기 전에는 켜지 않는다.
//
// 안전장치
//   · 형제 문서 id가 정해져 있다(`<원본>_s<k>`) — 다시 돌려도 중복이 안 생긴다.
//   · 형제를 먼저 쓰고, 원본에서 지우는 것은 맨 마지막이다. 중간에 끊겨도 줄이
//     사라지지 않는다.
//   · 재전사가 끝난 방만 나눈다(진행 중이면 옮겨진 줄을 되쓰려다 실패한다).
// ====================================================================

const bool kDuoSegmentSplit =
    bool.fromEnvironment('DUO_SEGMENT_SPLIT', defaultValue: false);

/// 시험 빌드만 `--dart-define=DUO_SEGMENT_MS=60000`으로 줄인다. 기본 10분.
const int kDuoSegmentMs =
    int.fromEnvironment('DUO_SEGMENT_MS', defaultValue: 10 * 60 * 1000);

/// 이 줄이 어느 시각의 줄인가. 나누기 계획의 입력.
class DuoSplitRow {
  const DuoSplitRow({required this.id, required this.createdAtMs});
  final String id;
  final int createdAtMs;
}

/// 두 번째 조각부터의 시작 시각들(오름차순). 조각이 하나뿐이면 빈 목록이다.
///
/// 첫 줄 시각 기준 [segMs] 칸으로 나누되, **줄이 하나도 없는 칸은 건너뛴다**
/// (10분 넘게 말이 없었으면 그만큼 빈 기록을 만들지 않는다).
List<int> duoSegmentBoundsMs(
  List<DuoSplitRow> rows, {
  int segMs = kDuoSegmentMs,
}) {
  if (rows.isEmpty) return const <int>[];
  final sorted = [...rows]
    ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  final int t0 = sorted.first.createdAtMs;
  final seen = <int>{};
  for (final r in sorted) {
    final int cell = (r.createdAtMs - t0) ~/ segMs;
    if (cell > 0) seen.add(cell);
  }
  final cells = seen.toList()..sort();
  return <int>[for (final c in cells) t0 + c * segMs];
}

/// [ms]가 몇 번째 조각인가(0부터). [bounds]는 [duoSegmentBoundsMs]의 결과.
int duoSegmentIndexOf(int ms, List<int> bounds) {
  var index = 0;
  for (final b in bounds) {
    if (ms >= b) index++;
  }
  return index;
}

/// 이 방을 나눠도 되는가. 판정만 하고 Firestore를 모른다.
bool shouldSplitDuoHistory(
  Map<String, dynamic>? room, {
  bool enabled = kDuoSegmentSplit,
}) {
  if (!enabled || room == null) return false;
  if ((room[kDuoRoomIdField] ?? '').toString().trim().isEmpty) return false;
  if ((room[kDuoModeField] ?? '').toString() != 'direct') return false;
  if ((room[kHistoryStateField] ?? '').toString() != kHistoryStateDraft) {
    return false;
  }
  if (room[kDuoCanonicalAppliedAtField] == null) return false;
  if (room[kDuoSegmentSplitAtField] != null) return false;
  // 재전사가 끝난 방만. 진행 중이면 옮긴 줄을 되쓰려다 실패한다.
  if (!duoFinalSupersedesRestoration(room)) return false;
  return true;
}

const String kDuoSegmentSplitAtField = 'duo_segment_split_at';
const String kDuoSegmentIndexField = 'duo_segment_index';
const String kDuoSegmentTotalField = 'duo_segment_total';
const String kDuoSegmentOfField = 'duo_segment_of';

int _ms(Object? v) => v is Timestamp ? v.millisecondsSinceEpoch : 0;

/// 방 하나를 10분 조각으로 나눈다. 나눴으면 조각 수, 아니면 1.
Future<int> splitDuoHistoryIntoSegments(
  DocumentReference<Map<String, dynamic>> historyRef,
) async {
  final snap = await historyRef.get();
  final room = snap.data();
  if (!shouldSplitDuoHistory(room)) return 1;

  final messages = await historyRef.collection('messages').get();
  final rows = <DuoSplitRow>[
    for (final d in messages.docs)
      DuoSplitRow(id: d.id, createdAtMs: _ms(d.data()['created_at']))
  ]..removeWhere((r) => r.createdAtMs == 0);
  final bounds = duoSegmentBoundsMs(rows);
  if (bounds.isEmpty) return 1;

  final int total = bounds.length + 1;
  final byId = {for (final d in messages.docs) d.id: d};
  final perSegment = List<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.generate(
      total, (_) => []);
  for (final r in rows) {
    perSegment[duoSegmentIndexOf(r.createdAtMs, bounds)].add(byId[r.id]!);
  }

  final String name = (room!['room_name'] ?? '').toString();
  final batch = ChunkedWriteBatch();
  for (var k = 1; k < total; k++) {
    final docs = perSegment[k];
    if (docs.isEmpty) continue;
    final sibling = historyRef.parent.doc('${historyRef.id}_s$k');
    final int visible =
        docs.where((d) => isStudyVisible(d.data()[kStudyStateField])).length;
    final int firstMs = docs.map((d) => _ms(d.data()['created_at'])).reduce(
        (a, b) => a < b ? a : b);
    final int lastMs = docs.map((d) => _ms(d.data()['created_at'])).reduce(
        (a, b) => a > b ? a : b);
    batch.set(sibling, <String, dynamic>{
      ...room,
      'room_name': '$name (${k + 1}/$total)',
      'msg_count': visible,
      'created_at': Timestamp.fromMillisecondsSinceEpoch(firstMs),
      'last_message_time': Timestamp.fromMillisecondsSinceEpoch(lastMs),
      kDuoSegmentIndexField: k,
      kDuoSegmentTotalField: total,
      kDuoSegmentOfField: historyRef.id,
      kDuoSegmentSplitAtField: FieldValue.serverTimestamp(),
    });
    for (final d in docs) {
      batch.set(sibling.collection('messages').doc(d.id), d.data());
    }
  }
  await batch.commit(); // 1) 형제를 먼저 쓴다.

  final cleanup = ChunkedWriteBatch();
  for (var k = 1; k < total; k++) {
    for (final d in perSegment[k]) {
      cleanup.delete(d.reference);
    }
  }
  final int firstVisible = perSegment[0]
      .where((d) => isStudyVisible(d.data()[kStudyStateField]))
      .length;
  cleanup.update(historyRef, <String, dynamic>{
    'room_name': '$name (1/$total)',
    'msg_count': firstVisible,
    kDuoSegmentIndexField: 0,
    kDuoSegmentTotalField: total,
    kDuoSegmentSplitAtField: FieldValue.serverTimestamp(),
  });
  await cleanup.commit(); // 2) 원본에서 옮긴 줄을 지우는 것은 맨 마지막이다.
  debugPrint('[DUO-SEGMENT] split history=${historyRef.id} segments=$total');
  return total;
}
