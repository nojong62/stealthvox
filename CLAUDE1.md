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

# 지시문: 크로스-프로바이더 계정 통합 (진단 → 수정)

## 배경

카카오로 로그인 → 로그아웃 → 앱 재시작 → Google로 로그인하면
기존 카카오 계정에 **병합되지 않고 새 Google 계정이 생성**된다. 반대도 마찬가지.

이전 작업으로 `linkOrCreateAccount` Cloud Function(이메일 기반 계정 통합)이 배포되어 있고,
`kakaoCustomAuth`에 `kakaoEmail` 추출 로직도 추가되어 있다.
그러나 **클라이언트 연동(지시문 4)이 미적용**되었을 가능성이 높다.

이 지시문은 Codex가 **먼저 현재 상태를 진단**하고, 누락된 부분만 정확히 보강한다.

## 불변 규칙

- Box 7 (`TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`, `HybridTtsPlayer`, `TtsCache`) 절대 수정 금지
- `lib/custom_code/임시/` 절대 수정 금지
- `dart format`은 개별 파일 단위로만 실행 (폴더 단위 금지 — 한국어 UTF-8 깨짐)
- 코드 수정 전 반드시 Phase 0 진단 완료 후 결과를 사용자에게 보고하고 승인받을 것
- Firebase 멀티 codebase 배포: `firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:[함수명]`
- Firebase CLI는 `firebase/` 서브디렉토리에서 실행

---

## Phase S: Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before cross-provider account linking fix"
```

---

## Phase 0: 진단 (결과를 사용자에게 보고 후 승인받고 진행)

아래 진단을 **모두** 실행하고, 결과를 정리하여 사용자에게 보여줄 것.

### 0-1. kakaoCustomAuth에서 Firebase Auth 이메일 설정 여부 확인

```bash
cd firebase/functions
grep -n "updateUser" index.js
# 기대: kakaoCustomAuth 내에서 admin.auth().updateUser(uid, { email: kakaoEmail }) 호출이 있어야 함
# 없으면 → Part A 수정 필요

grep -n "kakaoEmail" index.js
# kakaoEmail 추출은 지시문 3에서 추가됨 — 몇 줄 나오는지 확인
```

### 0-2. linkOrCreateAccount CF 존재 및 구조 확인

```bash
grep -n "exports.linkOrCreateAccount" index.js
# 기대: 1줄 (배포 완료 상태)

grep -n "getUserByEmail" index.js
# 기대: linkOrCreateAccount 내에서 이메일로 기존 유저를 찾는 로직
```

### 0-3. signInWithGoogle에서 linkOrCreateAccount 호출 여부 확인

```bash
grep -n "linkOrCreateAccount" lib/auth/social_auth_service.dart
# 기대: non-anonymous 경로에서 호출이 있어야 함
# 없으면 → Part B 수정 필요

grep -n "signInWithCredential\|signInWithCustomToken\|linkWithCredential" lib/auth/social_auth_service.dart
# 현재 Google 로그인 흐름 파악
```

### 0-4. signInWithGoogle 전체 메서드 확인

```bash
grep -n -A 50 "signInWithGoogle" lib/auth/social_auth_service.dart
# 전체 메서드 구조를 파악하여 사용자에게 보고
```

### 0-5. kakao_uid_map에 authEmailSet 필드 확인

```bash
grep -n "authEmailSet" index.js
# 카카오 빠른 경로(fast path) 최적화에서 이 필드가 사용됨
# updateUser 로직 추가 시 이 필드와의 관계 확인
```

### 진단 보고 형식

```
=== Phase 0 진단 결과 ===

[0-1] kakaoCustomAuth updateUser: 있음/없음 (n줄)
[0-2] linkOrCreateAccount CF: 있음/없음
[0-3] signInWithGoogle → linkOrCreateAccount 호출: 있음/없음
[0-4] signInWithGoogle 현재 흐름: (요약)
[0-5] authEmailSet: 있음/없음

=== 필요한 수정 ===
- Part A (서버): 필요/불필요
- Part B (클라이언트): 필요/불필요
```

**이 보고를 사용자에게 보여주고 승인을 받은 후 Phase 1로 진행한다.**

---

## Phase 1: Part A — kakaoCustomAuth Firebase Auth 이메일 설정

> Phase 0에서 `updateUser`가 이미 있으면 이 단계 건너뛴다.

### 수정 위치

`firebase/functions/index.js` → `kakaoCustomAuth` 함수 내부

### 수정 내용

custom token 발급 직후 (`admin.auth().createCustomToken(resolvedUid)` 직후),
카카오 이메일이 있으면 Firebase Auth 레코드에 이메일을 설정한다.

**삽입할 코드 (custom token 생성 직후에 추가):**

```javascript
// ── Firebase Auth 레코드에 카카오 이메일 설정 (계정 통합용) ──
if (kakaoEmail) {
  try {
    await admin.auth().updateUser(resolvedUid, { email: kakaoEmail });
    functions.logger.info(`[kakaoCustomAuth] email set: ${kakaoEmail} → ${resolvedUid}`);
  } catch (emailErr) {
    // email-already-exists: 다른 Firebase 유저가 이미 해당 이메일 사용 중
    // → 계정 통합 대상이므로 에러를 무시하되 로깅
    if (emailErr.code === 'auth/email-already-exists') {
      functions.logger.warn(
        `[kakaoCustomAuth] email ${kakaoEmail} already used by another account — linking will be handled by linkOrCreateAccount`
      );
    } else {
      functions.logger.error(`[kakaoCustomAuth] updateUser email failed:`, emailErr);
    }
  }
}
```

### 삽입 위치 찾기

```bash
grep -n "createCustomToken" index.js
# 이 줄 직후(return 문 직전)에 위 코드를 삽입
```

**주의:** `kakao_uid_map`의 fast path (`authEmailSet: true`)가 있는 경우,
fast path에서도 동일하게 이메일 설정이 필요한지 확인할 것.
fast path는 이미 계정이 만들어진 상태이므로 이메일도 이미 설정되어 있을 가능성이 높다.
확인 후 불필요하면 건너뛴다.

### 검증

```bash
grep -n "updateUser" index.js
# 기대: kakaoCustomAuth 내에 1줄 이상

node -c index.js
# 기대: no syntax error
```

---

## Phase 2: Part B — signInWithGoogle 계정 통합 연동

> Phase 0에서 `linkOrCreateAccount` 호출이 이미 있으면 이 단계 건너뛴다.

### 수정 위치

`lib/auth/social_auth_service.dart` → `signInWithGoogle()` 메서드

### 변경 로직

```
[현재 — 추정]
1. GoogleSignIn → googleAuth (idToken + accessToken)
2. GoogleAuthProvider.credential 생성
3. if (currentUser != null && isAnonymous):
   a. linkWithCredential → 성공: anonymous UID에 Google 연결
   b. credential-already-in-use → signInWithCredential (기존 Google 계정으로 전환)
4. else: signInWithCredential

[변경 후]
1. GoogleSignIn → googleAuth (idToken + accessToken)
2. GoogleAuthProvider.credential 생성
3. if (currentUser != null && isAnonymous):
   ── 체험 중 가입: 기존 linkWithCredential 로직 유지 (체험 데이터 보존) ──
   a. linkOrCreateAccount CF 호출 ({ provider: 'google', idToken })
   b. 응답의 isNewUser == true → linkWithCredential (anonymous UID 보존)
   c. 응답의 isNewUser == false → signInWithCustomToken (기존 계정으로 전환)
4. else (non-anonymous — 로그아웃 후 재로그인):
   ── 핵심 변경: linkOrCreateAccount 경유 ──
   a. linkOrCreateAccount CF 호출 ({ provider: 'google', idToken })
   b. signInWithCustomToken(token) (기존 계정이든 신규든 서버가 결정)
```

### 교체할 코드

**기존** `signInWithGoogle()` 메서드 전체를 아래로 교체한다.
(Phase 0-4에서 확인한 현재 코드를 `old_str`로 사용)

```dart
  static Future<UserCredential> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final currentUser = _auth.currentUser;

    // ── Case 1: anonymous 유저 (체험 중 가입) ──
    if (currentUser != null && currentUser.isAnonymous) {
      // 서버에 먼저 물어봄: 이 Google 이메일로 된 기존 계정이 있는가?
      try {
        final callable = _functions.httpsCallable('linkOrCreateAccount');
        final result = await callable.call<Map<String, dynamic>>({
          'provider': 'google',
          'idToken': googleAuth.idToken,
        });
        final isNewUser = result.data['isNewUser'] == true;
        final token = result.data['token'] as String;

        if (isNewUser) {
          // 신규 유저 → anonymous UID에 Google 연결하여 체험 데이터 보존
          try {
            final linked = await currentUser.linkWithCredential(credential);
            return linked;
          } on FirebaseAuthException catch (e) {
            if (e.code == 'credential-already-in-use') {
              // 드문 케이스: CF는 신규라 했지만 Firebase Auth에는 이미 존재
              return await _auth.signInWithCustomToken(token);
            }
            rethrow;
          }
        } else {
          // 기존 유저 발견 → 해당 계정으로 전환 (체험 데이터는 clean-start 정책에 따라 폐기)
          return await _auth.signInWithCustomToken(token);
        }
      } catch (e) {
        // CF 호출 실패 시 기존 방식으로 fallback
        debugPrint('[Auth] linkOrCreateAccount failed, fallback: $e');
        try {
          return await currentUser.linkWithCredential(credential);
        } on FirebaseAuthException catch (linkErr) {
          if (linkErr.code == 'credential-already-in-use') {
            return await _auth.signInWithCredential(credential);
          }
          rethrow;
        }
      }
    }

    // ── Case 2: non-anonymous (로그아웃 후 재로그인, 또는 비로그인 상태) ──
    try {
      final callable = _functions.httpsCallable('linkOrCreateAccount');
      final result = await callable.call<Map<String, dynamic>>({
        'provider': 'google',
        'idToken': googleAuth.idToken,
      });
      final token = result.data['token'] as String;
      return await _auth.signInWithCustomToken(token);
    } catch (e) {
      // CF 호출 실패 시 기존 방식으로 fallback
      debugPrint('[Auth] linkOrCreateAccount failed (non-anon), fallback: $e');
      return await _auth.signInWithCredential(credential);
    }
  }
```

### 검증

```bash
grep -n "linkOrCreateAccount" lib/auth/social_auth_service.dart
# 기대: 3줄 이상 (httpsCallable 호출 2곳 + fallback 로그 2곳)

grep -n "signInWithCustomToken" lib/auth/social_auth_service.dart
# 기대: 3줄 이상

# dart format (개별 파일만)
dart format lib/auth/social_auth_service.dart

# 분석
flutter analyze lib/auth/social_auth_service.dart 2>&1 | head -20
```

---

## Phase 3: linkOrCreateAccount CF 검증

### CF가 Google idToken을 올바르게 처리하는지 확인

```bash
cd firebase/functions
grep -n -A 30 "exports.linkOrCreateAccount" index.js | head -50
```

확인할 항목:
1. `provider === 'google'` 분기가 있는지
2. Google `idToken`에서 이메일을 추출하는지 (Firebase Admin `verifyIdToken` 또는 Google OAuth2 API)
3. `getUserByEmail`로 기존 유저를 찾는지
4. 기존 유저 발견 시 `isNewUser: false` + `token` 반환하는지
5. 신규면 `isNewUser: true` + `token` 반환하는지

**만약 CF가 Google idToken을 처리하지 못하는 구조라면**,
사용자에게 보고하고 CF 수정 방향을 제안할 것.

---

## Phase 4: 배포

```bash
# Part A 수정한 경우에만
cd firebase
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:kakaoCustomAuth

# CF 구조 변경한 경우
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:linkOrCreateAccount
```

---

## Phase 5: 커밋

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "fix: cross-provider account linking via linkOrCreateAccount"
git push origin main
```

---

## Phase 6: 롤백 (문제 발생 시)

```bash
git revert HEAD --no-edit
git push origin main

# CF 롤백 필요 시
cd firebase
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:kakaoCustomAuth
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:linkOrCreateAccount
```

---

## 테스트 시나리오 (수동 확인)

### 시나리오 1: 카카오 → 로그아웃 → Google (동일 이메일)
1. 카카오로 로그인 (카카오 이메일: user@gmail.com)
2. 로그아웃
3. 앱 종료 → 재시작
4. "이전에 카카오로 로그인했습니다" 표시 확인
5. Google로 로그인 (동일 user@gmail.com)
6. **기대:** 기존 카카오 계정의 UID 유지, remainingTime 보존

### 시나리오 2: Google → 로그아웃 → 카카오 (동일 이메일)
1. Google로 로그인
2. 로그아웃
3. 앱 종료 → 재시작
4. 카카오로 로그인 (동일 이메일)
5. **기대:** 기존 Google 계정의 UID 유지

### 시나리오 3: 다른 이메일
1. 카카오(naver.com 이메일)로 로그인 → 로그아웃
2. Google(gmail.com)로 로그인
3. **기대:** 이메일이 다르므로 별개 계정 생성 (이것은 정상 동작)

### 시나리오 4: 체험 → 카카오 가입 → 로그아웃 → Google 재로그인
1. 체험 완료
2. 카카오로 가입 (신규)
3. 로그아웃 → 앱 재시작
4. Google로 로그인
5. **기대:** 동일 이메일이면 카카오 계정에 병합, 다른 이메일이면 별개 계정

---

## 한계 (감수 사항)

1. **카카오 이메일 미제공:** 사용자가 카카오 동의항목에서 이메일 거부 시 매칭 불가 → 별개 계정
2. **카카오 이메일 ≠ Google 이메일:** 이메일이 다르면 매칭 불가 → 업계 표준에서도 감수하는 한계
3. **기존 중복 UID:** 이미 생성된 중복 계정은 자동 통합 불가 → 별도 관리자 스크립트 필요