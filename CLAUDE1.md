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

# 오토포즈 과금정책 수정 + 과금 상태 인디케이터

## 목적
1. **Duo**: 오토포즈 전체 제거 (과금은 `_startDuoBilling`/`_stopDuoBilling`만)
2. **History List**: 화면 진입 시 과금 제거 → Keepers 탭 진입 시에만 quarter 과금 + 오토포즈
3. **과금 상태 인디케이터**: 4개 대화모드의 타이머 아이콘(`Icons.timer_outlined`)을 색깔 동그라미로 교체
   - 🔵 파란색 `0xFF3B82F6`: full rate 과금 중
   - 🟢 초록색 `0xFF34D399`: quarter rate 과금 중
   - ⚫ 회색 `0xFF6B7280`: 과금 정지 (오토포즈 / 대기)

---

## 사전 준비

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "save: before autopause policy fix + billing dot"
```

---

## Part 0: billing_ticker.dart — 과금 상태 색상 노출

> 파일 위치: `lib/custom_code/actions/billing_ticker.dart`
> 편집 순서: bottom-to-top

### Edit 0-1: resume()에 _updateDotColor() 호출 추가

```
<<<<<<< OLD
  void resume() {
    _paused = false;
    _addBillingLog('[BILLING] resume');
  }
=======
  void resume() {
    _paused = false;
    _addBillingLog('[BILLING] resume');
    _updateDotColor();
  }
>>>>>>> NEW
```

### Edit 0-2: pause()에 _updateDotColor() 호출 추가

```
<<<<<<< OLD
  void pause() {
    _paused = true;
    _addBillingLog('[BILLING] pause');
    flushNow();
    saveUsageLog(); // 세션 종료 시 사용시간 이력 1회 저장 (중복 방지 포함)
  }
=======
  void pause() {
    _paused = true;
    _addBillingLog('[BILLING] pause');
    _updateDotColor();
    flushNow();
    saveUsageLog(); // 세션 종료 시 사용시간 이력 1회 저장 (중복 방지 포함)
  }
>>>>>>> NEW
```

### Edit 0-3: setRate()에 _updateDotColor() 호출 추가

```
<<<<<<< OLD
  void setRate(BillingRate rate) {
    _rate = rate;
    final rateStr = rate == BillingRate.full ? 'rate=full' : 'rate=quarter';
    _addBillingLog('[BILLING] $rateStr');
  }
=======
  void setRate(BillingRate rate) {
    _rate = rate;
    final rateStr = rate == BillingRate.full ? 'rate=full' : 'rate=quarter';
    _addBillingLog('[BILLING] $rateStr');
    _updateDotColor();
  }
>>>>>>> NEW
```

### Edit 0-4: billingDotColor 선언 + _updateDotColor 헬퍼 추가 (remainingSecondsNotifier 바로 아래)

```
<<<<<<< OLD
  final ValueNotifier<int> remainingSecondsNotifier = ValueNotifier<int>(0);

  Timer? _tickTimer;
=======
  final ValueNotifier<int> remainingSecondsNotifier = ValueNotifier<int>(0);

  /// 과금 상태 색상 인디케이터 (UI 타이머 위젯의 동그라미 색상)
  /// gray=정지, blue=full rate, green=quarter rate
  final ValueNotifier<Color> billingDotColor =
      ValueNotifier(const Color(0xFF6B7280));

  void _updateDotColor() {
    if (_paused) {
      billingDotColor.value = const Color(0xFF6B7280); // gray — 정지
    } else if (_rate == BillingRate.full) {
      billingDotColor.value = const Color(0xFF3B82F6); // blue — full
    } else {
      billingDotColor.value = const Color(0xFF34D399); // green — quarter
    }
  }

  Timer? _tickTimer;
>>>>>>> NEW
```

---

## Part 1: routine_mode_duo.dart — 오토포즈 전체 제거 + 타이머 아이콘 교체

> 편집 순서: bottom-to-top

### Edit 1-1: 타이머 아이콘 → 과금 상태 동그라미 (line ~1444)

```
<<<<<<< OLD
                      const Icon(Icons.timer_outlined,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 6),
=======
                      ValueListenableBuilder<Color>(
                        valueListenable: BillingTicker.instance.billingDotColor,
                        builder: (_, dotColor, __) => Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dotColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
>>>>>>> NEW
```

### Edit 1-2: idle pause 아이콘 UI 제거 (line ~1401)

```
<<<<<<< OLD
          Row(children: [
            // ── Idle pause 아이콘 (T버튼 왼쪽, 클릭 시 pause 해제) ──
            if (_isIdlePaused)
              GestureDetector(
                onTap: _resetIdleTimer,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4, right: 6),
                  child: Icon(
                    Icons.pause_circle_filled_rounded,
                    color: Color(0xFFFFD54F),
                    size: 20,
                  ),
                ),
              ),
            IconButton(
=======
          Row(children: [
            IconButton(
>>>>>>> NEW
```

### Edit 1-3: _buildIdleOverlay() 호출 제거 (line ~1189)

```
<<<<<<< OLD
                    _buildIdleOverlay(),
                  ]),
=======
                  ]),
>>>>>>> NEW
```

### Edit 1-4: _onPttEnd에서 _resetIdleTimer 제거 (line ~789)

```
<<<<<<< OLD
  void _onPttEnd() {
    _resetIdleTimer();
    if (_duoState == 'recording') {
=======
  void _onPttEnd() {
    if (_duoState == 'recording') {
>>>>>>> NEW
```

### Edit 1-5: _onPttStart에서 _resetIdleTimer 제거 (line ~777)

```
<<<<<<< OLD
  void _onPttStart() {
    _resetIdleTimer();
    if (!_isConversationActive) {
=======
  void _onPttStart() {
    if (!_isConversationActive) {
>>>>>>> NEW
```

### Edit 1-6: _handleIncomingMessage에서 _resetIdleTimer 제거 (line ~664)

```
<<<<<<< OLD
    if (raw.trim().isEmpty) return;

    _resetIdleTimer();

    // 상대 발화를 들려주는 동안 내 녹음 일시 정지 (스피커 음성이 마이크에 새는 것 방지)
=======
    if (raw.trim().isEmpty) return;

    // 상대 발화를 들려주는 동안 내 녹음 일시 정지 (스피커 음성이 마이크에 새는 것 방지)
>>>>>>> NEW
```

### Edit 1-7: _processRelayPipeline에서 _resetIdleTimer 제거 (line ~510)

```
<<<<<<< OLD
  Future<void> _processRelayPipeline(String finalTranscript) async {
    _resetIdleTimer();
    _turnCounter++;
=======
  Future<void> _processRelayPipeline(String finalTranscript) async {
    _turnCounter++;
>>>>>>> NEW
```

### Edit 1-8: _stopAndSendToWhisper에서 _resetIdleTimer 제거 (line ~413)

```
<<<<<<< OLD
  Future<void> _stopAndSendToWhisper() async {
    _silenceTimer?.cancel();
    _resetIdleTimer();
    _setDuoState('processing');
=======
  Future<void> _stopAndSendToWhisper() async {
    _silenceTimer?.cancel();
    _setDuoState('processing');
>>>>>>> NEW
```

### Edit 1-9: _playAudioAndWait에서 _resetIdleTimer 제거 (line ~327)

```
<<<<<<< OLD
  Future<void> _playAudioAndWait(Uint8List? bytes) async {
    if (bytes == null || !_isConversationActive) return;
    _resetIdleTimer();
    _isTtsActive = true;
=======
  Future<void> _playAudioAndWait(Uint8List? bytes) async {
    if (bytes == null || !_isConversationActive) return;
    _isTtsActive = true;
>>>>>>> NEW
```

### Edit 1-10: dispose에서 _clearIdleTimers 제거 (line ~283)

```
<<<<<<< OLD
  void dispose() {
    _clearIdleTimers();
    _partnerJoinedSubscription?.cancel();
=======
  void dispose() {
    _partnerJoinedSubscription?.cancel();
>>>>>>> NEW
```

### Edit 1-11: initState postFrameCallback에서 _resetIdleTimer 제거 (line ~277)

```
<<<<<<< OLD
      if (mounted) _resetIdleTimer();
    });
  }
=======
    });
  }
>>>>>>> NEW
```

### Edit 1-12: idle timer 변수/메서드 블록 전체 제거 (line ~179-217)

```
<<<<<<< OLD
  // ── Idle Timeout (무반응 자동 일시정지) ────────────────────────────────────
  Timer? _idlePauseTimer;
  bool _isIdlePaused = false;

  void _resetIdleTimer() {
    _idlePauseTimer?.cancel();
    if (_isIdlePaused) {
      _isIdlePaused = false;
      if (mounted) setState(() {});
      // 🆕 [과금정책] 게스트 입장(과금 시작) 상태일 때만 resume — 대기 중엔 재개 금지
      if (_billingStarted) {
        BillingTicker.instance.resume();
        BillingTicker.instance.logMode('duo');
      }
    }
    _idlePauseTimer = Timer(const Duration(seconds: 60), _handleIdlePause);
  }

  void _handleIdlePause() {
    if (!mounted || _isIdlePaused) return;
    // 🔒 [오토포즈 가드] 최상단이 아니면 일시정지하지 말고 60초 타이머만 다시 건다
    if (ModalRoute.of(context)?.isCurrent == false) {
      _resetIdleTimer();
      return;
    }
    _isIdlePaused = true;
    BillingTicker.instance.pause();
    if (mounted) setState(() {});
  }

  void _clearIdleTimers() {
    _idlePauseTimer?.cancel();
    _idlePauseTimer = null;
  }

  Widget _buildIdleBanner() => const SizedBox.shrink();

  Widget _buildIdleOverlay() => const SizedBox.shrink();
  // ─────────────────────────────────────────────────────────────────────────
=======
>>>>>>> NEW
```

---

## Part 2: chat_history_list_master.dart — Keepers 탭 기준 과금 경계

> 편집 순서: bottom-to-top

### Edit 2-1: 일반 필터칩 onTap → _switchFilter 호출 (line ~778)

```
<<<<<<< OLD
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_selectedFilter == filterKey && filterKey != 'All') {
            _selectedFilter = 'All';
          } else {
            _selectedFilter = filterKey;
          }
          _selectedDocIds.clear();
        });
      },
=======
    return GestureDetector(
      onTap: () {
        final newFilter = (_selectedFilter == filterKey && filterKey != 'All')
            ? 'All'
            : filterKey;
        _switchFilter(newFilter);
      },
>>>>>>> NEW
```

### Edit 2-2: Keepers칩 onTap → _switchFilter 호출 (line ~679)

```
<<<<<<< OLD
      onTap: () {
        setState(() {
          _selectedFilter = isSelected ? 'All' : 'Keepers';
          _selectedDocIds.clear();
        });
      },
=======
      onTap: () {
        _switchFilter(isSelected ? 'All' : 'Keepers');
      },
>>>>>>> NEW
```

### Edit 2-3: initState에서 과금 시작 제거 (line ~252)

```
<<<<<<< OLD
  void initState() {
    super.initState();
    _fetchApiKey();
    BillingTicker.instance.setRate(BillingRate.quarter);
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('history_list');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetIdleTimer();
    });
  }
=======
  void initState() {
    super.initState();
    _fetchApiKey();
    // 과금은 Keepers 탭 진입 시에만 시작 (_switchFilter에서 제어)
  }
>>>>>>> NEW
```

### Edit 2-4: _switchFilter 헬퍼 메서드 추가 (line ~223 부근)

```
<<<<<<< OLD
  // ─────────────────────────────────────────────────────────────────────────

  // ── Keepers 전용 상태 ──
=======
  // ─────────────────────────────────────────────────────────────────────────

  // ── 필터 전환 + Keepers 과금 경계 제어 ──
  void _switchFilter(String newFilter) {
    final wasKeepers = _selectedFilter == 'Keepers';
    setState(() {
      _selectedFilter = newFilter;
      _selectedDocIds.clear();
    });
    final isKeepers = newFilter == 'Keepers';
    if (isKeepers && !wasKeepers) {
      // Keepers 진입 → quarter 과금 + 오토포즈 시작
      BillingTicker.instance.setRate(BillingRate.quarter);
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('history_list');
      _resetIdleTimer();
    } else if (!isKeepers && wasKeepers) {
      // Keepers 이탈 → 과금 정지 + 오토포즈 해제
      _clearIdleTimers();
      _isIdlePaused = false;
      BillingTicker.instance.pause();
    }
  }

  // ── Keepers 전용 상태 ──
>>>>>>> NEW
```

---

## Part 3: 나머지 3모드 — 타이머 아이콘 → 과금 상태 동그라미

> 3개 파일 동일 패턴 적용

### Edit 3-1: routine_mode_free_talk.dart (line ~1932)

```
<<<<<<< OLD
                  const Icon(Icons.timer_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 6),
=======
                  ValueListenableBuilder<Color>(
                    valueListenable: BillingTicker.instance.billingDotColor,
                    builder: (_, dotColor, __) => Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
>>>>>>> NEW
```

### Edit 3-2: routine_mode_roleplay.dart (line ~2049)

```
<<<<<<< OLD
                  const Icon(Icons.timer_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 6),
=======
                  ValueListenableBuilder<Color>(
                    valueListenable: BillingTicker.instance.billingDotColor,
                    builder: (_, dotColor, __) => Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
>>>>>>> NEW
```

### Edit 3-3: routine_mode_step_expand.dart (line ~3202)

```
<<<<<<< OLD
                  const Icon(Icons.timer_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 6),
=======
                  ValueListenableBuilder<Color>(
                    valueListenable: BillingTicker.instance.billingDotColor,
                    builder: (_, dotColor, __) => Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
>>>>>>> NEW
```

---

## 검증

### Grep 카운트 확인

```bash
# ── billing_ticker: billingDotColor 정의 확인 ──
echo "=== billingDotColor 정의 (expect: 2 — 선언 + _updateDotColor 내부) ==="
grep -c 'billingDotColor' lib/custom_code/actions/billing_ticker.dart

echo "=== _updateDotColor 호출 (expect: 4 — setRate/pause/resume + 정의) ==="
grep -c '_updateDotColor' lib/custom_code/actions/billing_ticker.dart

# ── Duo: 오토포즈 완전 제거 ──
echo "=== Duo _resetIdleTimer (expect: 0) ==="
grep -c '_resetIdleTimer' lib/custom_code/widgets/routine_mode_duo.dart

echo "=== Duo _isIdlePaused (expect: 0) ==="
grep -c '_isIdlePaused' lib/custom_code/widgets/routine_mode_duo.dart

echo "=== Duo _idlePauseTimer (expect: 0) ==="
grep -c '_idlePauseTimer' lib/custom_code/widgets/routine_mode_duo.dart

echo "=== Duo _startDuoBilling 유지 (expect: ≥1) ==="
grep -c '_startDuoBilling' lib/custom_code/widgets/routine_mode_duo.dart

# ── History List: _switchFilter 추가 ──
echo "=== HistList _switchFilter (expect: ≥3) ==="
grep -c '_switchFilter' lib/custom_code/widgets/chat_history_list_master.dart

echo "=== HistList initState에 resume 없음 (expect: 0) ==="
grep -A5 'void initState' lib/custom_code/widgets/chat_history_list_master.dart | grep -c 'resume'

# ── 타이머 아이콘 교체 확인 ──
echo "=== Icons.timer_outlined 잔존 (expect: 각 0) ==="
grep -c 'Icons.timer_outlined' lib/custom_code/widgets/routine_mode_duo.dart
grep -c 'Icons.timer_outlined' lib/custom_code/widgets/routine_mode_free_talk.dart
grep -c 'Icons.timer_outlined' lib/custom_code/widgets/routine_mode_roleplay.dart
grep -c 'Icons.timer_outlined' lib/custom_code/widgets/routine_mode_step_expand.dart

echo "=== billingDotColor 사용 (expect: 각 1) ==="
grep -c 'billingDotColor' lib/custom_code/widgets/routine_mode_duo.dart
grep -c 'billingDotColor' lib/custom_code/widgets/routine_mode_free_talk.dart
grep -c 'billingDotColor' lib/custom_code/widgets/routine_mode_roleplay.dart
grep -c 'billingDotColor' lib/custom_code/widgets/routine_mode_step_expand.dart
```

### flutter analyze

```bash
flutter analyze lib/custom_code/actions/billing_ticker.dart
flutter analyze lib/custom_code/widgets/routine_mode_duo.dart
flutter analyze lib/custom_code/widgets/routine_mode_free_talk.dart
flutter analyze lib/custom_code/widgets/routine_mode_roleplay.dart
flutter analyze lib/custom_code/widgets/routine_mode_step_expand.dart
flutter analyze lib/custom_code/widgets/chat_history_list_master.dart
```

### 저장

```bash
git add -A && git commit -m "fix: Duo 오토포즈 제거 + HistList Keepers과금경계 + 과금상태 dot indicator"
```

---

## 변경 요약

| 파일 | 변경 내용 |
|---|---|
| `billing_ticker.dart` | `billingDotColor` ValueNotifier + `_updateDotColor()` 추가, resume/pause/setRate에서 색상 자동 갱신 |
| `routine_mode_duo.dart` | 오토포즈 전체 제거 (12곳) + 타이머 아이콘→동그라미 |
| `routine_mode_free_talk.dart` | 타이머 아이콘→동그라미 |
| `routine_mode_roleplay.dart` | 타이머 아이콘→동그라미 |
| `routine_mode_step_expand.dart` | 타이머 아이콘→동그라미 |
| `chat_history_list_master.dart` | initState 과금 제거 + `_switchFilter()` Keepers 경계 제어 |

### 유저 시각적 변화

| 상황 | 동그라미 색 |
|---|---|
| 대화 3모드 진입 | 🔵 파란색 (full rate 과금 중) |
| 대화 3모드 오토포즈 | ⚫ 회색 (과금 정지됨) |
| 오토포즈 해제 (탭) | 🔵 파란색 (과금 재개) |
| Duo 호스트 대기 | ⚫ 회색 (아직 과금 안 됨) |
| Duo 게스트 입장 | 🔵 파란색 (과금 시작) |
| Duo 상대 퇴장 | ⚫ 회색 (과금 정지) |

### 롤백

```bash
git log --oneline -3
git revert HEAD
```