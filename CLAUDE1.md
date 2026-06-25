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

# P2_속도선택_게이트수정_v2 — 기본선택 제거 + AI음성까지 게이트 + 칩 펄스

> 전제: `P2_속도선택_발화량팝업_v1`은 이미 적용됨(`_shadowStarted`, "속도 선택" 라벨, 칩 onTap 존재).
> 본 v2는 그 위에 얹는 **보정**. 대상 파일: `lib/custom_code/chat_history_master.dart`.

## 문제 (현재 증상)
1. 속도 칩 선택표시가 `_shadowSpeed == v` 기반 → 기본값 1.0 때문에 **"1"이 항상 선택돼 보임** (디폴트 없어야 함).
2. `_shadowStarted` 게이트가 **유저 줄(하이라이트)만** 막고, **AI 줄(`_checkAndPlayAILine`)은 즉시 재생** → "AI 소리 바로 시작".

## 목표
- 선택 전엔 **어떤 칩도 선택 표시 안 함**, 칩들이 **은은하게 펄스**(선택 유도).
- 속도 칩을 고르기 전엔 **AI 음성·유저 하이라이트 모두 시작 안 함**.
- 칩 탭 → 그 속도로 시작(첫 줄이 AI면 재생, 유저면 하이라이트). 진행 중 재탭 = 새 속도로 현재 줄 재시작.

## 변경 3건 (Box 7·P1·P3·빌링 무손상)
1. `_checkAndStartTurn`에 P2 게이트를 **맨 위로** 올려 AI/유저 모두 차단
2. `_buildSpeedChip`: `sel` 기준을 `_shadowStarted && …`로, onTap을 `_checkAndStartTurn()`로
3. `_buildSpeedChip`: 선택 전 칩에 `_blinkController` 기반 미세 스케일 펄스

---

## PHASE 0 — 세이브포인트
```bash
git add -A && git commit -m "savepoint before P2_속도선택_게이트수정_v2"
```

## PHASE 1 — 앵커 발견 (각 1건)
```bash
F=lib/custom_code/chat_history_master.dart
grep -n "// \[P2-START\] Do not start until the user chooses a speed chip." $F   # 1
grep -n "final bool sel = _shadowSpeed == v;" $F                                  # 1
grep -n "// \[P2-START\] Choosing a speed starts P2; mid-line changes restart at that speed." $F  # 1
grep -n "Widget _buildStepExpandSelectScreen() {" $F                             # 1 (EDIT 1 종료 앵커)
```
모두 1건이면 진행. 다르면 **중단·보고**.

---

## PHASE 2 — 편집 (아래 → 위)

### EDIT 3 — 칩 종료부: 선택 전 펄스 래퍼 + return (≈6690행)
**old_str**
```dart
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStepExpandSelectScreen() {
```
**new_str**
```dart
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
    // [P2-START] 아직 안 골랐으면 칩을 은은하게 펄스시켜 선택을 유도한다.
    if (_phase == ShadowingPhase.part2Practice && !_shadowStarted) {
      return AnimatedBuilder(
        animation: _blinkController,
        builder: (_, child) => Transform.scale(
          scale: 1.0 + 0.06 * _blinkController.value,
          child: child,
        ),
        child: chip,
      );
    }
    return chip;
  }

  Widget _buildStepExpandSelectScreen() {
```

### EDIT 2 — 칩 시작부: sel 기준 + onTap 라우팅 (≈6660행)
**old_str**
```dart
  Widget _buildSpeedChip(double v, String label) {
    final bool sel = _shadowSpeed == v;
    return GestureDetector(
      onTap: () {
        setState(() => _shadowSpeed = v);
        // [P2-START] Choosing a speed starts P2; mid-line changes restart at that speed.
        if (_phase == ShadowingPhase.part2Practice && !isPaused) {
          _shadowStarted = true;
          _startShadowHighlight();
        }
      },
      child: Container(
```
**new_str**
```dart
  Widget _buildSpeedChip(double v, String label) {
    // [P2-START] 선택 전(_shadowStarted=false)에는 어떤 칩도 선택 표시하지 않는다.
    final bool sel = _shadowStarted && _shadowSpeed == v;
    final Widget chip = GestureDetector(
      onTap: () {
        setState(() => _shadowSpeed = v);
        // [P2-START] 속도 선택이 시작 트리거. 진행 중 재탭은 새 속도로 현재 줄 재시작.
        if (_phase == ShadowingPhase.part2Practice && !isPaused) {
          _shadowStarted = true;
          _checkAndStartTurn(); // AI 줄이면 재생, 유저 줄이면 하이라이트
        }
      },
      child: Container(
```

### EDIT 1 — `_checkAndStartTurn`: P2 게이트를 맨 위로 (AI·유저 모두 차단) (≈743행)
**old_str**
```dart
    final line = _tutorLines[currentIndex];
    final bool isAiTurn = _isAiTurn(line); // 🆕 [BOX-32]
    if (isAiTurn) {
      _checkAndPlayAILine();
    } else if (_phase == ShadowingPhase.part2Practice) {
      // [P2-START] Do not start until the user chooses a speed chip.
      if (_shadowStarted) _startShadowHighlight(); // [P2-SHADOW]
    } else {
```
**new_str**
```dart
    // [P2-START] 속도를 고르기 전엔 AI 줄·유저 줄 모두 시작하지 않는다.
    if (_phase == ShadowingPhase.part2Practice && !_shadowStarted) return;
    final line = _tutorLines[currentIndex];
    final bool isAiTurn = _isAiTurn(line); // 🆕 [BOX-32]
    if (isAiTurn) {
      _checkAndPlayAILine();
    } else if (_phase == ShadowingPhase.part2Practice) {
      _startShadowHighlight(); // [P2-SHADOW]
    } else {
```

---

## PHASE 3 — 검증
```bash
F=lib/custom_code/chat_history_master.dart
grep -c "final bool sel = _shadowStarted && _shadowSpeed == v;" $F                       # 1
grep -c "if (_phase == ShadowingPhase.part2Practice && !_shadowStarted) return;" $F      # 1
grep -c "_checkAndStartTurn(); // AI 줄이면" $F                                           # 1
grep -c "0.06 \* _blinkController.value" $F                                              # 1
grep -c "final bool sel = _shadowSpeed == v;" $F                                         # 기대 0 (구버전 제거)
grep -c "if (_shadowStarted) _startShadowHighlight();" $F                                # 기대 0 (게이트가 위로 이동)
```
이어서:
```bash
flutter analyze lib/custom_code/chat_history_master.dart
dart format lib/custom_code/chat_history_master.dart   # ⚠️ 개별 파일만, 폴더 금지
```

---

## 기대 동작 (적용 후)
1. P2 진입 → **어떤 속도도 선택 안 됨**, 0.8/1/1.2 칩이 **은은히 펄스**. 화면은 조용함(AI 음성 X).
2. 유저가 칩 하나 탭 → 그 속도로 시작. 첫 줄이 AI면 재생 후 자동으로 유저 줄 하이라이트.
3. 펄스는 선택 즉시 멈추고, 고른 칩만 앰버로 강조.
4. 진행 중 다른 속도 탭 → 새 속도로 현재 줄 재시작.

> 재탭 동작을 "현재 줄 재시작" 말고 "속도만 바꾸고 이어가기"로 원하면 EDIT 2의 `_checkAndStartTurn()`만 조정하면 됩니다(알려주세요).

## 롤백
```bash
git reset --hard HEAD~1        # push 전
# 또는
git revert <savepoint_해시>    # push 후
```