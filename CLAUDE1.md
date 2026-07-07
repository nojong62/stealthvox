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

# 지시문 2: intro_master.dart 전면 개편

## 목적
현재 `_isSignupMode` 토글 기반의 2모드 구조를 폐지하고,
스픽 스타일의 3화면 구조 (Welcome / SignUp / LogIn) + 약관 동의 시트로 전면 개편한다.

## 대상 파일
- **전면 수정**: `lib/custom_code/widgets/intro_master.dart`
- **역할 축소**: `lib/custom_code/widgets/trial_signup_sheet.dart` → 더 이상 사용하지 않음 (삭제하지는 않고 import만 제거)
- **신규 import**: `terms_agreement_sheet.dart` (지시문 1에서 생성)

## 선행 조건
- ✅ 지시문 1 완료 (`terms_agreement_sheet.dart` 존재)

---

## 핵심 설계 변경사항

### A. 상태 모델 변경

**기존:**
```dart
bool isLoginMode = true;       // 이메일 로그인/회원가입 토글
bool _isSignupMode = false;    // 체험화면 vs 가입화면 토글
bool _showEmailInSignup = false;
```

**변경:**
```dart
enum IntroScreen { welcome, signUp, logIn }

IntroScreen _currentScreen = IntroScreen.welcome;
bool _showEmailForm = false;   // 가입/로그인 모두에서 이메일 폼 토글
bool isLoginMode = true;       // 이메일 폼 내부의 로그인/회원가입 토글 (유지)
```

### B. 화면 분기 로직

```dart
Widget _buildMain(BuildContext context) {
  switch (_currentScreen) {
    case IntroScreen.welcome:
      return _buildWelcomeView(context);    // 체험 버튼 + "로그인하세요" 링크
    case IntroScreen.signUp:
      return _buildSignUpView(context);     // 가입 유도 (체험 완료 후)
    case IntroScreen.logIn:
      return _buildLogInView(context);      // 로그인 전용
  }
}
```

### C. 초기 화면 결정 로직 (initState)

```dart
// 기존: if (FFAppState().trialCompleted) _isSignupMode = true;
// 변경:
if (FFAppState().trialCompleted) {
  _currentScreen = IntroScreen.signUp;
} else {
  _currentScreen = IntroScreen.welcome;
}
```

### D. 체험 완료 기준 변경

**기존**: 공부방 2분까지 모두 마쳐야 완료
**변경**: 대화방 1분을 끝까지 채운 시점에 `trialCompleted = true`

- 대화방 1분 중간에 나감 → `trialCompleted` 변경 없음 (false 유지) → 재진입 시 Welcome 화면 → 체험 처음부터 다시
- 대화방 1분 완료 → `trialCompleted = true` 확정 → 공부방 진입 여부와 무관하게 재진입 시 SignUp 화면

> **주의**: 이 변경은 intro_master.dart 자체가 아닌, 대화방 모드 파일(routine_mode_anyone.dart 등)에서
> 타이머 종료 시 `FFAppState().trialCompleted = true`를 찍는 위치 변경이 필요할 수 있다.
> 현재 _cleanupTrialSandbox()에서 `FFAppState().trialCompleted = true`를 찍고 있는데,
> 이 시점을 "대화방 1분 완료 콜백"으로 이동해야 한다.
> → 이 부분은 Phase 2에서 _cleanupTrialSandbox() 수정 시 함께 처리.

---

## Phase 0: 사전 진단

```bash
# 1. 현재 파일 줄 수 확인
wc -l lib/custom_code/widgets/intro_master.dart

# 2. _isSignupMode 사용 위치 확인
grep -n "_isSignupMode" lib/custom_code/widgets/intro_master.dart

# 3. _buildSignupView 사용 위치 확인
grep -n "_buildSignupView" lib/custom_code/widgets/intro_master.dart

# 4. trialCompleted 설정 위치 확인
grep -rn "trialCompleted" lib/custom_code/widgets/intro_master.dart

# 5. trial_signup_sheet import 확인
grep -rn "trial_signup_sheet" lib/custom_code/widgets/

# 6. terms_agreement_sheet 존재 확인 (지시문 1 완료 여부)
ls lib/custom_code/widgets/terms_agreement_sheet.dart
```

---

## Phase 1: Savepoint

```bash
git add -A && git commit -m "savepoint: before intro_master overhaul"
```

---

## Phase 2: 수정 작업

이 파일은 1143줄의 전면 개편이므로, **전체 파일을 새로 작성**하는 방식이 안전하다.
기존 파일을 백업 후 새 파일로 교체한다.

```bash
# 백업
cp lib/custom_code/widgets/intro_master.dart lib/custom_code/widgets/intro_master.dart.bak
```

### 새 intro_master.dart 작성 시 반드시 유지해야 할 기존 로직

아래 함수/로직은 현재 파일에서 그대로 가져와야 한다 (수정 금지 또는 최소 수정):

1. **`_checkEntryStatus()`** — Duo invite 체크 + AppsFlyer 초기화 + 기존 회원 Lobby 라우팅
2. **`_routeAfterAuth()`** — pending Duo invite → StealthRoom, 그 외 → Lobby
3. **`_initAppsFlyer()`** — AppsFlyer 초기화
4. **`_startTrial()`** — 체험 시작 (익명 로그인 + 언어 설정 + 대화방 진입)
5. **`_enterTrialAnyone()`** — Firestore chat_history 생성 + StealthRoom pushNamed
6. **`_handleAuth()`** — 이메일 로그인/회원가입 (linkWithCredential 포함)
7. **`_resetPassword()`** — 비밀번호 재설정
8. **`_handleSocialAuth()`** — 소셜 로그인 처리
9. **`_cleanupTrialSandbox()`** — 체험 sandbox 삭제
10. **`_grantSignupBonusIfPossible()`** — 가입 보너스 지급
11. **`_showLanguageSettingDialog()`** — 언어 설정 다이얼로그
12. **`_languageDropdown()`** — 언어 드롭다운 위젯
13. **`_onDuoInviteSignal()`** — Duo 초대 시그널 리스너
14. **`_buildTextField()`** — 이메일/비밀번호 입력 필드
15. **`_buildWaveform()`** — 파형 위젯 (Welcome 화면에서 사용)
16. **`_buildBentoCard()`** — 벤토 카드 위젯
17. **`_buildTrialGuideCard()`** — 체험 안내 카드
18. **`_emailTabBtn()`** — 이메일 탭 버튼

### 삭제할 요소

- `bool _isSignupMode` → `IntroScreen _currentScreen` 으로 대체
- `bool _showEmailInSignup` → `bool _showEmailForm` 으로 이름 변경
- `_buildSignupView()` → `_buildSignUpView()` + `_buildLogInView()` 2개로 분리

### 새로 추가할 요소

- `enum IntroScreen { welcome, signUp, logIn }`
- `import 'terms_agreement_sheet.dart';`
- `_buildSignUpView()` — 가입 전용 화면
- `_buildLogInView()` — 로그인 전용 화면
- `_handleSocialSignUp()` — 약관 동의 → 소셜 로그인 (가입 경로)
- `_handleSocialLogIn()` — 약관 없이 소셜 로그인 (로그인 경로)

### 화면별 상세 구성

#### 화면 ① Welcome (= 현재 Intro A)

기존 `_buildMain()`의 `!_isSignupMode` 분기 내용을 기반으로 구성.
**변경사항:**
- 하단 "로그인" 버튼의 onPressed를 `setState(() => _isSignupMode = true)` 에서
  `setState(() => _currentScreen = IntroScreen.logIn)` 으로 변경
- 체험 버튼, 벤토카드, 체험안내카드, 이용방법 등은 그대로 유지

#### 화면 ② SignUp (체험 완료 후 가입 유도)

스픽 이미지 1 참고. 새로 작성:
```
[드래그 핸들 없음 — 전체 화면]

[상단 우측] "로그인" 텍스트 링크 → IntroScreen.logIn

[중앙]
  "계속하시려면 먼저
   가입해주세요"
  (흰색, 22px, bold, 중앙 정렬)

[카카오톡으로 계속하기] — 대형 노란색 버튼
  onTap: _handleSocialSignUp(SocialAuthService.signInWithKakao)

[다른 방법으로 가입하기] — 회색 텍스트
  [이메일 아이콘] [Google 아이콘]  — 원형 버튼 2개
  이메일 아이콘 onTap: setState(() => _showEmailForm = true)
  Google 아이콘 onTap: _handleSocialSignUp(SocialAuthService.signInWithGoogle)

[이메일 폼] — _showEmailForm == true 일 때만 표시
  이메일 + 비밀번호 + "가입하기" 버튼
  (기존 _buildTextField 재사용)
  (isLoginMode = false 고정)

[하단]
  "이미 계정이 있으신가요? 바로"
  "로그인하세요" — 파란색 텍스트 링크
  onTap: setState(() => _currentScreen = IntroScreen.logIn)
```

#### 화면 ③ LogIn (로그인 전용)

스픽 이미지 3 참고. 새로 작성:
```
[상단 좌측] ← 뒤로가기 아이콘
  onTap: setState(() {
    _currentScreen = FFAppState().trialCompleted
        ? IntroScreen.signUp
        : IntroScreen.welcome;
  })

[중앙 상단]
  "로그인하고
   계속하기"
  (흰색, 22px, bold, 중앙 정렬)

[카카오톡으로 계속하기] — 대형 노란색 버튼
[Google로 계속하기] — 흰색 버튼
[이메일로 계속하기] — 회색 버튼
  → 각각 _handleSocialLogIn() 또는 이메일 폼 토글

[이메일 폼] — _showEmailForm == true 일 때만
  이메일 + 비밀번호 + "로그인" 버튼 + "비밀번호 찾기"
  (isLoginMode = true 고정)

[하단]
  "계정이 없으신가요?"
  "가입하기" — 파란색 텍스트 링크
  onTap: setState(() => _currentScreen = IntroScreen.signUp)
```

### 핵심 메서드: _handleSocialSignUp

```dart
/// 회원가입 경로: 약관 동의 → 소셜 로그인
Future<void> _handleSocialSignUp(Future<dynamic> Function() authFn) async {
  // 1. 약관 동의 시트 표시
  final termsResult = await TermsAgreementSheet.show(context);
  if (termsResult == null) return; // 취소

  // 2. 기존 _handleSocialAuth 로직 실행
  await _handleSocialAuth(authFn);

  // 3. 마케팅 동의 여부를 Firestore에 저장 (향후)
  // TODO: termsResult.marketingAccepted → users/{uid}/marketing_consent
}
```

### 핵심 메서드: _handleSocialLogIn

```dart
/// 로그인 경로: 약관 없이 바로 소셜 로그인
Future<void> _handleSocialLogIn(Future<dynamic> Function() authFn) async {
  await _handleSocialAuth(authFn);
}
```

> 참고: `_handleSocialLogIn`은 사실상 `_handleSocialAuth`의 래퍼이지만,
> 향후 로그인 전용 로직(기존 계정 없으면 안내 등)을 추가할 여지를 위해 분리해둔다.

---

## Phase 3: 검증

```bash
# 1. 새 파일 컴파일 확인
dart format lib/custom_code/widgets/intro_master.dart
flutter analyze lib/custom_code/widgets/intro_master.dart

# 2. enum 사용 확인
grep -c "IntroScreen" lib/custom_code/widgets/intro_master.dart
# 기대: 10 이상

# 3. _isSignupMode 완전 제거 확인
grep -c "_isSignupMode" lib/custom_code/widgets/intro_master.dart
# 기대: 0

# 4. 3개 화면 빌드 메서드 존재 확인
grep -c "_buildWelcomeView\|_buildSignUpView\|_buildLogInView" lib/custom_code/widgets/intro_master.dart
# 기대: 3 이상 (정의 + 호출)

# 5. terms_agreement_sheet import 확인
grep "terms_agreement_sheet" lib/custom_code/widgets/intro_master.dart
# 기대: 1줄

# 6. trial_signup_sheet import 없음 확인
grep "trial_signup_sheet" lib/custom_code/widgets/intro_master.dart
# 기대: 0줄
```

---

## Phase 4: 커밋

```bash
git add -A && git commit -m "feat: overhaul intro_master with 3-screen model (Welcome/SignUp/LogIn)"
git push origin main
```

---

## Phase 5: 롤백 (문제 발생 시)

```bash
# 백업 파일에서 복원
cp lib/custom_code/widgets/intro_master.dart.bak lib/custom_code/widgets/intro_master.dart
git add -A && git commit -m "rollback: restore intro_master from backup"
git push origin main
```

---

## 추가 주의사항

### trial_signup_sheet.dart 처리
- 파일 자체는 삭제하지 않는다 (다른 곳에서 import하고 있을 수 있음)
- intro_master.dart에서의 import만 제거
- 추후 전체 프로젝트에서 `trial_signup_sheet` 사용처를 확인 후 안전하게 제거

### 체험 완료 시점 변경 관련
- 현재 `_cleanupTrialSandbox()`에서 `FFAppState().trialCompleted = true` 를 설정
- 이것은 "소셜 로그인 시 sandbox 정리 단계"에서 찍히는 것
- **대화방 1분 완료 시점**에도 별도로 `FFAppState().trialCompleted = true`를 찍어야 함
- 이 변경은 `routine_mode_anyone.dart`의 체험 타이머 종료 콜백에서 처리 필요
- → 별도 지시문으로 분리 권장 (이 지시문 범위 밖)

### _checkEntryStatus() 변경사항
- 기존: `user != null` → `_routeAfterAuth()` (Lobby 이동)
- 변경 없음: 이미 로그인된 사용자는 여전히 Lobby로 이동
- IntroScreen 상태는 로그인되지 않은 사용자에게만 의미 있음

지시문 2는 intro_master.dart 1143줄 전면 개편이라 지시문 1, 3과는 규모가 다릅니다. Codex가 전체 파일을 새로 작성하는 방식으로 갈 가능성이 높은데, 그 경우 기존 18개 핵심 메서드가 빠짐없이 포함되었는지 확인이 중요합니다. 특히:

_checkEntryStatus() — Duo invite + 기존 회원 라우팅
_cleanupTrialSandbox() — 체험 sandbox 삭제
_handleSocialAuth() — 소셜 로그인 처리
_onDuoInviteSignal() — Duo 시그널 리스너

이 4개가 빠지면 앱이 깨지니, Codex가 결과를 보여줄 때 이것들이 있는지 확인해주세요.