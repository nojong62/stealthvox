// 💾 [ALT-CACHE] 다른 표현은 줄 문서에 남겨 다시 부르지 않는다(2026-10-16).
//   배울글이 바뀐 줄에는 옛 문장을 쓰지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/alt_style.dart';

void main() {
  test('같은 배울글이면 저장된 문장을 쓴다', () {
    final data = <String, dynamic>{
      kAltStylesBaseField: 'I am fine.',
      kAltStylesField: <String, dynamic>{'Native': "I'm good.", 'Standard': ''},
    };
    expect(cachedAltStyles(data, ' I am fine. '), {'Native': "I'm good."});
  });

  test('배울글이 바뀌었으면 버린다', () {
    final data = <String, dynamic>{
      kAltStylesBaseField: 'I am fine.',
      kAltStylesField: <String, dynamic>{'Native': "I'm good."},
    };
    expect(cachedAltStyles(data, 'I am tired.'), isEmpty);
    expect(cachedAltStyles(null, 'x'), isEmpty);
  });

  test('비영어 타겟은 두 스타일뿐이다', () {
    expect(allAltStyles('Korean'), ['Standard', 'Native']);
  });
}
