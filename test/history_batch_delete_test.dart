// 🗑️ [BATCH-DELETE] 고른 것은 전부 지워진다
//
// 2026-09-11 실기기. 여러 줄을 골라 지우면 **한두 개만** 지워졌다. 스낵바는
// 안 떴고 선택도 안 풀렸다. 범위 선택을 넣기 전부터 그랬다.
//
// 원인은 순회 중인 집합을 스트림이 건드리는 것이었다.
//
//   for (String docId in _selectedDocIds) {      ← 이 집합을
//     await ....doc(docId).delete();             ← await 마다 루프가 돈다
//   }
//
// `delete()`의 await에서 Firestore 스냅샷이 도착하면 StreamBuilder가 다시
// 그리고, 그 안의 `_selectedDocIds.retainAll(_visibleHistoryDocIds)`가 방금
// 지운 id를 순회 중인 집합에서 빼 버린다. 다음 반복에서
// ConcurrentModificationError가 나고 루프가 끊긴다. 예외는 async onPressed
// 안에서 삼켜져 화면에는 아무 말도 안 남았다.
//
// 규칙: **지울 목록은 먼저 베낀다.** 그러면 스트림이 무엇을 하든 상관없다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _list = 'lib/custom_code/widgets/chat_history_list_master.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 자리: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 자리: $end');
  return src.substring(a, b);
}

void main() {
  final String list = _read(_list);
  final String del =
      _region(list, 'void _showBatchDeleteDialog()', 'void _showOptionMenu(');
  final String flatDel = _flat(del);

  group('① 살아 있는 집합을 순회하지 않는다', () {
    test('지울 목록을 먼저 베낀다', () {
      expect(del, contains('final List<String> targets = _selectedDocIds.toList();'));
    });

    test('순회 대상은 베낀 목록이다', () {
      expect(del, contains('for (final String docId in targets)'));
      expect(del, isNot(contains('for (String docId in _selectedDocIds)')),
          reason: 'await 중에 스트림이 이 집합을 건드려 루프가 끊긴다');
    });

    test('베끼기가 삭제보다 먼저다', () {
      expect(del.indexOf('_selectedDocIds.toList()'),
          lessThan(del.indexOf('_deleteHistoryRoomDeep(')));
    });

    test('선택 비우기가 삭제 루프보다 먼저다 — 스트림과 다툴 것이 없다', () {
      expect(del.indexOf('_selectedDocIds.clear()'),
          lessThan(del.indexOf('for (final String docId in targets)')));
    });
  });

  group('② 하나가 실패해도 나머지를 지운다', () {
    test('삭제마다 감싼다', () {
      final String loop = _region(del, 'for (final String docId in targets)',
          'if (!mounted) return;');
      expect(loop, contains('try {'));
      expect(loop, contains('} catch (e) {'));
      expect(loop, contains('failed.add(docId)'));
    });

    test('몇 개를 지웠는지 센다', () {
      expect(del, contains('int deleted = 0;'));
      expect(del, contains('deleted++;'));
    });
  });

  group('③ 결과를 사실대로 말한다', () {
    test('지운 개수를 문구에 넣는다', () {
      // 문구는 12개 언어 표(_DeletionUiCopy)에서 온다.
      expect(flatDel, contains("copy.count('success', deleted)"));
      expect(list, contains("'success': '{count}개의 기록을 삭제했습니다.',"));
    });

    test('실패가 있으면 그것도 말한다', () {
      expect(flatDel, contains("copy.result('partial', deleted, failed.length)"));
      expect(list,
          contains("'partial': '{deleted}개를 삭제했습니다. {failed}개는 실패했습니다.',"));
      expect(_flat(del), contains('backgroundColor: failed.isEmpty ? const Color(0xFF2C2C2E) : Colors.orangeAccent'));
    });

    test('예전의 뭉뚱그린 문구는 없다', () {
      expect(del, isNot(contains('"선택한 기록이 삭제되었습니다."')),
          reason: '한 개만 지워져도 같은 말을 해서 어긋난 것을 알 수 없었다');
    });
  });

  group('④ 범위 선택 기준점도 함께 정리된다', () {
    test('선택을 비울 때 기준점도 비운다', () {
      final String clearBlock =
          _region(del, 'final List<String> targets', 'int deleted = 0;');
      expect(clearBlock, contains('_selectedDocIds.clear();'));
      expect(clearBlock, contains('_rangeAnchorDocId = null;'));
    });
  });

  // ── ⑤ 대사까지 지운다 ────────────────────────────────────────
  //
  // Firestore는 문서를 지워도 하위 컬렉션을 안 지운다. `chat_history/{id}`만
  // 지우면 `messages`가 고아로 남는다 — 목록에서 사라져 지워진 것처럼
  // 보이지만 용량과 읽기 비용은 그대로 묶여 있고, 부모가 없어 되찾을 길도 없다.
  group('⑤ 방을 지우면 대사도 같이 간다', () {
    final String deep = _region(
        list, 'Future<void> _deleteHistoryRoomDeep(', 'void _showBatchDeleteDialog()');

    test('하위 messages를 훑어 지운다', () {
      expect(deep, contains("roomRef.collection('messages')"));
      expect(deep, contains('batch.delete(d.reference)'));
    });

    test('한 줄씩 왕복하지 않는다 — 배치로 묶는다', () {
      expect(deep, contains('FirebaseFirestore.instance.batch()'));
      expect(deep, contains('const int chunk = 300;'),
          reason: '배치 상한 500보다 여유를 둔다');
      expect(deep, contains('messages.limit(chunk).get()'));
    });

    test('다 지울 때까지 돌고 마지막에 방을 지운다', () {
      expect(deep, contains('while (true)'));
      expect(deep.indexOf('batch.commit()'), lessThan(deep.indexOf('roomRef.delete()')),
          reason: '순서가 뒤집히면 부모만 사라지고 대사가 남는다');
    });

    test('일괄 삭제가 이 길로 간다', () {
      expect(_flat(del), contains('await _deleteHistoryRoomDeep( currentUserReference!'));
      expect(_flat(del), isNot(contains('.doc(docId) .delete()')),
          reason: '방 문서만 지우던 길이다');
    });

    test('단건 삭제도 같은 길로 간다', () {
      final String menu = _region(list, 'void _showDeleteDialog(', 'void _showStudyRoomManual(');
      expect(menu, contains('_deleteHistoryRoomDeep(doc.reference)'));
      expect(menu, isNot(contains('await doc.reference.delete();')),
          reason: '방 문서만 지우던 길이다');
    });
  });
}
