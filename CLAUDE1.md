StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

 ⚙️ AI 작업 규칙

- 새 기능 추가 시 반드시 주제별 주석 블록으로 구분할 것.
- 기존 블록 내부에 의미 없이 이어붙이지 말 것.
- 기능이 커지면 private helper method로 분리할 것.
- build() 내부 코드를 계속 비대하게 만들지 말 것.
- 상태 변수도 기능별 블록으로 정리할 것.
- dispose(), timer, stream 정리 코드는 lifecycle 블록으로 모을 것.

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




StealthVox Idle UI 수정 지시문

목표:

기존에 만든 큰 무반응 안내 배너 문구를 제거하고, 작은 노란색 pause 아이콘 + 1초짜리 “pause” 팝업 방식으로 변경한다.

수정 대상:

routine_mode_duo.dart
routine_mode_roleplay.dart
routine_mode_clone.dart
routine_mode_step_expand.dart
chat_history_master.dart
chat_history_list_master.dart


---

1. 기존 큰 안내 배너 제거

각 파일에서 기존 idle 안내 배너를 제거하거나 비활성화한다.

제거 대상 예시:

_buildIdleBanner()
복습이 잠시 멈췄습니다...
연습이 잠시 멈췄습니다...
잠시 멈춤 상태입니다...
재생하거나 연습을 시작하면...

중요:

30초 pause 로직 자체는 유지한다.

60초/90초 자동 이동 로직은 기존 정책대로 유지한다.

History / History List는 자동 이동 없음 정책 유지.

BillingTicker.pause(), resume(), logMode() 흐름은 건드리지 않는다.

UI 표시 방식만 변경한다.



---

2. 30초 무반응 시 새 UI

30초 무반응으로 _handleIdlePause()가 실행되면:

BillingTicker.pause()
작은 노란색 pause 아이콘 표시
pause 팝업 1초 표시 후 자동 사라짐

아이콘은 화면을 가리지 않게 작게 표시한다.

권장 아이콘:

Icons.pause_circle_filled_rounded

색상:

Color(0xFFFFD54F)

또는 기존 amber 계열:

Colors.amberAccent

크기:

18~22


---

3. pause 팝업

30초 무반응이 감지되는 순간, 화면 중앙 또는 상단 중앙에 작게:

pause

만 표시한다.

조건:

글자는 영어 소문자 pause

표시 시간은 약 1초

1초 후 자동 사라짐

긴 안내문 금지

SnackBar처럼 화면 하단을 크게 차지하지 말 것

콘텐츠 목록이나 대화 자막을 가리지 않게 작게 표시


권장 구현:

_showPauseToast = true
Timer(Duration(seconds: 1), () {
  if (mounted) setState(() => _showPauseToast = false);
});

필요 상태값:

bool _showPauseToast = false;
Timer? _pauseToastTimer;

dispose에서 반드시 정리:

_pauseToastTimer?.cancel();


---

4. 작은 pause 아이콘 표시 위치

각 화면에서 공간을 적게 차지하는 위치에 표시한다.

권장 위치:

상단 우측 작은 아이콘 영역
또는 기존 상단 상태 표시줄 근처
또는 Stack의 Positioned(top: 8, right: 12)

표시 조건:

_isIdlePaused == true

아이콘만 표시하고 문구는 표시하지 않는다.

예:

if (_isIdlePaused)
  Icon(
    Icons.pause_circle_filled_rounded,
    color: Color(0xFFFFD54F),
    size: 20,
  )


---

5. 사용자 재조작 시 처리

사용자가 다시 조작하면:

_isIdlePaused = false
_showPauseToast = false
_pauseToastTimer?.cancel()
BillingTicker.resume()
logMode(...)
_resetIdleTimer()

그리고 작은 pause 아이콘도 사라져야 한다.

사용자 동작 기준:

말하기 버튼 누름
재생 버튼 누름
다음 진행
터치
스크롤
회차 이동
역할 선택


---

6. 기존 자동 이동 정책 유지

UI만 바꾸고 정책은 유지한다.

Duo / Stealth Room
- 30초: pause + 작은 노란 아이콘 + pause 1초 팝업
- 60초: 모드 선택 화면 자동 이동

Roleplay / Clone / Step Expand
- 30초: pause + 작은 노란 아이콘 + pause 1초 팝업
- 90초: 모드 선택 화면 자동 이동

History / History List
- 30초: pause + 작은 노란 아이콘 + pause 1초 팝업
- 자동 이동 없음


---

7. 완료 기준

1. 기존 큰 idle 안내 문구가 더 이상 보이지 않는다.


2. 30초 무반응 시 작은 노란 pause 아이콘만 표시된다.


3. 30초 무반응 순간 pause 팝업이 약 1초만 보이고 사라진다.


4. 화면 콘텐츠나 History 목록을 가리지 않는다.


5. 사용자가 다시 조작하면 pause 아이콘이 사라진다.


6. 기존 BillingTicker pause/resume/logMode 흐름은 유지된다.


7. 60초/90초 자동 이동 정책은 기존대로 유지된다.


8. History / History List는 자동 이동하지 않는다.


9. dispose 시 timer 정리가 되어 setState 오류가 없어야 한다.


10. APK/AAB 빌드는 하지 않는다.


11. flutter analyze/check 수준까지만 확인한다.




---

핵심은 기능은 유지하고, 경고문 UI만 조용한 Auto Pause 표시로 바꾸는 것입니다.