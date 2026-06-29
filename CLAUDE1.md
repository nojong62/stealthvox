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
- 완료후 관리자가 APK 라고 적으면, 날자와 시간이 이름에 들어간 APK만들어 줘. 

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# Phase B — 소셜 로그인 클라이언트 통합 (완전 최종본)

"Step 7 실행 전에 먼저 grep -rn "_claimWelcomeBonus\|claimWelcomeBonus" lib/ 결과를 보여줘"

## 목표
- 카카오 · 구글 · 이메일 로그인 모달 추가
- Store 구매 게이트: 익명이면 모달 팝업 → 가입 → 결제 자동 재진행
- 웰컴보너스 호출 제거
- 기존 익명 uid 아래 체험 데이터 보존

## 전제 (Phase A 완료 기준)
- `kakao_flutter_sdk_user` pubspec에 추가됨 ✓
- `kakaoCustomAuth` Cloud Function 배포됨 ✓
- `kakao_uid_map` Firestore 규칙 하드닝됨 ✓
- `google_sign_in` 이미 pubspec에 존재 ✓

## 작업 파일 목록
| 파일 | 작업 |
|---|---|
| `pubspec.yaml` | `cloud_functions`, `kakao_flutter_sdk_common` 추가 |
| `android/app/src/main/AndroidManifest.xml` | 카카오 URL 스킴 Activity 추가 |
| `lib/main.dart` | import 1줄 + `KakaoSdk.init()` 1줄 |
| `lib/auth/social_auth_service.dart` | 신규 생성 |
| `lib/components/social_login_modal.dart` | 신규 생성 |
| `lib/custom_code/widgets/store_master.dart` | `_executePurchase` 게이트 교체 + import 추가 |

> **Box 7 원칙 준수**: store_master.dart는 구매 게이트 분기 1곳만 수정. TTS/STT 관련 코드 일절 미접촉.

---

## 0. Savepoint

```bash
cd F:/flutter_project/stealth_vox
git add -A
git commit -m "savepoint: before Phase B social auth client wiring"
```

---

## 1. 추가 의존성

```bash
flutter pub add cloud_functions
flutter pub add kakao_flutter_sdk_common
```

✅ 확인: `pubspec.lock`에 두 항목 존재

---

## 2. 카카오 콘솔 + AndroidManifest (병행 가능)

### 2-1. 카카오 디벨로퍼스 (웹 콘솔, 수동)
[developers.kakao.com](https://developers.kakao.com) → 내 애플리케이션 → 앱 생성:
- 플랫폼 → Android: 패키지명 `com.aienglishpractice.stealthvox` + Phase A Step 1-3 **디버그 키해시** 등록
- 카카오 로그인 → 활성화: **ON**
- 동의항목: **닉네임만** (이메일 불필요 — uid 바인딩에 이메일 미사용)
- **네이티브 앱키** 복사 → 이하 `YOUR_KAKAO_NATIVE_APP_KEY` 자리에 사용

### 2-2. AndroidManifest.xml

**앵커 확인**:
```bash
grep -n "android:name=\"com.kakao" android/app/src/main/AndroidManifest.xml | wc -l
# 기대값: 0 (아직 없음)
grep -n "</application>" android/app/src/main/AndroidManifest.xml | wc -l
# 기대값: 1
```

**str_replace**:

old_str (유일):
```xml
        </application>
```

new_str:
```xml
        <!-- 카카오 커스텀 URL 스킴 -->
        <activity
            android:name="com.kakao.sdk.auth.AuthCodeHandlerActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="kakaoYOUR_KAKAO_NATIVE_APP_KEY" />
            </intent-filter>
        </activity>
        </application>
```

> `kakaoYOUR_KAKAO_NATIVE_APP_KEY` → 예: 앱키 `abc123`이면 `kakaoabc123`

**검증**:
```bash
grep -n "AuthCodeHandlerActivity" android/app/src/main/AndroidManifest.xml | wc -l
# 기대값: 1
```

---

## 3. main.dart 수정

### 3-1. 앵커 확인
```bash
grep -n "await initFirebase();" lib/main.dart | wc -l
# 기대값: 1
grep -n "KakaoSdk.init" lib/main.dart | wc -l
# 기대값: 0
grep -n "kakao_flutter_sdk_common" lib/main.dart | wc -l
# 기대값: 0
```

### 3-2. import 추가
main.dart 상단 import 블록에서 firebase_core import 줄을 찾아 바로 뒤에 추가:

old_str (유일):
```dart
import 'package:firebase_core/firebase_core.dart';
```

new_str:
```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';
```

### 3-3. KakaoSdk.init() 삽입

old_str (유일):
```dart
  await initFirebase();
```

new_str:
```dart
  await initFirebase();
  KakaoSdk.init(nativeAppKey: 'YOUR_KAKAO_NATIVE_APP_KEY');
```

### 3-4. 검증
```bash
grep -n "KakaoSdk.init" lib/main.dart | wc -l
# 기대값: 1
grep -n "kakao_flutter_sdk_common" lib/main.dart | wc -l
# 기대값: 1
```

---

## 4. lib/auth/social_auth_service.dart 신규 생성

```dart
// lib/auth/social_auth_service.dart
//
// 카카오 · 구글 · 이메일 로그인을 현재 익명 uid에 통합하는 서비스.
// Phase B: 클라이언트 wiring 전용.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

class SocialAuthService {
  static final _auth = FirebaseAuth.instance;
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  // ─────────────────────────────────────────────
  // 카카오 로그인
  //   1) 카카오앱/웹으로 OAuth → accessToken
  //   2) kakaoCustomAuth Cloud Function → customToken
  //   3) signInWithCustomToken → 익명 uid 보존
  // ─────────────────────────────────────────────
  static Future<UserCredential> signInWithKakao() async {
    OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      token = await UserApi.instance.loginWithKakaoTalk();
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }

    final callable = _functions.httpsCallable('kakaoCustomAuth');
    final result = await callable.call<Map<String, dynamic>>({
      'kakaoAccessToken': token.accessToken,
    });

    final customToken = result.data['token'] as String;
    return await _auth.signInWithCustomToken(customToken);
  }

  // ─────────────────────────────────────────────
  // 구글 로그인
  //   linkWithCredential 시도 → already-in-use면 signInWithCredential
  // ─────────────────────────────────────────────
  static Future<UserCredential> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled.');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final currentUser = _auth.currentUser;
    if (currentUser != null && currentUser.isAnonymous) {
      try {
        return await currentUser.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use') {
          return await _auth.signInWithCredential(credential);
        }
        rethrow;
      }
    }
    return await _auth.signInWithCredential(credential);
  }

  // ─────────────────────────────────────────────
  // 이메일 로그인 / 가입
  //   linkWithCredential 시도 → already-in-use면 signInWithEmailAndPassword
  // ─────────────────────────────────────────────
  static Future<UserCredential> signInWithEmail(
    String email,
    String password, {
    bool isSignUp = false,
  }) async {
    final credential =
        EmailAuthProvider.credential(email: email, password: password);
    final currentUser = _auth.currentUser;

    if (isSignUp && currentUser != null && currentUser.isAnonymous) {
      try {
        return await currentUser.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          return await _auth.signInWithEmailAndPassword(
              email: email, password: password);
        }
        rethrow;
      }
    }
    return await _auth.signInWithEmailAndPassword(
        email: email, password: password);
  }
}
```

---

## 5. lib/components/social_login_modal.dart 신규 생성

```dart
// lib/components/social_login_modal.dart
//
// 카카오 · 구글 · 이메일 로그인 버튼 모달.
// showDialog()로 호출. 로그인 성공 시 Navigator.pop(true).

import 'package:flutter/material.dart';
import '../auth/social_auth_service.dart';
import '/flutter_flow/flutter_flow_theme.dart';

class SocialLoginModal extends StatefulWidget {
  const SocialLoginModal({super.key});

  @override
  State<SocialLoginModal> createState() => _SocialLoginModalState();
}

class _SocialLoginModalState extends State<SocialLoginModal> {
  bool _isLoading = false;
  String? _errorMessage;

  bool _showEmailForm = false;
  bool _isSignUp = false;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // Future<dynamic>으로 UserCredential 반환 타입과 호환
  Future<void> _handleResult(Future<dynamic> Function() action) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyError(e);
          _isLoading = false;
        });
      }
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('cancelled') || msg.contains('cancel')) {
      return '로그인을 취소했습니다.';
    }
    if (msg.contains('network')) return '네트워크 오류가 발생했습니다.';
    if (msg.contains('wrong-password') ||
        msg.contains('invalid-credential')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }
    if (msg.contains('user-not-found')) return '가입된 계정이 없습니다.';
    if (msg.contains('weak-password')) return '비밀번호는 6자 이상이어야 합니다.';
    if (msg.contains('invalid-email')) return '이메일 형식을 확인해주세요.';
    return '로그인에 실패했습니다. 다시 시도해주세요.';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '진행 상황을 저장하려면\n계정을 만드세요',
              style: FlutterFlowTheme.of(context).headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '체험 데이터가 그대로 유지됩니다.',
              style: FlutterFlowTheme.of(context).bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_showEmailForm)
              _buildEmailForm()
            else
              _buildButtons(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style:
                    TextStyle(color: Colors.red.shade600, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Column(
      children: [
        // 카카오 (1순위)
        _SocialButton(
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
                color: Color(0xFF191919)),
          ),
          onTap: () => _handleResult(SocialAuthService.signInWithKakao),
        ),
        const SizedBox(height: 12),
        // 구글
        _SocialButton(
          label: 'Google로 계속하기',
          backgroundColor: Colors.white,
          textColor: Colors.black87,
          border: Border.all(color: Colors.grey.shade300),
          icon: Image.asset(
            'assets/images/google_logo.png',
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) => const Icon(
                Icons.g_mobiledata,
                size: 24,
                color: Colors.blue),
          ),
          onTap: () => _handleResult(SocialAuthService.signInWithGoogle),
        ),
        const SizedBox(height: 16),
        // 구분선
        Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('다른 방법으로 가입하기',
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 12)),
          ),
          const Expanded(child: Divider()),
        ]),
        const SizedBox(height: 12),
        // 이메일
        _SocialButton(
          label: '이메일로 시작하기',
          backgroundColor: Colors.grey.shade100,
          textColor: Colors.black87,
          icon: const Icon(Icons.email_outlined,
              size: 20, color: Colors.black54),
          onTap: () => setState(() => _showEmailForm = true),
        ),
        const SizedBox(height: 16),
        // 로그인 링크
        GestureDetector(
          onTap: () => setState(() {
            _showEmailForm = true;
            _isSignUp = false;
          }),
          child: RichText(
            text: TextSpan(
              text: '이미 계정이 있으신가요? ',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              children: [
                TextSpan(
                  text: '바로 로그인하세요',
                  style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _tabBtn('로그인', !_isSignUp,
                () => setState(() => _isSignUp = false)),
            const SizedBox(width: 8),
            _tabBtn('회원가입', _isSignUp,
                () => setState(() => _isSignUp = true)),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
              labelText: '이메일', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: '비밀번호', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => _handleResult(
            () => SocialAuthService.signInWithEmail(
              _emailCtrl.text.trim(),
              _passwordCtrl.text,
              isSignUp: _isSignUp,
            ),
          ),
          child: Text(_isSignUp ? '가입하기' : '로그인'),
        ),
        TextButton(
          onPressed: () => setState(() => _showEmailForm = false),
          child: const Text('← 뒤로'),
        ),
      ],
    );
  }

  Widget _tabBtn(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? Colors.black : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight:
                  active ? FontWeight.bold : FontWeight.normal,
              color: active ? Colors.black : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Widget icon;
  final VoidCallback onTap;
  final BoxBorder? border;

  const _SocialButton({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.icon,
    required this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: border,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 6. store_master.dart — 구매 게이트 교체

### 6-1. import 추가 앵커 확인
```bash
grep -n "social_login_modal" lib/custom_code/widgets/store_master.dart | wc -l
# 기대값: 0
grep -n "^import 'package:purchases_flutter" lib/custom_code/widgets/store_master.dart | wc -l
# 기대값: 1
```

### 6-2. import 추가

old_str (유일):
```dart
import 'package:purchases_flutter/purchases_flutter.dart';
```

new_str:
```dart
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import '/components/social_login_modal.dart';
```

### 6-3. 구매 게이트 교체 앵커 확인
```bash
grep -n "currentUserReference == null" lib/custom_code/widgets/store_master.dart | wc -l
# 기대값: 1 (또는 2 이상이면 중단 후 알려주세요)
grep -n "_showFeedback.*로그인 후 이용" lib/custom_code/widgets/store_master.dart | wc -l
# 기대값: 1
```

### 6-4. 게이트 교체

old_str (유일):
```dart
    if (currentUserReference == null) {
      _showFeedback("로그인 후 이용해 주세요.", const Color(0xFFF87171));
      return;
    }
```

new_str:
```dart
    // 익명 또는 미로그인 → 소셜 로그인 모달
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const SocialLoginModal(),
      );
      if (result != true || !mounted) return; // 취소 or 언마운트 → 중단
      // 가입 성공 → 구매 계속 진행
    }
```

### 6-5. 검증
```bash
grep -n "SocialLoginModal" lib/custom_code/widgets/store_master.dart | wc -l
# 기대값: 1
grep -n "isAnonymous" lib/custom_code/widgets/store_master.dart | wc -l
# 기대값: 1
```

---

## 7. 웰컴보너스 호출 제거

### 7-1. 앵커 확인
```bash
grep -rn "_claimWelcomeBonus\|claimWelcomeBonus" lib/ | wc -l
# 기대값: 2 이상 (호출부 확인)
```

### 7-2. 호출부 주석 처리
`_claimWelcomeBonus` 또는 `claimWelcomeBonus`가 호출되는 줄을 찾아 주석 처리:
```dart
// [웰컴보너스 제거] 30초 무료 체험으로 대체됨
// await _claimWelcomeBonus();
```

> 함수 정의 자체는 삭제하지 않음 — 호출부만 주석. 추후 정리는 별도 커밋.

---

## 8. flutter analyze

```bash
flutter analyze lib/auth/social_auth_service.dart \
  lib/components/social_login_modal.dart \
  lib/custom_code/widgets/store_master.dart \
  lib/main.dart
```

**기대값**: 오류 0건 (info/warning은 무시)

---

## 9. 동작 시나리오 검증

| 시나리오 | 기대 동작 |
|---|---|
| 익명 유저 구매 탭 | SocialLoginModal 팝업 |
| 카카오 로그인 성공 | `kakao_uid_map` 문서 생성, 모달 닫힘, 구매 진행 |
| 구글 로그인 성공 | 익명 uid에 google.com provider 연결, 구매 진행 |
| 이메일 가입 성공 | 익명 uid에 password provider 연결, 구매 진행 |
| 모달 취소 | 구매 중단, 스토어 화면 유지 |
| 이미 정식 가입된 유저 | 모달 건너뛰고 바로 구매 진행 |
| uid 보존 확인 | 로그인 전후 `FirebaseAuth.instance.currentUser!.uid` 동일 |
| RC 연동 | 동일 uid로 RC 구독 그대로 유지 |

---

## 10. 마지막 커밋

```bash
git add -A
git commit -m "feat: Phase B — social login modal + store gate + kakao/google/email auth"
```

---

## 롤백
```bash
git revert HEAD   # 또는
git reset --hard <Phase B savepoint 해시>
```

---

## Phase B 완료 후 병행 사항 (외부 콘솔)

| 항목 | 위치 |
|---|---|
| 카카오 키해시 등록 | developers.kakao.com (Phase A Step 1-3 출력값) |
| Google 로그인 ON + SHA-1 | Firebase Console → Auth → Sign-in method |
| 로고 이미지 | `assets/images/kakao_logo.png`, `google_logo.png` (없으면 fallback 자동 사용) |