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

StealthVox Store 사용 내역 구조 정리 지시문

목표:

정식 앱 기준으로 스토어 화면을 사용자용 Usage 중심으로 정리한다.
기존 Time Log 상세 과금 검증 기능은 삭제하지 말고, 실장/관리자만 확인할 수 있는 숨김 기능으로 전환한다.

수정 대상:

lib/custom_code/widgets/store_master.dart

필요 시 참고:

lib/custom_code/actions/billing_ticker.dart

중요:

APK/AAB 빌드 명령은 실행하지 말 것.
기존 usage_logs 저장 로직은 건드리지 말 것.
Firestore 구조 users/{uid}/usage_logs는 유지할 것.
기존 Receipt / 구매 내역 기능은 유지할 것.
사용자에게 개발자용 디버그 느낌이 보이면 안 됨.
1. 버튼 구조 변경

현재 Store 상단 우측 구조:

[로그복사] [Time Log] [Receipt]

이를 정식 앱 기준으로 다음처럼 변경한다.

[Usage] [Receipt]

또는 한국어 UI면:

[사용 내역] [구매 내역]

권장:

Usage
Receipt

Usage는 사용자용 사용 내역 화면이다.
Time Log라는 문구는 일반 사용자 화면에서 제거한다.

2. 사용자용 Usage 화면

새 사용자용 함수명을 명확히 한다.

_openUsageSheet()

또는 기존 _openUsageHistorySheet()를 사용자용으로 정리해도 된다.

사용자에게 보여줄 정보:

사용 모드 이름
사용 날짜/시간
실제 사용 시간
차감된 시간

예시 표시:

Duo 대화
2026.05.26 18:30
3분 20초 사용

AI 연습처럼 할인 차감이 있는 경우:

AI Practice
2026.05.26 19:10
실제 10분 사용 · 5분 차감

사용자에게 숨길 정보:

rate: 0.5
before_seconds
after_seconds
room_id
Firestore 경로
mode 원문
debug log
productId
entitlementId
RevenueCat 원문 로그

단, 내부 데이터로는 사용해도 되지만 화면에 직접 노출하지 않는다.

3. 관리자용 Time Log는 숨김 기능으로 유지

기존 상세 Time Log 기능은 삭제하지 말고 별도 함수로 분리한다.

함수명 예시:

_openAdminTimeLogSheet()

관리자용 Time Log에는 기존처럼 상세 정보를 표시해도 된다.

표시 가능 정보:

mode 원문
rate
actual_seconds
seconds_used
before_seconds → after_seconds
room_id
created_at

단, 이 버튼은 일반 사용자에게 보이면 안 된다.

4. 관리자 접근 방식

가장 간단한 방식으로 숨김 진입을 만든다.

권장 방식 A:

스토어의 STORE 제목을 길게 누르면 관리자 Time Log가 열린다.

GestureDetector(
  onLongPress: _openAdminTimeLogSheet,
  child: Text('STORE')
)

또는 남은 시간 카드 길게 누르기:

REMAINING TIME 카드 long press
→ Admin Time Log 열기

이미 Billing Debug Log가 남은 시간 카드 길게 누르기로 연결되어 있다면, 그 구조와 충돌하지 않게 한다.

추천 우선순위:

STORE 제목 long press → Admin Time Log
REMAINING TIME long press → Billing Debug Log
5. 관리자 조건 추가 권장

가능하면 관리자 이메일 조건을 추가한다.

예시 개념:

currentUserEmail == '실장님 관리자 이메일'

또는 FFAppState에 관리자 플래그가 있다면:

FFAppState().isAdmin == true

조건:

if (!isAdmin) return;

관리자가 아니면 아무 반응 없게 하거나, SnackBar 없이 조용히 무시한다.

관리자 이메일이 아직 확정되지 않았다면 TODO로 남긴다.

// TODO: 관리자 이메일 또는 isAdmin 플래그 확정 후 Admin Time Log 접근 제한 적용
6. 화면 이름 정리

정식 사용자 화면 문구:

Usage
Purchase History

또는 한국어:

사용 내역
구매 내역

관리자용 문구:

Admin Time Log
Billing Debug Log

사용자 화면에 Time Log, Debug, rate, Firestore, BillingTicker 같은 단어가 나오지 않게 한다.

7. 빈 상태 문구 변경

사용자용 Usage 빈 상태:

아직 사용 내역이 없습니다.
대화를 시작하면 사용 시간이 이곳에 표시됩니다.

영어 UI:

No usage history yet.
Your usage will appear here after a session.

관리자용 Time Log 빈 상태:

사용시간 로그가 없습니다.
8. 완료 기준
Store 일반 화면에는 Usage와 Receipt만 보인다.
Time Log라는 버튼명은 일반 사용자에게 보이지 않는다.
Usage 클릭 시 사용자 친화적인 사용 내역이 표시된다.
사용자용 Usage에는 rate, before_seconds, after_seconds, room_id 같은 개발자 정보가 직접 노출되지 않는다.
관리자용 Time Log는 숨김 동작으로 접근 가능하다.
관리자용 Time Log에서는 상세 과금 검증 정보를 확인할 수 있다.
users/{uid}/usage_logs 저장 구조는 그대로 유지된다.
BillingTicker 저장 로직은 건드리지 않는다.
기존 Receipt 기능은 그대로 작동한다.
flutter analyze에서 신규 오류가 없어야 한다.
APK/AAB 빌드는 하지 않는다.
추천 최종 구조
Store 화면
 ├─ Remaining Time
 ├─ Usage          ← 사용자용 사용 내역
 ├─ Receipt        ← 사용자용 구매 내역
 └─ 숨김 진입
     ├─ Admin Time Log
     └─ Billing Debug Log

이렇게 하면 정식 앱에서는 깔끔하고, 실장님은 나중에 문제가 생겼을 때 상세 과금 로그를 따로 확인할 수 있습니다.

생활영어로는 사용자용 버튼은 Usage가 가장 무난하고, 관리자용은 Admin Time Log가 명확합니다.
“사용자는 Usage, 나는 Time Log” 이 구분으로 기억하면 됩니다.