StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

 ⚙️ AI 작업 규칙
1. 복사붙여넣기: FlutterFlow 웹 에디터에 바로 적용할 수 있게 `import`와 클래스 구조 전체를 제공한다.
2. 디자인: `lib/flutter_flow/flutter_flow_theme.dart`의 테마 변수를 최우선으로 사용한다.
3. 작업 시작 전에 반드시 다음 순서로 진행해 주세요.
0. 네가 이해한 지시문 내용을 요약해서 맞는지 동의를 받는다.
1. git status 확인
2. 현재 브랜치 확인
3. 새 작업 브랜치 생성
4. 현재 상태를 백업 커밋
5. 관련 파일 전체 분석
6. 수정 대상 파일과 수정 계획 먼저 요약
7. 코드 수정
8. flutter pub get 실행
9. flutter analyze 실행
10. 오류 발생 시 원인 분석 후 수정 반복
11. 최종적으로 git diff 확인
12. 수정된 파일 목록, 핵심 변경사항, 남은 이슈 보고
13. main 브랜치에 머지해 줘.
14. 원격 저장소에 push 해줘

주의사항:
- 기존 정상 작동 기능을 깨지 말 것
- FlutterFlow generated code 구조를 함부로 대규모 변경하지 말 것
- 앱 실행/빌드 가능성을 최우선으로 할 것
- 불확실한 부분은 임의 삭제하지 말고 보고할 것

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문

[StealthVox StoreMaster RevenueCat 진단 로그 복사 기능 추가]

대상 파일:
- lib/custom_code/widgets/store_master.dart

참고 파일:
- lib/custom_code/widgets/routine_mode_roleplay.dart

목표:
routine_mode_roleplay.dart에 있는 화면 로그 구조처럼,
store_master.dart에도 RevenueCat 결제 진단 로그를 쌓고 사용자가 복사할 수 있는 기능을 추가한다.

필수 구현:
1. store_master.dart에 Clipboard import 추가
   import 'package:flutter/services.dart';

2. State 클래스 안에 진단 로그 리스트와 로그 함수 추가

예시:
final List<String> _debugLogs = [];

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  final line = '[$ts] $tag $msg';
  print(line);
  _debugLogs.add(line);
  if (_debugLogs.length > 500) {
    _debugLogs.removeRange(0, 50);
  }
}

3. 화면 상단 또는 Receipt 버튼 근처에 “로그 복사” 버튼 추가

버튼 동작:
- _debugLogs.join('\n') 전체를 Clipboard에 복사
- 복사 성공 시 SnackBar 표시
  “✅ 스토어 로그가 복사되었습니다”

버튼 예시:
ElevatedButton.icon(
  icon: const Icon(Icons.copy, size: 16),
  label: const Text('로그 복사'),
  onPressed: () async {
    final text = _debugLogs.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 스토어 로그가 복사되었습니다'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  },
)

4. RevenueCat 관련 주요 지점에 _log() 삽입

반드시 로그 찍을 위치:

A. initState
_log('STORE', 'StoreMaster initState');

B. _initRevenueCatUser 시작/성공/실패
- currentUserUid
- Purchases.isAnonymous 결과
- logIn 실행 여부

예:
_log('RC_INIT', 'uid=$uid');
_log('RC_INIT', 'isAnonymous=$isAnon');
_log('RC_INIT', 'Purchases.logIn completed');

C. 구매 버튼 클릭 시
- plan id
- plan title
- currentUserUid
- currentUserReference 존재 여부

예:
_log('PURCHASE', 'tap productId=${plan['id']} title=${plan['title']} uid=$currentUserUid');

D. Purchases.getOfferings() 호출 직후
- offerings.current 존재 여부
- current offering identifier
- availablePackages 개수
- 각 package.identifier
- 각 package.storeProduct.identifier
- 각 package.storeProduct.priceString 가능하면 출력

예:
final offerings = await Purchases.getOfferings();
final offering = offerings.current ?? offerings.getOffering('default');

_log('OFFERINGS', 'current=${offerings.current?.identifier}');
_log('OFFERINGS', 'default=${offerings.getOffering('default')?.identifier}');
_log('OFFERINGS', 'selected=${offering?.identifier}');
_log('OFFERINGS', 'packageCount=${offering?.availablePackages.length ?? 0}');

for (final p in offering?.availablePackages ?? []) {
  _log(
    'OFFERINGS',
    'package=${p.identifier}, product=${p.storeProduct.identifier}, price=${p.storeProduct.priceString}',
  );
}

E. Package 매칭 결과
- 요청 productId
- 매칭 성공/실패

예:
_log('MATCH', 'request productId=$productId');
_log('MATCH', 'matched package=${matchedPackage?.identifier}, product=${matchedPackage?.storeProduct.identifier}');

F. 구매 실행 직전
_log('PURCHASE', 'purchasePackage start productId=$productId');

G. 구매 성공 직후
- customerInfo originalAppUserId
- active entitlements keys
- all purchased product ids 가능하면 출력

예:
_log('PURCHASE', 'success appUserId=${customerInfo.originalAppUserId}');
_log('PURCHASE', 'activeEntitlements=${customerInfo.entitlements.active.keys.join(',')}');

H. _syncPurchaseData 시작/성공/실패
- productId
- earnedSeconds
- clientTxId
- current remainingTime
- Firestore increment 성공 여부

I. PlatformException catch
- errorCode
- e.message
- e.details

예:
_log('ERROR', 'platform code=$errorCode message=${e.message} details=${e.details}');

J. 일반 catch
- error 내용
- stackTrace 일부

5. 기존 구매 로직 변경 금지
이번 작업의 목적은 로그 확인이다.
purchaseProduct → purchasePackage 변경은 아직 하지 말고,
먼저 현재 로직에서 getOfferings 결과가 실제로 들어오는지 확인할 수 있게 로그만 추가한다.

단, 현재 코드에 이미 getOfferings 진단용 코드가 들어가 있다면 그 결과도 _log에 기록해라.

6. UI 깨지지 않게 로그 복사 버튼은 작게 추가
- 가능하면 상단 Receipt 오른쪽 근처
- 또는 스토어 상단 카드 아래
- 기존 구매 카드 레이아웃을 크게 변경하지 말 것

7. 중요:
- RevenueCat 초기화 로직 변경 금지
- AppsFlyer 로직 변경 금지
- billingTicker 로직 변경 금지
- 상품 ID/가격 변경 금지
- remaining_seconds 증가 로직 변경 금지
- APK/AAB 빌드 명령 실행 금지
- 수정 후 flutter analyze 또는 FlutterFlow Custom Code Check 수준까지만 확인

완료 후 보고:
- 수정한 위치
- 추가된 로그 태그 목록
- 로그 복사 버튼 위치
- 컴파일/분석 결과