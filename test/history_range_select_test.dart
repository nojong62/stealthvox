// 📏 [RANGE] 대화목록 삭제 — 전체선택을 빼고 범위 선택을 넣는다
//
// 전체선택은 "다 지운다"에 너무 가까운 단추였다. 목록 삭제에서 쓰는 손짓은
// 보통 "여기서부터 저기까지"이고, Gmail·파일 탐색기의 Shift+클릭이 그 모양이다.
// 모바일에는 Shift가 없으니 **첫 칸 탭 → 끝 칸 길게**로 같은 일을 한다.
//
// 지켜야 하는 것 셋.
//   ① 전체선택은 흔적까지 없다 — 단추도 문구도 남기지 않는다
//   ② 범위는 화면에 보이는 **순서**로 정한다. 집합만으로는 사이를 못 정한다
//   ③ 카드 본체의 탭(들어가기)과 길게 누르기(덧메뉴)는 그대로다
//      범위 집기는 네모 자리가 맡는다 — 원래 고르는 손짓만 받던 자리다

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _list = 'lib/custom_code/widgets/chat_history_list_master.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 목록 한 줄을 그리는 자리. 네모의 손짓이 여기 들어 있다.
String _tileRegion(String src) {
  final int a = src.indexOf('if (showCheckbox)');
  if (a < 0) throw StateError('네모 자리를 못 찾았다');
  final int b = src.indexOf('IgnorePointer', a);
  if (b < a) throw StateError('네모 그림을 못 찾았다');
  return src.substring(a, b);
}

void main() {
  final String list = _read(_list);
  final String flat = _flat(list);

  // ── ① 전체선택 제거 ────────────────────────────────────────────
  group('① 전체선택은 없다', () {
    test('단추가 사라졌다', () {
      expect(list, isNot(contains('_buildSelectAllActionChip')));
    });

    test('문구도 남지 않았다', () {
      // 화면에 뜨는 문구만 본다. 주석에서 옛 동작을 설명하는 것은 기록이다.
      expect(list, isNot(contains("'전체선택'")));
      expect(list, isNot(contains("'선택해제'")));
      expect(list, isNot(contains('Icons.select_all_rounded')));
    });

    test('보이는 것을 통째로 담는 길이 없다', () {
      expect(list, isNot(contains('_selectedDocIds.addAll(_visibleHistoryDocIds)')),
          reason: '전체선택이 이름만 바꿔 살아 있으면 안 된다');
      expect(list,
          isNot(contains('_selectedDocIds.removeAll(_visibleHistoryDocIds)')));
    });
  });

  // ── ② 범위 선택 ────────────────────────────────────────────────
  group('② 첫 칸 탭 → 끝 칸 길게', () {
    test('순서 목록을 들고 있다 — 집합만으로는 사이를 못 정한다', () {
      expect(list, contains('List<String> _visibleHistoryDocOrder'));
      expect(flat,
          contains('_visibleHistoryDocOrder = filteredDocs.map((doc) => doc.id).toList'));
    });

    test('기준점을 들고 있다', () {
      expect(list, contains('String? _rangeAnchorDocId'));
    });

    test('탭이 기준점을 옮긴다 — 지울 때도 마찬가지다', () {
      final String tile = _tileRegion(list);
      final int onTap = tile.indexOf('onTap:');
      final int onLong = tile.indexOf('onLongPress:');
      expect(onTap, greaterThan(-1));
      expect(onLong, greaterThan(onTap));
      final String tapBody = tile.substring(onTap, onLong);
      expect(tapBody, contains('_selectedDocIds.remove(doc.id)'));
      expect(tapBody, contains('_selectedDocIds.add(doc.id)'));
      expect(tapBody, contains('_rangeAnchorDocId = doc.id'),
          reason: '집든 지우든 방금 손댄 자리가 다음 범위의 끝이다');
    });

    test('길게 누르면 사이를 통째로 집는다', () {
      final String tile = _flat(_tileRegion(list));
      expect(tile, contains('_visibleHistoryDocOrder.indexOf(doc.id)'));
      expect(tile, contains('_visibleHistoryDocOrder.indexOf(_rangeAnchorDocId!)'));
      expect(tile, contains('_visibleHistoryDocOrder.sublist(lo, hi + 1)'));
    });

    test('위아래 어느 쪽으로 찍어도 같다', () {
      final String tile = _flat(_tileRegion(list));
      expect(tile, contains('final int lo = from < to ? from : to;'));
      expect(tile, contains('final int hi = from < to ? to : from;'));
    });

    test('기준점이 없으면 조용히 넘어가지 않는다 — 하나라도 집는다', () {
      final String tile = _flat(_tileRegion(list));
      expect(tile, contains('if (from < 0 || to < 0)'));
      expect(tile, contains('HapticFeedback.selectionClick()'));
    });

    test('범위를 집으면 손끝에 알려 준다', () {
      expect(_tileRegion(list), contains('HapticFeedback.mediumImpact()'));
    });

    test('집은 끝이 다음 범위의 시작이 된다 — 이어서 집기', () {
      final String tile = _tileRegion(list);
      final int long = tile.indexOf('onLongPress:');
      final String body = tile.substring(long);
      expect(body.split('_rangeAnchorDocId = doc.id').length - 1, 2,
          reason: '기준점 없을 때와 범위를 집은 뒤, 두 자리 모두 옮겨야 한다');
    });
  });

  // ── ③ 기준점 정리 ──────────────────────────────────────────────
  group('③ 기준점은 오래 남지 않는다', () {
    test('필터를 바꾸면 지운다', () {
      final int a = list.indexOf('_selectedFilter = newFilter;');
      final String body = list.substring(a, list.indexOf('});', a));
      expect(body, contains('_rangeAnchorDocId = null'));
      expect(body, contains('_visibleHistoryDocOrder = <String>[]'));
    });

    test('목록에서 사라진 기록은 기준점이 될 수 없다', () {
      expect(
          flat,
          contains('if (_rangeAnchorDocId != null && '
              '!_visibleHistoryDocIds.contains(_rangeAnchorDocId)) '
              '{ _rangeAnchorDocId = null; }'));
    });
  });

  // ── ④ 기존 손짓 보존 ───────────────────────────────────────────
  group('④ 카드 본체는 그대로다', () {
    test('탭은 여전히 대화로 들어간다', () {
      expect(list, contains("context.pushNamed(\n          'ChatDetail',"));
      expect(list, contains('guardBillingEntry(context)'));
    });

    test('카드를 길게 누르면 여전히 덧메뉴다', () {
      expect(list, contains('onLongPress: () => _showOptionMenu(doc)'));
    });

    test('안내 칩은 기준점이 있을 때만 눌린다', () {
      final int a = list.indexOf('Widget _buildRangeHintChip()');
      expect(a, greaterThan(-1));
      final String body =
          list.substring(a, list.indexOf('// ── Keepers 전용 필터 칩 ──', a));
      expect(body, contains('첫 칸 탭 → 끝 칸 길게'));
      expect(_flat(body), contains('onTap: armed ?'),
          reason: '기준점이 없을 때도 눌리면 전체선택 자리로 되돌아간다');
      expect(_flat(body), contains('onTap: armed ? () { '
          'HapticFeedback.selectionClick(); '
          'setState(() => _rangeAnchorDocId = null); } : null'));
    });

    test('취소 표시는 기준점이 있을 때만 나온다', () {
      final int a = list.indexOf('Widget _buildRangeHintChip()');
      final String body =
          list.substring(a, list.indexOf('// ── Keepers 전용 필터 칩 ──', a));
      final int mark = body.indexOf('if (armed) ...[');
      expect(mark, greaterThan(-1),
          reason: '없을 때 ✕가 보이면 무엇을 취소하는지 알 수 없다');
      expect(body.substring(mark), contains('Icons.close_rounded'));
      expect(body.substring(mark), contains("'취소'"));
    });

    test('지우고 나면 기준점도 함께 사라진다', () {
      final int a = list.indexOf('_showBatchDeleteDialog');
      final int b = list.indexOf('_selectedDocIds.clear();', a);
      expect(b, greaterThan(-1));
      expect(list.substring(b, b + 120), contains('_rangeAnchorDocId = null'));
    });
  });
}
