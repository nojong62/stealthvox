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

Firestore 인덱스 오류 해결 + 결제 동기화 검증 지시문

현재 로그 분석 결과:

RevenueCat 결제 자체는 정상 성공 상태.

로그:
- PURCHASE success
- PURCHASE activeEntitlements=time_charge

까지 정상 확인됨.

문제는 이후 Firestore purchases 조회 단계에서 아래 오류가 발생:

[cloud_firestore/failed-precondition] The query requires an index

원인:
purchases 컬렉션에서
product_id + purchased_at 조합 쿼리를 사용 중인데,
Firestore 복합 인덱스가 없어 결제 후 동기화(SYNC)가 실패 중.

==================================================
1. Firebase Console에서 Firestore 복합 인덱스 생성
==================================================

Firebase Console → Firestore Database → Indexes → Composite Indexes

Collection ID:
purchases

Fields:
- product_id → Ascending
- purchased_at → Ascending
- __name__ → Ascending

생성 후 ENABLED 상태까지 기다릴 것.
(보통 수 분 소요)

==================================================
2. 테스트 전 사전 확인
==================================================

Firestore:

users/rJChsLrIqAhXhLZotYeeLZo6KK42

문서 열어서 현재:

remaining_seconds

값 미리 메모해둘 것.

==================================================
3. 인덱스 생성 완료 후 테스트
==================================================

앱 재실행 후:

10분권(stealthvox_10m) 1회만 테스트 구매.

==================================================
4. 테스트 후 로그 확인 항목
==================================================

아래 흐름이 순서대로 떠야 정상:

PURCHASE success
SYNC start
Firestore update success
remaining_seconds increased

특히:
- Firestore update success
- remaining_seconds increased

반드시 확인.

==================================================
5. remaining_seconds 검증
==================================================

테스트 전 메모해둔 값보다:

+600초

증가했는지 확인.

==================================================
6. 중요 추가 주의사항
==================================================

이전 테스트들:

600 + 3600 + 600 + 600 + 600

총 약 6000초 분량 결제가 이미 성공했지만,
Firestore 인덱스 오류 때문에 동기화 실패 상태로 남아 있을 가능성이 있음.

따라서 인덱스 생성 후 앱 재실행 시:

pending transaction 재처리
또는 밀린 동기화 처리

가 발생할 수 있음.

그 결과:
remaining_seconds가 한 번에 크게 증가해도 이상하지 않을 수 있음.

==================================================
7. 코드 수정 관련
==================================================

지금 단계에서는 코드 수정하지 말 것.

먼저:
- Firestore 인덱스 생성
- 동기화 정상 여부 확인

만 진행.

APK/AAB 빌드 금지.
flutter analyze 수준까지만.