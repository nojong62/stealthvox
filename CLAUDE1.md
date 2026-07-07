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

# 지시문 3: Cloud Function — 이메일 기반 자동 계정 통합

## 목적
사용자가 카카오로 가입한 뒤 앱을 삭제하고, 재설치 후 Google로 로그인하는 경우
같은 이메일이면 자동으로 기존 계정과 통합되도록 서버측 로직을 추가한다.

사용자 눈에는 아무 추가 확인 없이 기존 데이터(시간, 기록)가 그대로 살아있는 것처럼 보여야 한다.

## 대상 파일
- **수정**: `firebase/functions/index.js`

## 선행 조건
- ✅ 지시문 1, 2 완료
- ✅ 카카오 개발자 콘솔에서 "이메일" 동의항목이 활성화되어 있는지 확인 필요
  (카카오 비즈앱 등록 시 이메일은 기본 제공, 단 사용자가 동의 거부하면 null)

---

## 핵심 아키텍처

### 현재 구조의 문제점

```
카카오 로그인 → kakaoCustomAuth → kakao_uid_map 에서 UID 조회/생성
Google 로그인 → Firebase GoogleAuthProvider → 별도 UID 생성
이메일 로그인 → Firebase EmailAuthProvider → 별도 UID 생성
```

세 경로가 완전히 분리되어 있어, 같은 사람이 다른 provider로 로그인하면 별개의 UID가 생성된다.

### 해결 방향

**Google/이메일 로그인 시** 서버에서 이메일 기반 기존 계정 존재 여부를 체크하고,
기존 계정이 있으면 해당 UID의 custom token을 발급하여 기존 계정으로 로그인시킨다.

```
Google 로그인 시나리오:
1. 클라이언트: Google Sign-In SDK → idToken 획득
2. 클라이언트: linkOrCreateAccount({ provider: 'google', idToken: '...' }) 호출
3. 서버:
   a. idToken 검증 → 이메일 추출
   b. 이메일로 기존 Firebase Auth 사용자 조회 (admin.auth().getUserByEmail)
   c. 기존 사용자 있음 → 그 UID의 custom token 반환
   d. 기존 사용자 없음 → 새 사용자 생성 → custom token 반환
4. 클라이언트: signInWithCustomToken(token)
```

```
카카오 로그인 시나리오 (기존 kakaoCustomAuth 확장):
1. 카카오 API에서 이메일 추출 (profile.kakao_account.email)
2. 이메일이 있으면 → admin.auth().getUserByEmail 로 기존 계정 체크
3. 기존 계정 있음 → kakao_uid_map 업데이트 + 그 UID의 custom token 반환
4. 기존 계정 없음 → 기존 로직대로 anonymous UID 바인딩
```

---

## Phase 0: 사전 진단

```bash
# 1. 현재 index.js 함수 목록 확인
grep "^exports\." firebase/functions/index.js

# 2. kakaoCustomAuth에서 이메일 처리 여부 확인
grep -n "email" firebase/functions/index.js

# 3. 현재 배포된 함수 목록
firebase --project stealth-vox-3p3rq3 functions:list
```

---

## Phase 1: Savepoint

```bash
cd firebase/functions
git add -A && git commit -m "savepoint: before account linking CF"
```

---

## Phase 2: 수정 작업

### 2-A: kakaoCustomAuth 확장 — 이메일 기반 기존 계정 매칭 추가

**현재 kakaoCustomAuth 로직:**
```
카카오 token → kapi.kakao.com 검증 → kakaoId 추출 → kakao_uid_map 조회 → UID 결정
```

**변경 후:**
```
카카오 token → kapi.kakao.com 검증 → kakaoId + email 추출
→ kakao_uid_map에 기존 매핑 있으면 → 기존 UID (변경 없음)
→ kakao_uid_map에 매핑 없으면:
   → email로 admin.auth().getUserByEmail 조회
   → 기존 계정 있으면 → 그 UID로 kakao_uid_map 생성 + custom token
   → 기존 계정 없으면 → anonymous UID 바인딩 (기존 로직)
```

#### str_replace 편집

**앵커**: `const profile = await resp.json();`
**위치**: kakaoCustomAuth 함수 내부

기존:
```javascript
      const profile = await resp.json();
      kakaoId = profile && profile.id != null ? String(profile.id) : null;
```

변경:
```javascript
      const profile = await resp.json();
      kakaoId = profile && profile.id != null ? String(profile.id) : null;
      // 이메일 추출 (카카오 동의항목에서 이메일 제공 시)
      kakaoEmail = profile && profile.kakao_account && profile.kakao_account.email
        ? profile.kakao_account.email
        : null;
```

그리고 `kakaoEmail` 변수 선언을 `kakaoId` 선언 옆에 추가:
```javascript
    let kakaoId = null;
    let kakaoEmail = null;
```

**앵커**: `const resolvedUid = await firestore.runTransaction(async (tx) => {`
기존 트랜잭션 내부 로직 변경:

기존:
```javascript
    const resolvedUid = await firestore.runTransaction(async (tx) => {
      const mapDoc = await tx.get(mapRef);
      if (mapDoc.exists && mapDoc.data().uid) {
        return mapDoc.data().uid;
      }
      tx.set(mapRef, {
        uid: anonUid,
        kakao_id: kakaoId,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return anonUid;
    });
```

변경:
```javascript
    const resolvedUid = await firestore.runTransaction(async (tx) => {
      const mapDoc = await tx.get(mapRef);
      if (mapDoc.exists && mapDoc.data().uid) {
        return mapDoc.data().uid;
      }

      // 이메일 기반 기존 계정 매칭 시도
      let targetUid = anonUid;
      if (kakaoEmail) {
        try {
          const existingUser = await admin.auth().getUserByEmail(kakaoEmail);
          if (existingUser && existingUser.uid) {
            targetUid = existingUser.uid;
            functions.logger.info("kakaoCustomAuth: email match found", {
              kakaoEmail: kakaoEmail,
              existingUid: existingUser.uid,
            });
          }
        } catch (emailErr) {
          // getUserByEmail throws if user not found — this is normal
          if (emailErr.code !== "auth/user-not-found") {
            functions.logger.warn("kakaoCustomAuth: getUserByEmail error", {
              error: String(emailErr),
            });
          }
        }
      }

      tx.set(mapRef, {
        uid: targetUid,
        kakao_id: kakaoId,
        kakao_email: kakaoEmail || null,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return targetUid;
    });
```

### 2-B: linkOrCreateAccount 신규 Cloud Function 추가

Google/이메일 로그인 시 이메일 기반 기존 계정 매칭을 위한 새 callable 함수.

**index.js 맨 하단에 추가:**

```javascript
// ----------------------------------------------------------------------------
// linkOrCreateAccount
// Type:   HTTPS Callable
// Input:  { provider: 'google' | 'email', idToken?: string, email?: string, password?: string }
// Output: { token: string, isNewUser: boolean }
//
// 이메일 기반 계정 통합:
//   1. provider별로 이메일 추출
//   2. admin.auth().getUserByEmail 로 기존 계정 조회
//   3. 기존 계정 있음 → 해당 UID의 custom token 반환
//   4. 기존 계정 없음 → 새 사용자 생성 → custom token 반환
//
// 참고: 이 함수를 사용하면 클라이언트에서 signInWithCredential 대신
//       signInWithCustomToken을 사용해야 한다.
// ----------------------------------------------------------------------------
exports.linkOrCreateAccount = functions.https.onCall(async (data, context) => {
  const provider = data && data.provider;
  if (!provider || !["google", "email"].includes(provider)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "provider must be 'google' or 'email'."
    );
  }

  let email = null;
  let displayName = null;

  if (provider === "google") {
    const idToken = data.idToken;
    if (!idToken) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "idToken is required for Google provider."
      );
    }
    // Google ID Token 검증
    try {
      const decodedToken = await admin.auth().verifyIdToken(idToken);
      email = decodedToken.email;
      displayName = decodedToken.name || null;
    } catch (e) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Invalid Google ID token: " + String(e)
      );
    }
  } else if (provider === "email") {
    email = data.email;
    if (!email || typeof email !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "email is required for email provider."
      );
    }
    // 이메일 로그인의 경우, 기존 Firebase Auth 로직을 사용하므로
    // 이 함수에서는 기존 계정 존재 여부 확인만 수행
  }

  if (!email) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Could not extract email from provider data."
    );
  }

  // 기존 계정 조회
  let existingUser = null;
  try {
    existingUser = await admin.auth().getUserByEmail(email);
  } catch (e) {
    if (e.code !== "auth/user-not-found") {
      throw new functions.https.HttpsError(
        "internal",
        "Failed to check existing account: " + String(e)
      );
    }
  }

  if (existingUser) {
    // 기존 계정 발견 → custom token 발급
    const token = await admin.auth().createCustomToken(existingUser.uid, {
      provider: provider,
      linked: true,
    });

    functions.logger.info("linkOrCreateAccount: existing user matched", {
      email: email,
      uid: existingUser.uid,
      provider: provider,
    });

    return { token: token, isNewUser: false };
  }

  // 기존 계정 없음 → 새 사용자 생성
  const newUser = await admin.auth().createUser({
    email: email,
    displayName: displayName,
  });

  const token = await admin.auth().createCustomToken(newUser.uid, {
    provider: provider,
    linked: false,
  });

  functions.logger.info("linkOrCreateAccount: new user created", {
    email: email,
    uid: newUser.uid,
    provider: provider,
  });

  return { token: token, isNewUser: true };
});
```

---

## Phase 3: 검증

```bash
# 1. 문법 오류 확인
cd firebase/functions
node -c index.js
# 기대: "index.js: no syntax error"

# 2. 새 함수 존재 확인
grep "exports.linkOrCreateAccount" index.js
# 기대: 1줄

# 3. kakaoEmail 변수 추가 확인
grep "kakaoEmail" index.js
# 기대: 4줄 이상

# 4. getUserByEmail 사용 확인
grep "getUserByEmail" index.js
# 기대: 2줄 이상 (kakaoCustomAuth + linkOrCreateAccount)
```

---

## Phase 4: 배포

```bash
# 주의: 멀티 코드베이스 배포 형식
# kakaoCustomAuth 수정 + linkOrCreateAccount 신규 → 둘 다 배포

firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:kakaoCustomAuth
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:linkOrCreateAccount

# 또는 전체 배포 (다른 함수에 영향 없음을 확인한 경우):
# firebase deploy --project stealth-vox-3p3rq3 --only functions
```

---

## Phase 5: 커밋

```bash
git add -A && git commit -m "feat: add email-based account linking (kakaoAuth + linkOrCreateAccount)"
git push origin main
```

---

## Phase 6: 롤백 (문제 발생 시)

```bash
git revert HEAD --no-edit
git push origin main

# Cloud Function 재배포
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:kakaoCustomAuth
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:linkOrCreateAccount
```

---

## 클라이언트 측 변경 (별도 지시문 권장)

지시문 3의 서버 로직이 완성되면, 클라이언트 `SocialAuthService`의 Google 로그인 플로우를
아래와 같이 변경해야 한다:

### 현재 (추정):
```dart
// Google Sign-In → signInWithCredential(GoogleAuthProvider)
final googleUser = await GoogleSignIn().signIn();
final googleAuth = await googleUser!.authentication;
final credential = GoogleAuthProvider.credential(
  idToken: googleAuth.idToken,
  accessToken: googleAuth.accessToken,
);
await FirebaseAuth.instance.signInWithCredential(credential);
```

### 변경 후:
```dart
// Google Sign-In → idToken → linkOrCreateAccount → signInWithCustomToken
final googleUser = await GoogleSignIn().signIn();
final googleAuth = await googleUser!.authentication;

final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
    .httpsCallable('linkOrCreateAccount');
final result = await callable.call({
  'provider': 'google',
  'idToken': googleAuth.idToken,
});

final token = result.data['token'] as String;
await FirebaseAuth.instance.signInWithCustomToken(token);
```

> 이 클라이언트 변경은 별도 지시문 4로 작성하는 것을 권장한다.
> SocialAuthService.dart 파일을 직접 수정해야 하며, 카카오/이메일 로그인 경로도
> 동일한 패턴으로 통합해야 한다.

---

## 제한사항 및 향후 과제

1. **카카오 이메일 미제공 케이스**: 사용자가 카카오 동의항목에서 이메일 제공을 거부하면
   `kakaoEmail = null`이 되어 이메일 매칭이 불가능하다. 이 경우 기존 로직(anonymous UID 바인딩)으로
   fallback되므로 동작에는 문제 없지만, 계정 통합은 이뤄지지 않는다.

2. **카카오 이메일 ≠ Google 이메일**: 카카오에 `naver.com` 이메일, Google에 `gmail.com` 이메일을
   사용하는 경우 이메일이 달라서 매칭되지 않는다. 이는 업계 표준에서도 감수하는 한계이다.

3. **기존 사용자 데이터 마이그레이션**: 이미 중복 UID가 생성된 기존 사용자의 경우,
   이 로직만으로는 자동 통합되지 않는다. 별도의 관리자 스크립트가 필요하다.

4. **Anonymous → 정식 계정 전환**: 현재 `signInAnonymously` → 카카오 로그인 시
   anonymous UID를 재사용하는 구조(`kakao_uid_map`)는 유지된다.
   Google 로그인도 `linkOrCreateAccount`를 통해 동일한 패턴으로 동작한다.