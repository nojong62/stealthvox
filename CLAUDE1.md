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

# 지시문: kakaoCustomAuth 역방향 계정 통합 (Google → 로그아웃 → 카카오)

## 배경

`linkOrCreateAccount` CF 덕분에 **카카오 → Google** 방향은 이메일 기반 병합이 된다.
그러나 **Google 먼저 가입 → 로그아웃 → 카카오 로그인** 시,
`kakaoCustomAuth`가 기존 Google 계정을 찾지 못하고 별개 UID를 생성할 수 있다.

이 지시문은 Codex가 `kakaoCustomAuth` 코드를 살펴보고,
이메일 기반 기존 유저 탐색이 이미 있는지 확인한 뒤, 없으면 보강한다.

## 불변 규칙

- 코드 수정 전 반드시 Phase 0 진단 완료 후 결과를 사용자에게 보고하고 승인받을 것
- Firebase CLI는 `firebase/` 서브디렉토리에서 실행
- 멀티 codebase 배포: `firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:[함수명]`

---

## Phase S: Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before kakaoCustomAuth reverse-linking fix"
```

---

## Phase 0: 진단 (결과를 사용자에게 보고 후 승인받고 진행)

### 0-1. kakaoCustomAuth 전체 흐름 확인

```bash
cd firebase/functions
grep -n -A 80 "exports.kakaoCustomAuth" index.js | head -120
```

아래 항목을 확인하여 보고:

1. **kakaoEmail 추출:** 카카오 API에서 이메일을 가져오는 코드가 있는가?
2. **kakao_uid_map 조회:** `kakao_uid_map/{kakaoId}` 문서를 확인하는가?
3. **fast path:** `authEmailSet: true`일 때 바로 custom token 발급하고 끝나는가?
4. **getUserByEmail:** `kakao_uid_map`에 없을 때, `kakaoEmail`로 `admin.auth().getUserByEmail()`을 호출하여 기존 유저를 찾는 로직이 있는가?
5. **기존 유저 발견 시:** 찾은 유저의 UID로 custom token을 발급하고 `kakao_uid_map`에 매핑을 저장하는가?

### 0-2. signInWithKakao 클라이언트 흐름 확인

```bash
grep -n -A 30 "signInWithKakao" lib/auth/social_auth_service.dart | head -50
```

확인할 항목:
- 카카오 로그인 후 `kakaoCustomAuth` CF만 호출하는지, 아니면 `linkOrCreateAccount`도 경유하는지

### 진단 보고 형식

```
=== Phase 0 진단 결과 ===

[0-1] kakaoCustomAuth 흐름:
  - kakaoEmail 추출: 있음/없음
  - kakao_uid_map 조회: 있음/없음
  - fast path: 있음/없음
  - getUserByEmail (이메일 기반 기존 유저 탐색): 있음/없음
  - 기존 유저 발견 시 UID 재사용: 있음/없음

[0-2] signInWithKakao 흐름:
  - kakaoCustomAuth만 호출 / linkOrCreateAccount도 경유

=== 필요한 수정 ===
- kakaoCustomAuth에 getUserByEmail 추가: 필요/불필요
- signInWithKakao에서 linkOrCreateAccount 경유 추가: 필요/불필요
```

**이 보고를 사용자에게 보여주고 승인을 받은 후 Phase 1로 진행한다.**

---

## Phase 1: 수정 (진단 결과에 따라 해당하는 것만 적용)

### 시나리오 A: kakaoCustomAuth에 getUserByEmail이 없는 경우

`kakao_uid_map`에 매핑이 없을 때 (= 이 카카오 계정으로 처음 로그인),
`kakaoEmail`이 있으면 `getUserByEmail`로 기존 Firebase 유저를 찾고,
발견되면 해당 UID를 재사용하여 계정을 통합한다.

**수정 위치:** `kakaoCustomAuth` 함수 내부에서 `kakao_uid_map` 조회 후
"매핑 없음 → 신규 유저 생성" 분기 **직전**에 아래 로직을 삽입:

```javascript
// ── 이메일 기반 기존 계정 탐색 (Google 등 다른 provider로 먼저 가입한 경우) ──
if (!resolvedUid && kakaoEmail) {
  try {
    const existingUser = await admin.auth().getUserByEmail(kakaoEmail);
    if (existingUser) {
      resolvedUid = existingUser.uid;
      functions.logger.info(
        `[kakaoCustomAuth] existing account found by email: ${kakaoEmail} → ${resolvedUid}`
      );
      // kakao_uid_map에 매핑 저장 (다음 로그인부터 fast path)
      await admin.firestore().collection("kakao_uid_map").doc(String(kakaoId)).set({
        firebaseUid: resolvedUid,
        kakaoEmail: kakaoEmail,
        authEmailSet: true,
        linkedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  } catch (emailErr) {
    if (emailErr.code === "auth/user-not-found") {
      functions.logger.info(`[kakaoCustomAuth] no existing user for email: ${kakaoEmail}`);
    } else {
      functions.logger.error(`[kakaoCustomAuth] getUserByEmail error:`, emailErr);
    }
  }
}
```

**삽입 위치를 정확히 찾기 위해:**

```bash
# kakao_uid_map 조회 후 resolvedUid가 null인 분기를 찾는다
grep -n "resolvedUid" index.js
# 또는
grep -n "createUser\|createCustomToken" index.js
# → "resolvedUid가 없으면 새 유저 생성" 직전이 삽입 위치
```

**주의:** 코드 삽입 시 기존 변수명(`resolvedUid`, `kakaoId`, `kakaoEmail`)과
정확히 일치하는지 확인. Phase 0에서 파악한 실제 변수명을 사용할 것.

### 시나리오 B: 이미 getUserByEmail이 있는 경우

그럼 문제는 다른 곳에 있다. 아래를 추가 진단:

```bash
# getUserByEmail 호출이 실제로 실행되는 경로인지 확인
# fast path에서 일찍 return 하여 getUserByEmail에 도달하지 못하는지?
grep -n "return\|authEmailSet" index.js | head -30
```

fast path가 `kakao_uid_map` 문서가 존재하기만 하면 바로 return하는 구조라면,
이전에 카카오 로그인한 적이 있는 경우 `getUserByEmail`에 도달하지 못한다.
이 경우 사용자에게 보고하고 방향을 논의할 것.

---

## Phase 2: 검증

```bash
cd firebase/functions

# 문법 검증
node -c index.js
# 기대: no syntax error

# getUserByEmail 호출 횟수
grep -n "getUserByEmail" index.js
# 기대: kakaoCustomAuth 내 1줄 + linkOrCreateAccount 내 1줄 = 2줄 이상
```

---

## Phase 3: 배포

```bash
cd firebase
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:kakaoCustomAuth
```

배포 성공 여부를 보고.

---

## Phase 4: 커밋

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "fix: kakaoCustomAuth email-based account linking for reverse direction"
git push origin main
```

---

## Phase 5: 롤백 (문제 발생 시)

```bash
git revert HEAD --no-edit
git push origin main
cd firebase
firebase deploy --project stealth-vox-3p3rq3 --only functions:functions:kakaoCustomAuth
```