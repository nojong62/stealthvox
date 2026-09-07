// 🧭 [HISTORY-SUBJECT] 한국어가 안 쓰는 주어를 영어가 지어내지 않게 한다
//
// 한국어는 이미 통하는 주어·목적어를 생략한다. 영어는 못 한다. 그래서 배울글을
// 만드는 GPT가 **매번 찍어야** 하는데, 줄마다 호출이 따로 도는 구조라
// (`_historyRepairContext`는 앞뒤 4줄 + 첫 2줄만 싣는다) 호출끼리 서로 뭘
// 골랐는지 모른다. 3번째 줄은 he, 8번째 줄은 They가 되는 이유가 그것이다.
//
// 그래서 규칙을 이렇게 세운다.
//   ① 두 사람의 통화다 — 거의 모든 줄이 나 아니면 너다
//   ② 한국어는 3자를 말할 땐 **소리 내어 말한다**("그 사람이", "선생님이")
//   ③ 3자는 성별 없는 역할 이름으로 부른다 — the teacher, my friend
//   ④ 성별은 절대 지어내지 않는다
//
// ③이 핵심이다. 역할 이름은 **줄끼리 맞출 필요가 없다** — 3번째 줄에서도
// 8번째 줄에서도 그냥 "the teacher"라, 호출이 갈라져 있어도 흔들리지 않는다.
//
// 프롬프트는 위젯 안 문자열이라 단위 테스트로 못 돌린다. 다른 프롬프트 시험과
// 같은 방식으로 **규칙이 그 자리에 있는지**를 소스에서 지킨다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _master = 'lib/custom_code/widgets/chat_history_master.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final String master = _read(_master);

  group('🧭 주어는 나와 너가 먼저다', () {
    test('두 사람의 통화라는 것을 프롬프트가 안다', () {
      expect(master, contains('This is a call between two people'));
      expect(master, contains('Reach for "I" and "you" first'));
    });

    test('통화 중인 두 사람은 절대 he·she·they가 아니다', () {
      // 실측: 두 사람뿐인 대화에서 상대가 They로 나왔다. 3자 문제가 아니라
      // 그냥 틀린 것이라, 예외 없는 줄로 못 박는다.
      expect(master,
          contains('THE TWO PEOPLE ON THIS CALL ARE NEVER "he", "she", OR "they"'));
      expect(master, contains('The one speaking is "I"'));
      expect(master, contains('The one being spoken to is "you"'));
    });

    test('빠져나갈 구멍을 남기지 않는다', () {
      expect(master,
          contains('There is no wording, no missing subject, and no awkward phrasing'));
    });

    test('3자로 밀어붙이던 옛 규칙은 사라졌다', () {
      // 이 두 줄이 주어 없는 줄을 3인칭 쪽으로 몰았고, 성별 정보가 없으니
      // 결국 They로 떨어졌다. 되살리면 같은 문제가 다시 난다.
      expect(master,
          isNot(contains('Never fall back on "I" just because the subject is missing')));
      expect(
          master,
          isNot(contains(
              'A line with no subject continues to be about that person')));
    });

    test('한국어가 3자를 소리 내어 말한다는 것이 판단 근거다', () {
      expect(master, contains('says a third person out loud whenever it means one'));
      expect(master, contains('그 사람이'));
      expect(master, contains('선생님이'));
    });

    test('앞 줄이 3자 얘기였으면 이어지는 줄도 그 사람이다', () {
      // ①만 있으면 반대 방향으로 틀린다 — "지금 취업 준비 중이야"가
      // 전부 말한 사람 얘기가 된다.
      expect(master, contains('The one exception'));
      expect(master, contains('plainly carries that same topic on'));
    });
  });

  group('🙅 성별은 지어내지 않는다', () {
    test('3자는 역할·관계 이름으로 부른다', () {
      expect(master, contains('name them by the role or relationship'));
      expect(master, contains('the teacher, the guide, my friend, your mom'));
    });

    test('역할 이름을 쓰는 이유가 적혀 있다 — 줄마다 같게 읽힌다', () {
      expect(master,
          contains('A role noun reads the same on every line'));
    });

    test('대화가 말해 주지 않은 성별은 쓰지 않는다', () {
      expect(master, contains('NEVER invent a gender'));
      expect(master,
          contains('only where the conversation states which one'));
    });

    test('they는 마지막 수단이고, 한 번 쓰면 끝까지 they다', () {
      expect(master, contains('Fall back on "they" only when the conversation gives no noun at all'));
      expect(master, contains('never switching to "he" or "she" later'));
    });
  });

  group('🔒 이 규칙은 번역에만 걸린다', () {
    test('교정된 원문(한국어)에는 손대지 않는다', () {
      expect(master,
          contains('These subject rules serve the TRANSLATION only'));
      expect(master,
          contains('Never reach back and change the corrected'));
    });

    test('사람 사이의 관계를 바꾸거나 지어내지 않는다', () {
      expect(master,
          contains("Keep each person's relationship to the speaker exactly as stated"));
      expect(master, contains('do not invent one who was never mentioned'));
    });
  });
}
