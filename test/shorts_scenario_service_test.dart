import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/shorts_scenario_service.dart';

void main() {
  test('server result becomes three fields plus expressions', () {
    final r = parseShortsScenarioResult({
      'usable': true,
      'situation': ' 옷가게에서 더 작은 사이즈를 찾는다. ',
      'aiRole': '매장 점원',
      'userRole': '손님',
      'expressions': [
        {'text': 'Do you have this in a smaller size?', 'meaning': '이거 더 작은 사이즈 있나요?'},
        {'text': '', 'meaning': '빈 문장은 버린다'},
        'not a map',
      ],
      'sourceUrl': 'https://www.youtube.com/shorts/QEw4oTtNUac',
      'cached': false,
    });
    expect(r.sourceUrl, 'https://www.youtube.com/shorts/QEw4oTtNUac');
    expect(r.situation, '옷가게에서 더 작은 사이즈를 찾는다.');
    expect(r.aiRole, '매장 점원');
    expect(r.userRole, '손님');
    expect(r.expressions, hasLength(1));
    expect(r.expressions.single.text, 'Do you have this in a smaller size?');
    expect(r.expressions.single.meaning, '이거 더 작은 사이즈 있나요?');
  });

  test('unusable or broken results throw the right code', () {
    expect(
      () => parseShortsScenarioResult({'usable': false}),
      throwsA(isA<ShortsScenarioException>().having((e) => e.code, 'code', 'unusable')),
    );
    expect(
      () => parseShortsScenarioResult({'usable': true, 'situation': 's', 'aiRole': '', 'userRole': 'u'}),
      throwsA(isA<ShortsScenarioException>().having((e) => e.code, 'code', 'unusable')),
    );
    expect(
      () => parseShortsScenarioResult('x'),
      throwsA(isA<ShortsScenarioException>().having((e) => e.code, 'code', 'failed')),
    );
  });

  test('function error codes map to screen copy codes', () {
    expect(shortsErrorCodeFor('invalid-argument'), 'notYoutube');
    expect(shortsErrorCodeFor('not-found'), 'unavailable');
    expect(shortsErrorCodeFor('resource-exhausted'), 'limit');
    expect(shortsErrorCodeFor('permission-denied'), 'noTime');
    expect(shortsErrorCodeFor('out-of-range'), 'adultOnly');
    expect(shortsErrorCodeFor('internal'), 'failed');
  });

  test('youtube link check', () {
    expect(looksLikeYoutubeLink('https://youtube.com/shorts/QEw4oTtNUac?si=x'), isTrue);
    expect(looksLikeYoutubeLink(' https://youtu.be/QEw4oTtNUac '), isTrue);
    expect(looksLikeYoutubeLink('https://www.tiktok.com/@a/video/1'), isFalse);
  });

  test('prompt block is empty without expressions, so old prompts are unchanged', () {
    expect(shortsExpressionsPromptBlock(const []), '');
    final block = shortsExpressionsPromptBlock(const [
      ShortsExpression(text: 'That fits like a glove.', meaning: '몸에 딱 맞네요.'),
      ShortsExpression(text: 'On the house.', meaning: ''),
    ]);
    expect(block, contains('- That fits like a glove. (= 몸에 딱 맞네요.)'));
    expect(block, contains('- On the house.'));
    expect(block, isNot(contains('On the house. (=')));
  });
}
