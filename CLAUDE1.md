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

# StealthVox 오토포즈 "한 줄 가드" 수정 지시문

## 목표
묻힌(스택 아래에 깔린) 페이지가 자기 idle 타이머로 공유 싱글톤 `BillingTicker`를
pause시키는 버그를 막는다.

방법: 각 페이지의 idle 핸들러 맨 위에 **"내가 최상단 active route인가?"** 가드 한 줄만 추가한다.
플래그(`_isPageActive` 등) 신규 추가 없음, 이동부(`pushNamed`) 수정 없음.

## 원리
`ModalRoute.of(context)?.isCurrent`는 이 페이지가 Navigator 최상단일 때만 true.
다른 페이지가 위에 push되면 false → idle 누적을 멈추고 빠져나가므로 절대 60초에
도달하지 못함 → `BillingTicker.pause()` 호출 자체가 일어나지 않는다.
복귀하면 다시 true → 정상 누적. 앞으로 어디서 push를 추가해도 자동으로 안전.

`isCurrent`가 null이면 `null == false`는 false라 가드가 발동하지 않음(기존 동작 유지) → fail-safe.

---

## 절대 건드리지 말 것 (CRITICAL)
- **Box 7 통신 엔진**: `TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`,
  `_AudioDiskCache`, `TtsCache` 등 — 한 글자도 수정 금지.
- `_idleTick` / `_handleIdlePause`의 **기존 로직(나머지 줄)은 그대로**. 가드 한 블록만 "삽입".
- 이동부(`context.pushNamed(...)`) 코드는 **수정하지 않는다**.
- `import` 추가 불필요 (`ModalRoute`는 이미 import된 material에 포함).

---

## 수정 내용

### 그룹 A — history 2개 파일 (`_idleTick`, 주석 없는 버전)

**대상**
- `chat_history_list_master.dart` : `_idleTick()` (시작 줄 72, `if (!mounted) return;`는 73줄)
- `chat_history_master.dart`      : `_idleTick()` (시작 줄 215, `if (!mounted) return;`는 216줄)

**작업**: `if (!mounted) return;` 바로 다음 줄에 가드 블록 삽입.

**교체 후 `_idleTick()` 전체 (이 모양이 되어야 함):**
```dart
  void _idleTick() {
    if (!mounted) return;
    // 🔒 [오토포즈 가드] 최상단 active route가 아니면(다른 페이지가 위에) idle 누적 금지
    if (ModalRoute.of(context)?.isCurrent == false) {
      _idleElapsedSec = 0;
      return;
    }
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
```

---

### 그룹 B — study 3개 파일 (`_idleTick`, `// 유저나 AI가...` 주석 있는 버전)

**대상**
- `routine_mode_clone.dart`       : `_idleTick()` (시작 줄 97,  `if (!mounted) return;`는 98줄)
- `routine_mode_roleplay.dart`    : `_idleTick()` (시작 줄 307, `if (!mounted) return;`는 308줄)
- `routine_mode_step_expand.dart` : `_idleTick()` (시작 줄 96,  `if (!mounted) return;`는 97줄)

**작업**: `if (!mounted) return;` 바로 다음 줄에 가드 블록 삽입.
(기존 `// 유저나 AI가 작동 중이면...` 주석과 그 아래 `_isSystemBusy` 블록은 그대로 둘 것.)

**교체 후 `_idleTick()` 전체 (이 모양이 되어야 함):**
```dart
  void _idleTick() {
    if (!mounted) return;
    // 🔒 [오토포즈 가드] 최상단 active route가 아니면(다른 페이지가 위에) idle 누적 금지
    if (ModalRoute.of(context)?.isCurrent == false) {
      _idleElapsedSec = 0;
      return;
    }
    if (_isIdlePaused) return;
    // 유저나 AI가 작동 중이면 idle 누적을 멈추고 리셋
    if (_isSystemBusy) {
      _idleElapsedSec = 0;
      return;
    }
    _idleElapsedSec++;
    if (_idleElapsedSec >= 60) {
      _handleIdlePause();
    }
  }
```

---

### Duo — `routine_mode_duo.dart` (구조 다름: 60초 단발 Timer)

Duo는 1초 tick 방식이 아니라 `Timer(60s, _handleIdlePause)` 단발 방식이라
`_idleTick`이 없다. 가드는 `_handleIdlePause()`에 넣는다.

**대상**: `_handleIdlePause()` (시작 줄 191, `if (!mounted || _isIdlePaused) return;`는 192줄)

**작업**: `if (!mounted || _isIdlePaused) return;` 바로 다음 줄에 가드 블록 삽입.

**교체 후 `_handleIdlePause()` 전체 (이 모양이 되어야 함):**
```dart
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
```

---

## 검증 체크리스트

1. **컴파일**: `flutter analyze` → 에러 0개.

2. **삽입 확인 (각 파일 isCurrent가 정확히 1개):**
   ```
   grep -c "isCurrent" chat_history_list_master.dart   # 1
   grep -c "isCurrent" chat_history_master.dart         # 1
   grep -c "isCurrent" routine_mode_clone.dart          # 1
   grep -c "isCurrent" routine_mode_roleplay.dart       # 1
   grep -c "isCurrent" routine_mode_step_expand.dart    # 1
   grep -c "isCurrent" routine_mode_duo.dart            # 1
   ```

3. **위치 확인 (가드가 mounted 체크 바로 아래에 있는지):**
   ```
   grep -nA1 "if (!mounted) return;" routine_mode_step_expand.dart   # 다음 줄에 🔒 주석
   grep -nA1 "_isIdlePaused) return;" routine_mode_duo.dart          # 다음 줄에 🔒 주석
   ```

4. **Box 7 무수정 확인:**
   ```
   grep -c "TtsQueueManager\|DeepgramV2VoiceManager" routine_mode_step_expand.dart
   ```
   (수정 전후 동일해야 함)

---

## 테스트 시나리오 (수정 후 실기기/에뮬)

1. **History List → Detail → Practice → 복귀 (핵심)**
   - Practice 화면에서 60초 이상 머물러도 뒤의 List가 과금을 pause시키면 실패.
   - 리스트로 복귀했을 때 pause 아이콘/오버레이가 보이면 실패.
   - 복귀 후 정상 quarter resume이면 성공.

2. **History List에서 아무 조작 없이 60초 방치**
   - 이때만 오토포즈가 걸리면 성공.

3. **Roleplay / Clone / Step Expand**
   - AI 발화 중 / 유저 녹음 중 오토포즈 금지.
   - 아무 조작 없이 60초 방치하면 오토포즈 성공.

4. **Duo**
   - 게스트 입장 후 60초 무반응 → 오토포즈 성공 (기존 `_billingStarted` 가드 유지 확인).

---

## 롤백
삽입한 가드 블록(🔒 주석 + `if (ModalRoute.of(context)?.isCurrent == false) { ... }`)
6곳을 삭제하면 원상 복구. 다른 줄은 건드리지 않았으므로 블록 제거만으로 완전 롤백.

## 알려진 전제
go_router `pushNamed`가 새 route를 push해 이전 route의 `isCurrent`를 false로 만든다는
동작에 의존한다. 테스트 시나리오 1번이 깨지면(여전히 pause됨) `isCurrent`가 이 라우팅
구성에서 안 먹는 것이므로, 명시적 `_isPageActive` 플래그 방식으로 폴백한다.