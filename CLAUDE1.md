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

routine_mode_step_expand.dart, routine_mode_roleplay.dart, routine_mode_clone.dart
세 파일 모두에 동일 패턴을 적용합니다.
목표: Auto Pause가 "유저 무음"만 보지 않고, "유저도 AI도 아무 작동이 없을 때"부터 30초 뒤 걸리게 한다.

[핵심 원리]
- AI가 작동 중인지 = _ttsQueueManager.isBusy (TTS 재생/대기 중) 로 판정
- 유저가 작동 중인지 = _voiceManager != null (마이크 연결/녹음 중) 로 판정
- 둘 중 하나라도 true면 "작동 중" → idle 카운트 진행 안 함
- 둘 다 false인 상태가 연속 30초 지속되면 그때 pause
- Box 7(TtsQueueManager, DeepgramV2VoiceManager)은 getter만 읽고 절대 수정하지 않는다.

[절대 건드리지 말 것]
- TtsQueueManager, DeepgramV2VoiceManager 클래스 내부 (isBusy getter 등은 읽기만)
- _resetIdleTimer 호출 지점들 (그대로 둠 — 유저 액션 시 즉시 깨우는 역할 유지)
- BillingTicker 관련 로직의 의미 (pause/resume 호출 위치)

──────────────────────────────────────────────
[수정 — 3개 파일 공통] idle 타이머 블록 교체
──────────────────────────────────────────────

각 파일에서 아래 블록을 찾습니다 (logMode 인자만 파일별로 다름:
  step_expand='study_room', roleplay='roleplay', clone='clone'):

  void _resetIdleTimer() {
    _idlePauseTimer?.cancel();
    if (_isIdlePaused) {
      _isIdlePaused = false;
      if (mounted) setState(() {});
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('<MODE>');
    }
    _idlePauseTimer = Timer(const Duration(seconds: 30), _handleIdlePause);
  }

  void _handleIdlePause() {
    if (!mounted || _isIdlePaused) return;
    _isIdlePaused = true;
    BillingTicker.instance.pause();
    if (mounted) setState(() {});
  }

  void _clearIdleTimers() {
    _idlePauseTimer?.cancel();
    _idlePauseTimer = null;
  }

이 블록 전체를 아래로 교체합니다 (logMode 인자 '<MODE>'는 각 파일의 기존 값을 그대로 유지할 것):

  // ── Idle Timeout v2 ───────────────────────────────────────────────
  // 기준: "유저도 AI도 아무 작동이 없는 상태"가 연속 30초 지속되면 pause.
  //  - AI 작동 = _ttsQueueManager.isBusy (TTS 재생/대기)
  //  - 유저 작동 = _voiceManager != null (마이크 연결/녹음)
  // 1초 주기 감시 타이머가 작동 여부를 보고 idle 누적초를 증감한다.
  int _idleElapsedSec = 0;

  bool get _isSystemBusy {
    final ttsBusy = _ttsQueueManager.isBusy;
    final micBusy = _voiceManager != null;
    return ttsBusy || micBusy;
  }

  void _resetIdleTimer() {
    _idleElapsedSec = 0;
    if (_isIdlePaused) {
      _isIdlePaused = false;
      if (mounted) setState(() {});
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('<MODE>');
    }
    _idlePauseTimer?.cancel();
    _idlePauseTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _idleTick());
  }

  void _idleTick() {
    if (!mounted) return;
    if (_isIdlePaused) return;
    // 유저나 AI가 작동 중이면 idle 누적을 멈추고 리셋
    if (_isSystemBusy) {
      _idleElapsedSec = 0;
      return;
    }
    _idleElapsedSec++;
    if (_idleElapsedSec >= 30) {
      _handleIdlePause();
    }
  }

  void _handleIdlePause() {
    if (!mounted || _isIdlePaused) return;
    _isIdlePaused = true;
    _idleElapsedSec = 0;
    BillingTicker.instance.pause();
    if (mounted) setState(() {});
  }

  void _clearIdleTimers() {
    _idlePauseTimer?.cancel();
    _idlePauseTimer = null;
    _idleElapsedSec = 0;
  }
  // ──────────────────────────────────────────────────────────────────

[검증 — 3개 파일 각각]
1. dart analyze → 에러 0
2. grep -c "_isSystemBusy" 각 파일 → 2 (getter 정의 1 + _idleTick 사용 1)
3. grep -c "Timer.periodic(const Duration(seconds: 1)" 각 파일 → 1
4. grep -c "Timer(const Duration(seconds: 30), _handleIdlePause)" 각 파일 → 0 (옛 단발 타이머 제거 확인)
5. grep -c "_ttsQueueManager.isBusy" 각 파일 → 최소 1
6. logMode 인자가 파일별로 그대로인지 확인:
   step_expand → grep "logMode('study_room')"
   roleplay    → grep "logMode('roleplay')"
   clone       → grep "logMode('clone')"
7. TtsQueueManager / DeepgramV2VoiceManager 클래스 내부에 diff 변경 0인지 확인 (getter만 읽음)
8. _resetIdleTimer() 호출 지점(initState, 마이크 시작, 발화 끝, 파이프라인 등)이 그대로 남아있는지 확인 — 유저 액션 시 즉시 깨우는 동작 유지