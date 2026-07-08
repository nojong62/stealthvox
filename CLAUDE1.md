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

# 지시문 10: 체험 완료 기준 — Anyone 1분 완료 시 trialCompleted = true

## 목적
현재 `trialCompleted = true`는 가입 시점에서만 찍힌다.
대화방 Anyone 1분 완료 시점에도 찍어야, 공부방 중간 이탈 → 앱 재실행 시
Welcome(체험 버튼)이 아닌 Auth 화면이 뜬다.

## 대상 파일
- **수정**: `lib/custom_code/widgets/routine_mode_anyone.dart` (1곳)

---

## Phase 1: Savepoint

```bash
git checkout -b fix/trial-completed-timing
git add -A && git commit -m "savepoint: before trialCompleted timing fix"
```

## Phase 2: 수정

**앵커 — `_handleTrialEnd` 메서드 시작 (현재 1542줄):**

```dart
  Future<void> _handleTrialEnd() async {
    if (!trialMode) return;
    trialMode = false;
    disposeTrialTimer();
    BillingTicker.instance.pause();
```

**변경:**

```dart
  Future<void> _handleTrialEnd() async {
    if (!trialMode) return;
    trialMode = false;
    disposeTrialTimer();
    BillingTicker.instance.pause();
    // Anyone 1분 완료 = 체험 완료 확정
    // 이후 앱 재진입 시 Welcome이 아닌 Auth 화면 표시
    FFAppState().trialCompleted = true;
```

> **효과**: 대화방 1분 타이머가 0이 되어 `_handleTrialEnd()`가 호출되는 순간
> `trialCompleted = true`가 SharedPreferences에 저장된다.
> 이후 공부방 진입 여부와 무관하게, 앱 재실행 시 Auth 화면이 뜬다.
>
> **기존 가입 시점 설정과 충돌 없음**: `_handleUnifiedAuth`와 `_handleAuth`에서도
> `trialCompleted = true`를 찍지만, 이미 true인 값을 다시 true로 쓰는 것은 무해.

## Phase 3: 검증

```bash
dart format lib/custom_code/widgets/routine_mode_anyone.dart
flutter analyze lib/custom_code/widgets/routine_mode_anyone.dart

grep "trialCompleted" lib/custom_code/widgets/routine_mode_anyone.dart
# 기대: 1줄
```

## Phase 4: 커밋

```bash
git add -A && git commit -m "fix: set trialCompleted=true on Anyone 1min timer end"
git checkout main && git merge fix/trial-completed-timing
git push origin main
```

---
---

# 지시문 11: 보호자 동의 이메일 발송 Cloud Function

## 목적
14세 미만 가입 시 저장된 `parentEmail`로 동의 요청 이메일을 발송하고,
보호자가 링크를 클릭하면 `parentConsentPending: false`로 업데이트한다.

## 대상 파일
- **수정**: `firebase/functions/index.js` (함수 2개 추가)
- **수정**: `lib/custom_code/widgets/intro_master.dart` (1곳 — CF 호출 추가)

---

## Phase 1: Savepoint

```bash
git checkout -b feat/parent-consent-email
git add -A && git commit -m "savepoint: before parent consent email CF"
```

## Phase 2-A: Cloud Function 추가 — sendParentConsentEmail

`firebase/functions/index.js` 맨 하단에 추가:

```javascript
// ----------------------------------------------------------------------------
// sendParentConsentEmail
// Type:   HTTPS Callable
// Input:  { parentEmail: string }
// Output: { sent: boolean }
//
// 14세 미만 가입자의 보호자에게 동의 요청 이메일을 발송한다.
// 이메일에 포함된 링크를 클릭하면 confirmParentConsent 엔드포인트가 호출되어
// Firestore의 parentConsentPending이 false로 업데이트된다.
// ----------------------------------------------------------------------------
exports.sendParentConsentEmail = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "로그인이 필요합니다."
      );
    }

    const parentEmail = data && data.parentEmail;
    if (!parentEmail || typeof parentEmail !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "parentEmail is required."
      );
    }

    const uid = context.auth.uid;
    const projectId = process.env.GCLOUD_PROJECT || "stealth-vox-3p3rq3";

    // 동의 확인 URL (confirmParentConsent HTTPS endpoint)
    const consentUrl =
      `https://us-central1-${projectId}.cloudfunctions.net/confirmParentConsent?uid=${encodeURIComponent(uid)}`;

    // Firebase Auth의 이메일 발송 기능 사용
    // (별도 이메일 서비스 없이 Admin SDK의 generateEmailVerificationLink를 활용하거나,
    //  간단히 Firestore에 mail collection을 만들어 Firebase Extensions "Trigger Email"을 사용)
    //
    // 가장 간단한 방법: Firestore 'mail' 컬렉션에 문서 생성
    // → Firebase Extension "Trigger Email from Firestore" 사용 시 자동 발송
    // → Extension이 없으면 수동으로 nodemailer 등 사용

    const mailRef = admin.firestore().collection("mail").doc();
    await mailRef.set({
      to: parentEmail,
      message: {
        subject: "StealthVox - 자녀 가입 동의 요청",
        html: `
          <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; padding: 24px;">
            <h2 style="color: #333;">StealthVox 보호자 동의</h2>
            <p style="color: #555; line-height: 1.6;">
              자녀가 StealthVox 앱에 가입하려고 합니다.<br>
              만 14세 미만 사용자는 보호자의 동의가 필요합니다.
            </p>
            <p style="color: #555; line-height: 1.6;">
              아래 버튼을 눌러 자녀의 가입에 동의해 주세요.
            </p>
            <a href="${consentUrl}"
               style="display: inline-block; padding: 14px 32px; background-color: #4A90D9;
                      color: white; text-decoration: none; border-radius: 8px; font-weight: bold;
                      margin-top: 16px;">
              동의합니다
            </a>
            <p style="color: #999; font-size: 12px; margin-top: 24px;">
              본인이 요청하지 않았다면 이 이메일을 무시하셔도 됩니다.
            </p>
          </div>
        `,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    functions.logger.info("sendParentConsentEmail: mail queued", {
      uid: uid,
      parentEmail: parentEmail,
    });

    return { sent: true };
  });
```

## Phase 2-B: Cloud Function 추가 — confirmParentConsent

```javascript
// ----------------------------------------------------------------------------
// confirmParentConsent
// Type:   HTTPS Request (GET)
// Query:  ?uid=<firebase_uid>
// Action: Firestore users/{uid}.parentConsentPending = false
// Response: HTML 확인 페이지
// ----------------------------------------------------------------------------
exports.confirmParentConsent = functions
  .region("us-central1")
  .https.onRequest(async (req, res) => {
    const uid = req.query.uid;
    if (!uid || typeof uid !== "string") {
      res.status(400).send("<h1>잘못된 요청입니다.</h1>");
      return;
    }

    try {
      const userRef = admin.firestore().collection("users").doc(uid);
      const userDoc = await userRef.get();

      if (!userDoc.exists) {
        res.status(404).send("<h1>사용자를 찾을 수 없습니다.</h1>");
        return;
      }

      await userRef.update({ parentConsentPending: false });

      functions.logger.info("confirmParentConsent: consent granted", {
        uid: uid,
      });

      res.status(200).send(`
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="font-family: sans-serif; text-align: center; padding: 60px 24px;">
          <h1 style="color: #4A90D9;">동의가 완료되었습니다</h1>
          <p style="color: #555; font-size: 16px; line-height: 1.6;">
            자녀의 StealthVox 가입이 승인되었습니다.<br>
            이 페이지를 닫아도 됩니다.
          </p>
        </body>
        </html>
      `);
    } catch (e) {
      functions.logger.error("confirmParentConsent: error", {
        uid: uid,
        error: String(e),
      });
      res.status(500).send("<h1>오류가 발생했습니다. 다시 시도해 주세요.</h1>");
    }
  });
```

## Phase 2-C: intro_master.dart — _showParentEmailDialog에서 CF 호출

**파일**: `lib/custom_code/widgets/intro_master.dart`

보호자 이메일 저장 후 `sendParentConsentEmail` CF를 호출한다.

**앵커 (현재 코드, _showBirthYearDialog 내부):**
```dart
        await userRef.set({
          'birthYear': selectedYear,
          'parentEmail': parentEmail,
          'parentConsentPending': true,
        }, SetOptions(merge: true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
```

**변경:**
```dart
        await userRef.set({
          'birthYear': selectedYear,
          'parentEmail': parentEmail,
          'parentConsentPending': true,
        }, SetOptions(merge: true));

        // 보호자에게 동의 요청 이메일 발송
        try {
          final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('sendParentConsentEmail');
          await callable.call({'parentEmail': parentEmail});
          debugPrint('[Auth] parent consent email sent to $parentEmail');
        } catch (e) {
          debugPrint('[Auth] parent consent email failed (non-blocking): $e');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
```

## Phase 3: 검증

```bash
# index.js 문법 확인
node -c firebase/functions/index.js

# 새 함수 존재 확인
grep "sendParentConsentEmail\|confirmParentConsent" firebase/functions/index.js
# 기대: 2줄 이상

# 클라이언트 호출 확인
grep "sendParentConsentEmail" lib/custom_code/widgets/intro_master.dart
# 기대: 1줄

dart format lib/custom_code/widgets/intro_master.dart
flutter analyze lib/custom_code/widgets/intro_master.dart
```

## Phase 4: 배포

```bash
# Cloud Functions 배포
cd firebase
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:sendParentConsentEmail
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:confirmParentConsent
cd ..

git add -A && git commit -m "feat: parent consent email CF + client integration"
git checkout main && git merge feat/parent-consent-email
git push origin main
```

> **중요**: `sendParentConsentEmail`은 Firestore `mail` 컬렉션에 문서를 만드는 방식이다.
> 이 방식이 동작하려면 Firebase Extension "Trigger Email from Firestore"가 설치되어 있어야 한다.
>
> Extension 설치: Firebase Console → Extensions → "Trigger Email from Firestore" → Install
> SMTP 설정: Gmail, SendGrid, Mailgun 등 SMTP 정보 입력 필요
>
> Extension 없이 하려면 `sendParentConsentEmail` 내부에 nodemailer를 직접 사용해야 한다.
> 어느 방식이든 SMTP 설정이 필요하므로, 배포 후 실제 이메일 발송 테스트 필수.

---
---

# 지시문 12: 카카오 로그인 속도 최적화 — 재방문자 anonymous 스킵

## 목적
재방문 사용자(`lastAuthProvider` 있음)는 `signInAnonymously()`를 건너뛰고
바로 카카오 인증을 시작하여 로그인 속도를 개선한다.

## 대상 파일
- **수정**: `lib/auth/social_auth_service.dart` (signInWithKakao 수정)

---

## Phase 1: Savepoint

```bash
git checkout -b perf/kakao-skip-anonymous
git add -A && git commit -m "savepoint: before kakao anonymous skip optimization"
```

## Phase 2: 수정

### 현재 signInWithKakao 문제점

```dart
static Future<UserCredential> signInWithKakao() async {
  // currentUser가 null이면 무조건 signInAnonymously()
  if (_auth.currentUser == null) {
    await _auth.signInAnonymously();  // ← 재방문자에게 불필요 (1초 소요)
  }
  // Kakao SDK 로그인
  // kakaoCustomAuth CF 호출 (anonymous UID를 서버에 전달)
  // signInWithCustomToken
}
```

재방문자는 `kakaoCustomAuth`가 `kakao_uid_map`에서 기존 UID를 찾아주므로
anonymous UID가 필요 없다. 하지만 CF가 `context.auth.uid`를 요구하므로
인증 없이는 호출할 수 없다.

### 해결: skipAnonymous 파라미터 추가

**앵커 (현재 코드):**
```dart
  static Future<UserCredential> signInWithKakao() async {
    try {
      debugPrint(
          '[KakaoAuth] signInWithKakao start, currentUser=${_auth.currentUser?.uid}, isAnonymous=${_auth.currentUser?.isAnonymous}');

      if (_auth.currentUser == null) {
        debugPrint('[KakaoAuth] signInAnonymously start');
        await _auth.signInAnonymously();
        debugPrint(
            '[KakaoAuth] signInAnonymously complete, uid=${_auth.currentUser?.uid}');
      }
```

**변경:**
```dart
  static Future<UserCredential> signInWithKakao({
    bool skipAnonymous = false,
  }) async {
    try {
      debugPrint(
          '[KakaoAuth] signInWithKakao start, currentUser=${_auth.currentUser?.uid}, isAnonymous=${_auth.currentUser?.isAnonymous}, skipAnonymous=$skipAnonymous');

      if (_auth.currentUser == null && !skipAnonymous) {
        debugPrint('[KakaoAuth] signInAnonymously start');
        await _auth.signInAnonymously();
        debugPrint(
            '[KakaoAuth] signInAnonymously complete, uid=${_auth.currentUser?.uid}');
      }
```

### kakaoCustomAuth CF 호출 시 — 인증 없이 호출할 수 있도록

현재 `kakaoCustomAuth`는 `context.auth.uid`로 anonymous UID를 받는다.
`skipAnonymous` 시 `currentUser`가 null이므로 CF가 unauthenticated 에러를 낸다.

**해결**: `kakaoCustomAuth` CF가 `anonUid`를 클라이언트에서 직접 받을 수 있도록 변경하거나,
또는 **재방문자는 `signInAnonymously()`는 하되 라우터 알림을 이미 억제했으므로 Lobby로 안 감**
→ 사실상 현재 구조(지시문 7)에서 이미 안전하다.

> **재평가**: 지시문 7에서 `_handleUnifiedAuth`가 `notifyOnAuthChange(false)`로
> 라우터를 이미 억제하고 있다. `signInAnonymously()`가 실행되어도 Lobby로 안 간다.
> 그러면 `skipAnonymous`의 장점은 순수 1초 절약뿐이다.
>
> 하지만 CF 구조를 바꾸지 않고 1초를 절약하려면 `kakaoCustomAuth`에
> optional `anonUid` 파라미터를 추가해야 하는데, 이건 서버 수정까지 필요하다.
>
> **현실적 판단**: 1초 절약을 위해 서버 + 클라이언트 양쪽을 건드리는 건 위험 대비 이득이 작다.
> 대신, 재방문자에게 **bonus 재지급 체크를 스킵**하는 것이 더 효과적이다.

### 대안: 재방문자 bonus 스킵으로 속도 개선

**파일**: `lib/custom_code/widgets/intro_master.dart`

**앵커 (현재 코드, _handleUnifiedAuth 내부):**
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

위는 이미 지시문 8에서 적용된 부분이므로 변경 불필요.

bonus 스킵을 위해, `_grantSignupBonusIfPossible()` 호출 전에 체크:

**앵커:**
```dart
      await _grantSignupBonusIfPossible();
```

**변경:**
```dart
      // 이전에 로그인한 적 있는 재방문자는 bonus 이미 지급됨 → 스킵
      final isReturningUser = provider.isNotEmpty &&
          FFAppState().lastAuthProvider == provider;
      if (!isReturningUser) {
        await _grantSignupBonusIfPossible();
      } else {
        debugPrint('[Auth] returning user — skip bonus check');
        // Firestore에서 최신 remainingTime 가져오기
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            final rt = doc.data()?['remainingTime'] as int?;
            if (rt != null) {
              FFAppState().remainingTime = rt;
              FFAppState().remainingTimeLoaded = true;
            }
          } catch (e) {
            debugPrint('[Auth] returning user time fetch failed: $e');
          }
        }
      }
```

> **효과**: 재방문자는 `grantSignupBonus` CF 호출(서버 왕복 ~2초)을 건너뛰고,
> Firestore에서 직접 `remainingTime`을 읽는다(~0.5초).
> 체감 로그인 속도가 약 1.5초 개선된다.
>
> **주의**: `isReturningUser` 판별은 `lastAuthProvider`가 현재 provider와
> **같을 때만** 스킵한다. 다른 provider로 로그인하면(카카오→구글 전환)
> bonus 체크를 정상 수행한다.

## Phase 3: 검증

```bash
dart format lib/auth/social_auth_service.dart lib/custom_code/widgets/intro_master.dart
flutter analyze lib/auth/social_auth_service.dart lib/custom_code/widgets/intro_master.dart

# skipAnonymous 파라미터 확인
grep "skipAnonymous" lib/auth/social_auth_service.dart
# 기대: 2줄 (파라미터 정의 + 조건)

# bonus 스킵 로직 확인
grep "isReturningUser\|skip bonus" lib/custom_code/widgets/intro_master.dart
# 기대: 2줄 이상
```

## Phase 4: 커밋

```bash
git add -A && git commit -m "perf: skip bonus CF for returning users, add skipAnonymous to signInWithKakao"
git checkout main && git merge perf/kakao-skip-anonymous
git push origin main
```

---

## 3개 지시문 실행 순서

```
지시문 10 (F5: trialCompleted 타이밍) → 독립적, 먼저 실행
  ↓
지시문 11 (F3: 보호자 이메일 CF) → index.js + intro_master.dart
  ↓
지시문 12 (카톡 속도 최적화) → social_auth_service.dart + intro_master.dart
```

각 지시문은 독립 브랜치에서 작업 후 테스트 → main 머지 순서.
지시문 12는 11의 intro_master.dart 변경과 겹칠 수 있으므로 11 머지 후 실행 권장.