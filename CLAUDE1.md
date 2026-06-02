StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):
"임시/ 폴더에는 적용하지 말 것"

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

[StealthVox History 실전 튜터링 오토포즈 해제 누락 수정 지시문]

대상 파일:
- lib/custom_code/widgets/chat_history_master.dart

문제:
History 화면에서 오토포즈 상태(_isIdlePaused == true)일 때,
소리듣기 버튼을 누르면 오토포즈가 정상 해제되지만,
말풍선 옆 보라색 학교 아이콘의 “실전 튜터링”을 누르면 오토포즈가 해제되지 않는다.

확인된 원인:
- 오디오 재생 함수 쪽에는 _resumeHistoryFromUserAction() 호출이 들어가 있다.
- 하지만 실전 튜터링 팝업 진입 함수인 _showTutoringPopup(String docId, String baseText) 시작부에는 _resumeHistoryFromUserAction() 호출이 없다.
- 현재 _showTutoringPopup() 안에서는 BillingTicker.instance.setRate(BillingRate.full)만 실행되고, BillingTicker resume/logMode 복구는 실행되지 않는다.
- 따라서 오토포즈 상태에서 튜터링을 열면 과금 rate는 full로 바뀌지만 pause 상태는 그대로 남는다.

수정 목표:
History에서 사용자가 실전 튜터링을 누르는 순간, 오토포즈가 즉시 해제되어야 한다.
튜터링 팝업 열기, 녹음 시작, 새 문장 생성 같은 실제 활동도 모두 사용자 활동으로 인정해야 한다.

수정 지점:

1. _showTutoringPopup(String docId, String baseText)
- 함수 시작 직후, appAudioRecorder 정리보다 먼저 또는 최소한 setState 전에 _resumeHistoryFromUserAction()을 호출하라.
- 이 함수가 실전 튜터링의 진입점이므로 여기서 반드시 오토포즈를 해제해야 한다.
- BillingTicker.instance.setRate(BillingRate.full) 전에 호출하는 것이 가장 안전하다.

적용 의도:
오토포즈 상태에서 학교 아이콘을 누르는 순간
_isIdlePaused = false
BillingTicker.instance.resume()
BillingTicker.instance.logMode('history')
_idle timer 재시작
이 한 번에 실행되어야 한다.

2. _startAppRecording()
- 함수 시작 직후 _resumeHistoryFromUserAction()을 호출하라.
- 튜터링 팝업을 열어둔 상태에서 다시 오토포즈가 걸린 뒤 녹음 버튼을 누르는 경우도 해제되어야 한다.

3. _stopAppRecordAndProcess(String targetKo, String targetEn)
- 함수 시작 직후 _resumeHistoryFromUserAction()을 호출하라.
- 녹음 종료 후 STT/GPT 교정 처리는 명백한 튜터링 활동이므로 pause 상태로 진행되면 안 된다.

4. _generateAppText(String baseText)
- 함수 시작 직후 _resumeHistoryFromUserAction()을 호출하라.
- 실전 튜터링 최초 문장 생성과 Another Sentence 모두 사용자 활동으로 처리되어야 한다.

5. _startShadowRecord()
- 함수 시작 직후 _resumeHistoryFromUserAction()을 호출하라.
- 교정 TTS를 듣고 쉐도잉 녹음에 들어가는 것도 오토포즈 해제 대상이다.

6. _stopShadowRecord()
- 함수 시작 직후 _resumeHistoryFromUserAction()을 호출하라.
- 쉐도잉 녹음 종료도 사용자 활동으로 처리한다.

주의:
- 기존 _resumeHistoryFromUserAction() helper는 이미 있으므로 새로 만들 필요 없다.
- _resetIdleTimer() 로직 자체는 건드리지 말 것.
- _handleIdlePause() 로직도 건드리지 말 것.
- 소리듣기 쪽은 이미 정상 동작하므로 불필요하게 수정하지 말 것.
- 튜터링 종료 시 BillingTicker.instance.setRate(BillingRate.quarter)로 복귀하는 기존 whenComplete 로직은 유지한다.
- History 화면은 자동 이동이 없어야 하므로 navigation 추가 금지.
- APK/AAB 빌드 명령은 실행하지 말고, 코드 수정 후 flutter analyze/check 수준까지만 확인한다.

검증 시나리오:
1. History 화면에서 아무 동작 없이 오토포즈가 걸릴 때까지 대기한다.
2. 상단 pause 아이콘이 보이는 상태에서 말풍선 옆 보라색 학교 아이콘 “실전 튜터링”을 누른다.
3. 튜터링 팝업이 열리는 즉시 pause 아이콘이 사라지는지 확인한다.
4. BillingTicker가 resume 되고 history 모드 로그가 다시 찍히는지 확인한다.
5. 튜터링 팝업을 열어둔 상태에서 다시 오토포즈가 걸리게 둔다.
6. 녹음 버튼을 누르면 즉시 오토포즈가 해제되는지 확인한다.
7. Another Sentence 버튼을 눌러도 오토포즈가 해제되는지 확인한다.
8. Shadow This / 쉐도잉 녹음 시작에서도 오토포즈가 해제되는지 확인한다.