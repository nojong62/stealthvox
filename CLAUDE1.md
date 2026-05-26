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

StealthVox Idle Timeout / 무반응 과금 정지 및 자동 이동 적용 지시문

목표:

StealthVox의 대화/학습 화면에서 사용자가 일정 시간 아무 동작을 하지 않으면 과금을 먼저 일시정지하고, 모드에 따라 일정 시간 후 대화 모드 선택 페이지로 자동 이동하도록 한다.

단, History 계열 화면은 사용자가 자막을 읽거나 복습 중일 수 있으므로 자동 이동하지 않고 과금 정지만 적용한다.

수정 대상 후보 파일

우선 아래 파일들을 확인한다.

lib/custom_code/actions/billing_ticker.dart
lib/custom_code/widgets/stealth_room_master.dart
lib/custom_code/widgets/routine_mode_duo.dart
lib/custom_code/widgets/routine_mode_roleplay.dart
lib/custom_code/widgets/routine_mode_clone.dart
lib/custom_code/widgets/routine_mode_step_expand.dart
lib/custom_code/widgets/chat_history_master.dart
lib/custom_code/widgets/chat_history_list_master.dart

실제 파일명이 다르면, 각 모드 진입/종료와 BillingTicker 호출이 있는 파일을 기준으로 작업한다.

중요:

APK/AAB 빌드 명령은 실행하지 말 것.
기존 결제, RevenueCat, Usage, Admin Time Log, Receipt 기능은 건드리지 말 것.
usage_logs 저장 로직은 유지할 것.
BillingTicker.pause()가 호출되면 기존 사용시간 로그 저장 흐름이 깨지지 않아야 한다.
녹음 중, TTS 재생 중, AI 응답 대기 중에는 무조건 “무반응”으로 판단하지 말고 실제 대기 상태를 고려한다.
코드 수정 후 flutter analyze 또는 정적 체크 수준까지만 확인한다.
1. 적용 정책
A. Duo / Stealth Room

정책:

30초 무반응
→ 과금 일시정지
→ 화면에 경고 또는 일시정지 안내 표시

60초 무반응
→ 대화 모드 선택 페이지로 자동 이동

적용 대상:

duo
stealth_room

30초 안내 문구 예시:

잠시 멈춤 상태입니다.
말하기 버튼을 누르면 다시 시작됩니다.

60초 이동 전 처리:

녹음 중이면 중지
TTS 재생 중이면 정리
BillingTicker.pause()
사용시간 로그 저장 흐름 유지
대화 모드 선택 페이지로 이동
B. Roleplay / Clone / Step Expand

정책:

30초 무반응
→ 과금 일시정지
→ 화면에 경고 또는 일시정지 안내 표시

90초 무반응
→ 대화 모드 선택 페이지로 자동 이동

적용 대상:

roleplay
clone
step_expand
study_room

30초 안내 문구 예시:

연습이 잠시 멈췄습니다.
계속하려면 말하기 또는 다음 진행 버튼을 눌러주세요.

90초 이동 전 처리:

녹음 중이면 중지
AI 응답 대기 중이면 안전하게 종료 또는 무시 처리
TTS 재생 중이면 정리
BillingTicker.pause()
사용시간 로그 저장 흐름 유지
대화 모드 선택 페이지로 이동
C. History / History List

정책:

30초 무반응
→ 과금 일시정지
→ 자동 이동 없음

적용 대상:

history
history_list
chat_history

주의:

History 계열은 사용자가 자막을 읽거나 복습 중일 수 있으므로 자동 이동하지 않는다.

안내 문구 예시:

복습이 잠시 멈췄습니다.
재생하거나 연습을 시작하면 다시 진행됩니다.
2. “무반응” 판단 기준

다음 사용자 동작이 발생하면 idle timer를 리셋한다.

PTT 버튼 누름
PTT 버튼 뗌
녹음 시작
녹음 종료
AI 응답 시작
AI 응답 완료
TTS 재생 시작
TTS 재생 완료
다음 대사 진행
역할 선택
회차 이동
화면 터치
스크롤
주요 버튼 클릭

단, 단순한 내부 타이머 tick은 사용자 반응으로 보지 않는다.

3. 과금 일시정지 처리

30초 무반응 시 반드시 다음을 실행한다.

BillingTicker.instance.pause()

단, 이미 pause 상태라면 중복 호출로 문제가 생기지 않게 한다.

필요하면 상태값을 둔다.

_isIdlePaused = true

사용자가 다시 조작하면:

_isIdlePaused = false
BillingTicker.instance.resume 또는 기존 시작 로직 재개
idle timer reset

만약 현재 BillingTicker에 resume()이 없다면, 기존 프로젝트에서 사용하는 재시작 방식, 예를 들어 setRate() 후 logMode() 호출 방식과 충돌하지 않게 기존 패턴을 따른다.

4. 자동 이동 대상 페이지

자동 이동 목적지는 “대화 모드 선택 페이지”다.

현재 프로젝트 구조상 다음 중 실제 사용 중인 목적지를 확인해서 적용한다.

stealth_room_master.dart의 모드 선택 화면
또는 Lobby에서 대화 모드 선택 영역
또는 _currentMode = 0 같은 모드 선택 상태

중요:

새로운 라우트를 임의로 만들지 말고, 기존 앱에서 사용자가 대화 모드를 선택하는 화면으로 돌아가게 한다.

예상 구조:

StealthRoomMaster 내부라면:
_currentMode = 0

별도 페이지라면:
context.goNamed(...)

정확한 방식은 기존 네비게이션 구조를 확인해서 최소 수정으로 적용한다.

5. 안내 UI

30초 무반응 이후에는 사용자가 “왜 시간이 멈췄는지” 알 수 있도록 작은 안내를 표시한다.

권장 방식:

상단 또는 하단에 작은 배너
SnackBar
또는 카드 내부의 작은 상태 문구

문구는 사용자 친화적으로 한다.

Duo / Stealth Room:

잠시 멈춤 상태입니다. 말하기 버튼을 누르면 다시 시작됩니다.

Roleplay / Clone / Step Expand:

연습이 잠시 멈췄습니다. 계속하려면 다시 진행해 주세요.

History / History List:

복습이 잠시 멈췄습니다. 재생하거나 연습을 시작하면 다시 진행됩니다.

사용자에게 다음 단어는 보이지 않게 한다.

BillingTicker
rate
idle timeout
debug
usage_logs
6. 중복 이동 방지

자동 이동은 한 번만 실행되어야 한다.

필요 상태값:

_hasAutoReturnedToModeSelect

자동 이동 직전:

이미 이동했으면 return
이동 직전에 true 처리

다음 상황에서 중복 이동이 생기지 않도록 한다.

dispose()
pause()
background 전환
timer callback 중복 실행
화면 전환 중 setState 호출
7. 타이머 정리

각 화면의 dispose()에서 idle timer를 반드시 정리한다.

정리 대상:

30초 pause timer
60초 auto-return timer
90초 auto-return timer
idle 상태 배너 timer

화면이 dispose된 뒤에는 setState가 호출되지 않게 mounted 체크를 넣는다.

8. 모드별 최종 정책표
Duo
- 30초 무반응: 과금 정지 + 안내
- 60초 무반응: 모드 선택 페이지 이동

Stealth Room
- 30초 무반응: 과금 정지 + 안내
- 60초 무반응: 모드 선택 페이지 이동

Roleplay
- 30초 무반응: 과금 정지 + 안내
- 90초 무반응: 모드 선택 페이지 이동

Clone
- 30초 무반응: 과금 정지 + 안내
- 90초 무반응: 모드 선택 페이지 이동

Step Expand / Study Room
- 30초 무반응: 과금 정지 + 안내
- 90초 무반응: 모드 선택 페이지 이동

History
- 30초 무반응: 과금 정지 + 안내
- 자동 이동 없음

History List
- 30초 무반응: 과금 정지 + 안내
- 자동 이동 없음
9. 완료 기준
Duo에서 30초 무반응 시 과금이 정지된다.
Duo에서 60초 무반응 시 대화 모드 선택 페이지로 이동한다.
Stealth Room에서도 Duo와 동일하게 작동한다.
Roleplay에서 30초 무반응 시 과금이 정지된다.
Roleplay에서 90초 무반응 시 대화 모드 선택 페이지로 이동한다.
Clone에서도 Roleplay와 동일하게 작동한다.
Step Expand / Study Room에서도 Roleplay와 동일하게 작동한다.
History / History List에서는 30초 무반응 시 과금만 정지되고 자동 이동하지 않는다.
사용자가 다시 버튼을 누르거나 조작하면 idle 상태가 해제된다.
자동 이동은 중복 실행되지 않는다.
화면 dispose 후 timer로 인한 setState 오류가 없어야 한다.
BillingTicker usage log 저장 흐름이 깨지지 않아야 한다.
Usage / Admin Time Log / Receipt 기능은 그대로 유지된다.
신규 flutter analyze 오류가 없어야 한다.
APK/AAB 빌드는 하지 않는다.
추가 권장

내부 함수명은 다음처럼 잡으면 의미가 명확합니다.

_resetIdleTimer()
_handleIdlePause()
_handleIdleAutoReturn()
_clearIdleTimers()

사용자용 기능명은 Auto Pause가 좋습니다.
개발자용 명칭은 Idle Timeout이 자연스럽습니다.