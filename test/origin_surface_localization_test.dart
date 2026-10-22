// 🌐 화면 문구는 휴대폰 언어를 따른다(2026-10-22 일본어 화면 실기기).
//   튜터링·Duo 통역 상태등이 한국어·영어로 박혀 있었다.
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_surface_localization.dart';

void main() {
  final ja = OriginSurfaceCopy.forLanguage('Japanese');

  test('튜터링·통역 문구가 일본어로 나온다', () {
    expect(ja['tutorTapToRecord'], 'タップして録音開始');
    expect(ja['tutorShadowThis'], 'シャドーイング');
    expect(ja['interpReady'], '話しかけてください');
    expect(ja['interpPreparing'], '通訳を準備しています');
  });

  test('언어 이름은 화면 언어로 적는다', () {
    expect(ja.languageName('Korean'), '韓国語');
    expect(OriginSurfaceCopy.forLanguage('Korean').languageName('Japanese'),
        '일본어');
    expect(OriginSurfaceCopy.forLanguage('English').languageName('Korean'),
        'Korean');
    expect(ja.languageName('Klingon'), 'Klingon');
  });
}
