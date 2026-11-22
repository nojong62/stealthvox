import 'package:cloud_firestore/cloud_firestore.dart';

// ====================================================================
// 🧱 [CHUNKED-BATCH] 500건 한도를 넘지 않게 나눠 쓰는 batch
// --------------------------------------------------------------------
// Firestore WriteBatch는 한 번에 500건까지다. 넘으면 **통째로 실패**한다.
// Duo canonical 적용은 줄마다 쓰기를 하나씩 얹으므로, 긴 통화에서 이 한도에
// 닿을 수 있다.
//
// WriteBatch와 같은 모양(`update`/`set`/`commit`)이라 바꿔 끼우기만 하면 된다.
//
// ⚠️ 덩어리 사이는 원자적이지 않다. 중간 덩어리가 실패하면 앞 덩어리는 이미
// 반영돼 있다. 호출부는 **다시 돌려도 같은 결과가 되는 쓰기**(문서 id가 정해진
// set·update)에만 써야 한다 — canonical 적용이 그렇다.
// ====================================================================

typedef _BatchOp = void Function(WriteBatch batch);

class ChunkedWriteBatch {
  ChunkedWriteBatch({FirebaseFirestore? firestore, this.maxOps = 400})
      : _db = firestore ?? FirebaseFirestore.instance,
        assert(maxOps > 0 && maxOps <= 500);

  final FirebaseFirestore _db;

  /// 덩어리 하나가 담는 최대 쓰기 수. 한도(500)보다 여유를 둔다.
  final int maxOps;

  final List<_BatchOp> _ops = <_BatchOp>[];

  int get opCount => _ops.length;

  void update(DocumentReference<Object?> ref, Map<String, dynamic> data) {
    _ops.add((b) => b.update(ref, data));
  }

  void set(
    DocumentReference<Object?> ref,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) {
    _ops.add((b) => b.set(ref, data, options));
  }

  void delete(DocumentReference<Object?> ref) {
    _ops.add((b) => b.delete(ref));
  }

  Future<void> commit() async {
    for (var i = 0; i < _ops.length; i += maxOps) {
      final batch = _db.batch();
      final end = i + maxOps < _ops.length ? i + maxOps : _ops.length;
      for (var j = i; j < end; j++) {
        _ops[j](batch);
      }
      await batch.commit();
    }
  }

  /// [total]건을 [max]건씩 나누면 몇 번 커밋하는가. 테스트용.
  static int commitsFor(int total, int max) =>
      total <= 0 ? 0 : (total + max - 1) ~/ max;
}
