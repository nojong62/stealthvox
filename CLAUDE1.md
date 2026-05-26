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

StealthVox 사용시간 이력 저장 로직 연결 지시문

목표:

스토어의 Time Log 버튼에서 실제 사용시간 이력이 보이도록, 시간이 차감되는 로직에 Firestore 저장 기능을 연결한다.

수정 대상 후보 파일:

lib/custom_code/actions/billing_ticker.dart

또는 실제로 잔여 시간이 차감되는 파일.

중요:

store_master.dart는 이미 수정되었으므로 건드리지 말 것.
APK/AAB 빌드 명령은 실행하지 말 것.
코드 수정 후 flutter analyze 또는 정적 체크 수준까지만 확인할 것.
매초 Firestore에 저장하지 말 것.
사용시간 기록은 세션 종료 시 1회 저장 또는 의미 있는 차감 단위마다 1회 저장 방식으로 처리할 것.
저장 경로
users/{uid}/usage_logs/{autoId}

저장 필드:

created_at: FieldValue.serverTimestamp()
mode: 'duo' | 'roleplay' | 'ai_practice' | 'stealth_room'
seconds_used: int
actual_seconds: int
rate: 1.0 | 0.5 | 0.25
before_seconds: int
after_seconds: int
room_id: optional String
reason: optional String
핵심 로직

사용 시작 시점에 다음 값을 보관한다.

sessionStartTime
beforeSeconds
mode
rate
roomId

사용 종료 시점에 다음을 계산한다.

actual_seconds = 실제 이용 시간
seconds_used = 실제 차감된 시간
after_seconds = 현재 남은 시간

그 후 Firestore에 1회 저장한다.

예시:

duo 모드 3분 사용
rate = 1.0
actual_seconds = 180
seconds_used = 180
before_seconds = 3600
after_seconds = 3420

AI 연습 모드 예시:

ai_practice 10분 사용
rate = 0.5
actual_seconds = 600
seconds_used = 300
before_seconds = 3600
after_seconds = 3300

quarter 요금 예시:

rate = 0.25
actual_seconds = 600
seconds_used = 150
중복 저장 방지

반드시 중복 저장을 막는다.

필요 상태값 예시:

bool _usageLogSaved = false;

세션 종료 처리에서:

if (_usageLogSaved) return;
_usageLogSaved = true;

다음 상황에서도 중복 저장되지 않아야 한다.

나가기 버튼 클릭
dispose()
앱 백그라운드 전환
방 종료 콜백
게스트 퇴장
저장 조건

다음 조건에서는 저장하지 않는다.

seconds_used <= 0
currentUserReference == null
before_seconds <= after_seconds

단, 디버그 확인을 위해 저장 실패 시 로그는 남긴다.

모드명 표준화

mode 값은 아래 중 하나로 통일한다.

duo
roleplay
ai_practice
stealth_room

스토어 화면에서 사람이 보기 좋은 이름으로 바꾸는 것은 store_master.dart의 표시 로직에서 처리한다.

완료 기준
Duo 또는 Stealth Room에서 실제 시간이 차감된 뒤 스토어로 이동한다.
Time Log 버튼을 누르면 사용시간 이력이 표시된다.
최신 기록이 맨 위에 나온다.
before_seconds → after_seconds가 정확히 표시된다.
AI 연습 모드는 실제 사용시간보다 적게 차감된 값이 기록된다.
같은 세션이 2번 이상 중복 저장되지 않는다.
Firestore 쓰기는 매초 발생하지 않는다.
기존 결제, 구매 복원, Receipt 기능은 깨지지 않는다.
APK/AAB 빌드는 하지 않는다.

핵심은 Time Log 화면은 이미 준비됐고, 이제 BillingTicker가 영수증처럼 사용 기록을 한 장씩 찍어주게 만드는 단계입니다.
영어 표현으로는 이 기능을 사용자에게 “Time Log” 또는 **“Usage History”**라고 부르면 자연스럽고, 앱 버튼에는 짧은 Time Log가 더 좋습니다.