// 🩹 [USER_FIX] AI 답변과 한 호출에서 직전 유저 전사를 되살린다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/user_line_fix.dart';

String _src(String path) => File(path).readAsStringSync();

const String _circle = 'lib/custom_code/widgets/routine_mode_circle_talk.dart';
const String _scenario =
    'lib/custom_code/widgets/routine_mode_scenario_talk.dart';

void main() {
  group('형식 파싱', () {
    test('[USER_FIX] … [REPLY] … 를 유저 줄과 답으로 가른다', () {
      final fix = parseUserLineFix('''[USER_FIX]
회원 아닌 사람을 데려가도 되나요?
[REPLY]
그럼요, 이번엔 지인도 괜찮다고 하더라고요.''');
      expect(fix, isNotNull);
      expect(fix!.userLine, '회원 아닌 사람을 데려가도 되나요?');
      expect(fix.reply, '그럼요, 이번엔 지인도 괜찮다고 하더라고요.');
    });

    test('따옴표와 대소문자는 너그럽게 받는다', () {
      final fix = parseUserLineFix(
          '[user_fix] "비회원도 회비를 내야 하나요?" [reply] "아니요, 비회원은 안 내요."');
      expect(fix!.userLine, '비회원도 회비를 내야 하나요?');
      expect(fix.reply, '아니요, 비회원은 안 내요.');
    });

    test('태그가 없으면 null — 평소 답변은 그대로 흐른다', () {
      expect(parseUserLineFix('그럼요, 데려오세요.'), isNull);
      expect(parseUserLineFix(''), isNull);
    });

    test('한쪽이 비면 null', () {
      expect(parseUserLineFix('[USER_FIX]\n\n[REPLY]\n답'), isNull);
      expect(parseUserLineFix('[USER_FIX]\n유저\n[REPLY]\n'), isNull);
    });

    test('Step 2: 유저 줄은 한국어, 답은 영어여도 그대로 가른다', () {
      final fix = parseUserLineFix('''[USER_FIX]
회원 아닌 친구를 데려가도 되나요?
[REPLY]
Of course. Friends are welcome this time.''');
      expect(fix!.userLine, contains('친구'));
      expect(fix.reply, startsWith('Of course'));
    });
  });

  group('스트리밍 보류', () {
    test('태그의 앞부분이 오는 동안은 내보내지 않는다', () {
      expect(userLineFixMayBeControlSignal(''), isTrue);
      expect(userLineFixMayBeControlSignal('['), isTrue);
      expect(userLineFixMayBeControlSignal('[USER'), isTrue);
      expect(userLineFixMayBeControlSignal('[USER_FIX]\n회원'), isTrue);
    });
    test('평범한 첫 글자면 바로 내보낸다', () {
      expect(userLineFixMayBeControlSignal('그럼요'), isFalse);
      expect(userLineFixMayBeControlSignal('[HEARD_CONFIRM]'), isFalse);
    });
  });

  group('안전선 — 복원이지 다시 쓰기가 아니다', () {
    test('낱말 하나 바꾼 것은 받는다', () {
      expect(
          userLineFixIsPlausible(
              original: '피는 아닌 사람을 데려가도 되나요?',
              fixed: '회원 아닌 사람을 데려가도 되나요?'),
          isTrue);
    });
    test('원문과 같으면 고칠 게 없었던 것', () {
      expect(userLineFixIsPlausible(original: '선착순인가요?', fixed: '선착순인가요? '),
          isFalse);
    });
    test('길이가 절반 아래·두 배 넘게 달라지면 다시 쓴 것', () {
      expect(
          userLineFixIsPlausible(
              original: '선착순인가요?',
              fixed: '이번 모임은 선착순으로 받는 건지, 아니면 미리 신청을 해야 하는 건지 궁금합니다.'),
          isFalse);
      expect(
          userLineFixIsPlausible(
              original: '이번 모임에 회비가 있나요? 있으면 얼마인가요?',
              fixed: '회비요?'),
          isFalse);
    });
    test('빈 값은 거른다', () {
      expect(userLineFixIsPlausible(original: '', fixed: '회비'), isFalse);
      expect(userLineFixIsPlausible(original: '회비', fixed: ''), isFalse);
    });
  });

  group('규칙과 저장 필드', () {
    test('규칙은 복원만 허용하고 말투·문법·어순은 못 건드리게 한다', () {
      final policy = buildUserFixPolicy(nativeLang: 'Korean');
      expect(policy, contains('[USER_FIX]'));
      expect(policy, contains('[REPLY]'));
      expect(policy, contains('in Korean'));
      expect(policy, contains('This is restoration, not polishing'));
      expect(policy, contains('the sentence ending and the speech level exactly'));
      expect(policy, contains('reply normally with no tags'));
    });
    test('원 전사는 stt_text로 남고 user_fix 표가 붙는다', () {
      expect(userLineFixFields(sttText: ' 피는 아닌 사람을 '),
          {'stt_text': '피는 아닌 사람을', 'user_fix': true});
    });
  });

  group('두 대화방 배선', () {
    for (final path in <String>[_circle, _scenario]) {
      final source = _src(path);
      final name = path.contains('circle') ? '서클톡' : '시나리오톡';

      test('$name: 프롬프트에 규칙이 붙는다', () {
        expect(source, contains('buildUserFixPolicy(nativeLang:'));
        expect(source, contains('\$userFixPolicy'));
      });

      test('$name: 답에서 유저 줄을 갈라 안전선을 지나면 말풍선·저장 줄을 바꾼다', () {
        expect(source, contains('parseUserLineFix('));
        expect(source, contains('userLineFixIsPlausible('));
        expect(source, contains("_log('🩹 [USER-FIX]'"));
        expect(source, contains("_log('🩹 [USER-FIX-REJECT]'"));
        expect(source,
            contains('if (sttText != null) ...userLineFixFields(sttText: sttText),'));
        expect(source,
            contains("if (line['stt_text'] != null) 'stt_text': line['stt_text'],"));
      });
    }

    test('서클톡: 되살린 줄은 HOST 말풍선 id로 갈아 끼운다', () {
      final source = _src(_circle);
      expect(source,
          contains('updateBubbleTextById(_localMessages, hostBubbleId, userOriginal);'));
      expect(source, contains('userOriginal = userFix.userLine;'));
    });

    test('시나리오톡: 태그가 확정될 때까지 화면·TTS로 내보내지 않는다', () {
      final source = _src(_scenario);
      // 2026-10-08부터 [RETRY]가 맨 앞에 붙는다(불명확한 말은 되묻지 않고 재시도).
      expect(source,
          contains("['[RETRY]', '[HEARD_CONFIRM]', '[CORRECTION]', kUserFixTag]"));
      expect(source, contains("hostBubble['target'] = userKorean;"));
      expect(source, contains('userKorean = userFix.userLine;'));
    });
  });
}
