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

# 지시문 8: 재방문 사용자 안내 — lastAuthProvider + Auth 화면 개선

## 목적
1. 로그인 성공 시 사용한 provider를 SharedPreferences에 저장
2. Auth 화면 재진입 시 "이전에 카카오로 가입했습니다" 안내 + 해당 버튼 강조
3. 이메일 로그인/가입 시에도 `trialCompleted = true` + `lastAuthProvider` 저장

## 대상 파일
- **수정**: `lib/custom_code/widgets/intro_master.dart` (3곳)

## 선행 조건
- ✅ 지시문 1~7 완료

---

## Phase 0: 사전 진단

```bash
# 1. lastAuthProvider 사용 여부 (아직 없어야 함)
grep -n "lastAuthProvider" lib/custom_code/widgets/intro_master.dart
# 기대: 0줄

# 2. FFAppState에 lastAuthProvider 필드가 있는지 확인
grep -rn "lastAuthProvider" lib/
# 없으면 FFAppState에 추가 필요

# 3. _handleUnifiedAuth에서 authFn 호출 직후 위치 확인
grep -n "await authFn()" lib/custom_code/widgets/intro_master.dart

# 4. _handleAuth에서 _checkAgeAndRoute 호출 위치 확인
grep -n "_checkAgeAndRoute" lib/custom_code/widgets/intro_master.dart
```

> **Phase 0 결과에 따른 분기**:
> `FFAppState`에 `lastAuthProvider` 필드가 없으면 먼저 추가해야 한다.
> `FFAppState`는 SharedPreferences 기반이므로 `String` 타입 필드를 추가한다.
> 
> ```bash
> grep -n "class FFAppState" lib/app_state.dart
> grep -n "trialCompleted" lib/app_state.dart
> ```
>
> `trialCompleted`가 정의된 방식과 동일하게 `lastAuthProvider`를 추가한다.
> (getter/setter + SharedPreferences 읽기/쓰기)
>
> 값: `'kakao'` | `'google'` | `'email'` | `''` (미설정)

---

## Phase 1: Savepoint

```bash
git checkout -b feat/last-auth-provider
git add -A && git commit -m "savepoint: before lastAuthProvider feature"
```

---

## Phase 2: 수정

### 2-0: FFAppState에 lastAuthProvider 추가 (Phase 0에서 없는 경우)

**파일**: `lib/app_state.dart`

`trialCompleted` 필드와 동일한 패턴으로 추가:

```dart
// SharedPreferences key
static const String _kLastAuthProvider = 'ff_lastAuthProvider';

String _lastAuthProvider = '';
String get lastAuthProvider => _lastAuthProvider;
set lastAuthProvider(String val) {
  _lastAuthProvider = val;
  _safePrefs((prefs) => prefs.setString(_kLastAuthProvider, val));
}
```

그리고 `initializePersistedState()` 또는 유사한 초기화 메서드에:
```dart
_lastAuthProvider = prefs.getString(_kLastAuthProvider) ?? '';
```

> **주의**: FFAppState의 정확한 구조는 프로젝트마다 다르다.
> Phase 0에서 `trialCompleted`의 패턴을 grep으로 확인하고 동일하게 따라야 한다.
> `_safePrefs` 같은 헬퍼가 없으면 직접 `SharedPreferences.getInstance()`를 사용.

---

### 2-1: _handleUnifiedAuth — lastAuthProvider 저장

**파일**: `lib/custom_code/widgets/intro_master.dart`

소셜 로그인 시 어떤 provider를 썼는지 알아야 하므로, `_handleUnifiedAuth`에 provider 이름 파라미터를 추가한다.

**앵커 (현재 코드):**
```dart
  Future<void> _handleUnifiedAuth(Future<dynamic> Function() authFn) async {
```

**변경:**
```dart
  Future<void> _handleUnifiedAuth(
    Future<dynamic> Function() authFn, {
    String provider = '',
  }) async {
```

그리고 `trialCompleted = true` 바로 다음 줄에 추가:

**앵커 (현재 코드):**
```dart
      await authFn();
      FFAppState().trialCompleted = true;
```

**변경:**
```dart
      await authFn();
      FFAppState().trialCompleted = true;
      if (provider.isNotEmpty) {
        FFAppState().lastAuthProvider = provider;
      }
```

---

### 2-2: _buildAuthView — provider 파라미터 전달 + 호출부 수정

**파일**: `lib/custom_code/widgets/intro_master.dart`

카카오 버튼 onTap:

**앵커:**
```dart
            onTap: () => _handleUnifiedAuth(SocialAuthService.signInWithKakao),
```

**변경:**
```dart
            onTap: () => _handleUnifiedAuth(SocialAuthService.signInWithKakao, provider: 'kakao'),
```

Google 버튼 onTap:

**앵커:**
```dart
            onTap: () => _handleUnifiedAuth(SocialAuthService.signInWithGoogle),
```

**변경:**
```dart
            onTap: () => _handleUnifiedAuth(SocialAuthService.signInWithGoogle, provider: 'google'),
```

---

### 2-3: _handleAuth — 이메일 경로에도 trialCompleted + lastAuthProvider 저장

**파일**: `lib/custom_code/widgets/intro_master.dart`

**앵커 (현재 코드):**
```dart
      if (!isLoginMode) {
        await _grantSignupBonusIfPossible();
      }
      // 가입/로그인 모두 연령 정보 확인 (birthYear 있으면 자동 통과)
```

**변경:**
```dart
      FFAppState().trialCompleted = true;
      FFAppState().lastAuthProvider = 'email';
      if (!isLoginMode) {
        await _grantSignupBonusIfPossible();
      }
      // 가입/로그인 모두 연령 정보 확인 (birthYear 있으면 자동 통과)
```

---

### 2-4: _buildAuthView — 재방문 사용자 안내 UI 추가

**파일**: `lib/custom_code/widgets/intro_master.dart`

`_buildAuthView` 메서드를 전면 교체한다. 현재 3개 버튼이 동일 크기로 나열되어 있는데,
`lastAuthProvider`가 있으면 레이아웃을 변경한다.

**앵커 (현재 코드, 제목 ~ 이메일 버튼 사이 전체):**
```dart
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
            icon: const Icon(
              Icons.email_outlined,
              size: 20,
              color: Colors.white70,
            ),
            onTap: () => setState(() {
              _showEmailForm = !_showEmailForm;
            }),
          ),
```

**변경:**
```dart
          // 제목 + 재방문 안내
          ..._buildAuthHeader(),
          const SizedBox(height: 34),
          // provider 버튼들 (재방문 시 이전 provider 강조)
          ..._buildProviderButtons(),
```

---

### 2-5: _buildAuthHeader 신규 메서드

```dart
  List<Widget> _buildAuthHeader() {
    final lastProvider = FFAppState().lastAuthProvider;
    final providerLabel = switch (lastProvider) {
      'kakao' => '카카오',
      'google' => 'Google',
      'email' => '이메일',
      _ => '',
    };

    return [
      Text(
        lastProvider.isNotEmpty ? '$providerLabel 계정으로\n계속하기' : '계정으로 계속하기',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.32,
        ),
      ),
      if (lastProvider.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          '이전에 $providerLabel 계정으로 가입했습니다',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9C9CA6),
            fontSize: 13,
          ),
        ),
      ],
    ];
  }
```

---

### 2-6: _buildProviderButtons 신규 메서드

```dart
  List<Widget> _buildProviderButtons() {
    final lastProvider = FFAppState().lastAuthProvider;

    // 각 provider 버튼 정의
    Widget kakaoBtn({bool large = true}) => SharedSocialButton(
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
          onTap: () => _handleUnifiedAuth(
              SocialAuthService.signInWithKakao,
              provider: 'kakao'),
        );

    Widget googleBtn({bool large = true}) => SharedSocialButton(
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
          onTap: () => _handleUnifiedAuth(
              SocialAuthService.signInWithGoogle,
              provider: 'google'),
        );

    Widget emailBtn() => SharedSocialButton(
          label: '이메일로 계속하기',
          backgroundColor: const Color(0xFF33333A),
          textColor: Colors.white,
          icon: const Icon(
            Icons.email_outlined,
            size: 20,
            color: Colors.white70,
          ),
          onTap: () => setState(() {
            _showEmailForm = !_showEmailForm;
          }),
        );

    // 이전 provider가 없으면 기본 순서
    if (lastProvider.isEmpty) {
      return [
        kakaoBtn(),
        const SizedBox(height: 12),
        googleBtn(),
        const SizedBox(height: 12),
        emailBtn(),
      ];
    }

    // 이전 provider가 있으면: 해당 버튼을 위에 크게, 나머지는 "다른 계정으로 계속하기" 아래에
    Widget primaryBtn;
    List<Widget> secondaryBtns;

    switch (lastProvider) {
      case 'kakao':
        primaryBtn = kakaoBtn();
        secondaryBtns = [googleBtn(), const SizedBox(height: 12), emailBtn()];
        break;
      case 'google':
        primaryBtn = googleBtn();
        secondaryBtns = [kakaoBtn(), const SizedBox(height: 12), emailBtn()];
        break;
      case 'email':
        primaryBtn = emailBtn();
        secondaryBtns = [kakaoBtn(), const SizedBox(height: 12), googleBtn()];
        break;
      default:
        primaryBtn = kakaoBtn();
        secondaryBtns = [googleBtn(), const SizedBox(height: 12), emailBtn()];
    }

    return [
      primaryBtn,
      const SizedBox(height: 24),
      const Text(
        '다른 계정으로 계속하기',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF9C9CA6),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      ...secondaryBtns,
    ];
  }
```

---

## Phase 3: 검증

```bash
# 1. 컴파일 확인
dart format lib/custom_code/widgets/intro_master.dart
flutter analyze lib/custom_code/widgets/intro_master.dart

# 2. lastAuthProvider 사용 확인
grep -c "lastAuthProvider" lib/custom_code/widgets/intro_master.dart
# 기대: 8줄 이상

# 3. provider 파라미터 전달 확인
grep "provider: 'kakao'\|provider: 'google'\|provider: 'email'" lib/custom_code/widgets/intro_master.dart
# 기대: 3줄

# 4. 신규 메서드 존재 확인
grep "_buildAuthHeader\|_buildProviderButtons" lib/custom_code/widgets/intro_master.dart
# 기대: 4줄 이상 (정의 2 + 호출 2)

# 5. FFAppState lastAuthProvider 존재 확인
grep "lastAuthProvider" lib/app_state.dart
# 기대: 3줄 이상 (getter, setter, 초기화)
```

---

## Phase 4: 빌드 및 테스트

```bash
flutter clean
flutter pub get
flutter build apk --release
```

### 테스트 시나리오

**시나리오 A: 최초 방문 (lastAuthProvider 없음)**
1. 앱 데이터 삭제 → 체험 완료 → Auth 화면
2. **기대**: "계정으로 계속하기" 제목, 3개 버튼 동일 크기

**시나리오 B: 카카오 가입 → 로그아웃 → 재진입**
1. 카카오로 가입 → Lobby → 로그아웃 → 앱 재실행
2. **기대**: "카카오 계정으로 계속하기" 제목 + "이전에 카카오 계정으로 가입했습니다" 안내
3. 카카오 버튼이 위에 크게, 나머지는 "다른 계정으로 계속하기" 아래에

**시나리오 C: Google 가입 → 로그아웃 → 재진입**
1. 시나리오 B와 동일하되 Google로 진행
2. **기대**: Google 버튼이 위에 강조

**시나리오 D: 이메일 가입 → 로그아웃 → 재진입**
1. 이메일로 가입 → 로그아웃 → 재진입
2. **기대**: 이메일 버튼이 위에 강조

---

## Phase 5: 커밋 및 머지

```bash
git add -A && git commit -m "feat: show last auth provider on Auth screen for returning users"

# 테스트 후
git checkout main
git merge feat/last-auth-provider
git push origin main
```

---

## Phase 6: 롤백 (문제 발생 시)

```bash
git checkout main
git revert HEAD --no-edit
git push origin main
```