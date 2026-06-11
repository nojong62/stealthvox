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

# 📦 Box 7 패치 지시서 — USER-DRAIN-SIGNAL 추가

**버전:** v1.0
**작성일:** 2026-06-12
**대상 파일 (3개, 동일 패치):**
- `F:\flutter_project\stealth_vox\lib\custom_code\widgets\routine_mode_free_talk.dart`
- `F:\flutter_project\stealth_vox\lib\custom_code\widgets\routine_mode_roleplay.dart`
- `F:\flutter_project\stealth_vox\lib\custom_code\widgets\routine_mode_step_expand.dart`

**Clone 모드는 제외.** (이번 작업 범위 아님)

---

## 1. 작업 목적

`TtsQueueManager`에 **유저 큐 드레인(drain) 시그널** 기능을 추가합니다.

- **신규 API:** `sealUserStream()` + `waitUserDrained()`
- **기존 API:** 단 한 줄도 수정/삭제 안 함 — 추가만.
- **회귀 위험:** 신규 메서드를 호출하지 않으면 동작 100% 동일. 기존 호출부(`addAudio`, `setAiPaused`, `setUserTurn`, `isBusy`, `stop`, `dispose`) 영향 없음.

---

## 2. 사전 준비

### 2.1. 세이브포인트 (필수)

```powershell
cd F:\flutter_project\stealth_vox
git status
git add -A
git commit -m "save before box7 user-drain-signal patch"
git log --oneline -1
```

위 마지막 명령으로 출력된 해시를 메모. 롤백 시 사용.

### 2.2. 원본 클래스 위치 확인 (3개 파일 동일 패치)

```powershell
grep -n "class TtsQueueManager" lib\custom_code\widgets\routine_mode_free_talk.dart
grep -n "class TtsQueueManager" lib\custom_code\widgets\routine_mode_roleplay.dart
grep -n "class TtsQueueManager" lib\custom_code\widgets\routine_mode_step_expand.dart
```

예상 결과 (현재 시점 기준):
- routine_mode_free_talk.dart : **2665**
- routine_mode_roleplay.dart : **2994**
- routine_mode_step_expand.dart : **4451**

라인 번호가 다르면 정상(파일 수정 이력에 따라). 클래스 본문 내용은 3개 파일 모두 동일하므로 str_replace 앵커는 그대로 적용됨.

---

## 3. 패치 적용 (3개 파일 각각, bottom-to-top 순서)

각 파일에서 **4단계** 적용. 라인 번호 드리프트 방지를 위해 **아래쪽부터 위쪽 순서로** 진행.

### Step 1 — `stop()` 메서드 수정 (deadlock 방지)

**삭제 대상:** 없음 (메서드 내부에 코드 추가)

**위치 식별 (각 파일에서 grep로 확인):**

```powershell
grep -n "void stop()" lib\custom_code\widgets\routine_mode_step_expand.dart
```

해당 메서드의 시작줄 부근부터 약 9줄. 내용은 다음 블록(현재 원본):

```dart
  void stop() {
    _userQueue.clear();
    _aiQueue.clear();
    _isPlaying = false;
    _aiPaused = false;
    _player.stop();
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
  }
```

**str_replace 적용:**

`old_str`:
```dart
  void stop() {
    _userQueue.clear();
    _aiQueue.clear();
    _isPlaying = false;
    _aiPaused = false;
    _player.stop();
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
  }
```

`new_str`:
```dart
  void stop() {
    _userQueue.clear();
    _aiQueue.clear();
    _isPlaying = false;
    _aiPaused = false;
    _player.stop();
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
    // 🌱 [Box 7 USER-DRAIN-SIGNAL] 드레인 대기자 풀어주기 (deadlock 방지)
    if (_userDrainedCompleter != null && !_userDrainedCompleter!.isCompleted) {
      _userDrainedCompleter!.complete();
    }
    _userDrainedCompleter = null;
    _userStreamSealed = false;
    _currentChunkIsUser = false;
  }
```

---

### Step 2 — `_processQueue` 메서드 수정 (드레인 신호 발생 지점)

**위치 식별:**

```powershell
grep -n "Future<void> _processQueue" lib\custom_code\widgets\routine_mode_step_expand.dart
```

원본 블록(현재):

```dart
  Future<void> _processQueue() async {
    if (_isPlaying) return;
    _isPlaying = true;
    onPlayStart?.call();

    // 🔧 [v3.5] 재생 우선순위:
    //   1순위: 유저 큐 (항상 우선)
    //   2순위: AI 큐 (유저 큐 비고 _aiPaused=false일 때만)
    while (_userQueue.isNotEmpty || (!_aiPaused && _aiQueue.isNotEmpty)) {
      Uint8List bytes;
      if (_userQueue.isNotEmpty) {
        bytes = _userQueue.removeAt(0);
      } else if (!_aiPaused && _aiQueue.isNotEmpty) {
        bytes = _aiQueue.removeAt(0);
      } else {
        break;
      }

      if (bytes.isEmpty) continue;

      _completer = Completer<void>();
      final estimatedDuration = Duration(
        seconds: ((bytes.length / 16000) + 3).ceil(),
      );

      try {
        await _player.play(BytesSource(bytes));
        await _completer!.future.timeout(estimatedDuration);
      } catch (_) {
      } finally {
        if (_completer != null && !_completer!.isCompleted) {
          _completer!.complete();
        }
      }
    }

    _isPlaying = false;
    if (_userQueue.isEmpty && _aiQueue.isEmpty) onQueueEmpty?.call();
  }
```

**str_replace 적용:**

`old_str`: 위 원본 블록 전체

`new_str`:
```dart
  Future<void> _processQueue() async {
    if (_isPlaying) return;
    _isPlaying = true;
    onPlayStart?.call();

    // 🔧 [v3.5] 재생 우선순위:
    //   1순위: 유저 큐 (항상 우선)
    //   2순위: AI 큐 (유저 큐 비고 _aiPaused=false일 때만)
    while (_userQueue.isNotEmpty || (!_aiPaused && _aiQueue.isNotEmpty)) {
      Uint8List bytes;
      if (_userQueue.isNotEmpty) {
        bytes = _userQueue.removeAt(0);
        _currentChunkIsUser = true; // 🌱 [Box 7 USER-DRAIN-SIGNAL]
      } else if (!_aiPaused && _aiQueue.isNotEmpty) {
        bytes = _aiQueue.removeAt(0);
        _currentChunkIsUser = false; // 🌱 [Box 7 USER-DRAIN-SIGNAL]
      } else {
        break;
      }

      if (bytes.isEmpty) continue;

      _completer = Completer<void>();
      final estimatedDuration = Duration(
        seconds: ((bytes.length / 16000) + 3).ceil(),
      );

      try {
        await _player.play(BytesSource(bytes));
        await _completer!.future.timeout(estimatedDuration);
      } catch (_) {
      } finally {
        if (_completer != null && !_completer!.isCompleted) {
          _completer!.complete();
        }
      }

      // 🌱 [Box 7 USER-DRAIN-SIGNAL] 유저 청크 재생 완료 직후
      //   유저 큐가 비었고 sealed면 드레인 신호 발사
      if (_currentChunkIsUser &&
          _userStreamSealed &&
          _userQueue.isEmpty) {
        if (_userDrainedCompleter != null &&
            !_userDrainedCompleter!.isCompleted) {
          _userDrainedCompleter!.complete();
        }
      }
      _currentChunkIsUser = false;
    }

    _isPlaying = false;
    if (_userQueue.isEmpty && _aiQueue.isEmpty) onQueueEmpty?.call();
  }
```

---

### Step 3 — 신규 메서드 2개 추가 (`sealUserStream`, `waitUserDrained`)

**삽입 위치:** `addAudio` 메서드 바로 다음, `_processQueue` 바로 앞.

원본의 해당 영역(현재):

```dart
  /// 🔧 [v3.5] isUser=true면 유저 큐, false면 AI 큐에 적재
  Future<void> addAudio(Uint8List bytes, {required bool isUser}) async {
    if (isUser) {
      _userQueue.add(bytes);
    } else {
      _aiQueue.add(bytes);
    }
    if (!_isPlaying) _processQueue();
  }

  Future<void> _processQueue() async {
```

**str_replace 적용:**

`old_str`:
```dart
  /// 🔧 [v3.5] isUser=true면 유저 큐, false면 AI 큐에 적재
  Future<void> addAudio(Uint8List bytes, {required bool isUser}) async {
    if (isUser) {
      _userQueue.add(bytes);
    } else {
      _aiQueue.add(bytes);
    }
    if (!_isPlaying) _processQueue();
  }

  Future<void> _processQueue() async {
```

`new_str`:
```dart
  /// 🔧 [v3.5] isUser=true면 유저 큐, false면 AI 큐에 적재
  Future<void> addAudio(Uint8List bytes, {required bool isUser}) async {
    if (isUser) {
      _userQueue.add(bytes);
    } else {
      _aiQueue.add(bytes);
    }
    if (!_isPlaying) _processQueue();
  }

  // 🌱 [Box 7 USER-DRAIN-SIGNAL] 유저 청크 스트림 봉인.
  //   호출 시점 = "더 이상 유저 청크 안 들어옴" 선언.
  //   호출 후 waitUserDrained()와 짝지어 사용.
  void sealUserStream() {
    _userStreamSealed = true;
    // 봉인 시점에 이미 유저 큐가 비고 현재 재생도 유저 청크가 아니면 즉시 신호
    if (_userQueue.isEmpty && !_currentChunkIsUser) {
      if (_userDrainedCompleter != null &&
          !_userDrainedCompleter!.isCompleted) {
        _userDrainedCompleter!.complete();
      }
    }
  }

  // 🌱 [Box 7 USER-DRAIN-SIGNAL] 유저 큐 완전 비움(마지막 샘플 재생 완료)까지 대기.
  //   timeout 기본 45초 = 좀비 방지 ceiling.
  //   정상 동작 시에는 마지막 청크 재생 완료 즉시 반환.
  //   타임아웃 시에도 예외 없이 정상 반환 — 호출부는 항상 진행 보장.
  //   호출 후 상태 자동 리셋(다음 턴 대비).
  Future<void> waitUserDrained({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    // 즉시 조건 만족: 바로 반환
    if (_userQueue.isEmpty && !_currentChunkIsUser) {
      _userStreamSealed = false;
      return;
    }
    // completer 생성 (재진입 안전: 기존 것 재사용)
    _userDrainedCompleter ??= Completer<void>();
    try {
      await _userDrainedCompleter!.future.timeout(timeout);
    } catch (_) {
      // 타임아웃 — 강제 진행 (좀비 방지)
    } finally {
      _userDrainedCompleter = null;
      _userStreamSealed = false;
    }
  }

  Future<void> _processQueue() async {
```

---

### Step 4 — 필드 3개 추가 (클래스 상단)

**삽입 위치:** `bool _isUserTurn = true;` 다음 줄.

원본 영역(현재):

```dart
  // 🔧 [v3.6] 외부에서 _aiPaused 상태 조회 (UI 업데이트 보류 판단용)
  bool get aiPaused => _aiPaused;
  // UI 상태 표시용 (레거시 호환)
  bool _isUserTurn = true;

  /// 유저 재생 중이거나 유저 큐에 남은 게 있으면 busy
```

**str_replace 적용:**

`old_str`:
```dart
  // 🔧 [v3.6] 외부에서 _aiPaused 상태 조회 (UI 업데이트 보류 판단용)
  bool get aiPaused => _aiPaused;
  // UI 상태 표시용 (레거시 호환)
  bool _isUserTurn = true;

  /// 유저 재생 중이거나 유저 큐에 남은 게 있으면 busy
```

`new_str`:
```dart
  // 🔧 [v3.6] 외부에서 _aiPaused 상태 조회 (UI 업데이트 보류 판단용)
  bool get aiPaused => _aiPaused;
  // UI 상태 표시용 (레거시 호환)
  bool _isUserTurn = true;

  // 🌱 [Box 7 USER-DRAIN-SIGNAL] 유저 큐 완전 드레인 감지용
  bool _userStreamSealed = false;
  Completer<void>? _userDrainedCompleter;
  bool _currentChunkIsUser = false;

  /// 유저 재생 중이거나 유저 큐에 남은 게 있으면 busy
```

---

## 4. 검증 (각 파일별로)

### 4.1. grep 카운트 검증

3개 파일 각각에 대해 다음을 실행:

```powershell
$f = "lib\custom_code\widgets\routine_mode_step_expand.dart"
# (free_talk, roleplay 도 동일)

# 신규 식별자 출현 횟수 — 모두 0보다 커야 함
(grep -c "sealUserStream" $f)           # 기대값: 1 (정의만)
(grep -c "waitUserDrained" $f)          # 기대값: 1 (정의만)
(grep -c "_userStreamSealed" $f)        # 기대값: 3 (선언1 + 사용2)
(grep -c "_userDrainedCompleter" $f)    # 기대값: 5 (선언1 + 사용4)
(grep -c "_currentChunkIsUser" $f)      # 기대값: 5 (선언1 + 사용4)
(grep -c "USER-DRAIN-SIGNAL" $f)        # 기대값: 6 (주석 6곳)
```

기대값과 어긋나면 해당 파일 패치 불완전 → Step 1~4 중 누락된 곳 재검토.

### 4.2. 컴파일 검증

```powershell
cd F:\flutter_project\stealth_vox
flutter analyze lib\custom_code\widgets\routine_mode_free_talk.dart
flutter analyze lib\custom_code\widgets\routine_mode_roleplay.dart
flutter analyze lib\custom_code\widgets\routine_mode_step_expand.dart
```

새로운 에러/경고 없어야 함. 기존 info-level 경고는 무관.

### 4.3. 동작 검증 (수동)

이 패치만으로는 호출부가 없으므로 **기존 동작 100% 동일**이어야 함:

- 3모드 각각 1턴씩 대화 → 정상 진행 확인
- 로그에 `🌱 [Box 7 USER-DRAIN-SIGNAL]` 관련 출력은 아직 없음 (정상)
- `isBusy`, `setAiPaused`, `stop`, `dispose` 모두 기존과 동일하게 동작

---

## 5. 호출부 작업은 별도 지시서

이 패치는 **API 추가만** 하고 호출부는 손대지 않음.

호출부(`routine_mode_*.dart`의 `_processRelayPipeline` 안)에서 `sealUserStream()` + `waitUserDrained()`를 실제 사용하는 작업은 **별도 지시서**로 진행 예정.

순서:
1. ✅ **이 지시서:** Box 7 API 추가 (3파일 동일 패치)
2. ⏳ 다음 지시서: Step Expand 호출부 마이그레이션 + floor 로직 제거
3. ⏳ 그 다음: Free Talk 호출부 마이그레이션
4. ⏳ 그 다음: Roleplay 호출부 마이그레이션

각 단계마다 별도 git 세이브포인트.

---

## 6. 롤백 절차

이 패치만 되돌리려면:

```powershell
cd F:\flutter_project\stealth_vox
git restore lib\custom_code\widgets\routine_mode_free_talk.dart
git restore lib\custom_code\widgets\routine_mode_roleplay.dart
git restore lib\custom_code\widgets\routine_mode_step_expand.dart
```

이미 커밋한 후라면:

```powershell
git log --oneline -5
git revert <패치커밋해시>
```

---

## 7. 체크리스트 요약

각 파일(FT/RP/SE)별로 다음을 모두 통과해야 작업 완료:

- [ ] Step 1: `stop()` 메서드 수정 완료
- [ ] Step 2: `_processQueue` 메서드 수정 완료
- [ ] Step 3: `sealUserStream` / `waitUserDrained` 메서드 추가 완료
- [ ] Step 4: 필드 3개 추가 완료
- [ ] 검증 4.1: grep 카운트 모두 기대값 일치
- [ ] 검증 4.2: `flutter analyze` 에러 0
- [ ] 검증 4.3: 1턴 대화 정상 (기존 동작 무변경)

3개 파일 모두 위 체크리스트 통과 → Box 7 패치 완료.

---

**EOF**