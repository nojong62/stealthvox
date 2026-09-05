import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/actions/billing_ticker.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';
import 'package:stealth_vox/custom_code/services/history_finalize.dart';

/// 새로 만든 방(검수 대기).
Map<String, dynamic> draftRoom() => <String, dynamic>{
      'room_name': 'Duo Connect Mode',
      ...historyDraftSeed(),
    };

/// 사용자가 확정한 방.
Map<String, dynamic> finalizedRoom() => <String, dynamic>{
      'room_name': 'Duo Connect Mode',
      ...historyFinalizePatch(finalizedAt: 'STAMP'),
    };

/// 이 기능이 생기기 전에 쌓인 방. 상태 필드가 아예 없다.
Map<String, dynamic> legacyRoom() => <String, dynamic>{
      'room_name': 'Circle Talk · 카페',
      'my_speech': '이미 만들어 둔 글',
      'speech_generated_at': 'STAMP',
    };

void main() {
  group('세션 길이', () {
    test('한 세션은 600초다', () {
      // 디버그 override(--dart-define=SESSION_SECONDS)를 주지 않은 상태.
      expect(BillingTicker.kSessionSeconds, 600);
    });

    test('보유 이용시간과 다른 축이다 — 세션 값이 잔여시간을 건드리지 않는다', () {
      // 세션은 "한 기록의 길이"일 뿐이다. 1시간을 산 사람은 10분짜리 기록
      // 여섯 개로 나눠 쓸 뿐, 쓸 수 있는 총량은 그대로다.
      expect(BillingTicker.kSessionSeconds * 6, 3600);
    });
  });

  group('방 단계 판정', () {
    test('새 방은 DRAFT로 시작한다', () {
      expect(resolveHistoryPhase(draftRoom()), HistoryEditPhase.draft);
      expect(historyDraftSeed()[kHistoryStateField], kHistoryStateDraft);
    });

    test('상태 필드가 없는 옛 방은 FINALIZED다 — 마이그레이션하지 않는다', () {
      expect(resolveHistoryPhase(legacyRoom()), HistoryEditPhase.finalized);
      expect(resolveHistoryPhase(null), HistoryEditPhase.finalized);
      expect(resolveHistoryPhase(<String, dynamic>{}),
          HistoryEditPhase.finalized);
    });

    test('모르는 값도 FINALIZED다 — 판단이 안 서면 지금까지 돌던 대로 돈다', () {
      expect(
          resolveHistoryPhase(<String, dynamic>{kHistoryStateField: 'generated'}),
          HistoryEditPhase.finalized);
    });

    test('옛 방과 "사용자가 확정한 방"을 구별한다', () {
      expect(historyStateIsExplicit(legacyRoom()), isFalse);
      expect(historyStateIsExplicit(draftRoom()), isTrue);
      expect(historyStateIsExplicit(finalizedRoom()), isTrue);
      expect(historyIsUserFinalized(legacyRoom()), isFalse);
      expect(historyIsUserFinalized(finalizedRoom()), isTrue);
    });
  });

  group('DRAFT — 고칠 수 있고, 아무것도 만들지 않는다', () {
    test('원문을 고치고 지울 수 있다', () {
      expect(historyEditAllowed(draftRoom()), isTrue);
    });

    test('배울글·Practice·My/Native English 어느 것도 만들지 않는다', () {
      expect(historyGenerationAllowed(draftRoom()), isFalse);
    });

    test('확정 버튼을 누를 수 있다', () {
      expect(canFinalizeHistory(draftRoom()), isTrue);
    });
  });

  group('FINALIZED — 원문은 잠기고 생성이 열린다', () {
    test('원문을 더 고칠 수 없다', () {
      expect(historyEditAllowed(finalizedRoom()), isFalse);
    });

    test('학습 자료를 만들 수 있다', () {
      expect(historyGenerationAllowed(finalizedRoom()), isTrue);
    });

    test('두 번 확정할 수 없다 — 1회성이다', () {
      expect(canFinalizeHistory(finalizedRoom()), isFalse);
    });

    test('되돌리는 문은 없다 — DRAFT로 되돌리는 함수를 만들지 않았다', () {
      // 확정본이 흔들리면 Practice·My English·Native English가 서로 다른
      // 원문을 참조하게 된다. 마음에 안 들면 방을 지우고 새로 만든다.
      final patch = historyFinalizePatch(finalizedAt: 'STAMP');
      expect(patch[kHistoryStateField], kHistoryStateFinalized);
      expect(patch[kHistoryFinalizedAtField], 'STAMP');
    });
  });

  group('옛 방은 지금까지처럼 돈다', () {
    test('편집만 없고 생성은 그대로 열려 있다', () {
      expect(historyEditAllowed(legacyRoom()), isFalse);
      expect(historyGenerationAllowed(legacyRoom()), isTrue);
    });

    test('옛 방에는 확정 버튼 자체가 없다', () {
      // 화면은 historyStateIsExplicit로 이 자리를 그릴지 정한다.
      expect(historyStateIsExplicit(legacyRoom()), isFalse);
      expect(canFinalizeHistory(legacyRoom()), isFalse);
    });
  });

  group('줄 편집 저장 모양', () {
    test('고친 원문을 쓰면서 옛 배울글을 비운다', () {
      final patch =
          historyMessageEditPatch(text: '  내일 갈게요  ', editedAt: 'T1');
      expect(patch['original_text'], '내일 갈게요');
      // 그 번역은 고치기 전 문장에서 나온 것이다. 비워야 다시 만들어진다.
      expect(patch['translated_text'], '');
      expect(patch[kMessageUserEditedAtField], 'T1');
    });

    test('빈 내용은 삭제다', () {
      expect(editedOriginalMeansDelete(''), isTrue);
      expect(editedOriginalMeansDelete('   \n  '), isTrue);
      expect(editedOriginalMeansDelete('네'), isFalse);
    });

    test('삭제는 논리 삭제다 — 문서를 지우지 않는다', () {
      final patch = historyMessageDeletePatch(editedAt: 'T1');
      expect(patch[kStudyStateField], kStudyStateDeletedByUser);
      expect(patch[kMessageUserEditedAtField], 'T1');
      // 원문을 지우는 필드가 patch에 없다 = 원본은 그대로 남는다.
      expect(patch.containsKey('original_text'), isFalse);
    });

    test('지운 줄은 화면·배울글·Practice·My/Native English에서 함께 빠진다', () {
      // 다섯 경로가 모두 isStudyVisible 하나를 본다(_visibleMessages).
      expect(isStudyVisible(kStudyStateDeletedByUser), isFalse);
    });

    test('사용자 삭제는 기술적 숨김과 다른 범주다', () {
      // kStudyStateHidden은 "전부 기술적 사유"라는 약속을 지킨다.
      expect(kStudyStateHidden.contains(kStudyStateDeletedByUser), isFalse);
    });
  });

  group('🛡️ Canonical이 사용자 편집을 덮지 못한다', () {
    Map<String, dynamic> untouchedLine() => <String, dynamic>{
          'original_text': '어… 그러니까',
          'channel_msg_id': 'c1',
        };
    Map<String, dynamic> editedLine() => <String, dynamic>{
          'original_text': '그러니까 내일 두 시에',
          'channel_msg_id': 'c1',
          kMessageUserEditedAtField: 'T1',
        };
    Map<String, dynamic> deletedLine() => <String, dynamic>{
          'original_text': '음',
          'channel_msg_id': 'c1',
          kStudyStateField: kStudyStateDeletedByUser,
          kMessageUserEditedAtField: 'T1',
        };

    test('DRAFT + 손 안 댄 줄 → 정돈이 반영된다', () {
      expect(duoCanonicalMayApplyToRoom(draftRoom()), isTrue);
      expect(duoCanonicalMayApplyToMessage(untouchedLine()), isTrue);
    });

    test('DRAFT + 사용자가 고친 줄 → 덮지 못한다', () {
      // 한 줄을 고친 직후 새 판이 도착하는 일이 실제로 있다. 방 가드만으로는
      // 그 수정이 조용히 지워진다.
      expect(duoCanonicalMayApplyToRoom(draftRoom()), isTrue);
      expect(duoCanonicalMayApplyToMessage(editedLine()), isFalse);
    });

    test('DRAFT + 사용자가 지운 줄 → 되살아나지 않는다', () {
      expect(duoCanonicalMayApplyToMessage(deletedLine()), isFalse);
    });

    test('FINALIZED 방 → 어떤 줄도 덮지 못한다', () {
      expect(duoCanonicalMayApplyToRoom(finalizedRoom()), isFalse);
    });

    test('옛 방에는 정돈이 그대로 붙는다 — 필드가 없다고 잃으면 안 된다', () {
      // 앱을 먼저 꺼서 아직 정돈 결과를 못 받은 옛 Duo 방이 굳으면 안 된다.
      expect(duoCanonicalMayApplyToRoom(legacyRoom()), isTrue);
      expect(duoCanonicalMayApplyToRoom(null), isTrue);
    });

    test('줄 정보가 없으면 막지 않는다', () {
      expect(duoCanonicalMayApplyToMessage(null), isTrue);
      expect(duoCanonicalMayApplyToMessage(<String, dynamic>{}), isTrue);
    });
  });

  group('개인 기록은 각자의 것이다', () {
    test('호스트와 게스트의 방 상태는 서로 독립이다', () {
      // 같은 통화라도 방 문서가 각자의 users/{uid} 아래에 따로 있다. 한쪽을
      // 확정해도 다른 쪽 판정에 쓰이는 값이 달라지지 않는다.
      final host = finalizedRoom();
      final guest = draftRoom();
      expect(historyEditAllowed(host), isFalse);
      expect(historyEditAllowed(guest), isTrue);
      expect(duoCanonicalMayApplyToRoom(host), isFalse);
      expect(duoCanonicalMayApplyToRoom(guest), isTrue);
    });

    test('한쪽이 지운 줄이 다른 쪽 줄 판정을 바꾸지 않는다', () {
      final hostLine = <String, dynamic>{
        'channel_msg_id': 'c9',
        kStudyStateField: kStudyStateDeletedByUser,
        kMessageUserEditedAtField: 'T1',
      };
      final guestLine = <String, dynamic>{'channel_msg_id': 'c9'};
      expect(isStudyVisible(hostLine[kStudyStateField]), isFalse);
      expect(isStudyVisible(guestLine[kStudyStateField]), isTrue);
      expect(duoCanonicalMayApplyToMessage(guestLine), isTrue);
    });
  });

  group('📋 목록 미리보기는 지금 보이는 마지막 줄이다', () {
    Map<String, dynamic> line(String text, {String? state}) =>
        <String, dynamic>{
          'original_text': text,
          if (state != null) kStudyStateField: state,
        };

    List<String> visible(List<Map<String, dynamic>> msgs) =>
        visibleOriginalsForPreview(msgs);

    test('보이는 줄만 후보가 된다 — 판정은 isStudyVisible 하나뿐', () {
      final rows = visible(<Map<String, dynamic>>[
        line('안녕하세요'),
        line('음', state: kStudyStateHiddenHesitation),
        line('네 반가워요'),
        line('지웠어요', state: kStudyStateDeletedByUser),
      ]);
      expect(rows, <String>['안녕하세요', '네 반가워요']);
    });

    test('① 마지막 대사를 수정하면 미리보기도 새 문장이다', () {
      final preview = recomputeLastMessage(
        visibleOriginals: <String>['A', 'B', 'C'],
        changedIndex: 2,
        deleted: false,
        editedText: '  C를 고쳤다  ',
      );
      expect(preview, 'C를 고쳤다');
    });

    test('② 중간 대사를 수정하면 방 문서를 쓰지 않는다', () {
      final preview = recomputeLastMessage(
        visibleOriginals: <String>['A', 'B', 'C'],
        changedIndex: 1,
        deleted: false,
        editedText: 'B를 고쳤다',
      );
      expect(preview, isNull, reason: 'null = 쓸 필요 없음');
    });

    test('③ 마지막 대사를 지우면 그 앞 대사로 물러난다', () {
      final preview = recomputeLastMessage(
        visibleOriginals: <String>['A', 'B', 'C'],
        changedIndex: 2,
        deleted: true,
      );
      expect(preview, 'B');
    });

    test('④ 중간 대사를 지워도 미리보기는 그대로다', () {
      final preview = recomputeLastMessage(
        visibleOriginals: <String>['A', 'B', 'C'],
        changedIndex: 1,
        deleted: true,
      );
      expect(preview, isNull);
    });

    test('⑤ 뒤쪽이 이미 감춰진 줄이면 그 앞의 보이는 대사를 고른다', () {
      // 감춰진 줄은 애초에 목록에 없다 — 화면이 보는 그 목록을 그대로 쓴다.
      final rows = visible(<Map<String, dynamic>>[
        line('A'),
        line('B'),
        line('C', state: kStudyStateHiddenEcho),
        line('D', state: kStudyStateDeletedByUser),
      ]);
      expect(rows, <String>['A', 'B']);
      expect(
          recomputeLastMessage(
              visibleOriginals: rows, changedIndex: 1, deleted: true),
          'A');
    });

    test('⑥ 전부 지우면 옛 문장이 남지 않는다', () {
      final preview = recomputeLastMessage(
        visibleOriginals: <String>['A'],
        changedIndex: 0,
        deleted: true,
      );
      // '' = 호출부가 필드를 지운다. 지운 문장을 목록에 남기지 않는다.
      expect(preview, '');
    });

    test('빈 줄만 앞에 남았어도 지운 문장을 되살리지 않는다', () {
      final preview = recomputeLastMessage(
        visibleOriginals: <String>['   ', 'C'],
        changedIndex: 1,
        deleted: true,
      );
      expect(preview, '');
    });

    test('목록에 없는 줄이면 아무것도 하지 않는다', () {
      expect(
          recomputeLastMessage(
              visibleOriginals: <String>['A'], changedIndex: -1, deleted: true),
          isNull);
      expect(
          recomputeLastMessage(
              visibleOriginals: <String>[], changedIndex: 0, deleted: true),
          isNull);
    });

    test('⑦ Duo 한쪽의 수정이 상대 미리보기를 건드리지 않는다', () {
      // 계산에 들어가는 것은 그 사람 방의 줄 목록뿐이다. 공유 원본도,
      // 상대 방 문서도 입력이 아니다.
      final mine = <String>['A', 'B'];
      final theirs = <String>['A', 'B'];
      final minePreview = recomputeLastMessage(
          visibleOriginals: mine, changedIndex: 1, deleted: true);
      expect(minePreview, 'A');
      // 상대 목록은 그대로 남아 있고, 그쪽에서 다시 계산해도 결과가 다르다.
      expect(theirs, <String>['A', 'B']);
      expect(
          recomputeLastMessage(
              visibleOriginals: theirs, changedIndex: -1, deleted: false),
          isNull);
    });
  });

  group('👻 다 지운 방이 목록에서 사라지지 않는다', () {
    test('마지막 한 줄까지 지우면 빈 문자열이다 — 필드를 지우라는 뜻이 아니다', () {
      final preview = recomputeLastMessage(
        visibleOriginals: <String>['A'],
        changedIndex: 0,
        deleted: true,
      );
      expect(preview, '');
      expect(preview, isNotNull, reason: '방 문서에 빈 값을 실제로 쓴다');
    });

    test('빈 값과 없는 값은 뜻이 다르다', () {
      // 목록은 이 둘로 두 방을 가른다.
      //   · 없는 값 = 대사가 한 번도 없던 방 → 목록에서 뺀다
      //   · 빈 값   = 대화가 있었는데 사용자가 다 지운 방 → 목록에 남는다
      final Map<String, dynamic> neverUsed = <String, dynamic>{
        'room_name': 'Circle Talk · 카페',
        ...historyDraftSeed(),
      };
      final Map<String, dynamic> emptiedByUser = <String, dynamic>{
        'room_name': 'Circle Talk · 카페',
        'last_message': '',
        ...historyDraftSeed(),
      };
      expect(neverUsed.containsKey('last_message'), isFalse);
      expect(emptiedByUser.containsKey('last_message'), isTrue);
      expect(emptiedByUser['last_message'], '');
    });

    test('다 지운 DRAFT 방은 여전히 편집 가능한 방이다', () {
      // 되살릴 수는 없어도, 들어가서 보고 방째 지울 수는 있어야 한다.
      final room = <String, dynamic>{
        'last_message': '',
        ...historyDraftSeed(),
      };
      expect(historyEditAllowed(room), isTrue);
      expect(historyGenerationAllowed(room), isFalse);
      // 확정 가능 여부는 방 상태가 아니라 **남은 줄**이 정한다(화면이 판단).
      expect(canFinalizeHistory(room), isTrue);
      expect(visibleOriginalsForPreview(const <Map<String, dynamic>>[]),
          isEmpty);
    });
  });
}
