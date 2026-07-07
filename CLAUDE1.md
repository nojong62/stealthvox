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

# 지시문 4: 클라이언트 계정 통합 연동 + kakaoCustomAuth 이메일 보강

## 목적
지시문 3에서 배포한 `linkOrCreateAccount` Cloud Function이 실제로 동작하도록
서버/클라이언트 양쪽을 보강한다.

## 핵심 문제 2가지

### 문제 1: 카카오 계정에 이메일이 없다
`kakaoCustomAuth`는 custom token으로 Firebase 유저를 생성하지만,
Firebase Auth 레코드에 **email 필드를 설정하지 않는다.**
→ 나중에 Google로 로그인할 때 `getUserByEmail`로 카카오 계정을 찾을 수 없다.
→ 같은 사람인데 별개 UID가 생성된다.

### 문제 2: 체험 데이터 보존과 계정 통합의 양립
현재 `signInWithGoogle()`은 anonymous 상태에서 `linkWithCredential`로
anonymous UID에 Google 계정을 연결하여 체험 데이터를 보존한다.
이걸 단순히 `linkOrCreateAccount`로 교체하면 anonymous UID가 버려진다.
→ **anonymous 상태에서는 기존 로직 유지, non-anonymous에서만 linkOrCreateAccount 경유**

## 대상 파일
- **수정**: `firebase/functions/index.js` (kakaoCustomAuth 보강)
- **수정**: `lib/auth/social_auth_service.dart` (signInWithGoogle 변경)

## 선행 조건
- ✅ 지시문 1, 2, 3 완료
- ✅ `linkOrCreateAccount` CF 배포 완료
- ✅ `kakaoCustomAuth`에 `kakaoEmail` 추출 로직 이미 추가됨 (지시문 3)

---

## Part A: kakaoCustomAuth — Firebase Auth에 이메일 설정

### 현재 상태
지시문 3에서 `kakaoEmail`을 추출하고 `kakao_uid_map`에 저장하지만,
Firebase Auth 레코드(`admin.auth().getUser(uid)`)에는 email이 비어있다.

### 수정 내용
custom token 발급 직후, `admin.auth().updateUser()`로 이메일을 설정한다.

### Phase 0: 사전 진단

```bash
# kakaoEmail 관련 코드 확인
grep -n "kakaoEmail" firebase/functions/index.js

# createCustomToken 위치 확인
grep -n "createCustomToken" firebase/functions/index.js

# 현재 kakaoCustomAuth에서 updateUser 사용 여부
grep -n "updateUser" firebase/functions/index.js
# 기대: 0줄 (아직 없음)
```

### Phase 1: Savepoint

```bash
git add -A && git commit -m "savepoint: before kakaoCustomAuth email enrichment"
```

### Phase 2: 수정

**앵커**: kakaoCustomAuth 함수 내부, custom token 발급 직후 (로깅 직전)

기존:
```javascript
    const token = await admin
      .auth()
      .createCustomToken(resolvedUid, { provider: "kakaocorp.com" });

    functions.logger.info("kakaoCustomAuth", {
```

변경:
```javascript
    const token = await admin
      .auth()
      .createCustomToken(resolvedUid, { provider: "kakaocorp.com" });

    // Firebase Auth 레코드에 카카오 이메일 설정 (이메일 기반 계정 통합의 전제 조건)
    if (kakaoEmail) {
      try {
        const existingAuthUser = await admin.auth().getUser(resolvedUid);
        if (!existingAuthUser.email) {
          await admin.auth().updateUser(resolvedUid, { email: kakaoEmail });
          functions.logger.info("kakaoCustomAuth: email set on auth record", {
            uid: resolvedUid,
            email: kakaoEmail,
          });
        }
      } catch (updateErr) {
        // 이메일 설정 실패해도 로그인 자체는 진행 (non-blocking)
        functions.logger.warn("kakaoCustomAuth: updateUser email failed", {
          uid: resolvedUid,
          error: String(updateErr),
        });
      }
    }

    functions.logger.info("kakaoCustomAuth", {
```

**핵심 포인트:**
- `getUser`로 먼저 기존 이메일 존재 여부를 확인 → 이미 있으면 덮어쓰지 않음
- `updateUser` 실패해도 로그인은 진행 (try/catch로 감싸서 non-blocking)
- 이미 다른 Firebase 유저가 같은 이메일을 쓰고 있으면 `updateUser`가 실패할 수 있음 (이것도 non-blocking 처리)

### Phase 3: 검증

```bash
node -c firebase/functions/index.js
# 기대: 문법 오류 없음

grep -c "updateUser" firebase/functions/index.js
# 기대: 1 이상

grep "email set on auth record" firebase/functions/index.js
# 기대: 1줄
```

### Phase 4: 배포

```bash
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:kakaoCustomAuth
```

### Phase 5: 커밋

```bash
git add -A && git commit -m "feat: set kakao email on Firebase Auth record for account linking"
git push origin main
```

---

## Part B: signInWithGoogle — 계정 통합 연동

### 현재 로직 (social_auth_service.dart)

```
1. GoogleSignIn → googleAuth (idToken + accessToken)
2. GoogleAuthProvider.credential 생성
3. if (currentUser != null && isAnonymous):
   a. linkWithCredential → 성공: anonymous UID에 Google 연결 (체험 데이터 보존)
   b. credential-already-in-use → signInWithCredential (기존 Google 계정으로 전환)
4. else: signInWithCredential
```

### 변경 로직

```
1. GoogleSignIn → googleAuth (idToken + accessToken)
2. GoogleAuthProvider.credential 생성
3. if (currentUser != null && isAnonymous):
   a. linkOrCreateAccount({ provider: 'google', idToken }) 호출
   b. 응답의 isNewUser == true → linkWithCredential (anonymous UID 보존, 체험 데이터 유지)
   c. 응답의 isNewUser == false → signInWithCustomToken(token) (기존 계정으로 전환)
4. else (이미 로그인된 상태에서 재로그인 — 앱 삭제 후 재설치 등):
   a. linkOrCreateAccount({ provider: 'google', idToken }) 호출
   b. signInWithCustomToken(token) (기존 계정이든 신규든 서버가 결정)
```

### Phase 0: 사전 진단

```bash
# 현재 signInWithGoogle 구조 확인
grep -n "signInWithGoogle\|linkWithCredential\|signInWithCredential\|GoogleAuthProvider" lib/auth/social_auth_service.dart

# linkOrCreateAccount 호출 여부 확인 (아직 없어야 함)
grep -n "linkOrCreateAccount" lib/auth/social_auth_service.dart
# 기대: 0줄
```

### Phase 1: Savepoint

```bash
git add -A && git commit -m "savepoint: before signInWithGoogle account linking"
```

### Phase 2: 수정

`signInWithGoogle()` 메서드 전체를 아래로 교체한다.

기존:
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
    if (currentUser != null && currentUser.isAnonymous) {
      try {
        final linked = await currentUser.linkWithCredential(credential);
        FFAppState().hasLinkedAccount = true;
        return linked;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use') {
          final signedIn = await _auth.signInWithCredential(credential);
          FFAppState().hasLinkedAccount = true;
          return signedIn;
        }
        rethrow;
      }
    }

    final signedIn = await _auth.signInWithCredential(credential);
    FFAppState().hasLinkedAccount = true;
    return signedIn;
  }
```

변경:
```dart
  static Future<UserCredential> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: idToken,
    );

    final currentUser = _auth.currentUser;

    // ── Case 1: Anonymous 유저 (체험 후 첫 가입) ──
    if (currentUser != null && currentUser.isAnonymous) {
      // 서버에 이메일 기반 기존 계정 존재 여부를 먼저 확인
      final checkResult = await _callLinkOrCreate('google', idToken: idToken);
      final isNewUser = checkResult['isNewUser'] as bool;
      final serverToken = checkResult['token'] as String;

      if (isNewUser) {
        // 신규 사용자 → anonymous UID에 Google credential 연결 (체험 데이터 보존)
        try {
          final linked = await currentUser.linkWithCredential(credential);
          FFAppState().hasLinkedAccount = true;
          return linked;
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use') {
            // 극히 드문 케이스: 서버는 신규라 했는데 Firebase Auth는 이미 존재
            // → 서버가 만든 계정으로 전환
            final signedIn = await _auth.signInWithCustomToken(serverToken);
            FFAppState().hasLinkedAccount = true;
            return signedIn;
          }
          rethrow;
        }
      } else {
        // 기존 사용자 발견 → 서버가 내려준 custom token으로 기존 계정 전환
        // (anonymous UID는 버려지지만, 기존 계정의 시간/기록이 더 중요)
        final signedIn = await _auth.signInWithCustomToken(serverToken);
        FFAppState().hasLinkedAccount = true;
        return signedIn;
      }
    }

    // ── Case 2: 이미 로그인된 상태 또는 로그아웃 후 재로그인 ──
    // 서버가 이메일로 기존 계정을 찾아주므로 중복 계정 방지
    final checkResult = await _callLinkOrCreate('google', idToken: idToken);
    final serverToken = checkResult['token'] as String;
    final signedIn = await _auth.signInWithCustomToken(serverToken);
    FFAppState().hasLinkedAccount = true;
    return signedIn;
  }

  /// linkOrCreateAccount Cloud Function 호출 헬퍼
  static Future<Map<String, dynamic>> _callLinkOrCreate(
    String provider, {
    String? idToken,
    String? email,
  }) async {
    final callable = _functions.httpsCallable('linkOrCreateAccount');
    final result = await callable.call<Map<String, dynamic>>({
      'provider': provider,
      if (idToken != null) 'idToken': idToken,
      if (email != null) 'email': email,
    });
    return result.data;
  }
```

### 변경하지 않는 것

- `signInWithKakao()` — 이미 `kakaoCustomAuth` CF를 경유하고, 지시문 3에서 이메일 매칭 로직을 추가했으므로 변경 불필요
- `signInWithEmail()` — 이메일 로그인은 이메일 자체가 식별자이므로 `linkOrCreateAccount` 불필요 (Firebase Auth가 자체적으로 이메일 중복 방지)

### Phase 3: 검증

```bash
dart format lib/auth/social_auth_service.dart
flutter analyze lib/auth/social_auth_service.dart

# linkOrCreateAccount 호출 확인
grep -c "linkOrCreateAccount" lib/auth/social_auth_service.dart
# 기대: 1 (callable 이름)

# _callLinkOrCreate 헬퍼 존재 확인
grep -c "_callLinkOrCreate" lib/auth/social_auth_service.dart
# 기대: 3 이상 (정의 1 + 호출 2)

# signInWithCustomToken 사용 확인
grep -c "signInWithCustomToken" lib/auth/social_auth_service.dart
# 기대: 2 이상
```

### Phase 4: 커밋

```bash
git add -A && git commit -m "feat: integrate linkOrCreateAccount into signInWithGoogle for account linking"
git push origin main
```

### Phase 5: 롤백 (문제 발생 시)

```bash
git revert HEAD --no-edit
git push origin main
```

---

## 통합 테스트 시나리오

Part A + B 모두 완료 후, 아래 시나리오를 수동 테스트해야 한다:

### 시나리오 1: 카카오로 가입 → 앱 삭제 → Google로 재로그인 (같은 이메일)
1. 카카오 로그인 (이메일: user@naver.com)
2. 시간 충전 → remainingTime 확인
3. 앱 삭제 → 재설치
4. Google 로그인 (이메일: user@naver.com — 카카오와 동일)
5. **기대**: 기존 계정의 remainingTime이 그대로 살아있음

### 시나리오 2: 카카오로 가입 → 앱 삭제 → Google로 재로그인 (다른 이메일)
1. 카카오 로그인 (이메일: user@naver.com)
2. 앱 삭제 → 재설치
3. Google 로그인 (이메일: user@gmail.com — 카카오와 다름)
4. **기대**: 신규 계정 생성 (이메일이 달라서 매칭 불가 — 업계 표준 한계)

### 시나리오 3: 체험 → Google로 첫 가입 (신규)
1. 체험 시작 (anonymous)
2. 체험 완료 → 가입 화면
3. Google로 가입 (신규 이메일)
4. **기대**: anonymous UID에 Google 연결, 체험 중 생성된 chat_history 유지

### 시나리오 4: 체험 → Google로 가입 (기존 계정 존재)
1. 체험 시작 (anonymous)
2. 체험 완료 → 가입 화면
3. Google로 가입 (이미 카카오로 가입한 이메일)
4. **기대**: 기존 카카오 계정으로 전환 (anonymous 체험 데이터는 버려짐, 기존 시간/기록 복원)

---

## 제한사항

1. **카카오 이메일 동의 거부 시**: `kakaoEmail = null` → Firebase Auth에 이메일 미설정 → 이메일 매칭 불가.
   카카오 개발자 콘솔에서 "이메일" 항목을 **필수 동의**로 설정하면 해결 가능하나,
   비즈앱 등록이 필요할 수 있음.

2. **기존 카카오 유저**: 이 배포 이전에 가입한 카카오 유저들은 Firebase Auth에 이메일이 없음.
   → Part A의 `updateUser`는 **새 로그인 시에만** 이메일을 설정하므로,
   기존 유저가 다시 로그인해야 이메일이 채워진다.
   → 기존 유저 일괄 처리가 필요하면 별도 마이그레이션 스크립트 작성 권장.

3. **시나리오 4에서 체험 데이터 손실**: 기존 계정으로 전환하면 anonymous UID의 체험 데이터는 접근 불가.
   이건 의도된 동작 — 기존 계정의 시간/기록이 더 중요하므로 트레이드오프로 수용.