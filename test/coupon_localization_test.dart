// 🎟️ 쿠폰 입력 문구(2026-10-26). 서버 redeemCoupon의 거절 사유가 12개 언어
//   모두에 있어야 한다 — 빠지면 영어로 떨어진다.
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/coupon_localization.dart';

void main() {
  const serverReasons = [
    'needs_account', 'not_found', 'inactive', 'expired', 'full',
    'already_used', 'device_used', 'too_many', 'blocked',
  ];

  test('12개 언어가 영어와 같은 키를 다 갖는다', () {
    final table = CouponCopy.table;
    expect(table.length, 12);
    final englishKeys = table['English']!.keys.toSet();
    expect(englishKeys, containsAll(serverReasons));
    for (final entry in table.entries) {
      expect(entry.value.keys.toSet(), englishKeys, reason: entry.key);
      for (final value in entry.value.values) {
        expect(value.trim(), isNotEmpty, reason: entry.key);
      }
    }
  });

  test('모르는 사유와 모르는 언어는 영어 실패 문구로 떨어진다', () {
    final ko = CouponCopy.forLanguage('Korean');
    expect(ko['full'], '선착순 인원이 마감된 코드입니다.');
    expect(ko['no_user'], 'Could not apply the code. Please try again.');
    expect(CouponCopy.forLanguage('Klingon')['link'], 'Have a coupon code?');
  });

  test('지급 시간은 짧게 적는다', () {
    final ko = CouponCopy.forLanguage('Korean');
    expect(ko.duration(7200), '2시간');
    expect(ko.duration(5400), '1.5시간');
    expect(ko.duration(1800), '30분');
    expect(ko['added'].replaceAll('{time}', ko.duration(7200)), '2시간 추가되었습니다');
  });
}
