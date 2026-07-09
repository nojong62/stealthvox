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

# 지시문: 크로스 프로바이더 계정 통합 — 종합 진단 및 수정 (v2)

## 배경

카카오 → 로그아웃 → Google, 또는 Google → 로그아웃 → 카카오로 로그인 시
기존 계정과 합쳐지지 않고 새 계정으로 전환되는 문제.

서버 CF(`linkOrCreateAccount`, `kakaoCustomAuth`)에는 이메일 기반 계정 통합 로직이
구현되어 있고 최신 코드로 배포 완료(2026-07-10)되었으나, 클라이언트 연동이 불완전할 수 있다.

## 핵심 원칙 (모든 수정에 적용)

1. **계정 통합은 서버가 결정한다.** 클라이언트는 서버가 반환한 canonical UID + custom token만 사용한다.
2. **CF 실패 시 `signInWithCredential` fallback 절대 금지.** fallback하면 별도 UID가 생겨서 문제가 재발한다. 실패하면 사용자에게 에러를 보여주고 재시도하게 한다.
3. **Google OAuth ID token ≠ Firebase ID token.** CF에서 `admin.auth().verifyIdToken()`을 Google OAuth token에 쓰면 검증 실패한다. 현재 코드가 `tokeninfo` API로 동작 중이면 유지한다.
4. **`lastAuthProvider`는 UI 표시 용도일 뿐.** 계정 통합이나 재방문자 판정에 사용하면 안 된다.
5. **모든 provider는 `signInWithCustomToken(token)`으로 통일.** anonymous UID 보존(`linkWithCredential`)은 이번 범위에서 제외한다.

## 불변 규칙

- Box 7 (`TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`, `HybridTtsPlayer`, `TtsCache`) 절대 수정 금지
- `lib/custom_code/임시/` 절대 수정 금지
- `dart format`은 개별 파일 단위로만 (폴더 X — 한국어 UTF-8 깨짐)
- Firebase CLI는 `firebase/` 디렉토리에서, 배포: `firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:[함수명]`
- **코드 수정 전 반드시 Phase 0 전체 진단을 완료하고 사용자에게 보고 → 승인 후 진행**

---

## Phase S: Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before cross-provider-linking v2"
```

---

## Phase 0: 종합 진단 (전부 실행 후 결과 보고 → 사용자 승인 대기)

### 0-A. SocialAuthService — Google 로그인 흐름

```bash
cat -n lib/auth/social_auth_service.dart
```

확인 항목:

1. `signInWithGoogle()` 메서드에서 `linkOrCreateAccount` CF를 호출하는가?
2. CF 호출 후 `signInWithCustomToken(token)`으로 로그인하는가?
   아니면 `signInWithCredential`을 직접 사용하는가?
3. CF 실패 시 fallback이 있는가? → `signInWithCredential` fallback이면 **제거 대상**
4. CF에 전달하는 토큰: `googleAuth.idToken` (Google OAuth ID token)인가?

### 0-B. SocialAuthService — 카카오 로그인 흐름

같은 파일에서:

1. `signInWithKakao()` 메서드에서 `kakaoCustomAuth` CF를 호출하는가?
2. CF 응답의 custom token으로 `signInWithCustomToken(token)`을 하는가?

### 0-C. linkOrCreateAccount CF — Google 처리

```bash
cd firebase/functions
cat -n index.js | sed -n '/exports\.linkOrCreateAccount/,/^exports\./p' | head -150
```

확인 항목:

1. `provider === 'google'` 분기 존재 여부
2. Google idToken 검증 방법:
   - `tokeninfo` API 사용? → 현재 동작 중이면 유지 (교체는 후순위)
   - `admin.auth().verifyIdToken()` 사용? → **Google OAuth token이면 실패할 수 있음.** 실제로 전달되는 토큰이 Google OAuth ID token인지 Firebase ID token인지 확인
   - `google-auth-library` 사용? → 가장 안전한 방식
3. `getUserByEmail(email)` → 기존 유저 발견 시 해당 UID로 custom token 발급
4. 반환값에 `token`, `isNewUser` 포함 여부

### 0-D. kakaoCustomAuth CF — 이메일 기반 기존 유저 탐색

```bash
cat -n index.js | sed -n '/exports\.kakaoCustomAuth/,/^exports\./p' | head -150
```

확인 항목:

1. `kakaoEmail` 추출 (`profile.kakao_account.email`)
2. `kakao_uid_map` 조회 → fast path (`authEmailSet: true`) 시 바로 return
3. slow path에서 `getUserByEmail(kakaoEmail)` 호출 여부
4. 기존 유저 발견 시 해당 UID 재사용
5. `admin.auth().updateUser(resolvedUid, { email: kakaoEmail })` 여부
6. 반환값 구조: `{ token, ... }`

### 0-E. intro_master.dart — isReturningUser 판정

```bash
grep -n "isReturningUser\|previousAuthProvider\|lastAuthProvider\|grantSignupBonus\|signup_bonus_given" lib/custom_code/widgets/intro_master.dart
```

현재 로직 확인:
```dart
final isReturningUser = provider.isNotEmpty && previousAuthProvider == provider;
```
이 로직은 provider가 다르면 무조건 신규로 판정 → **수정 대상**

### 0-F. 이메일 가입도 서버 경유 여부

```bash
grep -n "linkOrCreateAccount\|signInWithCredential\|createUserWithEmailAndPassword\|signInWithCustomToken" lib/auth/social_auth_service.dart
```

### 진단 보고 형식

```
=== Phase 0 종합 진단 결과 ===

[A] signInWithGoogle:
    - linkOrCreateAccount 경유: 예/아니오
    - 로그인 방식: signInWithCustomToken / signInWithCredential
    - CF 실패 fallback: signInWithCredential(위험) / 에러 throw(안전) / 없음

[B] signInWithKakao:
    - kakaoCustomAuth 경유: 예/아니오
    - 로그인 방식: signInWithCustomToken / signInWithCredential

[C] linkOrCreateAccount CF:
    - Google 분기: 있음/없음
    - idToken 검증: tokeninfo / verifyIdToken / google-auth-library
    - getUserByEmail: 있음/없음
    - 반환값: { token, isNewUser }

[D] kakaoCustomAuth CF:
    - kakaoEmail 추출: 있음/없음
    - getUserByEmail (slow path): 있음/없음
    - updateUser(email): 있음/없음

[E] intro_master isReturningUser:
    - 현재 판정: previousAuthProvider == provider (provider 변경 시 신규 취급)
    - 서버 응답 기반: 사용/미사용

[F] 이메일 가입:
    - 서버 경유: 예/아니오

=== 발견된 Gap 목록 ===
(번호 매겨서 나열)

=== 수정 계획 ===
(Gap별로 어떤 Phase에서 수정할지)
```

**⚠️ 이 보고를 사용자에게 보여주고 승인을 받은 후에만 Phase 1로 진행한다.**

---

## Phase 1: 서버 수정

### Gap 해당 시만 적용. Phase 0에서 이미 구현 확인되면 건너뛴다.

### 1-A: linkOrCreateAccount에 Google 분기가 없는 경우

추가할 때 **주의**: Google OAuth ID token 검증은 현재 코드가 `tokeninfo` 방식이면 유지한다.
`admin.auth().verifyIdToken()`을 Google OAuth token에 사용하면 안 된다.

```javascript
if (provider === 'google') {
  const idToken = data.idToken;

  // ── Google OAuth ID token 검증 ──
  // tokeninfo 방식 (현재 동작 중이면 유지)
  const resp = await fetch(
    'https://oauth2.googleapis.com/tokeninfo?id_token=' + encodeURIComponent(idToken)
  );
  const tokenInfo = await resp.json();
  if (!tokenInfo.email || tokenInfo.email_verified !== 'true') {
    throw new functions.https.HttpsError('invalid-argument', 'Verified email required');
  }
  const email = tokenInfo.email;
  const displayName = tokenInfo.name || null;

  // ── 이메일로 기존 유저 탐색 ──
  let existingUser = null;
  try {
    existingUser = await admin.auth().getUserByEmail(email);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }

  if (existingUser) {
    const token = await admin.auth().createCustomToken(existingUser.uid);
    return { token, isNewUser: false, resolvedUid: existingUser.uid };
  } else {
    const newUser = await admin.auth().createUser({
      email, displayName, emailVerified: true
    });
    const token = await admin.auth().createCustomToken(newUser.uid);
    return { token, isNewUser: true, resolvedUid: newUser.uid };
  }
}
```

### 1-B: kakaoCustomAuth slow path에 getUserByEmail이 없는 경우

```javascript
// kakao_uid_map에 매핑 없고 kakaoEmail이 있을 때
if (!resolvedUid && kakaoEmail) {
  try {
    const existing = await admin.auth().getUserByEmail(kakaoEmail);
    if (existing) {
      resolvedUid = existing.uid;
      await admin.firestore().collection('kakao_uid_map').doc(String(kakaoId)).set({
        firebaseUid: resolvedUid,
        kakaoEmail: kakaoEmail,
        authEmailSet: true,
        linkedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
}
```

### 1-C: kakaoCustomAuth에서 Firebase Auth 이메일 미설정

```javascript
if (kakaoEmail && resolvedUid) {
  try {
    await admin.auth().updateUser(resolvedUid, { email: kakaoEmail });
  } catch (e) {
    if (e.code !== 'auth/email-already-exists') {
      functions.logger.error('[kakaoCustomAuth] updateUser email failed:', e);
    }
  }
}
```

---

## Phase 2: 클라이언트 수정

### 2-A: signInWithGoogle — linkOrCreateAccount 경유 + fallback 금지

> Phase 0-A에서 이미 올바르게 구현되어 있으면 건너뛴다.
> 단, `signInWithCredential` fallback이 있으면 **반드시 제거**한다.

```dart
static Future<UserCredential> signInWithGoogle() async {
  final googleUser = await GoogleSignIn().signIn();
  if (googleUser == null) throw Exception('Google sign-in cancelled.');

  final googleAuth = await googleUser.authentication;

  // ── 서버에서 canonical UID 결정 ──
  final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
      .httpsCallable('linkOrCreateAccount');
  final result = await callable.call<Map<String, dynamic>>({
    'provider': 'google',
    'idToken': googleAuth.idToken,
  });

  final token = result.data['token'] as String;

  // ── 항상 서버가 결정한 UID로 로그인 ──
  // fallback으로 signInWithCredential을 쓰면 별도 UID가 생길 수 있으므로 금지
  return await FirebaseAuth.instance.signInWithCustomToken(token);
}
```

**핵심:** `try-catch`로 감싸되, catch에서 `signInWithCredential`로 fallback하지 않는다.
에러는 `_handleUnifiedAuth`의 catch 블록까지 전파되어 사용자에게 "로그인 실패" 메시지를 보여준다.

### 2-B: signInWithKakao — 확인만

카카오는 이미 `kakaoCustomAuth` → `signInWithCustomToken` 흐름일 가능성이 높다.
Phase 0-B에서 확인하고, 맞으면 수정 없음.

만약 `signInWithCredential` fallback이 있다면 동일하게 제거한다.

### 2-C: intro_master.dart — isReturningUser 판정 수정

파일: `lib/custom_code/widgets/intro_master.dart`

**현재** (line ~1060):
```dart
final isReturningUser =
    provider.isNotEmpty && previousAuthProvider == provider;
```

**변경:**
```dart
// provider가 달라도 같은 계정이면 재방문자.
// signup_bonus_given 서버 플래그로 판정 (grantSignupBonus CF의 idempotency 보장).
final currentUser = FirebaseAuth.instance.currentUser;
bool isReturningUser = false;
if (currentUser != null) {
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    isReturningUser = userDoc.exists &&
        userDoc.data()?['signup_bonus_given'] == true;
  } catch (e) {
    debugPrint('[Auth] returning user check failed: $e');
  }
}
```

그리고 `isReturningUser == true` 블록 끝 (기존 line ~1082 이후)에 추가:
```dart
// provider 전환 시 UID가 이전 세션과 같더라도 lobby 재동기화 강제
LobbyBrain.lastSyncedUid = null;
```

### 2-D: _cleanupTrialSandbox와의 관계

`_cleanupTrialSandbox()`는 anonymous 체험 데이터를 정리하는 용도로,
소셜 로그인 전에 호출되는 기존 흐름을 유지한다.

**변경 없음.** anonymous UID 보존(`linkWithCredential`)을 하지 않으므로 충돌 없다.
체험 → 가입 시: sandbox 정리 → 서버 CF에서 canonical UID 결정 → `signInWithCustomToken`.

---

## Phase 3: 검증

```bash
# 서버 문법
cd firebase/functions
node -c index.js

# fallback 제거 확인 — signInWithCredential이 signInWithGoogle 안에 없어야 함
grep -n "signInWithCredential" lib/auth/social_auth_service.dart
# 기대: signInWithGoogle 메서드 안에는 0줄
# (다른 메서드에 있을 수 있으나, signInWithGoogle 안에는 없어야 함)

# linkOrCreateAccount 호출 확인
grep -n "linkOrCreateAccount" lib/auth/social_auth_service.dart
# 기대: 1줄 이상

# signInWithCustomToken 확인
grep -n "signInWithCustomToken" lib/auth/social_auth_service.dart
# 기대: signInWithGoogle + signInWithKakao 각각 1줄 이상

# isReturningUser 수정 확인
grep -n "signup_bonus_given\|isReturningUser" lib/custom_code/widgets/intro_master.dart

# 클라이언트 포맷/분석
dart format lib/auth/social_auth_service.dart
dart format lib/custom_code/widgets/intro_master.dart
flutter analyze lib/auth/social_auth_service.dart 2>&1 | head -20
flutter analyze lib/custom_code/widgets/intro_master.dart 2>&1 | head -20
```

---

## Phase 4: 배포 (서버 수정 있었을 경우만)

```bash
cd firebase
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:linkOrCreateAccount
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:kakaoCustomAuth
```

---

## Phase 5: 커밋

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "fix: cross-provider account linking v2 — no fallback, server canonical UID"
git push origin main
```

---

## Phase 6: 롤백

```bash
git revert HEAD --no-edit
git push origin main
cd firebase
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:linkOrCreateAccount
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:kakaoCustomAuth
```

---

## 테스트 시나리오

**사전 준비:** 기존 테스트 계정이 중복 UID 상태라면
회원탈퇴 → 앱 데이터 삭제(설정 → 앱 → StealthVox → 저장공간 → 데이터 삭제) → 앱 재시작.
운영 계정이나 결제/시간/히스토리가 있는 계정은 삭제하지 않는다.

### A: 카카오 → 로그아웃 → Google (동일 이메일)
1. 앱 데이터 초기화
2. 카카오 가입 → birthYear 입력 → Lobby → UID 기록
3. 로그아웃 → 앱 종료 → 재실행
4. Google로 계속하기
5. **확인:**
   - UID 동일 ✅
   - birthYear 다이얼로그 안 뜸 ✅
   - remainingTime 유지 ✅
   - signup bonus 중복 없음 ✅

### B: Google → 로그아웃 → 카카오 (동일 이메일)
위와 동일 기준으로 반대 방향 테스트

### C: 다른 이메일
카카오(naver.com) → 로그아웃 → Google(gmail.com)
**확인:** 별개 계정 (이메일이 다르므로 정상)

### D: 같은 provider 재로그인
카카오 → 로그아웃 → 카카오
**확인:** 같은 UID, birthYear 유지, bonus 중복 없음

### E: 이메일 가입 ↔ 소셜 (동일 이메일)
이메일 가입 → 로그아웃 → Google(같은 이메일)
**확인:** 같은 UID로 통합

### F: 카카오 이메일 미제공
카카오 동의항목에서 이메일 거부 → 로그아웃 → Google
**확인:** 자동 병합 없이 별개 계정 (이메일 비교 불가이므로 정상)

### G: CF 실패 시 동작
(Firebase emulator 또는 일시적 네트워크 차단으로 시뮬레이션)
**확인:** "로그인 실패: ... 다시 시도해 주세요" 메시지 표시.
signInWithCredential로 빠져서 별도 계정이 생기지 않음 ✅

---

## 한계 및 감수 사항

1. **카카오 이메일 미제공:** 동의항목 거부 시 매칭 불가 → 별개 계정 (업계 표준)
2. **카카오 ≠ Google 이메일:** 다른 이메일은 다른 사람 → 별개 계정
3. **기존 중복 UID:** 이미 생성된 중복 계정은 이 수정으로 자동 병합 불가.
   - 테스트 계정: 회원탈퇴 후 재가입 가능
   - 운영 계정(결제/시간/히스토리 보유): 삭제 금지. 별도 관리자 병합 스크립트 필요
4. **tokeninfo → google-auth-library 교체:** 보안 강화 차원이며, 현재 동작에 문제 없으면 후순위.
   `admin.auth().verifyIdToken()`은 Google OAuth token에 사용할 수 없으므로 교체 시 `google-auth-library`를 사용해야 한다.
5. **anonymous UID 보존:** 이번 수정에서는 범위 밖. 체험 → 가입 시 sandbox 정리 후 서버 UID 사용.
   필요 시 별도 요구사항으로 처리.