import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/routine_mode_duo.dart';

/// 대화 방식 선택 시트 문구는 로비 ORIGIN(대화 언어)으로 고른다.
/// 로비가 고를 수 있는 언어에 빠진 칸이 있으면 시트가 빈 줄로 뜨거나
/// `!` 단정에서 터진다. 그걸 여기서 막는다.
void main() {
  /// 로비 드롭다운(`lobby_master.dart`의 `languages`)과 게스트 오버레이가
  /// 쓰는 목록. ORIGIN은 반드시 이 안의 값이다.
  const lobbyLanguages = <String>[
    'English',
    'Japanese',
    'Chinese',
    'Spanish',
    'French',
    'German',
    'Korean',
    'Hindi',
    'Russian',
    'Portuguese',
    'Italian',
    'Dutch',
  ];

  const requiredKeys = <String>[
    // 대화 방식 선택 시트
    'title',
    'subtitle',
    'directTitle',
    'directDesc',
    'interpTitle',
    'interpDesc',
    'note',
    'cancel',
    'invite',
    // 초대 직후 화면 밑에서 올라오는 알림
    'inviteDoneDirect',
    'inviteDoneInterp',
    'inviteDoneDetail',
    'inviteFailTitle',
    'inviteFailDetail',
  ];

  group('kModePickerText', () {
    test('로비가 고를 수 있는 언어 전부를 덮는다', () {
      for (final lang in lobbyLanguages) {
        expect(kModePickerText.containsKey(lang), isTrue, reason: lang);
      }
      expect(kModePickerText.length, lobbyLanguages.length);
    });

    test('언어마다 문구 칸이 모두 있고 비어 있지 않다', () {
      for (final entry in kModePickerText.entries) {
        for (final key in requiredKeys) {
          final value = entry.value[key];
          expect(value, isNotNull, reason: '${entry.key}.$key');
          expect(value!.trim(), isNotEmpty, reason: '${entry.key}.$key');
        }
        expect(entry.value.keys.toSet(), requiredKeys.toSet(),
            reason: '${entry.key} — 남거나 빠진 칸');
      }
    });

    test('한국어 문구는 예전 그대로다', () {
      final ko = kModePickerText['Korean']!;
      expect(ko['title'], '대화 방식 선택');
      expect(ko['subtitle'], '초대할 대화 방식을 골라주세요.');
      expect(ko['directTitle'], '직접 대화');
      expect(ko['directDesc'], '서로의 실제 목소리로 통화합니다.');
      expect(ko['interpTitle'], '만능 통역');
      expect(ko['interpDesc'], '상대의 말을 통역 음성으로 들려줍니다.');
      expect(ko['note'], '상대방도 선택한 방식으로 초대됩니다.');
      expect(ko['cancel'], '취소');
      expect(ko['invite'], '초대하기');
      expect(ko['inviteDoneDirect'], '직접 대화로 초대했습니다');
      expect(ko['inviteDoneInterp'], '만능 통역으로 초대했습니다');
      expect(ko['inviteDoneDetail'], '초대 링크를 복사해 뒀어요.');
      expect(ko['inviteFailTitle'], '초대 링크를 만들지 못했습니다');
      expect(ko['inviteFailDetail'], '잠시 후 다시 시도해 주세요.');
    });

    /// 초대 알림은 모드 이름에 조사를 붙이지 않고 언어별 완성 문장을 쓴다.
    /// 두 모드의 문장이 같으면 어느 방식으로 초대했는지 알 수 없다.
    test('두 모드의 초대 완료 문장이 서로 다르다', () {
      for (final entry in kModePickerText.entries) {
        expect(entry.value['inviteDoneDirect'],
            isNot(equals(entry.value['inviteDoneInterp'])),
            reason: entry.key);
      }
    });
  });

  /// 초대 흐름(방식 선택 팝업 · 초대 완료·실패 알림)은 **영어 하나**를 쓴다.
  /// 로비 ORIGIN을 따라 갈리던 것을 2026-08-27에 통일했다.
  ///
  /// 언어별 표는 지우지 않았다 — 되돌릴 때 `kDuoInviteUiLang`만 바꾸면
  /// 그대로 돌아오고, 위 시험들이 12개 언어를 계속 지킨다.
  group('초대 흐름은 영어 하나', () {
    test('kDuoInviteUiLang이 English다', () {
      expect(kDuoInviteUiLang, 'English');
      expect(modePickerTextFor(kDuoInviteUiLang), kModePickerText['English']);
    });

    test('영어 문구가 시안대로 짧다', () {
      final en = kModePickerText['English']!;
      expect(en['title'], 'Choose Call Mode');
      expect(en['subtitle'], "Pick how you'd like to talk.");
      expect(en['directTitle'], 'Direct Call');
      expect(en['directDesc'], 'Talk with your real voices.');
      expect(en['interpTitle'], 'Live Translation');
      expect(en['interpDesc'], 'Hear their words in your language.');
      expect(en['note'], 'The guest will join in this mode.');
      expect(en['cancel'], 'Cancel');
      expect(en['invite'], 'Invite');
    });
  });

  group('modePickerTextFor', () {
    test('ORIGIN 언어의 문구를 준다', () {
      expect(modePickerTextFor('Korean')['title'], '대화 방식 선택');
      expect(modePickerTextFor('Japanese')['title'], '通話方法を選ぶ');
      expect(modePickerTextFor('Dutch')['cancel'], 'Annuleren');
    });

    test('앞뒤 공백은 흡수한다', () {
      expect(modePickerTextFor('  Korean  ')['title'], '대화 방식 선택');
    });

    test('빈 값·모르는 언어는 영어로 떨어진다', () {
      final en = kModePickerText['English']!;
      expect(modePickerTextFor('')['title'], en['title']);
      expect(modePickerTextFor('Klingon')['title'], en['title']);
      expect(modePickerTextFor('korean')['title'], en['title']);
    });

    test('어떤 입력에도 칸이 다 찬 표를 준다', () {
      for (final lang in [...lobbyLanguages, '', 'nonsense']) {
        final t = modePickerTextFor(lang);
        for (final key in requiredKeys) {
          expect(t[key]?.trim(), isNotEmpty, reason: '$lang.$key');
        }
      }
    });
  });
}
