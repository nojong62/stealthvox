// 📝 [HISTORY-DRAFT-GATE] 확정 전에는 아무것도 만들지 않는다
//
// 이 규칙은 화면(`chat_history_master.dart`) 안에서 갈래마다 서 있다. 위젯이
// Firestore·GPT·TTS를 통째로 물고 있어 단위 테스트로 돌릴 수 없으므로,
// `duo_canonical_order_test`와 같은 방식으로 **게이트가 그 자리에 그대로 있는지**
// 소스에서 지킨다. 게이트 하나가 조용히 빠지면 확정 전 방이 GPT를 부른다.
//
// 판정식 자체(무엇이 DRAFT이고 무엇이 열리는가)는
// `history_finalize_test.dart`가 값으로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _master = 'lib/custom_code/widgets/chat_history_master.dart';
const String _canon = 'lib/custom_code/services/duo_canonical.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final String master = _read(_master);
  final String canon = _read(_canon);

  group('확정 전에는 AI가 돌지 않는다', () {
    test('배울글 예약이 DRAFT에서 멈춘다', () {
      expect(
          master,
          contains('void _scheduleMissingTargetGeneration('
              'List<DocumentSnapshot> docs) {'));
      final int at = master.indexOf('void _scheduleMissingTargetGeneration(');
      final String body = master.substring(at, at + 900);
      expect(body, contains('if (_historyIsDraft) return;'));
    });

    test('연습 진입 직전 배울글 채우기도 DRAFT에서 멈춘다', () {
      final int at = master.indexOf('Future<void> _ensureHistoryTargets(');
      expect(at, greaterThan(0));
      final String body = master.substring(at, at + 600);
      expect(body, contains('if (_historyIsDraft) return;'));
    });

    test('Practice 진입이 DRAFT에서 멈추고 확정을 묻는다', () {
      final int at = master.indexOf('Future<void> _enterShadowingFromRoom(');
      expect(at, greaterThan(0));
      final String body = master.substring(
          at,
          master.indexOf('_cachedRoomMode = _inferHistoryMode(data);', at) +
              900);
      expect(body, contains('if (!historyGenerationAllowed(data)) {'));
      // 막고 끝내지 않는다 — 이 자리에서 확정을 묻고, 확정하지 않으면 돌아간다.
      expect(
          body, contains('if (!await _confirmFinalizeForPractice()) return;'));
    });

    test('Practice에서 물어본 확정도 실제로 확정된 방만 통과시킨다', () {
      final int at =
          master.indexOf('Future<bool> _confirmFinalizeForPractice(');
      expect(at, greaterThan(0));
      final String body = master.substring(
          at, master.indexOf('Future<bool> _askFinalize(', at));
      // 되돌릴 수 없다는 말을 먼저 하고,
      expect(body, contains('최종 확정하시면 더 이상 내용 수정을 할 수 없습니다.'));
      // 확정 여부는 방 문서로 판정한다("눌렀다"는 사실이 아니라).
      expect(body, contains('return historyIsUserFinalized(_cachedRoomData);'));
    });

    test('My English가 DRAFT에서 만들어지지 않는다', () {
      final int at = master.indexOf('Future<bool> _ensureMySpeech(');
      expect(at, greaterThan(0));
      final String body =
          master.substring(at, master.indexOf('MySpeechBuilder.build', at));
      expect(body, contains('if (!historyGenerationAllowed(roomData)) {'));
    });

    test('Native English가 DRAFT에서 만들어지지 않는다', () {
      final int at = master.indexOf('Future<bool> _ensureNativeEnglish(');
      expect(at, greaterThan(0));
      final String body = master.substring(
          at, master.indexOf('NativeEnglishSpeechBuilder.build', at));
      expect(
          body, contains('if (!historyGenerationAllowed(_cachedRoomData)) {'));
    });

    test('확정 성공 직후에 생성이 열린다', () {
      final int at = master.indexOf('Future<void> _finalizeHistory(');
      expect(at, greaterThan(0));
      final String body = master.substring(at, at + 1600);
      expect(body, contains('historyFinalizePatch('));
      expect(body, contains('_scheduleMissingTargetGeneration(_cachedDocs);'));
      // ⚠️ 생성이 실패해도 DRAFT로 되돌리지 않는다. 되돌리는 코드가 없어야 한다.
      expect(body, isNot(contains('kHistoryStateDraft')));
    });

    test('확정은 두 번 걸리지 않는다', () {
      final int at = master.indexOf('Future<void> _finalizeHistory(');
      final String body = master.substring(at, at + 700);
      expect(body, contains('if (_isFinalizing) return;'));
      expect(
          body, contains('if (!canFinalizeHistory(_cachedRoomData)) return;'));
    });
  });

  group('확정본이 유일한 기준이다', () {
    test('확정한 방에서는 전사 교정이 원문을 다시 쓰지 않는다', () {
      expect(master, contains('!historyStateIsExplicit(_cachedRoomData);'));
    });

    test('옛 교정 되돌리기가 사용자가 고친 줄을 건드리지 않는다', () {
      final int at = master.indexOf('void _revertOverreachingOriginRepairs(');
      expect(at, greaterThan(0));
      final String body = master.substring(at, at + 1600);
      expect(body,
          contains('if (historyStateIsExplicit(_cachedRoomData)) return;'));
      expect(body,
          contains('if (data[kMessageUserEditedAtField] != null) continue;'));
    });
  });

  group('🛡️ Canonical 두 겹 가드', () {
    test('방 가드 — 확정한 방에는 반영하지 않는다', () {
      expect(canon, contains('if (!duoCanonicalMayApplyToRoom(room)) {'));
      expect(canon, contains('roomData'));
    });

    test('줄 가드 — 사용자가 손댄 줄은 덮지 않는다', () {
      expect(
          canon,
          contains(
              'if (!duoCanonicalMayApplyToMessage(data)) userLocked.add(channelId);'));
      // 가드는 이제 **계획 단계 한 곳**에 있다(`planDuoCanonicalRows`).
      // 대표 줄과 흡수 줄이 같은 문을 지나므로 한쪽만 새는 일이 없다.
      expect(canon, contains('required Set<String> userLockedIds,'));
      expect(canon, contains('if (userLockedIds.contains(id)) continue;'));
      // 흡수(merged) 표시도 덮어쓰기다 — 사용자가 남긴 줄을 감추면 안 된다.
      expect(canon, contains('if (plan == null || plan.create) continue;'));
      // 잠긴 줄은 **만들지도 못한다.** 생성 갈래도 같은 계획을 따른다.
      expect(canon, contains('if (!plan.create) continue;'));
    });

    test('공유 원본 messages는 여전히 지우지 않는다', () {
      expect(canon, isNot(contains('.delete()')));
    });
  });

  group('말풍선 아이콘은 셋 그대로다', () {
    test('첫 화면에서 재생 아이콘이 사라졌다', () {
      // 말풍선의 재생 버튼만 없어졌다. 튜터링 팝업의 재생
      // (`Icons.play_circle_outline_rounded`)은 그대로다.
      expect(master, isNot(contains('Icons.play_circle,')));
      expect(master, isNot(contains('_playMsgAudio(docs[index].id')));
      expect(master, isNot(contains('"소리 듣기" : _studyAccess.gateLabel')));
    });

    test('그 자리에 수정 아이콘이 들어갔다', () {
      expect(master, contains('_buildEditBtn(docs[index], rawOriginal),'));
      expect(master, contains('Icons.edit_outlined'));
    });

    test('나머지 두 아이콘은 그대로다', () {
      expect(master, contains('_buildAppBtn(docs[index].id, translated),'));
      expect(master, contains('_buildAltStyleBtn(translated),'));
      expect(master, contains('Icons.school_rounded'));
    });

    test('확정된 방에서는 수정만 잠긴다', () {
      final int at = master.indexOf('Widget _buildEditBtn(');
      expect(at, greaterThan(0));
      final String body = master.substring(at, at + 900);
      expect(body, contains('final bool editable = _historyIsDraft;'));
      expect(body, contains('확정된 대화입니다'));
    });
  });

  group('👻 줄이 하나도 없는 방도 막다른 화면이 아니다', () {
    test('하단 바가 말풍선에서 떨어져 나와 혼자 선다', () {
      expect(master,
          contains('Widget _buildHistoryFooter({required bool hasLines})'));
      expect(master, contains('onPressed: _deleteHistoryRoom,'));
    });

    test('줄이 없는 화면에도 하단 바를 그린다 — 앞뒤 이동·방 삭제가 살아 있다', () {
      final int at = master.indexOf('if (docs.isEmpty) {');
      expect(at, greaterThan(0));
      final String body = master.substring(at, at + 900);
      expect(body, contains('데이터가 없습니다.'));
      expect(body, contains('_buildHistoryFooter(hasLines: false)'));
    });

    test('남은 줄이 없으면 확정할 수 없다', () {
      final int at = master.indexOf('Widget _buildFinalizeSection(');
      expect(at, greaterThan(0));
      final String body = master.substring(
          at, master.indexOf('Future<void> _confirmFinalizeHistory(', at));
      expect(body, contains('(draft && hasLines && !_isFinalizing)'));
      expect(body, contains('남은 대사가 없어 확정할 수 없습니다.'));
    });

    test('확정 가능 여부는 캐시가 아니라 지금 그리는 줄에서 온다', () {
      // _cachedDocs는 postFrame에 채워져 한 프레임 늦는다.
      final int at = master.indexOf('Widget _buildFinalizeSection(');
      final String body = master.substring(
          at, master.indexOf('Future<void> _confirmFinalizeHistory(', at));
      expect(body, isNot(contains('_cachedDocs.isNotEmpty')));
    });

    test('목록은 빈 값을 기존 문구로 그린다 — 새 placeholder를 만들지 않는다', () {
      final String list =
          _read('lib/custom_code/widgets/chat_history_list_master.dart');
      expect(list,
          contains('storedPreview.isEmpty ? "(대화 내용 없음)" : storedPreview'));
      // 값이 아예 없는 방(대사가 한 번도 없던 방)을 빼는 정책은 그대로다.
      expect(list, contains("if (data['last_message'] == null) return false;"));
    });
  });

  group('편집 저장은 원본을 지우지 않는다', () {
    test('빈 내용은 논리 삭제로 간다', () {
      final int at = master.indexOf('Future<void> _saveEditedMessage(');
      expect(at, greaterThan(0));
      final String body = master.substring(
          at, master.indexOf('Widget _buildInlineEditor(', at));
      expect(body, contains('editedOriginalMeansDelete(input)'));
      expect(body, contains('historyMessageDeletePatch(editedAt: stamp)'));
      expect(body,
          contains('historyMessageEditPatch(text: input, editedAt: stamp)'));
      // 문서를 지우는 길이 없다.
      expect(body, isNot(contains('.delete()')));
    });

    test('편집은 잘린 표시글이 아니라 저장된 원문 전체를 연다', () {
      expect(master, contains('final String rawOriginal = original;'));
    });

    test('목록 미리보기를 같은 자리에서 맞춘다', () {
      final int at = master.indexOf('Future<void> _saveEditedMessage(');
      final String body = master.substring(
          at, master.indexOf('Widget _buildInlineEditor(', at));
      // 줄을 쓰기 **전에** 계산한다 — 스트림을 기다리면 목록에 지운 문장이
      // 그대로 떠 있다.
      expect(body.indexOf('recomputeLastMessage('),
          lessThan(body.indexOf('await doc.reference.update(')));
      expect(body, contains('visibleOriginalsForPreview('));
      // 중간 줄이면 방 문서를 건드리지 않는다.
      expect(body, contains('if (preview != null) {'));
      // 남은 줄이 없어도 필드를 지우지 않는다 — 아래 유령 방 테스트 참고.
      expect(body, contains("{'last_message': preview}"));
    });

    test('다 지운 방은 필드를 지우지 않고 빈 값을 쓴다', () {
      final int at = master.indexOf('Future<void> _saveEditedMessage(');
      final String body = master.substring(
          at, master.indexOf('Widget _buildInlineEditor(', at));
      // FieldValue.delete()를 쓰면 목록 필터가 그 방을 통째로 걸러 유령 방이
      // 된다(`chat_history_list_master`의 last_message == null).
      expect(body, isNot(contains('FieldValue.delete()')));
      expect(body,
          contains(".update(<String, dynamic>{'last_message': preview})"));
    });

    test('상대 History는 입력에도 출력에도 없다', () {
      final int at = master.indexOf('Future<void> _saveEditedMessage(');
      final String body = master.substring(
          at, master.indexOf('Widget _buildInlineEditor(', at));
      // 쓰는 곳은 내 방 문서와 내 줄뿐이다.
      expect(body, contains('await widget.historyDoc'));
      expect(body, contains('await doc.reference.update('));
      expect(body, isNot(contains('duo_sessions')));
      expect(body, isNot(contains('collectionGroup')));
    });
  });
}
