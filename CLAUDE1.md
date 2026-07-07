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
- 앱 실행/빌드 가능성을 최우선으로 하되, 빌드할지는 먼저 물어 봐.
- 불확실한 부분은 임의 삭제하지 말고 보고할 것

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# 지시문 7: 카카오 로그인 후 Lobby 00:00 문제 해결

## 목적
카카오 로그인 시 `signInAnonymously()` → GoRouter가 Lobby로 조기 이동 → 보너스 지급 전에 00:00 표시되는 버그를 해결한다.

## 근본 원인
`signInWithKakao()` 내부에서 `signInAnonymously()`를 먼저 호출하면,
GoRouter의 `loggedIn` getter가 anonymous user도 "로그인됨"으로 판정하여
카카오 인증 완료 + 보너스 지급 전에 Lobby로 보내버린다.

## 대상 파일
- **수정**: `lib/flutter_flow/nav/nav.dart` (2곳)
- **수정**: `lib/custom_code/widgets/intro_master.dart` (1곳)

## 선행 조건
- ✅ 지시문 1~6 완료

---

## Phase 0: 사전 진단

```bash
# 1. loggedIn getter 현재 구현 확인
grep -n "get loggedIn" lib/flutter_flow/nav/nav.dart
# 기대: "bool get loggedIn => user?.loggedIn ?? false;"

# 2. update() 내부 auto-reset 확인
grep -n "updateNotifyOnAuthChange(true)" lib/flutter_flow/nav/nav.dart
# 기대: update() 메서드 안에서 1줄

# 3. _handleUnifiedAuth에서 notifyOnAuthChange 사용 여부
grep -n "notifyOnAuthChange\|updateNotifyOnAuthChange" lib/custom_code/widgets/intro_master.dart
# 기대: 0줄 (아직 없음)

# 4. FirebaseAuth import 존재 여부 (nav.dart)
grep -n "firebase_auth" lib/flutter_flow/nav/nav.dart
# 있으면 OK, 없으면 import 추가 필요
```

---

## Phase 1: Savepoint

```bash
git checkout -b fix/lobby-zero-time
git add -A && git commit -m "savepoint: before lobby 00:00 fix"
```

---

## Phase 2: 수정 (3곳)

### 수정 1: nav.dart — loggedIn에서 anonymous 제외

**파일**: `lib/flutter_flow/nav/nav.dart`

**먼저 import 확인** — 파일 상단에 `firebase_auth` import가 없으면 추가:

```dart
import 'package:firebase_auth/firebase_auth.dart';
```

**앵커 (현재 코드):**
```dart
  bool get loggedIn => user?.loggedIn ?? false;
```

**변경:**
```dart
  bool get loggedIn {
    if (!(user?.loggedIn ?? false)) return false;
    // anonymous 체험 유저는 "로그인 안 됨"으로 취급
    // → GoRouter가 Lobby로 자동 이동하지 않음
    // → 체험은 imperative navigation(pushNamed)으로 처리
    final fbUser = FirebaseAuth.instance.currentUser;
    return fbUser != null && !fbUser.isAnonymous;
  }
```

> **효과**: `signInAnonymously()` 완료 시 `loggedIn = false` → GoRouter가 Lobby로 안 감.
> 정식 로그인(`signInWithCustomToken`, `signInWithCredential` 등) 완료 시에만 `loggedIn = true`.
>
> **체험 플로우 영향 없음**: 체험은 `_startTrial()` → `signInAnonymously()` → `context.pushNamed('StealthRoom')`으로
> imperative navigation을 쓰므로 GoRouter의 `loggedIn` 판정과 무관.

---

### 수정 2: nav.dart — update()에서 suppressed 상태 auto-reset 방지

**파일**: `lib/flutter_flow/nav/nav.dart`

**앵커 (현재 코드):**
```dart
  void update(BaseAuthUser newUser) {
    final shouldUpdate =
        user?.uid == null || newUser.uid == null || user?.uid != newUser.uid;
    initialUser ??= newUser;
    user = newUser;
    // Refresh the app on auth change unless explicitly marked otherwise.
    // No need to update unless the user has changed.
    if (notifyOnAuthChange && shouldUpdate) {
      notifyListeners();
    }
    // Once again mark the notifier as needing to update on auth change
    // (in order to catch sign in / out events).
    updateNotifyOnAuthChange(true);
  }
```

**변경:**
```dart
  void update(BaseAuthUser newUser) {
    final shouldUpdate =
        user?.uid == null || newUser.uid == null || user?.uid != newUser.uid;
    initialUser ??= newUser;
    user = newUser;
    // Refresh the app on auth change unless explicitly marked otherwise.
    // No need to update unless the user has changed.
    if (notifyOnAuthChange && shouldUpdate) {
      notifyListeners();
    }
    // Auto-reset only when not explicitly suppressed.
    // Multi-step auth flows (e.g. anonymous → Kakao custom token → bonus)
    // suppress notifications and restore them manually after completion.
    if (notifyOnAuthChange) {
      updateNotifyOnAuthChange(true);
    }
  }
```

> **효과**: `notifyOnAuthChange = false`로 설정하면, `update()`가 호출되어도
> 자동으로 `true`로 돌아가지 않음. caller가 명시적으로 `true`로 복원해야 함.
>
> **기존 동작 영향 없음**: `notifyOnAuthChange`가 `true`인 정상 상태에서는
> `if (true) updateNotifyOnAuthChange(true)` → 값 변화 없음 → 기존과 동일.

---

### 수정 3: intro_master.dart — _handleUnifiedAuth에서 라우터 알림 억제

**파일**: `lib/custom_code/widgets/intro_master.dart`

**앵커 (현재 코드):**
```dart
  /// 통합 소셜 인증: 약관 시트 없이 바로 소셜 로그인 -> 신규면 연령 확인
  Future<void> _handleUnifiedAuth(Future<dynamic> Function() authFn) async {
    debugPrint('[Auth] _handleUnifiedAuth enter');
    setState(() => isLoading = true);
    try {
      await _cleanupTrialSandbox();
      await authFn();
```

**변경:**
```dart
  /// 통합 소셜 인증: 약관 시트 없이 바로 소셜 로그인 -> 신규면 연령 확인
  Future<void> _handleUnifiedAuth(Future<dynamic> Function() authFn) async {
    debugPrint('[Auth] _handleUnifiedAuth enter');
    setState(() => isLoading = true);
    // Multi-step auth 동안 GoRouter 자동 네비게이션 억제
    // (anonymous → custom token → bonus 지급 완료까지 Lobby 이동 방지)
    AppStateNotifier.instance.updateNotifyOnAuthChange(false);
    try {
      await _cleanupTrialSandbox();
      await authFn();
```

그리고 같은 메서드의 **finally 블록**:

**앵커 (현재 코드):**
```dart
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
```

**변경:**
```dart
    } finally {
      // GoRouter 알림 복원
      AppStateNotifier.instance.updateNotifyOnAuthChange(true);
      if (mounted) setState(() => isLoading = false);
    }
```

> **효과**: `_handleUnifiedAuth` 전체 실행 동안 GoRouter가 auth 변경에 반응하지 않음.
> `_checkAgeAndRoute()` → `_routeAfterAuth()` → `context.goNamed('Lobby')`로
> 보너스 지급 완료 후에만 Lobby로 이동.
> finally에서 복원하므로 이후 정상 auth 이벤트(로그아웃 등)에는 영향 없음.

---

## Phase 3: 검증

```bash
# 1. nav.dart 컴파일 확인
dart format lib/flutter_flow/nav/nav.dart
flutter analyze lib/flutter_flow/nav/nav.dart

# 2. intro_master.dart 컴파일 확인
dart format lib/custom_code/widgets/intro_master.dart
flutter analyze lib/custom_code/widgets/intro_master.dart

# 3. loggedIn 변경 확인
grep -A5 "get loggedIn" lib/flutter_flow/nav/nav.dart
# 기대: isAnonymous 체크 포함

# 4. update() auto-reset 변경 확인
grep -B2 -A1 "updateNotifyOnAuthChange" lib/flutter_flow/nav/nav.dart
# 기대: "if (notifyOnAuthChange)" 조건 안에서만 호출

# 5. _handleUnifiedAuth 알림 억제 확인
grep "updateNotifyOnAuthChange" lib/custom_code/widgets/intro_master.dart
# 기대: 2줄 (false 설정 1줄 + true 복원 1줄)

# 6. AppStateNotifier import 확인
grep "AppStateNotifier" lib/custom_code/widgets/intro_master.dart
# 기대: 2줄 이상

# 7. FirebaseAuth import 확인 (nav.dart)
grep "firebase_auth" lib/flutter_flow/nav/nav.dart
# 기대: 1줄
```

---

## Phase 4: 빌드 및 테스트

```bash
flutter clean
flutter pub get
flutter build apk --release
```

### 테스트 시나리오 (반드시 확인)

**시나리오 A: 신규 카카오 가입**
1. 앱 데이터 삭제 → 앱 실행 → Welcome
2. "로그인" → Auth → "카카오톡으로 계속하기"
3. 카카오 로그인 완료 → birthYear 팝업 → Lobby
4. **기대**: Lobby 첫 진입부터 05:00 표시 (00:00 아님)

**시나리오 B: 기존 카카오 재로그인**
1. 앱 데이터 삭제 → 앱 실행 → Auth → 카카오 로그인
2. **기대**: Lobby 진입 시 기존 잔여시간 표시

**시나리오 C: 체험 → 가입**
1. Welcome → "1분 무료 체험" → 대화방 진입 (StealthRoom으로 정상 이동하는지)
2. 체험 완료 → Auth → 카카오 가입
3. **기대**: 체험은 정상 동작, 가입 후 Lobby 05:00

**시나리오 D: 앱 껐다 켜기 (정식 회원)**
1. 정식 회원 로그인 상태에서 앱 종료 → 재실행
2. **기대**: 자동 Lobby 진입 (세션 유지, loggedIn=true)

---

## Phase 5: 커밋 및 머지

```bash
git add -A && git commit -m "fix: prevent premature Lobby navigation during multi-step auth (00:00 bug)"

# 테스트 통과 후 main 머지
git checkout main
git merge fix/lobby-zero-time
git push origin main
```

---

## Phase 6: 롤백 (문제 발생 시)

```bash
git checkout main
git revert HEAD --no-edit
git push origin main
```

---

## 수정 영향 범위

| 수정 | 영향 받는 플로우 | 영향 안 받는 플로우 |
|---|---|---|
| loggedIn anonymous 제외 | GoRouter 초기 화면 결정 | 체험 (imperative nav), Duo 초대 |
| update() auto-reset 방지 | 명시적 suppress 시에만 작동 | 일반 로그인/로그아웃 (suppress 안 할 때) |
| _handleUnifiedAuth 억제 | 소셜 로그인 플로우 | 이메일 로그인, 자동 Lobby 진입 |