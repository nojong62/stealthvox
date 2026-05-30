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

[작업] 히스토리 2개 파일 Auto Pause를 "틱 + 활동감지(_isSystemBusy)" 방식으로 교체
       → 튜터링·키퍼 재생·녹음·오디오 재생 중에는 카운터가 0으로 유지되어 오토포즈 안 걸림.
       → 정말 1분간 아무 활동 없을 때만 정지. (4개 모드 파일과 동일한 구조로 통일)

전제: dart:async 이미 import됨(확인 완료). 두 파일 모두 60초는 이미 적용된 상태.

══════════════════════════════════════════════════════════
[파일 1] chat_history_master.dart
──────────────────────────────────────────────────────────
■ 삭제 대상 (정확히 186 ~ 216줄)
  시작줄(186):  // ── Idle Timeout (무반응 과금 정지, History: 자동 이동 없음) ──────────────
  끝줄(216):    // ─────────────────────────────────────────────────────────────────────────
  (즉 기존 _idlePauseTimer 선언부터 마지막 구분선 주석까지 블록 전체)

■ 위 블록을 아래 전체로 교체:

  // ── Idle Timeout (무반응 과금 정지, History: 자동 이동 없음) ──────────────
  // 🔧 틱 방식: 1초마다 활동 여부 확인. 튜터링/녹음/오디오 재생 중엔 카운터 0 유지.
  Timer? _idlePauseTimer;
  bool _isIdlePaused = false;
  int _idleElapsedSec = 0;

  // 유저나 AI가 작동 중인지 판단 (활동 중이면 idle 누적 안 함)
  bool get _isSystemBusy {
    return _isTutorPlaying ||
        isPlaying ||
        _appIsRecording ||
        _appIsShadowRecording ||
        _isPlayingAppAudio;
  }

  void _resetIdleTimer() {
    _idleElapsedSec = 0;
    if (_isIdlePaused) {
      _isIdlePaused = false;
      if (mounted) setState(() {});
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('history');
    }
    _idlePauseTimer?.cancel();
    _idlePauseTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _idleTick());
  }

  void _idleTick() {
    if (!mounted) return;
    if (_isIdlePaused) return;
    if (_isSystemBusy) {
      _idleElapsedSec = 0;
      return;
    }
    _idleElapsedSec++;
    if (_idleElapsedSec >= 60) {
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

  Widget _buildIdleBanner() => const SizedBox.shrink();

  Widget _buildIdleOverlay() => const SizedBox.shrink();
  // ─────────────────────────────────────────────────────────────────────────

══════════════════════════════════════════════════════════
[파일 2] chat_history_list_master.dart
──────────────────────────────────────────────────────────
■ 삭제 대상 (정확히 45 ~ 75줄)
  시작줄(45):  // ── Idle Timeout (무반응 과금 정지, History List: 자동 이동 없음) ──────────
  끝줄(75):    // ─────────────────────────────────────────────────────────────────────────

■ 위 블록을 아래 전체로 교체:

  // ── Idle Timeout (무반응 과금 정지, History List: 자동 이동 없음) ──────────
  // 🔧 틱 방식: 1초마다 활동 여부 확인. 키퍼 재생/튜터링/녹음 중엔 카운터 0 유지.
  Timer? _idlePauseTimer;
  bool _isIdlePaused = false;
  int _idleElapsedSec = 0;

  // 유저나 AI가 작동 중인지 판단 (활동 중이면 idle 누적 안 함)
  bool get _isSystemBusy {
    return _keeperTutoringLoading ||
        _keeperIsRecording ||
        _isPlayingKeeper ||
        _keeperIsPlayingCorrected;
  }

  void _resetIdleTimer() {
    _idleElapsedSec = 0;
    if (_isIdlePaused) {
      _isIdlePaused = false;
      if (mounted) setState(() {});
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('history_list');
    }
    _idlePauseTimer?.cancel();
    _idlePauseTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _idleTick());
  }

  void _idleTick() {
    if (!mounted) return;
    if (_isIdlePaused) return;
    if (_isSystemBusy) {
      _idleElapsedSec = 0;
      return;
    }
    _idleElapsedSec++;
    if (_idleElapsedSec >= 60) {
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

  Widget _buildIdleBanner() => const SizedBox.shrink();

  Widget _buildIdleOverlay() => const SizedBox.shrink();
  // ─────────────────────────────────────────────────────────────────────────

══════════════════════════════════════════════════════════
[건드리지 말 것]
- 기존 _resetIdleTimer() 호출 지점(initState, _startTutorPlayback, _playKeeperAudio,
  onTap 등)은 그대로 둔다. 이제 시작 시 1번만 호출해도, 틱이 매초 _isSystemBusy를
  확인하므로 재생 도중 자동 리셋된다. 추가 호출 불필요.
- _handleIdlePause / _clearIdleTimers 의 호출 위치(dispose 등)는 변경 없음.
- 나머지 4개 모드 파일은 손대지 않는다(이미 동일 구조).

[검증]
1. grep -n "_idleElapsedSec"  chat_history_master.dart       → 5건 내외(새 블록)
2. grep -n "_idleElapsedSec"  chat_history_list_master.dart  → 5건 내외(새 블록)
3. grep -n "bool get _isSystemBusy" chat_history_master.dart chat_history_list_master.dart → 각 1건
4. grep -n "Timer.periodic(const Duration(seconds: 1)" chat_history_master.dart chat_history_list_master.dart → 각 1건
5. grep -n "_idlePauseTimer = Timer(const Duration(seconds: 60)" chat_history_master.dart chat_history_list_master.dart → 0건(원샷 제거됨)
6. dart analyze → 신규 에러 0건. 특히 _isSystemBusy 안의 변수 미정의 에러가 없어야 함
   (master: _isTutorPlaying/isPlaying/_appIsRecording/_appIsShadowRecording/_isPlayingAppAudio,
    list:   _keeperTutoringLoading/_keeperIsRecording/_isPlayingKeeper/_keeperIsPlayingCorrected)