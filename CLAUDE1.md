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

# P2 하이라이트 형광펜 + 속도 선택 세그먼트 토글 지시서

**대상 파일:** `lib/custom_code/widgets/chat_history_master.dart`
**목적:**
1. P2 따라읽기 하이라이트에서 **글자 크기·굵기 변동으로 줄바꿈이 들썩이는 현상 제거** → 크기/굵기 완전 고정, 현재 단어에 형광펜 배경박스만 표시 (`Text.rich`/`TextSpan` 단일 런)
2. **속도 선택 메뉴를 P1/P2/P3 알약과 확연히 다른 "이어진 세그먼트 토글 바"로 교체**
3. **"속도 선택" 글자를 깜박이게** (속도를 고르기 전까지만 깜박, 고르면 멈춤)

**불변(절대 손대지 않음):** Box 7 / P1 / P3(chunkPractice) / turnPractice / 빌링 / Firestore.
모든 변경은 `_phase == ShadowingPhase.part2Practice` 경로에만 영향.

---

## Phase 0 — 세이브포인트 (필수, 먼저 실행)

```bash
cd F:\flutter_project\stealth_vox
git add -A
git commit -m "savepoint: P2 하이라이트/속도선택 UI 수정 전"
```

> 이미 push된 상태에서 되돌리려면 마지막에 `git revert <hash>`.

---

## Phase 1 — 발견(grep) : 수정 전 카운트 확인

```bash
cd F:\flutter_project\stealth_vox

grep -nc "_buildSpeedChip"            lib/custom_code/widgets/chat_history_master.dart   # 기대: 4 (정의1 + 호출3)
grep -nc "_buildSpeedSegment"         lib/custom_code/widgets/chat_history_master.dart   # 기대: 0
grep -n  "return Wrap("               lib/custom_code/widgets/chat_history_master.dart   # P2 하이라이트 분기 위치 확인
grep -nc "Text.rich"                  lib/custom_code/widgets/chat_history_master.dart   # 기존 개수 기록 (변경 후 +1 되어야 함)
grep -n  "_buildShadowSpeedSelector"  lib/custom_code/widgets/chat_history_master.dart   # 기대: 2 (정의1 + 호출1)
```

`return Wrap(` 위치가 `_buildPracticeLineText`(약 4520~4557줄) 안의 `if (isShadowLine && _shadowWords.isNotEmpty)` 분기인지 눈으로 확인. 다른 `Wrap`도 있을 수 있으므로 **반드시 `_shadowWords` 가 가까이 있는 그 블록**을 수정 대상으로 삼는다.

---

## Phase 2 — 수정 (str_replace, 아래→위 순서로 적용)

> 라인 드리프트 방지를 위해 **편집 A(아래) → 편집 B → 편집 C(위)** 순서로 적용한다.

---

### 편집 A — `_buildSpeedChip` 함수 전체를 `_buildSpeedSegment`로 교체

세그먼트 한 칸. 첫/끝 칸만 모서리를 둥글게 한다.

**find (old_str):**
```dart
  Widget _buildSpeedChip(double v, String label) {
    // [P2-START] Before choosing a speed, no chip should look selected.
    final bool sel = _shadowStarted && _shadowSpeed == v;
    final Widget chip = GestureDetector(
      onTap: () {
        setState(() => _shadowSpeed = v);
        // [P2-START] Speed selection triggers start; mid-line changes restart current turn.
        if (_phase == ShadowingPhase.part2Practice && !isPaused) {
          _shadowStarted = true;
          _checkAndStartTurn(); // AI line plays, user line highlights.
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        decoration: BoxDecoration(
          color: sel
              ? Colors.amber.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: sel ? Colors.amber.withValues(alpha: 0.7) : Colors.white24,
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.amber : Colors.white54,
            fontSize: 12,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
    // [P2-START] Before selection, gently pulse chips to invite choosing one.
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
```

**replace (new_str):**
```dart
  // [P2-SHADOW] One cell of the connected segmented speed toggle bar.
  Widget _buildSpeedSegment(double v, String label,
      {bool first = false, bool last = false}) {
    // [P2-START] Before choosing a speed, no cell should look selected.
    final bool sel = _shadowStarted && _shadowSpeed == v;
    return GestureDetector(
      onTap: () {
        setState(() => _shadowSpeed = v);
        // [P2-START] Speed selection triggers start; mid-line changes restart current turn.
        if (_phase == ShadowingPhase.part2Practice && !isPaused) {
          _shadowStarted = true;
          _checkAndStartTurn(); // AI line plays, user line highlights.
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color:
              sel ? Colors.amber.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(first ? 15 : 0),
            right: Radius.circular(last ? 15 : 0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? Colors.amber : Colors.white54,
            fontSize: 13,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
```

---

### 편집 B — `_buildShadowSpeedSelector` 함수 전체 교체 (세그먼트 바 + 깜박이는 라벨)

**find (old_str):**
```dart
  // [P2-SHADOW] Top speed selector. Larger values read faster.
  Widget _buildShadowSpeedSelector() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.speed, color: Colors.white54, size: 15),
          const SizedBox(width: 5),
          const Text(
            "\uC18D\uB3C4 \uC120\uD0DD", // 속도 선택
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 10),
          _buildSpeedChip(0.8, "0.8"),
          const SizedBox(width: 6),
          _buildSpeedChip(1.0, "1"),
          const SizedBox(width: 6),
          _buildSpeedChip(1.2, "1.2"),
        ],
      ),
    );
  }
```

**replace (new_str):**
```dart
  // [P2-SHADOW] Top speed selector — connected segmented toggle bar.
  // Larger values read faster. Label blinks until a speed is chosen.
  Widget _buildShadowSpeedSelector() {
    const Color divider = Colors.white24;
    final bool blink = !_shadowStarted; // [P2] Blink label until speed chosen.
    final Widget label = Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.speed, color: Colors.white54, size: 15),
        SizedBox(width: 5),
        Text(
          "\uC18D\uB3C4 \uC120\uD0DD", // 속도 선택
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          blink
              ? AnimatedBuilder(
                  animation: _blinkController,
                  builder: (_, child) =>
                      Opacity(opacity: _blinkOpacity.value, child: child),
                  child: label,
                )
              : label,
          const SizedBox(width: 12),
          // [P2] Connected segmented bar — visually distinct from P1/P2/P3 pills.
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: divider, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSpeedSegment(0.8, "0.8", first: true),
                Container(width: 1, height: 22, color: divider),
                _buildSpeedSegment(1.0, "1"),
                Container(width: 1, height: 22, color: divider),
                _buildSpeedSegment(1.2, "1.2", last: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
```

---

### 편집 C — P2 하이라이트 분기를 `Text.rich`(형광펜 배경박스)로 교체

크기/굵기를 모든 단어에 동일하게 고정 → 폭 불변 → 줄바꿈 영원히 안정.
현재 단어에만 `background: Paint()`로 형광펜 박스. 단어 사이 공백은 배경 없는 별도 span.

**find (old_str):**
```dart
    if (isShadowLine && _shadowWords.isNotEmpty) {
      return Wrap(
        alignment: WrapAlignment.start,
        spacing: 6,
        runSpacing: 2,
        children: List.generate(_shadowWords.length, (j) {
          final bool done = j < _shadowWordIdx;
          final bool now = j == _shadowWordIdx;
          return Text(
            _shadowWords[j],
            style: TextStyle(
              color:
                  now ? Colors.amber : (done ? Colors.white38 : Colors.white),
              fontSize: (now ? 15 : 14) * _fontScale,
              height: 1.5,
              fontWeight: now ? FontWeight.bold : FontWeight.normal,
            ),
          );
        }),
      );
    }
```

**replace (new_str):**
```dart
    if (isShadowLine && _shadowWords.isNotEmpty) {
      // [P2-SHADOW] Single Text.rich run. Fixed size/weight for every word so
      // wrapping NEVER shifts. Current word gets a highlighter-style box only.
      final Paint hl = Paint()
        ..color = Colors.amber.withValues(alpha: 0.35)
        ..strokeJoin = StrokeJoin.round;
      return Text.rich(
        TextSpan(
          children: [
            for (int j = 0; j < _shadowWords.length; j++) ...[
              TextSpan(
                text: _shadowWords[j],
                style: TextStyle(
                  color: j == _shadowWordIdx
                      ? Colors.white
                      : (j < _shadowWordIdx ? Colors.white38 : Colors.white),
                  background: j == _shadowWordIdx ? hl : null,
                ),
              ),
              if (j != _shadowWords.length - 1) const TextSpan(text: ' '),
            ],
          ],
        ),
        style: TextStyle(
          fontSize: 14 * _fontScale,
          height: 1.5,
          fontWeight: FontWeight.normal,
        ),
      );
    }
```

---

## Phase 3 — 검증 (grep, 기대 카운트 대조)

```bash
cd F:\flutter_project\stealth_vox
set F=lib/custom_code/widgets/chat_history_master.dart

grep -nc "_buildSpeedChip"           %F%   # 기대: 0  (완전 제거)
grep -nc "_buildSpeedSegment"        %F%   # 기대: 4  (정의1 + 호출3)
grep -nc "_buildShadowSpeedSelector" %F%   # 기대: 2  (정의1 + 호출1, 변동 없음)
grep -nc "_blinkOpacity.value"       %F%   # 기대: 기존값 +1
grep -n  "background: j == _shadowWordIdx ? hl : null" %F%   # 기대: 1줄 (하이라이트 적용 확인)
grep -nc "return Wrap("              %F%   # P2 분기의 Wrap 제거 확인 (다른 Wrap이 있다면 그 개수만큼만 남아야 함)
```

> macOS/리눅스 셸이면 `%F%` 대신 변수 없이 파일 경로를 직접 넣거나 `F=...; grep ... "$F"` 사용.

---

## Phase 4 — 정적 분석 & 포맷 (게이트)

```bash
flutter analyze lib/custom_code/widgets/chat_history_master.dart
dart format lib/custom_code/widgets/chat_history_master.dart
```

- `flutter analyze`에 **새 에러/경고가 없어야** 통과.
- `dart format`은 **반드시 이 파일 하나만** 대상으로 (폴더 전체 금지 — 한글 문자열 깨짐 방지).

---

## Phase 5 — 런타임 확인 체크리스트 (P2 화면)

1. P2 진입 → "속도 선택" 글자가 깜박인다(opacity 0.3↔1.0).
2. 속도 바가 P1/P2/P3 알약과 다른 **하나로 이어진 막대**(가운데 구분선 2개)로 보인다.
3. 속도 한 칸을 누르면 → 글자 깜박임이 멈추고, 누른 칸만 amber로 채워진다.
4. 사용자 라인 따라읽기 시작 → 현재 단어에 **형광펜 노란 박스**가 칠해지며 단어가 이동.
5. 하이라이트가 지나가는 동안 **글자 크기 그대로, 줄바꿈 들썩임 없음** (캡처의 three/kilograms 깨짐 현상 사라짐).
6. 폰트 크기 토글(`_fontScale`)을 바꿔도 P2 하이라이트 줄바꿈 안정 유지.
7. P1 / P3 / turnPractice / 빌링 동작 이상 없음(회귀 없음).

---

## 롤백

```bash
# 아직 push 전:
git reset --hard HEAD~1

# 이미 push 후:
git revert <savepoint_커밋_hash>
```