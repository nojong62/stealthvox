// 🌐 [ALT-STYLE] 다른 표현의 스타일 지시문은 타겟 언어를 따른다(2026-10-22).
//   일본어→한국어 방에서 Native가 영어로 나왔다 — 영어 전용 지시문 탓이었다.
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/ai_style.dart';
import 'package:stealth_vox/custom_code/services/alt_style.dart';

void main() {
  test('영어 타겟은 기존 지시문 그대로', () {
    for (final style in ['Standard', 'American', 'British', 'Native']) {
      expect(altStyleInstruction(style, 'English'), aiStyleInstruction(style));
    }
  });

  test('한국어 타겟의 Native는 한국어 원어민 기준이고 영어를 말하지 않는다', () {
    final native = altStyleInstruction('Native', 'Korean');
    expect(native, contains('native Korean speaker'));
    expect(native, contains('Write it in Korean'));
    expect(native, isNot(contains('US native')));
    expect(native, isNot(contains('English')));
  });

  test('한국어 타겟의 Standard도 한국어다', () {
    final standard = altStyleInstruction('Standard', 'Korean');
    expect(standard, contains('standard Korean'));
    expect(standard, isNot(contains('English')));
  });
}
