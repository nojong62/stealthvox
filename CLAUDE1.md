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

지시문: 애니원 모드 안내음 → "텍스트 말풍선(1.5초 페이드)" 전환
사전 조치
git add -A && git commit -m "savepoint: before nudge sound to text-bubble change"
Edit 1 (최상단부터, 파일 하단→상단 순서) — build()의 Stack에 말풍선 추가
grep 확인 (count=1 기대):
grep -c "if (_showUsageGuide) _buildUsageGuide(), // 🆕 \[Anyone\] 이용방법 말풍선" routine_mode_anyone.dart
old_str:
dart              if (trialMode) buildTrialCountdown(),
              if (_showUsageGuide) _buildUsageGuide(), // 🆕 [Anyone] 이용방법 말풍선
            ]),
new_str:
dart              if (trialMode) buildTrialCountdown(),
              if (_showUsageGuide) _buildUsageGuide(), // 🆕 [Anyone] 이용방법 말풍선
              _buildNudgeBubble(), // 🆕 [즉시 안내 말풍선] 마이크 켜지면 1.5초 노출 후 소멸
            ]),

Edit 2 — _buildUsageGuide 바로 위에 새 말풍선 위젯 추가
grep 확인 (count=1 기대):
grep -c "Widget _buildUsageGuide() {" routine_mode_anyone.dart
old_str:
dart  // 🆕 [Anyone] 이용방법 말풍선 (배경/말풍선 어디든 톡 누르면 닫힘)
  Widget _buildUsageGuide() {
new_str:
dart  // 🆕 [즉시 안내 말풍선] 마이크 켜지는 즉시 표시, 1.5초 후 자동 페이드아웃
  // 텍스트라서 마이크/재생과 충돌 없음 → 타이밍 로직(대기/취소) 불필요.
  Widget _buildNudgeBubble() {
    return IgnorePointer( // 탭 막지 않음 — 유저가 바로 조작 가능
      child: Align(
        alignment: Alignment.center,
        child: AnimatedOpacity(
          opacity: _showNudgeBubble ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 36),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E22).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF7F77DD).withValues(alpha: 0.55),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2DD4BF).withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Text(
              '여기, 그 사람이 있어요. 편하게 말 걸어보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🆕 [Anyone] 이용방법 말풍선 (배경/말풍선 어디든 톡 누르면 닫힘)
  Widget _buildUsageGuide() {

Edit 3 — _armOpenerNudge 함수 완전 삭제 (더 이상 대기/타이머 불필요)
grep 확인 (count=1 기대):
grep -c "void _armOpenerNudge() {" routine_mode_anyone.dart
old_str:
dart  // 🆕 [유저 먼저 → 1초 침묵 시 안내음]
  // 마이크가 살아있는 상태에서 1초 grace. 그 안에 유저가 말하면
  // (onTranscriptUpdate에서 _userHasSpoken=true + 타이머 취소) 안내음은 안 나간다.
  void _armOpenerNudge() {
    _openerNudgeTimer?.cancel();
    _openerNudgeTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || !_isConversationActive) return;
      if (_userHasSpoken || _localMessages.isNotEmpty) return;
      _log('💡 [NUDGE]', '1초 침묵 → 안내음 재생 (마이크 유지)');
      _playNudgeSound();
    });
  }
new_str:

(통째로 삭제 — 빈 문자열로 교체)

Edit 4 — 마이크 연결 성공 직후 트리거를 "즉시 호출"로 변경
grep 확인 (count=1 기대):
grep -c "if (_localMessages.isEmpty && !_userHasSpoken) {" routine_mode_anyone.dart
old_str:
dart      // 🆕 [유저 먼저] 첫 턴이고 유저가 아직 말 안 했으면 2초 grace 후 AI가 운을 뗌
      if (_localMessages.isEmpty && !_userHasSpoken) {
        _armOpenerNudge();
      }
new_str:
dart      // 🆕 [즉시 안내 말풍선] 첫 턴이면 마이크 연결 직후 바로 표시 (텍스트라 겹침 걱정 없음)
      if (_localMessages.isEmpty && !_hasShownNudgeBubble) {
        _showNudgeBubbleOnce();
      }

Edit 5 — onTranscriptUpdate의 오프너 취소 로직 제거 (더 이상 취소할 타이머 없음)
grep 확인 (count=1 기대):
grep -c "// 🆕 \[유저 먼저\] 유저가 입을 떼는 순간 오프너 nudge 취소" routine_mode_anyone.dart
old_str:
dart          // 🆕 [유저 먼저] 유저가 입을 떼는 순간 오프너 nudge 취소
          if (!_userHasSpoken) {
            _userHasSpoken = true;
            _openerNudgeTimer?.cancel();
          }
          _swDeepgram.reset();
new_str:
dart          _swDeepgram.reset();

Edit 6 — _playNudgeSound() → _showNudgeBubbleOnce()로 교체 (mp3/AudioPlayer 제거)
grep 확인 (count=1 기대):
grep -c "Future<void> _playNudgeSound() async {" routine_mode_anyone.dart
old_str:
dart  // ====================================================================
  // 📦 [1초 침묵 안내음] — GPT 오프너 대신 사전 생성된 고정 mp3 재생
  // ====================================================================
  Future<void> _playNudgeSound() async {
    if (_hasPlayedNudge) return;
    _hasPlayedNudge = true;
    try {
      await _nudgeAudioPlayer
          .play(AssetSource('audios/anyone_nudge_fable.mp3'));
    } catch (e) {
      _log('❌ [NUDGE-SOUND-ERR]', '$e');
    }
  }
new_str:
dart  // ====================================================================
  // 📦 [즉시 안내 말풍선] — 소리 대신 화면 텍스트로 1.5초간 표시 후 자동 소멸
  // ====================================================================
  void _showNudgeBubbleOnce() {
    if (_hasShownNudgeBubble || !mounted) return;
    _hasShownNudgeBubble = true;
    setState(() => _showNudgeBubble = true);
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showNudgeBubble = false);
    });
  }

Edit 7 — _stopEverything: 플래그명 교체, 타이머 정리 제거
grep 확인 (count=1 기대):
grep -c "_hasPlayedNudge = false;" routine_mode_anyone.dart
old_str:
dart    _isConversationActive = false;
    _hasPlayedNudge = false;
    _isStartingListening = false;
    _isPipelineRunning = false;
    _listenGeneration++;
    _commitTimer?.cancel(); // 🔧 [v3.4] 대기 중 타이머 정리
    _commitTimer = null;
    _openerNudgeTimer?.cancel(); // 🆕 [유저 먼저] 오프너 nudge 정리
    _openerNudgeTimer = null;
    _pendingTranscript = ''; // 대기 중 발화도 버림
new_str:
dart    _isConversationActive = false;
    _hasShownNudgeBubble = false;
    _showNudgeBubble = false;
    _isStartingListening = false;
    _isPipelineRunning = false;
    _listenGeneration++;
    _commitTimer?.cancel(); // 🔧 [v3.4] 대기 중 타이머 정리
    _commitTimer = null;
    _pendingTranscript = ''; // 대기 중 발화도 버림

Edit 8 — _startFreeTalkSession: 플래그명 교체, 주석 정리
grep 확인 (count=1 기대):
grep -c "_userHasSpoken = false;" routine_mode_anyone.dart
old_str:
dart  /// 🆕 세션 자동 시작: 표시등 ON + 마이크 먼저(유저 먼저 말하게).
  /// 마이크 첫 청취가 시작되면 _isConversationActive=true 로 자동 점등.
  /// 첫 턴 1초 침묵 시 _armOpenerNudge가 고정 안내음을 재생.
  Future<void> _startFreeTalkSession() async {
    if (_deepgramKey.isEmpty || !mounted) return;
    if (_isConversationActive) return; // 중복 시작 방지
    _userHasSpoken = false;
    _hasPlayedNudge = false;
    _startDeepgramListening();
  }
new_str:
dart  /// 🆕 세션 자동 시작: 표시등 ON + 마이크 먼저(유저 먼저 말하게).
  /// 마이크 첫 청취가 시작되면 _isConversationActive=true 로 자동 점등.
  /// 마이크 연결 직후 안내 말풍선 1.5초 노출.
  Future<void> _startFreeTalkSession() async {
    if (_deepgramKey.isEmpty || !mounted) return;
    if (_isConversationActive) return; // 중복 시작 방지
    _hasShownNudgeBubble = false;
    _startDeepgramListening();
  }

Edit 9 — dispose()에서 AudioPlayer 정리 코드 제거
grep 확인 (count=1 기대):
grep -c "_nudgeAudioPlayer.dispose();" routine_mode_anyone.dart
old_str:
dart    _audioRecorder.dispose();
    _nudgeAudioPlayer.dispose();
    _ttsQueueManager.stop();
new_str:
dart    _audioRecorder.dispose();
    _ttsQueueManager.stop();

Edit 10 — 변수 선언부 교체 (가장 상단, 마지막에 진행)
grep 확인 (count=1 기대):
grep -c "final AudioPlayer _nudgeAudioPlayer = AudioPlayer(); // 🆕 \[1초 침묵 안내음\] 전용 플레이어" routine_mode_anyone.dart
old_str:
dart  bool _hasPlayedNudge = false; // 🆕 [1초 침묵 안내음] 세션당 1회 재생 가드
  final AudioPlayer _nudgeAudioPlayer = AudioPlayer(); // 🆕 [1초 침묵 안내음] 전용 플레이어

  // 🆕 [유저 먼저] 1초 grace 동안 유저가 말 안 하면 안내음 재생
  Timer? _openerNudgeTimer;
  bool _userHasSpoken = false;
new_str:
dart  bool _hasShownNudgeBubble = false; // 🆕 [즉시 안내 말풍선] 세션당 1회 노출 가드
  bool _showNudgeBubble = false; // 🆕 [즉시 안내 말풍선] 현재 표시 여부(페이드 애니메이션 트리거)

마무리 절차 (기존 워크플로우 그대로)

post-grep 검증 — 아래 문자열이 전부 0건인지 확인:

   grep -n "_openerNudgeTimer\|_hasPlayedNudge\|_nudgeAudioPlayer\|_userHasSpoken\|_armOpenerNudge\|_playNudgeSound" routine_mode_anyone.dart

dart format routine_mode_anyone.dart (해당 파일 단독)
flutter analyze — error 없는지 확인
실기기(또는 에뮬레이터) 확인: 마이크 켜지자마자 말풍선이 뜨는지, 1.5초 후 부드럽게 사라지는지(증발), 탭해도 화면 조작에 방해 안 되는지
문제 없으면 커밋: git add -A && git commit -m "feat: anyone mode replace nudge sound with instant fading text bubble"
문제 있으면 git reset --hard HEAD~1

참고 — 정리 대상에서 제외한 것: assets/audios/anyone_nudge_fable.mp3 파일 자체는 저장소에서 지울지 말지는 실장님 판단에 맡겨두겠습니다 (더 이상 코드에서 참조 안 되니 지워도 안전하지만, 급한 건 아닙니다). pubspec.yaml의 assets/audios/ 폴더 등록은 다른 파일(favicon.png 등)도 쓰고 있어서 그대로 두면 됩니다.
