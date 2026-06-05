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

대상 파일: routine_mode_step_expand.dart (이 파일만. chat_history_master.dart·chat_history_list_master.dart 수정 금지)
의도: 표시 로직·저장 payload·TTS·Box 7은 그대로 두고, 히스토리로 가는 자료가 어느 종료 경로에서도 누락 없이 입력되도록 보장한다. (1) 일반 턴 저장을 await 처리, (2) 안드로이드 시스템 뒤로가기도 저장을 거치도록 PopScope 추가, (3) 이중 종료 방지 가드.
수정 1 — 이중 호출 방지 플래그 선언
클래스 상태 변수 선언부(다른 bool _...= false; 멤버들이 모여 있는 곳, 예: _isConversationActive 근처)에 아래 한 줄을 추가하라.
dart  bool _isExiting = false; // 🔧 [EXIT-GUARD] PopScope+버튼 이중 종료 방지
수정 2 — _handleAutoSaveAndExit 진입부에 가드 추가 (약 2482행)
삭제 대상 (1줄):

2482행:   Future<void> _handleAutoSaveAndExit() async {

교체될 코드 (전체):
dart  Future<void> _handleAutoSaveAndExit() async {
    if (_isExiting) return; // 🔧 [EXIT-GUARD] 이미 종료 처리 중이면 무시
    _isExiting = true;
이유: 화면 버튼(2586행)과 PopScope가 동시에 이 함수를 호출하면 저장·종료가 두 번 실행될 수 있다. 진입 즉시 플래그로 차단한다. (try 블록은 다음 줄부터 그대로 이어진다.)
수정 3 — build()를 PopScope로 감싸기 (약 2554~2573행)
삭제 대상 범위:

시작 2554행:   Widget build(BuildContext context) {
끝 2573행: 이 build 메서드의 닫는 } (즉 return Container(...) 전체와 그 닫는 중괄호)

교체될 코드 (전체):
dart  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom == 0
        ? 24.0
        : MediaQuery.of(context).viewPadding.bottom + 8.0;
    return PopScope(
      // 🔧 [POPSCOPE] 시스템 제스처/하단바 뒤로가기도 AutoSave 경로를 타게 한다.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _handleAutoSaveAndExit();
      },
      child: Container(
        color: const Color(0xFF121212),
        child: SafeArea(
          child: Column(children: [
            _buildTopBar(),
            const SizedBox(height: 4),
            Expanded(
              child: Stack(children: [
                _buildChatList(),
                _buildIdleOverlay(),
              ]),
            ),
            _buildControlArea(bottomPad),
          ]),
        ),
      ),
    );
  }
이유: 현재 build는 Container 루트라 시스템 뒤로가기가 저장을 거치지 않는다. canPop: false + onPopInvokedWithResult로 시스템 pop을 가로채 _handleAutoSaveAndExit를 태운다. (가드 덕분에 화면 버튼으로 이미 나가는 중이면 재실행되지 않는다.)
참고: Flutter 버전이 3.22 미만이라 onPopInvokedWithResult에서 빌드 에러가 나면, 그 줄을 onPopInvoked: (bool didPop) async { 로 바꾸고 시그니처에서 , Object? result를 제거하라. 나머지는 동일하다.
수정 4 — 일반 턴 저장 await 보강 (약 2325~2327행)
삭제 대상 (3줄):

시작 2325행:       _saveTurnToFirestore([hostLine, systemLine]);
끝 2327행:       _log('🧠 [PIPE-10]', 'Firestore 저장 호출 완료');

교체될 코드 (전체):
dart      await _saveTurnToFirestore([hostLine, systemLine]);
      await _saveHistoryMessages([hostLine, systemLine]); // 🔧 [히스토리] 병행 저장 (await 보장)
      _log('🧠 [PIPE-10]', 'Firestore 저장 완료');
이유: await가 없으면 마지막 턴 직후 화면 이탈 시 messages·last_message 쓰기가 미완료로 끊긴다. 5턴 완료 경로(2038~2039행)와 동일하게 순차 저장을 보장한다.