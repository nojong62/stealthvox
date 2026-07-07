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

# 지시문 5 (수정판): intro_master.dart 간소화 — Auth 화면 통합 + 14세 미만 보호자 인증

## 목적
현재 3화면 (Welcome / SignUp / LogIn) 구조를
2화면 (Welcome / Auth) 으로 간소화한다.

- SignUp + LogIn → 하나의 Auth 화면으로 통합
- 약관 동의 바텀시트(terms_agreement_sheet) 제거 → 인라인 텍스트로 대체
- 신규 가입자에게 "태어난 해" 확인 → 14세 미만이면 보호자 이메일 수집

## 대상 파일
- **수정**: `lib/custom_code/widgets/intro_master.dart`
- **미사용 처리**: `lib/custom_code/widgets/terms_agreement_sheet.dart` (import 제거, 파일 자체는 보존)

## 선행 조건
- ✅ 지시문 1~4 완료

---

## 핵심 설계

### A. 상태 모델 변경

**현재:**
```dart
enum IntroScreen { welcome, signUp, logIn }
```

**변경:**
```dart
enum IntroScreen { welcome, auth }
```

### B. Auth 화면 — 단일 통합 화면

회원가입과 로그인의 구분이 없다. 사용자는 provider 버튼을 누르기만 하면
백엔드(linkOrCreateAccount / kakaoCustomAuth)가 신규/기존을 자동 판별한다.

```
[상단 좌측] ← 뒤로가기 (Welcome으로)
  — trialCompleted == false일 때만 표시
  — trialCompleted == true이면 뒤로 갈 곳이 없으니 숨김

[중앙]
  "계정으로 계속하기"
  (흰색, 22px, bold)

[카카오톡으로 계속하기]  — 대형 노란색 버튼 (kakao_logo.png 아이콘)
[Google로 계속하기]     — 흰색 버튼 (google_logo.png 아이콘)
[이메일로 계속하기]     — 회색 버튼 → 탭하면 이메일 폼 토글

[이메일 폼] — _showEmailForm == true 일 때만
  이메일 + 비밀번호 + 로그인/가입 탭 전환
  (기존 _buildEmailForm 재사용)

[하단 약관 텍스트]
  "가입하면 이용약관 및 개인정보 처리방침에 동의하는 것으로 간주합니다."
  — 이용약관, 개인정보 처리방침은 밑줄 + 탭 가능 (URL 연결, 현재는 placeholder)
  — 회색 11.5px 텍스트
```

### C. 가입 시 연령 확인 + 보호자 인증 플로우

모든 가입 경로(소셜/이메일)에서 로그인 성공 후,
Firestore `users/{uid}` 문서에 `birthYear` 필드가 없으면 연령 확인 다이얼로그를 띄운다.

```
[로그인 성공 후, birthYear 없음]
  → _showBirthYearDialog() 호출
  → 사용자가 태어난 해 선택 (연도 Picker)
  → 현재 연도 - 태어난 해 >= 14 → Firestore에 birthYear 저장 → Lobby 이동
  → 현재 연도 - 태어난 해 < 14 → 보호자 이메일 입력 다이얼로그
    → 이메일 입력 → Firestore에 저장 (parentEmail, parentConsentPending: true)
    → "보호자에게 동의 요청을 보냈습니다" 안내
    → Lobby 이동
```

> **참고**: 보호자 이메일 발송 + 링크 클릭 인증은 별도 Cloud Function(지시문 6)에서 처리.
> 이 지시문에서는 Firestore에 parentEmail을 저장하는 것까지만 구현.

---

## Phase 0: 사전 진단

```bash
# 1. 현재 IntroScreen enum 확인
grep -n "enum IntroScreen" lib/custom_code/widgets/intro_master.dart
# 기대: enum IntroScreen { welcome, signUp, logIn }

# 2. _buildSignUpView, _buildLogInView 존재 확인
grep -n "_buildSignUpView\|_buildLogInView" lib/custom_code/widgets/intro_master.dart

# 3. _handleSocialSignUp, _handleSocialLogIn, _handleSocialAuth 존재 확인
grep -n "_handleSocialSignUp\|_handleSocialLogIn\|_handleSocialAuth" lib/custom_code/widgets/intro_master.dart

# 4. terms_agreement_sheet import 확인
grep -n "terms_agreement_sheet" lib/custom_code/widgets/intro_master.dart

# 5. _authFooter, _roundAuthButton 존재 확인
grep -n "_authFooter\|_roundAuthButton" lib/custom_code/widgets/intro_master.dart

# 6. _handleAuth (이메일 로그인) 존재 확인
grep -n "_handleAuth" lib/custom_code/widgets/intro_master.dart
```

---

## Phase 1: Savepoint

```bash
git add -A && git commit -m "savepoint: before auth screen unification"
```

---

## Phase 2: 수정 작업

### 삭제 대상 (총 5개 메서드 + 1개 import)

| 대상 | 이유 |
|---|---|
| `import 'terms_agreement_sheet.dart';` | 약관 시트 미사용 |
| `_buildSignUpView()` | Auth 화면으로 통합 |
| `_buildLogInView()` | Auth 화면으로 통합 |
| `_handleSocialSignUp()` | _handleUnifiedAuth로 교체 |
| `_handleSocialLogIn()` | _handleUnifiedAuth로 교체 |
| `_handleSocialAuth()` | _handleUnifiedAuth가 이 로직을 포함 |
| `_authFooter()` | 통합 화면에서 불필요 (화면 전환 링크 없음) |
| `_roundAuthButton()` | 통합 화면에서 전체 크기 버튼만 사용 |

### 유지 대상 (변경 없이 그대로)

| 메서드 | 이유 |
|---|---|
| `_checkEntryStatus()` | Duo invite + 기존 회원 라우팅 |
| `_routeAfterAuth()` | Lobby/StealthRoom 라우팅 |
| `_initAppsFlyer()` | AppsFlyer 초기화 |
| `_startTrial()` | 체험 시작 |
| `_enterTrialAnyone()` | 체험 대화방 진입 |
| `_cleanupTrialSandbox()` | 체험 sandbox 삭제 |
| `_grantSignupBonusIfPossible()` | 가입 보너스 |
| `_resetPassword()` | 비밀번호 재설정 |
| `_showLanguageSettingDialog()` | 언어 설정 |
| `_languageDropdown()` | 언어 드롭다운 |
| `_onDuoInviteSignal()` | Duo 시그널 리스너 |
| `_buildWelcomeView()` | Welcome 화면 (일부 수정만) |
| `_buildAuthScaffold()` | Auth 화면 공통 래퍼 |
| `_buildEmailForm()` | 이메일 입력 폼 |
| `_buildTextField()` | 텍스트 입력 필드 |
| `_buildWaveform()` | 파형 위젯 |
| `_buildBentoCard()` | 벤토 카드 |
| `_buildTrialGuideCard()` | 체험 안내 카드 |
| `_emailTabBtn()` | 이메일 탭 버튼 |

### 2-1: enum 변경

기존:
```dart
enum IntroScreen { welcome, signUp, logIn }
```

변경:
```dart
enum IntroScreen { welcome, auth }
```

### 2-2: import 변경

기존:
```dart
import 'terms_agreement_sheet.dart';
```

**이 줄을 삭제한다.**

### 2-3: initState 변경

기존:
```dart
    if (FFAppState().trialCompleted) {
      _currentScreen = IntroScreen.signUp;
    } else {
      _currentScreen = IntroScreen.welcome;
    }
```

변경:
```dart
    if (FFAppState().trialCompleted) {
      _currentScreen = IntroScreen.auth;
    } else {
      _currentScreen = IntroScreen.welcome;
    }
```

### 2-4: _buildMain switch 변경

기존:
```dart
  Widget _buildMain(BuildContext context) {
    switch (_currentScreen) {
      case IntroScreen.welcome:
        return _buildWelcomeView(context);
      case IntroScreen.signUp:
        return _buildSignUpView(context);
      case IntroScreen.logIn:
        return _buildLogInView(context);
    }
  }
```

변경:
```dart
  Widget _buildMain(BuildContext context) {
    switch (_currentScreen) {
      case IntroScreen.welcome:
        return _buildWelcomeView(context);
      case IntroScreen.auth:
        return _buildAuthView(context);
    }
  }
```

### 2-5: Welcome 화면의 "로그인" 버튼 목적지 변경

앵커 (Welcome 화면 하단 로그인 버튼의 onPressed 내):
```dart
                            setState(() {
                              _currentScreen = IntroScreen.logIn;
                              _showEmailForm = false;
                              isLoginMode = true;
                            });
```

변경:
```dart
                            setState(() {
                              _currentScreen = IntroScreen.auth;
                              _showEmailForm = false;
                            });
```

### 2-6: _handleAuth (이메일 경로) — birthYear 체크 추가

앵커 (_handleAuth 내부, 가입 성공 후 Lobby 이동 직전):
```dart
      if (!isLoginMode) {
        await _grantSignupBonusIfPossible();
      }
      if (mounted) _routeAfterAuth();
```

변경:
```dart
      if (!isLoginMode) {
        await _grantSignupBonusIfPossible();
      }
      // 신규 가입 시 연령 확인
      if (!isLoginMode && mounted) {
        await _checkAgeAndRoute();
        return;
      }
      if (mounted) _routeAfterAuth();
```

### 2-7: _buildSignUpView + _buildLogInView 삭제, _buildAuthView 로 교체

`_buildSignUpView` 메서드 전체 (현재 671~767줄)와
`_buildLogInView` 메서드 전체 (현재 769~849줄)를 삭제하고,
아래의 `_buildAuthView` 하나로 교체한다.

```dart
  Widget _buildAuthView(BuildContext context) {
    return _buildAuthScaffold(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 뒤로가기: 체험 완료 전에만 표시
          if (!FFAppState().trialCompleted)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => setState(() {
                  _currentScreen = IntroScreen.welcome;
                  _showEmailForm = false;
                }),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: '뒤로',
              ),
            ),
          SizedBox(height: FFAppState().trialCompleted ? 60 : 24),
          // 제목
          const Text(
            '계정으로 계속하기',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 34),
          // 카카오 버튼
          SharedSocialButton(
            label: '카카오톡으로 계속하기',
            backgroundColor: const Color(0xFFFEE500),
            textColor: const Color(0xFF191919),
            icon: Image.asset(
              'assets/images/kakao_logo.png',
              width: 20,
              height: 20,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.chat_bubble,
                size: 20,
                color: Color(0xFF191919),
              ),
            ),
            onTap: () => _handleUnifiedAuth(SocialAuthService.signInWithKakao),
          ),
          const SizedBox(height: 12),
          // Google 버튼
          SharedSocialButton(
            label: 'Google로 계속하기',
            backgroundColor: Colors.white,
            textColor: Colors.black87,
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            icon: Image.asset(
              'assets/images/google_logo.png',
              width: 20,
              height: 20,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.g_mobiledata,
                size: 24,
                color: Colors.blue,
              ),
            ),
            onTap: () => _handleUnifiedAuth(SocialAuthService.signInWithGoogle),
          ),
          const SizedBox(height: 12),
          // 이메일 버튼
          SharedSocialButton(
            label: '이메일로 계속하기',
            backgroundColor: const Color(0xFF33333A),
            textColor: Colors.white,
            icon: const Icon(Icons.email_outlined, size: 20, color: Colors.white70),
            onTap: () => setState(() {
              _showEmailForm = !_showEmailForm;
            }),
          ),
          // 이메일 폼
          if (_showEmailForm) ...[
            const SizedBox(height: 18),
            _buildEmailForm(isLogin: isLoginMode),
          ],
          const SizedBox(height: 32),
          // 약관 동의 인라인 텍스트
          _buildTermsInlineText(),
        ],
      ),
    );
  }
```

### 2-8: _handleSocialSignUp + _handleSocialLogIn + _handleSocialAuth → _handleUnifiedAuth 교체

3개 메서드를 모두 삭제하고 아래 하나로 교체:

```dart
  /// 통합 소셜 인증: 약관 시트 없이 바로 소셜 로그인 → 신규면 연령 확인
  Future<void> _handleUnifiedAuth(Future<dynamic> Function() authFn) async {
    debugPrint('[Auth] _handleUnifiedAuth enter');
    setState(() => isLoading = true);
    try {
      await _cleanupTrialSandbox();
      await authFn();
      debugPrint(
          '[Auth] authFn complete, currentUser=${FirebaseAuth.instance.currentUser?.uid}');
      await _grantSignupBonusIfPossible();

      if (!mounted) return;
      await _checkAgeAndRoute();
    } catch (e, stack) {
      debugPrint('[Auth] _handleUnifiedAuth exception: $e');
      debugPrint('[Auth] stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }
```

### 2-9: _checkAgeAndRoute 신규 메서드

소셜/이메일 공통으로 사용하는 연령 확인 + 라우팅 메서드.

```dart
  /// 연령 확인 후 라우팅 (소셜/이메일 공통)
  Future<void> _checkAgeAndRoute() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final hasBirthYear =
          userDoc.exists && userDoc.data()?['birthYear'] != null;
      if (!hasBirthYear && mounted) {
        await _showBirthYearDialog();
      }
    } catch (e) {
      debugPrint('[Auth] birthYear check failed (non-blocking): $e');
    }

    if (mounted) _routeAfterAuth();
  }
```

### 2-10: _showBirthYearDialog 신규 메서드

```dart
  /// 신규 가입 시 태어난 해 확인 + 14세 미만 보호자 이메일 수집
  Future<void> _showBirthYearDialog() async {
    final currentYear = DateTime.now().year;
    int selectedYear = currentYear - 20;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161616),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF2A3A36), width: 1),
              ),
              title: const Text(
                '태어난 해를 알려주세요',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
              content: SizedBox(
                height: 150,
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 42,
                  physics: const FixedExtentScrollPhysics(),
                  controller: FixedExtentScrollController(
                    initialItem: 40, // currentYear-60 기준 +40 → 약 20세
                  ),
                  onSelectedItemChanged: (index) {
                    setDialogState(
                        () => selectedYear = (currentYear - 60) + index);
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    builder: (context, index) {
                      final year = (currentYear - 60) + index;
                      if (year < currentYear - 60 || year > currentYear - 4) {
                        return null;
                      }
                      return Center(
                        child: Text(
                          '$year년',
                          style: TextStyle(
                            color: year == selectedYear
                                ? Colors.white
                                : Colors.white38,
                            fontSize: year == selectedYear ? 20 : 16,
                            fontWeight: year == selectedYear
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                    childCount: 57,
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90D9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('확인',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final age = currentYear - selectedYear;
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);

    if (age >= 14) {
      await userRef.set({'birthYear': selectedYear}, SetOptions(merge: true));
    } else {
      final parentEmail = await _showParentEmailDialog();
      if (parentEmail != null && parentEmail.isNotEmpty) {
        await userRef.set({
          'birthYear': selectedYear,
          'parentEmail': parentEmail,
          'parentConsentPending': true,
        }, SetOptions(merge: true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '보호자에게 동의 요청을 보냈습니다.\n보호자가 동의하면 모든 기능을 이용할 수 있습니다.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Color(0xFF4A90D9),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        await userRef
            .set({'birthYear': selectedYear}, SetOptions(merge: true));
      }
    }
  }
```

### 2-11: _showParentEmailDialog 신규 메서드

```dart
  /// 14세 미만: 보호자 이메일 입력 다이얼로그
  Future<String?> _showParentEmailDialog() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161616),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF2A3A36), width: 1),
          ),
          title: const Text(
            '보호자 동의가 필요합니다',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '만 14세 미만은 보호자 동의가 필요합니다.\n보호자의 이메일 주소를 입력해 주세요.',
                style: TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '보호자 이메일',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon:
                      const Icon(Icons.email_outlined, color: Colors.white38),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child:
                  const Text('나중에', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                final email = controller.text.trim();
                Navigator.of(dialogContext).pop(email.isEmpty ? null : email);
              },
              child: const Text('동의 요청 보내기',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }
```

### 2-12: _buildTermsInlineText 신규 메서드

```dart
  Widget _buildTermsInlineText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
              color: Color(0xFF8A8A94), fontSize: 11.5, height: 1.4),
          children: [
            const TextSpan(text: '가입하면 '),
            TextSpan(
              text: '이용약관',
              style: const TextStyle(
                decoration: TextDecoration.underline,
                color: Color(0xFFAAAAAA),
              ),
              // TODO: recognizer → URL 연결 (GestureRecognizer)
            ),
            const TextSpan(text: ' 및 '),
            TextSpan(
              text: '개인정보 처리방침',
              style: const TextStyle(
                decoration: TextDecoration.underline,
                color: Color(0xFFAAAAAA),
              ),
              // TODO: recognizer → URL 연결 (GestureRecognizer)
            ),
            const TextSpan(text: '에 동의하는 것으로 간주합니다.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
```

### 2-13: _authFooter + _roundAuthButton 삭제

`_authFooter` 메서드 전체 (현재 994~1018줄)를 삭제한다.
`_roundAuthButton` 메서드 전체 (현재 956~992줄)를 삭제한다.

통합 Auth 화면에서는 화면 전환 링크와 소형 원형 버튼이 불필요하다.

---

## Phase 3: 검증

```bash
# 1. 컴파일 확인
dart format lib/custom_code/widgets/intro_master.dart
flutter analyze lib/custom_code/widgets/intro_master.dart

# 2. enum 변경 확인
grep "enum IntroScreen" lib/custom_code/widgets/intro_master.dart
# 기대: enum IntroScreen { welcome, auth }

# 3. 삭제 확인 — signUp, logIn이 enum에서 사라졌는지
grep "IntroScreen.signUp\|IntroScreen.logIn" lib/custom_code/widgets/intro_master.dart
# 기대: 0줄

# 4. 삭제 확인 — 구 메서드들
grep "_handleSocialSignUp\|_handleSocialLogIn\|_handleSocialAuth\|_authFooter\|_roundAuthButton\|_buildSignUpView\|_buildLogInView" lib/custom_code/widgets/intro_master.dart
# 기대: 0줄

# 5. 신규 메서드 존재 확인
grep "_handleUnifiedAuth\|_buildAuthView\|_buildTermsInlineText\|_showBirthYearDialog\|_showParentEmailDialog\|_checkAgeAndRoute" lib/custom_code/widgets/intro_master.dart
# 기대: 6줄 이상

# 6. terms_agreement_sheet import 제거 확인
grep "terms_agreement_sheet" lib/custom_code/widgets/intro_master.dart
# 기대: 0줄

# 7. birthYear 체크가 이메일 경로에도 있는지 확인
grep "_checkAgeAndRoute" lib/custom_code/widgets/intro_master.dart
# 기대: 3줄 (정의 1 + 소셜 호출 1 + 이메일 호출 1)
```

---

## Phase 4: 커밋

```bash
git add -A && git commit -m "feat: unify auth screen, inline terms, add birth year + parental consent"
git push origin main
```

---

## Phase 5: 롤백 (문제 발생 시)

```bash
git revert HEAD --no-edit
git push origin main
```

---

## 후속 작업 (지시문 6으로 분리)

- Cloud Function `sendParentConsentEmail`: 보호자 이메일로 동의 링크 발송
- 동의 링크 클릭 시 Firestore `parentConsentPending` → `false` 업데이트
- 이용약관 / 개인정보 처리방침 URL 연결 (웹페이지 준비 후)
- Lobby에서 `parentConsentPending == true`인 사용자에게 기능 제한 적용 (선택적)