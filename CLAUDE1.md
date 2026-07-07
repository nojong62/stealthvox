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

# 지시문 6: intro_master.dart — anonymous 분기 + 이메일 가입 UI + 이메일 로그인 birthYear

## 목적
intro_master.dart에서 확인된 3가지 문제를 최소 변경으로 수정한다.

1. `_checkEntryStatus`에서 anonymous user를 Lobby로 보내지 않기
2. 이메일 폼에 로그인/가입 탭 전환 UI 추가
3. 이메일 로그인 후에도 birthYear 확인

## 대상 파일
- **수정**: `lib/custom_code/widgets/intro_master.dart` (3곳만 수정)

## 선행 조건
- ✅ 지시문 5 완료 (현재 enum IntroScreen { welcome, auth } 구조)

---

## Phase 0: 사전 진단

```bash
# 1. _checkEntryStatus에서 anonymous 분기 없음 확인
grep -n "isAnonymous" lib/custom_code/widgets/intro_master.dart
# _checkEntryStatus 안에서는 나오지 않을 것 (다른 곳에서만 사용)

# 2. _emailTabBtn 미사용 확인
grep -n "_emailTabBtn\|unused_element" lib/custom_code/widgets/intro_master.dart
# 기대: "// ignore: unused_element" + _emailTabBtn 정의만 있고 호출은 없음

# 3. _handleAuth의 _checkAgeAndRoute 호출 위치 확인
grep -n "_checkAgeAndRoute" lib/custom_code/widgets/intro_master.dart
# 기대: !isLoginMode 조건 안에서만 호출됨

# 4. _buildEmailForm 호출부 확인
grep -n "_buildEmailForm" lib/custom_code/widgets/intro_master.dart
# 기대: _buildEmailForm(isLogin: isLoginMode) 형태
```

---

## Phase 1: Savepoint

```bash
git add -A && git commit -m "savepoint: before anonymous-gate + email-tab + login-birthYear fix"
```

---

## Phase 2: 수정 (3곳)

### 수정 1: _checkEntryStatus — anonymous를 Lobby로 보내지 않기

**파일**: `lib/custom_code/widgets/intro_master.dart`

**앵커 (현재 코드):**
```dart
    // 3순위: 이미 로그인된 회원도 pending invite 우선 체크
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      debugPrint(
          '[TrialDebug] _checkEntryStatus  routing existing user to Lobby via _routeAfterAuth, time=${DateTime.now().toIso8601String()}');
      _routeAfterAuth();
      return;
    }
```

**변경:**
```dart
    // 3순위: 정식 회원(non-anonymous)만 Lobby로 라우팅
    // anonymous 체험 유저는 Intro에 머물러야 함 (Welcome 또는 Auth)
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      debugPrint(
          '[TrialDebug] _checkEntryStatus  routing non-anonymous user to Lobby via _routeAfterAuth, time=${DateTime.now().toIso8601String()}');
      _routeAfterAuth();
      return;
    }
    if (user != null && user.isAnonymous) {
      debugPrint(
          '[TrialDebug] _checkEntryStatus  anonymous user stays on Intro, trialCompleted=${FFAppState().trialCompleted}');
    }
```

> **효과**: anonymous 체험 유저는 Intro에 머물고, initState에서 설정한
> `_currentScreen` (trialCompleted면 auth, 아니면 welcome)이 그대로 표시된다.
> 정식 회원만 Lobby로 자동 이동.

---

### 수정 2: _buildEmailForm — 로그인/가입 탭 전환 추가

**파일**: `lib/custom_code/widgets/intro_master.dart`

**앵커 (현재 코드, _buildEmailForm 메서드 시작):**
```dart
  Widget _buildEmailForm({required bool isLogin}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF222226),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          _buildTextField(
```

**변경:**
```dart
  Widget _buildEmailForm({required bool isLogin}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF222226),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // 로그인/가입 탭 전환
          Row(
            children: [
              _emailTabBtn('로그인', isLoginMode, () {
                setState(() => isLoginMode = true);
              }),
              _emailTabBtn('가입하기', !isLoginMode, () {
                setState(() => isLoginMode = false);
              }),
            ],
          ),
          const SizedBox(height: 14),
          _buildTextField(
```

그리고 `_emailTabBtn`의 `// ignore: unused_element` 주석을 제거한다.

**앵커:**
```dart
  // ignore: unused_element
  Widget _emailTabBtn(String label, bool active, VoidCallback onTap) {
```

**변경:**
```dart
  Widget _emailTabBtn(String label, bool active, VoidCallback onTap) {
```

> **효과**: 이메일 폼 상단에 "로그인 | 가입하기" 탭이 표시된다.
> 탭을 누르면 isLoginMode가 바뀌고, 버튼 텍스트("로그인" / "가입하기")와
> 버튼 색상(블루 / 골드)이 자동으로 전환된다.
> 비밀번호 찾기 링크는 로그인 모드에서만 표시된다 (기존 `if (isLogin)` 유지).

---

### 수정 3: _handleAuth — 이메일 로그인 후에도 birthYear 확인

**파일**: `lib/custom_code/widgets/intro_master.dart`

**앵커 (현재 코드):**
```dart
      // 신규 가입 시 연령 확인
      if (!isLoginMode && mounted) {
        await _checkAgeAndRoute();
        return;
      }
      if (mounted) _routeAfterAuth();
```

**변경:**
```dart
      // 가입/로그인 모두 연령 정보 확인 (birthYear 있으면 자동 통과)
      if (mounted) {
        await _checkAgeAndRoute();
      }
```

> **효과**: 이메일 로그인 시에도 `_checkAgeAndRoute()`가 호출된다.
> 기존 회원은 Firestore에 birthYear가 있으므로 `hasBirthYear=true` → 다이얼로그 스킵 → `_routeAfterAuth()`.
> birthYear가 없는 구 회원은 다이얼로그가 떠서 연령 확인 후 Lobby 진입.
> `_checkAgeAndRoute()` 마지막에 `_routeAfterAuth()`를 호출하므로 기존 `if (mounted) _routeAfterAuth();`는 제거.

**주의**: `_checkAgeAndRoute()` 내부(955줄)에 이미 `if (mounted) _routeAfterAuth();`가 있으므로,
기존의 별도 `_routeAfterAuth()` 호출을 제거해야 이중 호출이 방지된다.
또한 가입 시 보너스 지급(`_grantSignupBonusIfPossible`)도 `_checkAgeAndRoute` 전에
이미 실행되므로 순서 충돌 없음.

---

## Phase 3: 검증

```bash
# 1. 컴파일 확인
dart format lib/custom_code/widgets/intro_master.dart
flutter analyze lib/custom_code/widgets/intro_master.dart

# 2. 수정 1 확인: anonymous 분기
grep "!user.isAnonymous" lib/custom_code/widgets/intro_master.dart
# 기대: _checkEntryStatus 내에서 1줄

# 3. 수정 2 확인: _emailTabBtn 사용
grep "_emailTabBtn" lib/custom_code/widgets/intro_master.dart
# 기대: 정의 1줄 + 호출 2줄 (로그인, 가입하기) = 3줄 이상

# 4. 수정 2 확인: unused_element 주석 제거
grep "unused_element" lib/custom_code/widgets/intro_master.dart
# 기대: 0줄

# 5. 수정 3 확인: _checkAgeAndRoute가 isLoginMode 조건 없이 호출
grep -A2 "grantSignupBonusIfPossible" lib/custom_code/widgets/intro_master.dart | head -5
# _checkAgeAndRoute가 !isLoginMode 조건 밖에서 호출되는지 확인

# 6. 이중 _routeAfterAuth 호출 없음 확인
grep -c "_routeAfterAuth" lib/custom_code/widgets/intro_master.dart
# 기존보다 1줄 줄어들었는지 확인 (기존 _handleAuth 내 단독 호출 제거)
```

---

# Phase 4: 브랜치에서 커밋
git checkout -b fix/intro-auth-gates
git add -A && git commit -m "fix: anonymous gate, email tab toggle, login birthYear check"

# 테스트 후 main 머지
git checkout main
git merge fix/intro-auth-gates
git push origin main
---

## Phase 5: 롤백 (문제 발생 시)

```bash
git revert HEAD --no-edit
git push origin main
```

---

## 수정 영향 범위 확인

| 수정 | 영향 받는 플로우 | 영향 안 받는 플로우 |
|---|---|---|
| 수정 1 (anonymous gate) | 체험 후 앱 재진입, 체험 도중 앱 재진입 | 정식 회원 자동 로그인, Duo 초대 |
| 수정 2 (이메일 탭) | 이메일 가입/로그인 전환 | 카카오/구글 로그인 |
| 수정 3 (로그인 birthYear) | 이메일 로그인 후 Lobby 진입 | 소셜 로그인 (이미 _handleUnifiedAuth에서 처리) |

3개 수정 모두 서로 독립적이며, 기존 소셜 로그인/Duo 초대 플로우에 영향 없음.