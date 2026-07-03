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

# 지시문: 카카오 로그인 매번 새 UID 생성 문제 — 진단 및 수정

## 배경

카카오 로그인할 때마다 새 Firebase Auth UID가 생성되어:
- 이전 대화 히스토리가 보이지 않음
- remainingTime이 매번 초기화됨
- 로비 진입 시 Firestore 실제값(0)과 FFAppState 캐시값(2:46)이 불일치

Cloud Function `kakaoCustomAuth`(index.js)의 `kakao_uid_map` 트랜잭션 로직은 정상.
**근본 원인은 클라이언트 측 `SocialAuthService.signInWithKakao`에 있을 가능성이 높다.**

## 대상 파일 (진단 후 확정)
- `lib/auth/social_auth_service.dart` (1차 점검 대상)
- 로그아웃 로직이 있는 파일 (FFAppState 캐시 초기화)

---

## Phase 0 — Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before kakao uid duplication fix"
```

---

## Phase 1 — 진단 (반드시 결과를 실장에게 보고)

### 1-A: SocialAuthService 카카오 플로우 확인

```bash
cd F:\flutter_project\stealth_vox

# SocialAuthService 파일 위치 확인
find lib -name "social_auth_service*" -type f

# 파일 전체 내용 읽기
cat lib/auth/social_auth_service.dart
```

**다음 4가지를 확인하고 실장에게 보고:**

| 체크 항목 | 확인 방법 | 정상 기대값 |
|-----------|-----------|-------------|
| ① signInAnonymously 선행 | kakao 함수 내에서 현재 user가 null이면 `signInAnonymously()` 호출하는지 | 있어야 함 (Cloud Function이 `context.auth` 필요) |
| ② kakaoCustomAuth callable 호출 | `HttpsCallable`로 `kakaoCustomAuth`를 호출하고 결과의 `token`을 받는지 | 있어야 함 |
| ③ signInWithCustomToken 호출 | 반환된 token으로 `FirebaseAuth.instance.signInWithCustomToken(token)`을 **await**하는지 | **반드시 있어야 함 — 이것이 없으면 익명 uid로 남는다** |
| ④ 에러 핸들링 | ③이 try-catch 안에서 에러를 삼키고 있지 않은지 | 에러 시 throw 또는 rethrow |

**⚠️ ③이 없거나, await 없이 fire-and-forget이면 → 이것이 근본 원인**

### 1-B: 로그아웃 시 FFAppState 초기화 확인

```bash
# 로그아웃 로직 위치 찾기
grep -rn "signOut\|로그아웃\|logout\|logOut" lib/ --include="*.dart" -l

# remainingTime 초기화 여부 확인
grep -rn "remainingTime.*=.*0\|remainingTime.*reset" lib/ --include="*.dart"
```

**확인:**
- 로그아웃 시 `FFAppState().remainingTime = 0` (또는 전체 초기화)를 하는지
- 안 하면 → 이전 세션의 캐시값(2:46)이 다음 로그인에 유령처럼 표시됨

### 1-C: kakao_uid_map 데이터 확인 (참고용 — 코덱스가 직접 못함)

**실장님이 Firebase Console에서 수동 확인:**
- Firestore → `kakao_uid_map` 컬렉션 → 문서가 있는지
- 있다면 `uid` 필드값이 Firebase Auth 사용자 목록의 어떤 uid와 일치하는지
- Functions → 로그 → `kakaoCustomAuth` 검색 → `returning: true`가 나오는지 (한 번이라도 나오면 매핑 자체는 작동하는 것)

---

## Phase 2 — 수정

### Phase 1 진단 결과에 따라 아래 중 해당하는 것을 적용:

### Fix A: signInWithCustomToken 누락 시 (가장 가능성 높음)

`SocialAuthService.signInWithKakao` 함수에서 Cloud Function 호출 후
반환된 `token`으로 `signInWithCustomToken`을 **반드시 await** 해야 한다.

**정상적인 카카오 로그인 플로우 (이 순서대로 되어 있어야 함):**

```
1. 현재 user == null이면 → await signInAnonymously()
2. Kakao SDK 로그인 → accessToken 획득
3. await kakaoCustomAuth callable 호출 → { token } 수신
4. await FirebaseAuth.instance.signInWithCustomToken(token)   ← 핵심!
5. 이 시점에서 currentUser.uid == resolvedUid (매핑된 기존 uid)
```

**③→④ 사이에 token을 받고도 signInWithCustomToken을 호출하지 않거나,
await 없이 호출하고 있다면 수정해야 한다.**

수정 시 주의사항:
- `signInWithCustomToken`은 현재 인증 상태를 완전히 교체한다 (익명 uid → 매핑된 uid)
- 반드시 `await`해야 한다 — 안 하면 navigate가 먼저 실행되어 익명 uid로 Lobby 진입

### Fix B: signInAnonymously 선행 누락 시

kakaoCustomAuth Cloud Function은 `context.auth`가 필수.
카카오 로그인 시작 시점에 `FirebaseAuth.instance.currentUser`가 null이면
먼저 `await FirebaseAuth.instance.signInAnonymously()`를 호출해야 한다.

### Fix C: 로그아웃 시 FFAppState 캐시 초기화 (별도 수정)

로그아웃 함수에서 `FirebaseAuth.instance.signOut()` 직전 또는 직후에
FFAppState의 시간 관련 캐시를 초기화해야 한다:

```
FFAppState().remainingTime = 0
```

이것이 없으면:
- 로그아웃 → 재로그인 시 이전 세션의 remainingTime 캐시(예: 2:46)가 UI에 표시
- Firestore 실제값(0)과 불일치 → 대화방 진입 후 로비 복귀 시 갑자기 0으로 변경
- 사용자 혼란 유발

---

## Phase 3 — 사후 검증

### 3-A: 코드 검증

```bash
flutter analyze lib/auth/social_auth_service.dart
dart format lib/auth/social_auth_service.dart
```

⚠️ `dart format`은 반드시 단일 파일만 대상 (한글 UTF-8 깨짐 방지)

### 3-B: 실기기 테스트 시나리오 (실장님 수동 테스트)

**시나리오 1 — 최초 카카오 가입:**
1. 앱 데이터 삭제 (또는 새 기기)
2. 카카오 로그인 → 로비 진입
3. Firebase Console → Authentication → 사용자 탭에서 UID 기록 (uid-X)
4. Firestore → `kakao_uid_map` 컬렉션에 문서가 생겼는지 확인
5. 대화 모드 진입 → 몇 마디 대화 → 히스토리 확인

**시나리오 2 — 재로그인:**
1. 앱에서 로그아웃
2. 앱 완전 종료 후 재시작
3. 카카오 로그인 → 로비 진입
4. Firebase Console에서 UID 확인 → uid-X와 동일해야 함
5. 히스토리에 시나리오 1의 대화가 남아있어야 함

**시나리오 2에서 uid가 다르면 Fix A가 적용되지 않은 것이므로 재확인 필요**

---

## Phase 4 — 롤백

```bash
git revert HEAD
```

---

## 참고: 스토어 구매 오류 ("항목을 찾을 수 없습니다")

이 오류는 카카오 UID 문제와 별개.
Google Play 결제 프로필 조직→개인 마이그레이션이 진행 중(마감 7/16)이라
상품이 비활성 상태일 수 있음. 마이그레이션 응답 수신 후 상품 활성화 상태 확인 필요.