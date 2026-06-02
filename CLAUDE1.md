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

[StealthVox History 오토포즈 자동 해제 수정 지시문]

대상 파일:
- lib/custom_code/widgets/chat_history_master.dart

문제:
History 화면에서 60초 무반응으로 오토포즈(_isIdlePaused)가 걸린 뒤,
사용자가 소리듣기, AI 음성 다시 듣기, 전체 AI 듣기, 유저 녹음 듣기, 튜터링/AI 연습 시작을 눌러도
오토포즈 상태가 자동으로 해제되지 않고 상단 pause 아이콘/과금 pause 상태가 계속 유지된다.

현재 구조:
- _isIdlePaused == true 상태에서 _resetIdleTimer()가 호출되어야
  _isIdlePaused = false
  BillingTicker.instance.resume()
  BillingTicker.instance.logMode('history')
  가 실행된다.
- 하지만 일부 재생/튜터링 시작 함수에서 _resetIdleTimer() 호출이 빠져 있어,
  실제 사용자가 활동을 시작해도 pause 상태가 남는다.
- _isSystemBusy는 idle 누적 방지용일 뿐, 이미 걸린 _isIdlePaused를 자동 해제하지 않는다.

수정 목표:
History 화면에서는 사용자가 다시 실제 활동을 시작하는 순간 오토포즈가 자동 해제되어야 한다.

반드시 적용할 원칙:
1. 오토포즈 상태라도 사용자가 아래 동작을 시작하면 즉시 _resetIdleTimer()를 호출한다.
   - 튜터링/AI 연습 진입
   - 튜터링 시작 버튼 확정
   - AI TTS 재생
   - 청크 AI 다시 듣기
   - 전체 AI 듣기
   - 유저 녹음 듣기
   - 일반 History 오디오 재생
   - 앱 튜터링/교정 오디오 재생이 있다면 해당 시작 지점

2. 단순히 _isSystemBusy에 항목을 추가하는 방식만으로 해결하지 말 것.
   이미 _isIdlePaused == true인 경우 _idleTick()은 return하기 때문에,
   busy 상태가 되어도 pause가 풀리지 않는다.
   따라서 실제 사용자 액션 시작 함수에서 명시적으로 _resetIdleTimer()를 호출해야 한다.

3. 새 helper를 하나 만들어 중복을 줄여라.

권장 helper:
void _markUserActiveForHistory() {
  _resetIdleTimer();
}

또는 더 명확히:
void _resumeHistoryFromUserAction() {
  _resetIdleTimer();
}

수정 위치:
A. _enterShadowingFromRoom()
- 함수 시작 직후 또는 실제 연습 진입이 확정되기 전 _resumeHistoryFromUserAction() 호출.
- 사용자가 AI 연습 버튼을 눌렀다는 것 자체가 활동 재개이므로 오토포즈 해제 대상이다.

B. _confirmStart({required bool swap})
- 시작 선택 확정 직후 _resumeHistoryFromUserAction() 호출.
- 역할 선택 화면에서 대기 중 오토포즈가 걸렸더라도, 시작을 누르면 바로 해제되어야 한다.

C. _startTurnPractice()
- 이미 _resetIdleTimer()가 있으면 helper로 통일해도 된다.
- 이 함수는 유지 필수.

D. _startTutorPlayback()
- 이미 _resetIdleTimer()가 있으면 helper로 통일해도 된다.
- 이 함수는 유지 필수.

E. _playSmartAudio(String text)
- 실제 AI TTS 재생 시작 전 _resumeHistoryFromUserAction() 호출.
- turnPractice에서 AI가 말하는 순간은 명백한 활동 상태다.

F. _playChunkAI(int idx)
- 청크 AI 음성 재생 시작 전에 _resumeHistoryFromUserAction() 호출.
- Step Expand/Shadowing에서 AI 소리듣기 버튼으로 재생하는 경우도 pause가 풀려야 한다.

G. _replayChunkAI(int idx)
- 사용자가 AI 아이콘을 눌러 다시 듣기를 요청한 직후 _resumeHistoryFromUserAction() 호출.

H. _playFullAI()
- 전체 AI 듣기 시작 직후 _resumeHistoryFromUserAction() 호출.

I. _playFullUser()
- 전체 유저 녹음 듣기 시작 직후 _resumeHistoryFromUserAction() 호출.

J. _playUserChunk(int idx)
- 실제 유저 녹음 파일 재생 전 _resumeHistoryFromUserAction() 호출.
- 단, path가 null/empty라서 재생하지 않는 경우에는 굳이 호출하지 않아도 된다.

K. 일반 History 메시지의 오디오 재생 함수가 별도로 있다면
- audioPlayer.play(...)를 호출하는 모든 사용자 재생 액션 시작점에 _resumeHistoryFromUserAction()을 추가하라.
- grep 기준:
  audioPlayer.play(
  player.play(
  DeviceFileSource(
  BytesSource(
  를 검색해서 사용자 액션 기반 재생 시작점 누락 여부를 확인하라.

주의:
- dispose()의 BillingTicker.instance.pause()는 유지한다.
- _handleIdlePause()의 pause 로직은 유지한다.
- History 화면은 자동 이동이 없어야 하므로 navigation 로직을 추가하지 않는다.
- pause 아이콘을 탭해서 해제하는 기존 onTap: _resetIdleTimer 동작은 유지한다.
- APK/AAB 빌드 명령은 실행하지 말고, 코드 수정 후 flutter analyze/check 수준까지만 확인한다.

검증 시나리오:
1. History 화면 진입.
2. 아무 동작 없이 60초 이상 대기.
3. 상단 노란 pause 아이콘이 표시되는지 확인.
4. pause 아이콘을 직접 누르지 말고, 소리듣기/AI 다시 듣기 버튼을 누른다.
5. 즉시 pause 아이콘이 사라지고 BillingTicker가 history 모드로 resume 되는지 확인.
6. 다시 60초 무반응이면 pause가 다시 걸리는지 확인.
7. pause 상태에서 튜터링/AI 연습 시작 버튼을 누른다.
8. 역할 선택/시작 확정 후 pause가 자동 해제되고, AI 음성/녹음 턴이 정상 진행되는지 확인.
9. Step Expand 방의 청크 AI 다시 듣기, 전체 AI 듣기, 유저 녹음 듣기에서도 동일하게 pause가 자동 해제되는지 확인.