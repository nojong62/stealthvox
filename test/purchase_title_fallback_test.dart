import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/store_master.dart';

/// 구매이력 제목 복원.
///
/// 2026-06-13부터 RevenueCat 웹훅이 구매 문서를 쓰는데 `product_title`을
/// 넣지 않아 화면이 `Unknown Item`을 띄웠다. 옛 클라이언트 기록에는 제목이
/// 있으므로 **두 형식이 한 목록에 섞여 있어도** 둘 다 제대로 보여야 한다.
void main() {
  group('resolvePurchaseTitle', () {
    test('저장된 제목이 있으면 그대로 쓴다 (옛 클라이언트 기록)', () {
      final title = resolvePurchaseTitle({
        'product_id': 'stealthvox_10m',
        'product_title': '10 Minutes',
        'seconds_added': 600,
      }, kStorePlans);
      expect(title, '10 Minutes');
    });

    test('제목이 없으면 product_id로 되살린다 (웹훅 기록)', () {
      final title = resolvePurchaseTitle({
        'product_id': 'stealthvox_10m',
        'seconds_added': 600,
      }, kStorePlans);
      expect(title, '10 Minutes');
    });

    test('제목이 빈 문자열이어도 product_id로 되살린다', () {
      final title = resolvePurchaseTitle({
        'product_id': 'stealthvox_1h',
        'product_title': '   ',
        'seconds_added': 3600,
      }, kStorePlans);
      expect(title, '1 Hour');
    });

    test('저장된 제목은 상품 정의보다 우선한다 — 옛 기록을 덮어쓰지 않는다', () {
      final title = resolvePurchaseTitle({
        'product_id': 'stealthvox_10m',
        'product_title': '10분 체험권',
      }, kStorePlans);
      expect(title, '10분 체험권');
    });

    test('모르는 product_id는 Unknown Item으로 남는다', () {
      final title = resolvePurchaseTitle({
        'product_id': 'stealthvox_bogus',
        'seconds_added': 600,
      }, kStorePlans);
      expect(title, 'Unknown Item');
    });

    test('product_id도 제목도 없으면 Unknown Item', () {
      expect(resolvePurchaseTitle({'seconds_added': 600}, kStorePlans),
          'Unknown Item');
      expect(resolvePurchaseTitle({}, kStorePlans), 'Unknown Item');
    });

    test('네 상품 모두 ID로 제목이 나온다', () {
      const expected = <String, String>{
        'stealthvox_10m': '10 Minutes',
        'stealthvox_1h': '1 Hour',
        'stealthvox_5h': '5 Hours',
        'stealthvox_10h': '10 Hours',
      };
      for (final entry in expected.entries) {
        expect(
          resolvePurchaseTitle({'product_id': entry.key}, kStorePlans),
          entry.value,
          reason: entry.key,
        );
      }
    });
  });

  group('kStorePlans', () {
    /// 웹훅(`firebase/functions/index.js`의 `PRODUCTS`)과 같은 키·초·제목을
    /// 써야 구매이력 제목이 양쪽에서 같게 나온다. 여기가 어긋나면 배포된
    /// 함수와 앱이 다른 이름을 말하게 된다.
    test('웹훅 PRODUCTS와 id·seconds·title이 같다', () {
      const webhook = <String, List<Object>>{
        'stealthvox_10m': [600, '10 Minutes'],
        'stealthvox_1h': [3600, '1 Hour'],
        'stealthvox_5h': [18000, '5 Hours'],
        'stealthvox_10h': [36000, '10 Hours'],
      };
      expect(kStorePlans.length, webhook.length);
      for (final plan in kStorePlans) {
        final id = plan['id'] as String;
        expect(webhook.containsKey(id), isTrue, reason: 'unknown id $id');
        expect(plan['seconds'], webhook[id]![0], reason: id);
        expect(plan['title'], webhook[id]![1], reason: id);
      }
    });

    test('seconds_added 표시(분 환산)는 그대로다', () {
      for (final plan in kStorePlans) {
        final seconds = plan['seconds'] as int;
        expect(seconds % 60, 0, reason: plan['id'] as String);
      }
      expect(600 ~/ 60, 10);
      expect(36000 ~/ 60, 600);
    });
  });
}
