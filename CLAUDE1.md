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

# 근본 개선 지시문: remainingTime 표시 로직에 계정(uid) 인식 가드 도입

## 배경 — 방금 적용한 수정의 잔존 리스크

`_initializeLobbyData()`에서 `remainingTimeLoaded = false` 무조건 리셋을 **완전히 제거**하는 방식으로 카카오 플래시 버그는 해결됐습니다. 하지만 이 방식에는 구조적 허점이 하나 남습니다:

> **계정을 실제로 전환하는 경우** (로그아웃 → 다른 계정으로 로그인), Firestore 조회가 끝나기 전까지 **직전 계정(A)의 잔여시간이 화면에 잠깐 노출**될 수 있습니다. 리셋을 없앴기 때문에 "이전 값을 지우고 새로 받아온다"는 안전장치가 사라진 것입니다.

지금은 로그아웃 버튼이 `remainingTime = 0` + `remainingTimeLoaded = false`를 명시적으로 세팅하고 있어 일반적인 로그아웃→로그인 경로에서는 큰 문제가 안 되지만, **다음 같은 경로에서는 여전히 취약**합니다:
- 자동 로그인 세션이 남아있는 상태에서 앱을 재시작하고 곧바로 Lobby에 진입하는 경우
- 향후 "계정 전환" 기능이 추가되는 경우
- Duo 초대 등으로 게스트 세션 → 본인 세션 전환이 발생하는 경로

## 근본 해결 방향

**"화면 재진입 시 무조건 리셋"도 아니고 "무조건 유지"도 아닌, `현재 로그인된 uid가 마지막으로 동기화된 uid와 같은지`를 기준으로 판단**합니다.

- **같은 uid** (예: Intro에서 `grantSignupBonus`로 이미 값을 받아온 직후 Lobby 진입) → 기존 값 유지, 화면 안 깜빡임
- **다른 uid 또는 최초 진입** (예: 실제 계정 전환) → `remainingTimeLoaded = false`로 리셋 후 새로 조회 → 이전 계정 값 노출 방지

이를 위해 `LobbyBrain`(이미 존재하는 정적 유틸리티 클래스)에 `lastSyncedUid`라는 정적 필드 하나를 추가하고, Intro/Lobby/로그아웃 세 지점에서 이 값을 갱신·참조합니다. `LobbyBrain`은 `AppsFlyerManager`와 마찬가지로 `index.dart` 배럴을 통해 이미 `intro_master.dart`에서도 접근 가능한 것으로 확인됩니다 (동일 패턴으로 `AppsFlyerManager.initialize`를 import 없이 사용 중).

## 수정 대상 파일
- `lib/custom_code/widgets/lobby_master.dart` (3곳)
- `lib/custom_code/widgets/intro_master.dart` (1곳)

---

## Phase 1: Git Savepoint

```powershell
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before uid-aware remainingTime sync guard"
```

---

## Phase 2: Grep Anchor Validation (사전 확인)

```powershell
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern "class LobbyBrain \{" | Measure-Object | Select-Object -ExpandProperty Count
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern '_buildFooterLink\("로그아웃"' | Measure-Object | Select-Object -ExpandProperty Count
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern "Future<void> _initializeLobbyData" | Measure-Object | Select-Object -ExpandProperty Count
Select-String -Path "lib\custom_code\widgets\intro_master.dart" -Pattern "Future<void> _grantSignupBonusIfPossible" | Measure-Object | Select-Object -ExpandProperty Count
```

**각 결과 기대값: 1**

> ⚠️ 직전 커밋(a023685a)에서 `_initializeLobbyData` 내부가 이미 한 차례 수정되었으므로, 아래 BEFORE 코드가 실제 파일과 다를 수 있습니다. str_replace 적용 전 반드시 `view` 도구로 현재 내용을 재확인하고, 다를 경우 문맥에 맞게 조정하세요.

---

## Phase 3: str_replace 편집 (파일 내 bottom-to-top 순서)

### [lobby_master.dart] Edit 1 — `LobbyBrain`에 계정 추적 필드 추가 (파일 하단, 먼저 적용)

**BEFORE:**
```dart
class LobbyBrain {
  // 💡 서버 남은 시간 동기화
  static Future<int?> getRemainingTime(User? user) async {
```

**AFTER:**
```dart
class LobbyBrain {
  // 💡 마지막으로 remainingTime을 동기화한 사용자 uid (계정 전환 감지용)
  static String? lastSyncedUid;

  // 💡 서버 남은 시간 동기화
  static Future<int?> getRemainingTime(User? user) async {
```

### [lobby_master.dart] Edit 2 — 로그아웃 시 `lastSyncedUid` 초기화

**BEFORE:**
```dart
                          _buildFooterLink("로그아웃", () async {
                            FFAppState().remainingTime = 0;
                            FFAppState().remainingTimeLoaded = false;
                            await FirebaseAuth.instance.signOut();
                            if (!context.mounted) return;
                            context.goNamed('Intro');
                          }),
```

**AFTER:**
```dart
                          _buildFooterLink("로그아웃", () async {
                            FFAppState().remainingTime = 0;
                            FFAppState().remainingTimeLoaded = false;
                            LobbyBrain.lastSyncedUid = null;
                            await FirebaseAuth.instance.signOut();
                            if (!context.mounted) return;
                            context.goNamed('Intro');
                          }),
```

### [lobby_master.dart] Edit 3 — `_initializeLobbyData`에 uid 비교 가드 적용

먼저 `view` 도구로 `_initializeLobbyData` 현재 코드를 확인한 뒤, 아래 로직을 반영해 수정하세요 (직전 커밋에서 추가된 `alreadyLoaded` 디버그 로그는 유지하고 확장):

**목표 형태 (참고용, 실제 파일 상태에 맞춰 조정):**
```dart
  Future<void> _initializeLobbyData() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isSameAccountAsLastSync =
        currentUid != null && currentUid == LobbyBrain.lastSyncedUid;
    final alreadyLoaded = FFAppState().remainingTimeLoaded;
    debugPrint(
        '[Lobby] _initializeLobbyData enter, alreadyLoaded=$alreadyLoaded, sameAccount=$isSameAccountAsLastSync, remainingTime=${FFAppState().remainingTime}');
    setState(() {
      isLoading = true;
      // 계정이 바뀐 경우(다른 uid 또는 최초 동기화)에만 로딩 상태로 되돌린다.
      // 같은 계정으로 재진입한 경우(예: 로그인 직후 Lobby 진입)에는 이미 세팅된 값을 그대로 유지한다.
      if (!isSameAccountAsLastSync) {
        FFAppState().remainingTimeLoaded = false;
      }
    });
    try {
      // 1. DB 통신 분리: 서버 시간 및 남은 시간 동기화
      int? serverRemainingTime =
          await LobbyBrain.getRemainingTime(FirebaseAuth.instance.currentUser);
      debugPrint('[Lobby] Firestore remainingTime=$serverRemainingTime');
      if (mounted) {
        setState(() {
          if (serverRemainingTime != null) {
            FFAppState().remainingTime = serverRemainingTime;
          }
          FFAppState().remainingTimeLoaded = true;
        });
      }
      if (currentUid != null) {
        LobbyBrain.lastSyncedUid = currentUid;
      }
      if (serverRemainingTime != null) {
        BillingTicker.instance.remainingSecondsNotifier.value =
            serverRemainingTime;
        BillingTicker.instance.start();
        BillingTicker.instance.pause(); // 로비는 과금 없음
      }
```
(이후 `// 2. DB 통신 분리: 버전 체크...` 부터는 기존 코드 그대로 유지)

### [intro_master.dart] Edit 4 — `_grantSignupBonusIfPossible`에서 `lastSyncedUid` 세팅

**BEFORE:**
```dart
      if (remainingTime != null) {
        FFAppState().remainingTime = remainingTime;
        FFAppState().remainingTimeLoaded = true;
      }
```

**AFTER:**
```dart
      if (remainingTime != null) {
        FFAppState().remainingTime = remainingTime;
        FFAppState().remainingTimeLoaded = true;
        LobbyBrain.lastSyncedUid = FirebaseAuth.instance.currentUser?.uid;
      }
```

---

## Phase 4: Grep 검증

```powershell
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern "lastSyncedUid" | Measure-Object | Select-Object -ExpandProperty Count
```
**기대값: 4** (필드 선언 1 + 로그아웃 1 + `_initializeLobbyData` 내부 참조/갱신 2)

```powershell
Select-String -Path "lib\custom_code\widgets\intro_master.dart" -Pattern "LobbyBrain.lastSyncedUid" | Measure-Object | Select-Object -ExpandProperty Count
```
**기대값: 1**

```powershell
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern "isSameAccountAsLastSync" | Measure-Object | Select-Object -ExpandProperty Count
```
**기대값: 2** (선언 1 + setState 내부 조건 1)

---

## Phase 5: 빌드 & 포맷

```powershell
dart format lib\custom_code\widgets\lobby_master.dart
dart format lib\custom_code\widgets\intro_master.dart
flutter analyze lib/custom_code/widgets/lobby_master.dart lib/custom_code/widgets/intro_master.dart
```

> `LobbyBrain`이 `intro_master.dart`에서 인식되지 않는 오류(`undefined class`)가 발생하면, `index.dart` 배럴에 `LobbyBrain`이 export되어 있는지 확인하거나, `intro_master.dart` 상단에 `import 'lobby_master.dart';`를 명시적으로 추가하세요.

---

## Phase 6: 커밋 & 푸시

```powershell
git add -A && git commit -m "refactor: add uid-aware guard for remainingTime sync to prevent stale-account flash while preserving Kakao login fix"
git push origin main
```

---

## Phase 7: 롤백 절차

```powershell
git revert HEAD --no-edit
git push origin main
```

---

## 검증 시나리오 (실장 수동 테스트)

1. **카카오 로그인** (기존 버그 재발 방지): 로그아웃 → 카카오 로그인 → Lobby 즉시 정상 시간 표시
2. **구글 로그인**: 기존과 동일하게 정상 동작
3. **계정 전환 테스트** (신규 시나리오): 계정 A로 로그인해 시간 확인 → 로그아웃 → 계정 B(잔여시간이 다른 계정)로 로그인 → Lobby에서 **A의 잔여시간이 잠깐이라도 보이지 않고** B의 값만 표시되는지 확인
4. **신규 가입 보너스**: 신규 계정 가입 직후 Lobby 진입 시 보너스 시간 즉시 표시 (플래시 없음)
5. **adb logcat 확인**: `sameAccount=true`(같은 계정 재진입)와 `sameAccount=false`(계정 전환)가 각각 올바른 시나리오에서 찍히는지 확인