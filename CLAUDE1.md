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

# Kakao 로그인 후 Store 게이트 오탐 수정 — hasLinkedAccount 플래그 도입

## 원인 요약
Firebase의 `currentUser.isAnonymous`는 로그인 방법이 아니라 "실제 auth provider가 providerData에 연결돼 있는가"로 판정됩니다. Google/Email은 Firebase 내장 provider라 자동으로 `false`가 되지만, Kakao는 `kakaoCustomAuth` 클라우드 함수의 `createCustomToken()`으로 로그인하기 때문에 로그인 자체는 성공해도 `isAnonymous`가 계속 `true`로 남습니다. `store_master.dart`의 구매 게이트가 이 값만 보고 있어서, 카카오로 가입 완료한 사용자에게도 `SocialLoginModal`이 다시 뜹니다.

## 해결 방향
Firebase의 `isAnonymous`에 의존하지 않는 자체 플래그 `hasLinkedAccount`를 도입 — 소셜 로그인(카카오/구글/이메일) 성공 시점에 true로 세팅하고, Store 게이트는 이 플래그를 함께 확인.

## 영향 범위
- FFAppState 정의 파일 (경로 미확인 — Phase 0에서 탐색)
- `lib/auth/social_auth_service.dart`
- `lib/custom_code/widgets/store_master.dart`

---

## Phase 0 — savepoint + 탐색

```bash
git add -A && git commit -m "savepoint: before hasLinkedAccount flag"

grep -rn "class FFAppState" lib/
grep -n "bool isGuestSession" $(grep -rl "class FFAppState" lib/)
```

두 번째 grep으로 기존 bool 필드가 어떤 스타일로 선언돼 있는지(단순 필드인지, getter/setter + SharedPreferences 영속화가 있는지) 확인하고, 아래 Phase 1을 그 스타일에 맞춰 적용할 것. 스타일이 크게 다르면 진행 전에 실장에게 스타일 예시를 보고할 것.

---

## Phase 1 — FFAppState에 필드 추가

`isGuestSession`과 동일한 선언 방식으로 다음을 추가:

```dart
  bool hasLinkedAccount = false;
```

(만약 기존 필드들이 SharedPreferences 영속화 getter/setter 패턴이면, `hasLinkedAccount`도 앱 재시작 후에도 유지되도록 같은 패턴으로 맞출 것 — 카카오로 가입한 사용자가 앱을 껐다 켰을 때도 다시 게이트에 걸리면 안 되기 때문.)

---

## Phase 2 — social_auth_service.dart: 로그인 성공 시 플래그 세팅

### 2-1. import 추가

```
old_str:
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

new_str:
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import '/flutter_flow/flutter_flow_util.dart';
```

### 2-2. signInWithKakao — 성공 후 플래그 세팅

```
old_str:
    final customToken = result.data['token'] as String;
    return _auth.signInWithCustomToken(customToken);
  }

new_str:
    final customToken = result.data['token'] as String;
    final credential = await _auth.signInWithCustomToken(customToken);
    FFAppState().hasLinkedAccount = true;
    return credential;
  }
```

### 2-3. signInWithGoogle — 두 return 지점 모두에 플래그 세팅

```
old_str:
    final currentUser = _auth.currentUser;
    if (currentUser != null && currentUser.isAnonymous) {
      try {
        return await currentUser.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use') {
          return _auth.signInWithCredential(credential);
        }
        rethrow;
      }
    }

    return _auth.signInWithCredential(credential);
  }

new_str:
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

### 2-4. signInWithEmail — 세 return 지점 모두에 플래그 세팅

```
old_str:
    if (isSignUp && currentUser != null && currentUser.isAnonymous) {
      try {
        return await currentUser.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          return _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        }
        rethrow;
      }
    }

    if (isSignUp) {
      return _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    }

    return _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

new_str:
    if (isSignUp && currentUser != null && currentUser.isAnonymous) {
      try {
        final linked = await currentUser.linkWithCredential(credential);
        FFAppState().hasLinkedAccount = true;
        return linked;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          final signedIn = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          FFAppState().hasLinkedAccount = true;
          return signedIn;
        }
        rethrow;
      }
    }

    if (isSignUp) {
      final created = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      FFAppState().hasLinkedAccount = true;
      return created;
    }

    final signedIn = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    FFAppState().hasLinkedAccount = true;
    return signedIn;
  }
```

---

## Phase 3 — store_master.dart: 게이트 조건 수정

```
old_str:
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const SocialLoginModal(),
      );
      if (result != true || !mounted) return;
      await _initRevenueCatUser();
    }

new_str:
    final currentUser = FirebaseAuth.instance.currentUser;
    final needsAccount = currentUser == null ||
        (currentUser.isAnonymous && !FFAppState().hasLinkedAccount);
    if (needsAccount) {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const SocialLoginModal(),
      );
      if (result != true || !mounted) return;
      FFAppState().hasLinkedAccount = true;
      await _initRevenueCatUser();
    }
```

(`SocialLoginModal`이 내부적으로 이미 `SocialAuthService`를 호출하므로 Phase 2에서 플래그가 세팅되지만, 방어적으로 여기서도 한 번 더 세팅 — 두 경로 다 안전하게)

---

## Phase 4 — 검증

```bash
grep -c "hasLinkedAccount" lib/auth/social_auth_service.dart
# 5 이상 (카카오 1 + 구글 3 + 이메일 3 중 실제 반영된 개수)

grep -c "hasLinkedAccount" lib/custom_code/widgets/store_master.dart

flutter analyze lib/auth/social_auth_service.dart
flutter analyze lib/custom_code/widgets/store_master.dart
dart format lib/auth/social_auth_service.dart
dart format lib/custom_code/widgets/store_master.dart
```

---

## Phase 5 — 실기기 체크리스트

- [ ] 카카오로 가입 완료 → Lobby 진입 → Store에서 구매 버튼 클릭 → **팝업 안 뜨고 바로 구매 흐름 진행**
- [ ] 완전 신규(비로그인) 상태로 Store 구매 시도 → 팝업 정상적으로 뜸 (회귀 확인)
- [ ] 구글/이메일 로그인도 기존처럼 정상 동작 (회귀 확인)
- [ ] 앱을 완전히 종료했다가 재실행 후에도 카카오 계정 상태에서 팝업이 안 뜨는지 확인 (Phase 1에서 영속화 여부에 따라 결과가 갈림 — 안 되면 Phase 1을 SharedPreferences 영속화 패턴으로 다시 요청)

**롤백**: `git revert <savepoint 이후 커밋>` 또는 `git reset --hard <savepoint>`