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

# 지시문: 인트로 A/B 구조 + SharedPreferences 체험 게이트 단순화

## 목적
체험 완료 여부를 SharedPreferences `trialCompleted` 하나로 판단하여,
인트로 A(체험+로그인)와 인트로 B(로그인만)를 분기한다.
TrialDeviceGate(Firebase Installations ID)를 완전 제거한다.

## 흐름도
```
앱 실행
  → FirebaseAuth.currentUser != null (비익명)? → Yes → 로비 직행
  → No → FFAppState().trialCompleted?
    → false (또는 키 없음) → 인트로 A (체험 버튼 + 로그인 버튼)
    → true → 인트로 B (로그인 버튼만, 뒤로가기 버튼 없음)
```

앱 삭제→재설치 시 SharedPreferences 초기화 → trialCompleted 소실 → 체험 재허용 (의도된 동작).

---

## Phase 0 — Git Savepoint

```powershell
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before intro-ab-simplification"
```

---

## Phase 1 — 사전 grep 앵커 확인

아래 각 grep 결과가 기대값과 다르면 **즉시 중단하고 보고**.

### 1-1. consumeSignupOnEntry 선언 (trial_flow_state.dart)
```powershell
(Select-String -Path "lib\custom_code\widgets\trial\trial_flow_state.dart" -Pattern "consumeSignupOnEntry" | Measure-Object).Count
```
→ 기대값: 2 (메서드 선언 + bool 반환)

### 1-2. requestSignupOnEntry 호출처 (전체 프로젝트)
```powershell
Select-String -Path "lib\custom_code\widgets\*.dart" -Pattern "requestSignupOnEntry" -Recurse
```
→ 파일명과 라인 번호 모두 기록. 최소 1곳 (trial_flow_state.dart 외부 호출처).
→ 이 호출을 Phase 2에서 `FFAppState().trialCompleted = true;`로 교체해야 함.

### 1-3. TrialDeviceGate 전체 참조
```powershell
Select-String -Path "lib\**\*.dart" -Pattern "TrialDeviceGate" -Recurse
```
→ 모든 파일명·라인 기록. Phase 2에서 전부 제거.

### 1-4. _forceSignupOnEntry 참조
```powershell
(Select-String -Path "lib\custom_code\widgets\trial\trial_flow_state.dart" -Pattern "_forceSignupOnEntry" | Measure-Object).Count
```
→ 기대값: 3 (선언, requestSignupOnEntry 내, consumeSignupOnEntry 내)

### 1-5. intro_master.dart 앵커 확인
```powershell
(Select-String -Path "lib\custom_code\widgets\intro_master.dart" -Pattern "consumeSignupOnEntry" | Measure-Object).Count
```
→ 기대값: 1

```powershell
(Select-String -Path "lib\custom_code\widgets\intro_master.dart" -Pattern "trial_device_gate" | Measure-Object).Count
```
→ 기대값: 1 (import 문)

```powershell
(Select-String -Path "lib\custom_code\widgets\intro_master.dart" -Pattern "TrialDeviceGate" | Measure-Object).Count
```
→ 기대값: 3 (canTrial, snackbar 분기, markUsed)

### 1-6. app_state.dart trialStep 앵커
```powershell
(Select-String -Path "lib\app_state.dart" -Pattern "ff_trialStep" | Measure-Object).Count
```
→ 기대값: 2 (initializePersistedState + setter)

### 1-7. trial_device_gate.dart 존재 확인
```powershell
Test-Path "lib\custom_code\widgets\trial\trial_device_gate.dart"
```
→ 기대값: True

---

## Phase 2 — 코드 수정

⚠️ 각 파일 내 편집은 반드시 **아래→위(bottom-to-top)** 순서로 적용.
⚠️ Box 7 절대 수정 금지.
⚠️ `lib/custom_code/임시/` 폴더 수정 금지.
⚠️ `dart format`은 개별 파일 단위로만 실행.

---

### 2-1. app_state.dart — trialCompleted 필드 추가

#### 2-1a. setter/getter 추가 (trialHistoryPath 블록 바로 아래)

```
str_replace
파일: lib\app_state.dart

OLD:
  String _trialHistoryPath = '';
  String get trialHistoryPath => _trialHistoryPath;
  set trialHistoryPath(String value) {
    _trialHistoryPath = value;
    prefs.setString('ff_trialHistoryPath', value);
  }

NEW:
  String _trialHistoryPath = '';
  String get trialHistoryPath => _trialHistoryPath;
  set trialHistoryPath(String value) {
    _trialHistoryPath = value;
    prefs.setString('ff_trialHistoryPath', value);
  }

  bool _trialCompleted = false;
  bool get trialCompleted => _trialCompleted;
  set trialCompleted(bool value) {
    _trialCompleted = value;
    prefs.setBool('ff_trialCompleted', value);
  }
```

#### 2-1b. initializePersistedState에 로딩 추가 (trialHistoryPath 초기화 바로 아래)

```
str_replace
파일: lib\app_state.dart

OLD:
    _safeInit(() {
      _trialHistoryPath =
          prefs.getString('ff_trialHistoryPath') ?? _trialHistoryPath;
    });

NEW:
    _safeInit(() {
      _trialHistoryPath =
          prefs.getString('ff_trialHistoryPath') ?? _trialHistoryPath;
    });
    _safeInit(() {
      _trialCompleted =
          prefs.getBool('ff_trialCompleted') ?? _trialCompleted;
    });
```

---

### 2-2. intro_master.dart 수정 (4개 편집, bottom-to-top)

#### 2-2d. (가장 아래 편집) _buildSignupView 뒤로가기 버튼 — 체험 완료 시 숨김

```
str_replace
파일: lib\custom_code\widgets\intro_master.dart

OLD:
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => setState(() {
                            _isSignupMode = false;
                            _showEmailInSignup = false;
                          }),
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white70),
                          tooltip: '뒤로',
                        ),
                      ),

NEW:
                      if (!FFAppState().trialCompleted)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: () => setState(() {
                              _isSignupMode = false;
                              _showEmailInSignup = false;
                            }),
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white70),
                            tooltip: '뒤로',
                          ),
                        ),
```

#### 2-2c. _startTrial() — TrialDeviceGate 호출 제거

```
str_replace
파일: lib\custom_code\widgets\intro_master.dart

OLD:
      TrialFlowState.instance.restoreFromAppState();
      final canTry = await TrialDeviceGate.canTrial();
      if (!canTry) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('무료 체험은 기기당 1회만 가능합니다. 로그인해 주세요.')),
          );
        }
        return;
      }

NEW:
      TrialFlowState.instance.restoreFromAppState();
```

그리고 같은 함수 내에서 `markUsed()` 제거:

```
str_replace
파일: lib\custom_code\widgets\intro_master.dart

OLD:
      await TrialDeviceGate.markUsed();

      if (!context.mounted) return;

NEW:
      if (!context.mounted) return;
```

#### 2-2b. initState — consumeSignupOnEntry를 trialCompleted로 교체

```
str_replace
파일: lib\custom_code\widgets\intro_master.dart

OLD:
    if (TrialFlowState.instance.consumeSignupOnEntry()) {
      _isSignupMode = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkEntryStatus());
    }

NEW:
    if (FFAppState().trialCompleted) {
      _isSignupMode = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEntryStatus());
```

※ 기존에는 consumeSignupOnEntry가 true면 `_checkEntryStatus()`를 건너뛰었음 →
이미 로그인된 회원이 체험 후 돌아왔을 때 Lobby로 못 가는 버그 가능성이 있었음.
신규 로직은 `_checkEntryStatus()`를 항상 실행하여 로그인 상태면 로비 직행.

#### 2-2a. (가장 위 편집) import 문 — trial_device_gate 제거

```
str_replace
파일: lib\custom_code\widgets\intro_master.dart

OLD:
import 'trial/trial_flow_state.dart';
import 'trial/trial_device_gate.dart';

NEW:
import 'trial/trial_flow_state.dart';
```

---

### 2-3. trial_flow_state.dart — _forceSignupOnEntry 관련 코드 제거

```
str_replace
파일: lib\custom_code\widgets\trial\trial_flow_state.dart

OLD:
  int step = 0;
  bool _forceSignupOnEntry = false;

NEW:
  int step = 0;
```

```
str_replace
파일: lib\custom_code\widgets\trial\trial_flow_state.dart

OLD:
  /// Request signup mode the next time Intro is entered from the trial flow.
  /// This is consumed once and immediately reset.
  void requestSignupOnEntry() {
    _forceSignupOnEntry = true;
  }

  bool consumeSignupOnEntry() {
    final requested = _forceSignupOnEntry;
    _forceSignupOnEntry = false;
    return requested;
  }

NEW:
```

(빈 문자열로 교체 = 해당 블록 삭제)

---

### 2-4. requestSignupOnEntry() 외부 호출처 교체

Phase 1-2에서 찾은 파일에서 아래 패턴을 교체:

```
OLD: TrialFlowState.instance.requestSignupOnEntry();
NEW: FFAppState().trialCompleted = true;
```

※ 해당 파일에 `import '/flutter_flow/flutter_flow_util.dart';`가 없으면 추가.
※ 해당 파일에 `trial_flow_state.dart` import만 남아있고 다른 TrialFlowState 사용이 없으면 import도 제거.

---

### 2-5. TrialDeviceGate 나머지 참조 제거

Phase 1-3에서 intro_master.dart 외에 추가 참조가 있으면 해당 import와 호출을 모두 제거.

---

### 2-6. trial_device_gate.dart 파일 삭제

```powershell
Remove-Item "lib\custom_code\widgets\trial\trial_device_gate.dart"
```

---

## Phase 3 — 사후 검증

### 3-1. TrialDeviceGate 완전 제거
```powershell
(Select-String -Path "lib\**\*.dart" -Pattern "TrialDeviceGate" -Recurse | Measure-Object).Count
```
→ 기대값: 0

### 3-2. _forceSignupOnEntry 완전 제거
```powershell
(Select-String -Path "lib\**\*.dart" -Pattern "_forceSignupOnEntry" -Recurse | Measure-Object).Count
```
→ 기대값: 0

### 3-3. consumeSignupOnEntry 완전 제거
```powershell
(Select-String -Path "lib\**\*.dart" -Pattern "consumeSignupOnEntry" -Recurse | Measure-Object).Count
```
→ 기대값: 0

### 3-4. requestSignupOnEntry 완전 제거
```powershell
(Select-String -Path "lib\**\*.dart" -Pattern "requestSignupOnEntry" -Recurse | Measure-Object).Count
```
→ 기대값: 0

### 3-5. trialCompleted 추가 확인
```powershell
(Select-String -Path "lib\app_state.dart" -Pattern "trialCompleted" | Measure-Object).Count
```
→ 기대값: 4 (필드 선언, getter, setter, initializePersistedState)

### 3-6. trialCompleted 사용처 확인
```powershell
Select-String -Path "lib\**\*.dart" -Pattern "trialCompleted" -Recurse
```
→ 최소 3곳: app_state.dart + intro_master.dart(initState 분기 + 뒤로가기 조건) + 외부 호출처(Phase 2-4)

### 3-7. trial_device_gate.dart 삭제 확인
```powershell
Test-Path "lib\custom_code\widgets\trial\trial_device_gate.dart"
```
→ 기대값: False

---

## Phase 4 — 빌드 검증

```powershell
dart format lib\app_state.dart
dart format lib\custom_code\widgets\intro_master.dart
dart format lib\custom_code\widgets\trial\trial_flow_state.dart
```

Phase 2-4에서 수정한 외부 파일도 개별 dart format 실행.

```powershell
flutter analyze
flutter build appbundle
```

---

## Phase 5 — 커밋 & 푸시

```powershell
git add -A
git commit -m "refactor: intro A/B with SharedPreferences trialCompleted, remove TrialDeviceGate"
git push origin main
```

---

## Rollback

```powershell
git log --oneline -3
git revert HEAD --no-edit
```

---

## ⚠️ 절대 금지 사항
- Box 7 (TtsQueueManager, DeepgramV2VoiceManager, ChunkedTtsFetcher, HybridTtsPlayer, TtsCache) 수정 금지
- dart format 폴더 단위 실행 금지 — 개별 파일만
- lib/custom_code/임시/ 폴더 수정 금지
- trialStep / trialHistoryPath 삭제 금지 (다른 곳에서 아직 참조 가능)
- 앵커 grep count가 기대값과 다르면 즉시 중단 후 결과 보고