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

# P2_속도선택_발화량팝업_v1 — History Expand P2 동작 변경

대상 파일: `lib/custom_code/chat_history_master.dart` (단일 파일)
영향 범위: **P2(`part2Practice`) 전용.** Box 7·P1·P3·turnPractice·빌링·History 재생 무손상.

## 변경 요약
1. **(A) 라벨**: "속도" → "속도 선택"
2. **(B) 시작 게이트**: P2 진입 시 자동 시작 제거 → **속도 칩(0.8/1/1.2) 탭이 시작 트리거**
3. **(C) 발화량 50% 팝업**: 녹음 중 진폭 폴링으로 발화 비율 계산 → **50% 미만이면 "다시 말하기 / 다음 진행" 아이콘 팝업**, 다시 말하기 **3회까지**, 초과 시 자동 진행
   - 측정 = **무료 프록시**(진폭 `getAmplitude() > -25dBFS` 틱 비율, 기존 VAD 임계 재사용). **Whisper·과금 추가 없음.**

> ⚠️ Box 7 클래스(`TtsQueueManager`/`DeepgramV2VoiceManager`/`ChunkedTtsFetcher`/`HybridTtsPlayer`/`TtsCache`) 수정 금지. 본 작업은 `_ChatHistoryMasterState` 내부 메서드/상태만 변경.

---

## PHASE 0 — 세이브포인트
```bash
git add -A && git commit -m "savepoint before P2_속도선택_발화량팝업_v1"
```

## PHASE 1 — 앵커 발견 (편집 전 각 1건 확인)
```bash
grep -n 'double _shadowSpeed = 1.0; // \[P2-SHADOW\]' lib/custom_code/chat_history_master.dart   # 1
grep -n 'onTap: () => setState(() => _shadowSpeed = v),' lib/custom_code/chat_history_master.dart  # 1
grep -n '_shadowAdvanceTimer = Timer(const Duration(milliseconds: 1500)' lib/custom_code/chat_history_master.dart  # 1
grep -n "debugPrint('\[startShadowRecording\] \$e');" lib/custom_code/chat_history_master.dart    # 1
grep -n '_startShadowHighlight(); // \[P2-SHADOW\]' lib/custom_code/chat_history_master.dart        # 1 (in _checkAndStartTurn)
```
다섯 앵커 모두 1건이면 진행. 다르면 **중단·보고**.

---

## PHASE 2 — 편집 (아래 → 위 순서)

### EDIT 7 — 속도 칩 onTap: 시작 트리거화 (≈6520행)
**old_str**
```dart
    return GestureDetector(
      onTap: () => setState(() => _shadowSpeed = v),
      child: Container(
```
**new_str**
```dart
    return GestureDetector(
      onTap: () {
        setState(() => _shadowSpeed = v);
        // [P2-START] 속도 선택이 시작 트리거. 진행 중 재탭은 새 속도로 현재 줄 재시작.
        if (_phase == ShadowingPhase.part2Practice && !isPaused) {
          _shadowStarted = true;
          _startShadowHighlight();
        }
      },
      child: Container(
```

### EDIT 6 — 라벨 "속도" → "속도 선택" (≈6503행)
**old_str**
```dart
          const Text(
            "\uC18D\uB3C4",
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
```
**new_str**
```dart
          const Text(
            "\uC18D\uB3C4 \uC120\uD0DD", // 속도 선택
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
```

### EDIT 5 — P2 진입 리셋: 시작 게이트/카운터 초기화 (≈5950행)
**old_str**
```dart
        _shadowWords = []; // [P2-SHADOW]
        _shadowWordIdx = -1; // [P2-SHADOW]
        _shadowSpeed = 1.0; // [P2-SHADOW]
      });
```
**new_str**
```dart
        _shadowWords = []; // [P2-SHADOW]
        _shadowWordIdx = -1; // [P2-SHADOW]
        _shadowSpeed = 1.0; // [P2-SHADOW]
        _shadowStarted = false; // [P2-START] 속도 선택 대기 상태로 진입
        _shadowRereadCount = 0; // [P2-PROXY]
      });
```

### EDIT 4 — `_stopShadowRecording` 뒤에 평가/팝업 메서드 신설 (≈866행)
**old_str**
```dart
    _shadowRecordLineIdx = -1;
  }

  Future<void> _checkAndPlayAILine() async {
```
**new_str**
```dart
    _shadowRecordLineIdx = -1;
  }

  // [P2-PROXY] 녹음 종료 + 발화량(진폭) 50% 판정.
  //   ratio = 발화 틱 / 전체 틱. 50% 미만이고 다시읽기 3회 미만이면 팝업,
  //   그 외(통과 또는 3회 초과)는 다음으로 진행.
  Future<void> _stopShadowRecordingAndEvaluate() async {
    _shadowAmpTimer?.cancel();
    final double ratio =
        _shadowTotalTicks == 0 ? 0.0 : _shadowVoicedTicks / _shadowTotalTicks;
    await _stopShadowRecording();
    if (!mounted || _phase != ShadowingPhase.part2Practice || isPaused) return;
    if (ratio < 0.5 && _shadowRereadCount < 3) {
      _showShadowRetryDialog();
    } else {
      _shadowRereadCount = 0;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _phase == ShadowingPhase.part2Practice && !isPaused) {
          _nextTurn();
        }
      });
    }
  }

  // [P2-PROXY] 발화량 부족 시 아이콘 팝업: 다시 말하기 / 다음 진행
  void _showShadowRetryDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2E1C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "\uC870\uAE08 \uB354 \uD06C\uAC8C \uC77D\uC5B4\uBCFC\uAE4C\uC694?", // 조금 더 크게 읽어볼까요?
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 다시 말하기
                GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _shadowRereadCount++;
                    if (mounted &&
                        _phase == ShadowingPhase.part2Practice &&
                        !isPaused) {
                      _startShadowHighlight();
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.replay_rounded, color: Colors.amber, size: 34),
                      SizedBox(height: 6),
                      Text("\uB2E4\uC2DC \uB9D0\uD558\uAE30", // 다시 말하기
                          style: TextStyle(color: Colors.amber, fontSize: 12)),
                    ],
                  ),
                ),
                // 다음 진행
                GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _shadowRereadCount = 0;
                    if (mounted &&
                        _phase == ShadowingPhase.part2Practice &&
                        !isPaused) {
                      _nextTurn();
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.arrow_forward_rounded,
                          color: Colors.greenAccent, size: 34),
                      SizedBox(height: 6),
                      Text("\uB2E4\uC74C \uC9C4\uD589", // 다음 진행
                          style:
                              TextStyle(color: Colors.greenAccent, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkAndPlayAILine() async {
```

### EDIT 3 — `_stepShadowHighlight` 종료 분기: 자동진행 → 판정으로 교체 (≈794행)
**old_str**
```dart
    if (idx >= _shadowWords.length) {
      if (mounted) setState(() => _shadowWordIdx = _shadowWords.length);
      Future.delayed(
        const Duration(milliseconds: 700),
        () => _stopShadowRecording(),
      );
      _shadowAdvanceTimer?.cancel();
      _shadowAdvanceTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && _phase == ShadowingPhase.part2Practice && !isPaused) {
          _nextTurn();
        }
      });
      return;
    }
```
**new_str**
```dart
    if (idx >= _shadowWords.length) {
      if (mounted) setState(() => _shadowWordIdx = _shadowWords.length);
      // [P2-PROXY] 700ms 후 녹음 종료 + 발화량 판정 → 통과/3회초과면 진행, 아니면 팝업
      _shadowAdvanceTimer?.cancel();
      _shadowAdvanceTimer = Timer(const Duration(milliseconds: 700), () async {
        if (!mounted || _phase != ShadowingPhase.part2Practice || isPaused) {
          return;
        }
        await _stopShadowRecordingAndEvaluate();
      });
      return;
    }
```

### EDIT 2 — `_startShadowRecording`: 진폭 폴링 추가 (≈845행)
**old_str**
```dart
      _shadowRecording = true;
      _shadowRecordLineIdx = lineIdx;
    } catch (e) {
      debugPrint('[startShadowRecording] $e');
```
**new_str**
```dart
      _shadowRecording = true;
      _shadowRecordLineIdx = lineIdx;
      // [P2-PROXY] 녹음 중 100ms마다 진폭 폴링 → 발화 틱 비율 누적
      _shadowVoicedTicks = 0;
      _shadowTotalTicks = 0;
      _shadowAmpTimer?.cancel();
      _shadowAmpTimer =
          Timer.periodic(const Duration(milliseconds: 100), (t) async {
        if (!mounted || !_shadowRecording) {
          t.cancel();
          return;
        }
        try {
          if (await appAudioRecorder.isRecording()) {
            final amp = await appAudioRecorder.getAmplitude();
            _shadowTotalTicks++;
            if (amp.current > -25.0) _shadowVoicedTicks++; // VAD와 동일 임계
          }
        } catch (_) {
          t.cancel();
        }
      });
    } catch (e) {
      debugPrint('[startShadowRecording] $e');
```

### EDIT 1 — `_checkAndStartTurn`: 자동 시작 게이트 (≈740행)
**old_str**
```dart
    } else if (_phase == ShadowingPhase.part2Practice) {
      _startShadowHighlight(); // [P2-SHADOW]
    } else {
```
**new_str**
```dart
    } else if (_phase == ShadowingPhase.part2Practice) {
      // [P2-START] 속도를 고르기 전엔 시작하지 않는다. 칩 탭에서 시작.
      if (_shadowStarted) _startShadowHighlight(); // [P2-SHADOW]
    } else {
```

### EDIT 0 — 상태 필드 신설 (≈134행)
**old_str**
```dart
  double _shadowSpeed = 1.0; // [P2-SHADOW] 0.8/1.0/1.2, larger is faster.
```
**new_str**
```dart
  double _shadowSpeed = 1.0; // [P2-SHADOW] 0.8/1.0/1.2, larger is faster.
  // [P2-START] 속도 선택 전에는 시작하지 않는다 (속도 칩 탭이 시작 트리거).
  bool _shadowStarted = false;
  // [P2-PROXY] 발화량(진폭) 프록시 — Whisper 없이 50% 판정. 다시읽기 최대 3회.
  Timer? _shadowAmpTimer;
  int _shadowVoicedTicks = 0;
  int _shadowTotalTicks = 0;
  int _shadowRereadCount = 0;
```

---

## PHASE 3 — 검증 (기대 카운트)
```bash
F=lib/custom_code/chat_history_master.dart
grep -c "_shadowStarted" $F                    # 기대 4 (선언1+진입1+게이트1+칩1)
grep -c "_shadowAmpTimer" $F                   # 기대 4 (선언1 + start 2 + evaluate 1)
grep -c "_shadowVoicedTicks" $F                # 기대 3 (선언1 + start초기화1 + 증가1)
grep -c "_shadowTotalTicks" $F                 # 기대 4 (선언1 + start초기화1 + 증가1 + ratio1)
grep -c "_shadowRereadCount" $F                # 기대 6 (선언1+진입1+evaluate2+dialog2)
grep -c "_stopShadowRecordingAndEvaluate" $F   # 기대 2 (정의1+호출1)
grep -c "_showShadowRetryDialog" $F            # 기대 2 (정의1+호출1)
grep -n "uC18D.uB3C4 .uC120.uD0DD" $F          # 라벨 "속도 선택" 1건
grep -c "Timer(const Duration(milliseconds: 1500)" $F  # 기대 0 (구 자동진행 제거됨)
```
이어서:
```bash
flutter analyze lib/custom_code/chat_history_master.dart
dart format lib/custom_code/chat_history_master.dart   # ⚠️ 개별 파일만, 폴더 금지
```

---

## 기대 동작 (적용 후)
1. P2 진입 → 자동 시작 안 함. 상단에 **"속도 선택" + 0.8/1/1.2** 표시.
2. 칩 하나 탭 → 그 속도로 하이라이트 따라읽기 시작(+녹음).
3. 한 줄 끝 → 발화량 비율 계산. **≥50%면 800ms 후 자동 다음 줄**, **<50%면 팝업**.
4. 팝업: **다시 말하기**(같은 줄 재실행, 최대 3회) / **다음 진행**(즉시 다음). 4번째 실패 시 자동 진행.
5. 여러 줄이면 속도는 처음 한 번만 고르고 이후 줄은 동일 속도로 자동 진행.

## 비용/빌링
- Whisper STT **추가 없음** → P2 API 비용 0 추가. 진폭 폴링은 로컬. **빌링 로직 무변경.**

## 롤백
```bash
git reset --hard HEAD~1        # push 전
# 또는
git revert <savepoint_해시>    # push 후
```

## 참고 (낡은 주석)
129행·752행의 `// ... P2 only, no recording` 주석은 실제와 불일치(녹음함). EDIT와 무관하나, 원하면 752행 헤더를 `// [P2-SHADOW] Highlight read-along. (녹음 + 발화량 프록시 판정 포함)` 로 정정 가능.