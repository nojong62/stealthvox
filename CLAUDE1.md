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

# Phase A — 소셜 로그인 통합 (서버 + 의존성)

## 목표
카카오 · 구글 · 이메일 로그인을 **하나의 Firebase uid** 아래로 통합한다.
이 문서는 **서버 함수 + 의존성 + 셋업**까지만 다룬다. (클라이언트 UI/모달/Store 게이트/웰컴보너스 제거는 Phase B)

핵심 원칙: 카카오 로그인 시 **새 계정을 만들지 않고, 현재 익명 uid에 묶는다.** → 30초/1분 체험 데이터(익명 uid 아래 `chat_history`)가 그대로 보존된다.

전제(이미 충족):
- Blaze 플랜 사용 중 ✓ (외부 호출 가능)
- `google_sign_in` 이미 pubspec에 존재 ✓
- Cloud Functions 스타일: v1 (`functions.https.onCall` + `defineSecret`), Node 20

작업 디렉터리: 리포 루트(`F:\flutter_project\stealth_vox`). 함수 배포는 `firebase/` 하위에서.

> 이 Phase는 **순수 추가(additive)**다. 기존 동작을 바꾸지 않으므로 배포해도 현재 앱에 영향이 없다.

---

## 0. Savepoint

```bash
git add -A
git commit -m "savepoint: before Phase A social auth unify"
```

---

## 1. [Claude Code · 터미널] 의존성 + IAM 셋업

### 1-1. 카카오 SDK 추가 (pub이 최신 호환 버전 자동 해석)
```bash
flutter pub add kakao_flutter_sdk
```
> 버전을 수동으로 박지 말 것 — pub이 firebase_auth 5.6.0 등과 호환되는 버전을 해석한다.

### 1-2. createCustomToken용 IAM 권한 (한 번만)
`createCustomToken`은 서비스 계정의 `signBlob` 권한이 필요하다. gcloud가 설치돼 있으면:

```bash
gcloud services enable iamcredentials.googleapis.com iam.googleapis.com --project stealth-vox-3p3rq3

gcloud projects add-iam-policy-binding stealth-vox-3p3rq3 ^
  --member="serviceAccount:stealth-vox-3p3rq3@appspot.gserviceaccount.com" ^
  --role="roles/iam.serviceAccountTokenCreator"
```
> Windows cmd는 줄바꿈 `^`, PowerShell이면 백틱 `` ` ``, bash면 `\`로 바꿔서 실행.
> **gcloud 미설치 시 대안(수동):** Cloud Console → IAM → 주체 `stealth-vox-3p3rq3@appspot.gserviceaccount.com` → 역할 추가 → **Service Account Token Creator**.
> 첫 배포 후 호출에서 `auth/insufficient-permission`이 나면 이 단계가 누락된 것이니 다시 확인.

### 1-3. (Phase B 준비용 · 병행) 디버그 키해시 추출
카카오 앱 등록 때 붙여넣을 Android 디버그 키해시. 지금 뽑아두면 실장님이 카카오 콘솔에서 병행 등록 가능.
```bash
keytool -exportcert -alias androiddebugkey -keystore %USERPROFILE%\.android\debug.keystore -storepass android -keypass android | openssl sha1 -binary | openssl base64
```
> 출력된 한 줄(예: `Xo8WBi6jz...=`)을 실장님께 전달. (릴리즈 키해시는 출시 빌드 키스토어로 동일 방식 추출 — Phase B에서)

---

## 2. [Claude Code · 편집] `firebase/functions/index.js`에 `kakaoCustomAuth` 추가

### 2-1. 앵커 확인 (정확히 1이어야 함)
```bash
grep -n "after_seconds: afterSeconds," firebase/functions/index.js | wc -l   # 기대값: 1
grep -n "exports.kakaoCustomAuth" firebase/functions/index.js | wc -l        # 기대값: 0 (아직 없음)
```
두 값이 각각 1, 0이 아니면 **중단**하고 보고.

### 2-2. str_replace — 파일 끝(`logUsageSession`)의 return 블록 뒤에 함수 추가

**old_str** (파일 마지막 부분, 유일):
```js
  return {
    ok: true,
    before_seconds: beforeSeconds,
    after_seconds: afterSeconds,
  };
});
```

**new_str** (위 블록 + 아래 함수 이어붙임):
```js
  return {
    ok: true,
    before_seconds: beforeSeconds,
    after_seconds: afterSeconds,
  };
});

// ----------------------------------------------------------------------------
// kakaoCustomAuth
// Type:   HTTPS Callable (호출자는 익명 인증 상태여야 함)
// Input:  { kakaoAccessToken: string }
// Output: { token: string }   // 클라이언트가 signInWithCustomToken에 사용
//
// 통합 원칙:
//   1) 카카오 액세스 토큰을 kapi.kakao.com/v2/user/me로 검증 → kakaoId
//   2) kakao_uid_map/{kakaoId} 조회
//        - 있으면: 그 uid (복귀 카카오 유저)
//        - 없으면: 현재 익명 uid에 바인딩 + 매핑 저장 (체험 데이터 보존)
//   3) 해당 uid로 커스텀 토큰 발급 (provider: "kakaocorp.com")
// Node 20 전역 fetch 사용 → 추가 npm 의존성 없음.
// ----------------------------------------------------------------------------
exports.kakaoCustomAuth = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Request must be authenticated (anonymous ok)."
      );
    }
    const anonUid = context.auth.uid;

    const accessToken = data && data.kakaoAccessToken;
    if (!accessToken || typeof accessToken !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "kakaoAccessToken (string) is required."
      );
    }

    // 1. 카카오 토큰 검증 → kakaoId
    let kakaoId = null;
    try {
      const resp = await fetch("https://kapi.kakao.com/v2/user/me", {
        method: "GET",
        headers: { Authorization: "Bearer " + accessToken },
      });
      if (!resp.ok) {
        throw new functions.https.HttpsError(
          "unauthenticated",
          "Kakao token rejected (status " + resp.status + ")."
        );
      }
      const profile = await resp.json();
      kakaoId = profile && profile.id != null ? String(profile.id) : null;
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      throw new functions.https.HttpsError(
        "internal",
        "Kakao verification failed: " + String(e)
      );
    }
    if (!kakaoId) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "No Kakao id found in profile."
      );
    }

    // 2. 매핑 조회 → 기존 uid 또는 현재 익명 uid에 바인딩
    const firestore = admin.firestore();
    const mapRef = firestore.collection("kakao_uid_map").doc(kakaoId);

    const resolvedUid = await firestore.runTransaction(async (tx) => {
      const mapDoc = await tx.get(mapRef);
      if (mapDoc.exists && mapDoc.data().uid) {
        return mapDoc.data().uid; // 복귀 카카오 유저
      }
      tx.set(mapRef, {
        uid: anonUid,
        kakao_id: kakaoId,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return anonUid; // 최초 → 익명 uid 보존
    });

    // 3. 커스텀 토큰 발급
    const token = await admin
      .auth()
      .createCustomToken(resolvedUid, { provider: "kakaocorp.com" });

    functions.logger.info("kakaoCustomAuth", {
      anonUid: anonUid,
      resolvedUid: resolvedUid,
      kakaoIdPrefix: kakaoId.substring(0, 6),
      returning: resolvedUid !== anonUid,
    });

    return { token: token };
  });
```

### 2-3. 추가 검증
```bash
grep -n "exports.kakaoCustomAuth" firebase/functions/index.js | wc -l   # 기대값: 1
node -c firebase/functions/index.js && echo "SYNTAX OK"                  # 문법 오류 없어야 함
```

---

## 3. [Claude Code · 터미널] 배포

```bash
cd firebase
firebase deploy --only functions:functions:kakaoCustomAuth
cd ..
```
> 멀티 코드베이스라 단일 함수 배포는 `functions:functions:함수명` (codebase 이름 반복)이 맞다.
> 배포 로그에 `kakaoCustomAuth(us-central1)` 생성/업데이트가 보이면 성공.

---

## 4. 검증

1. **함수 생성 확인**
   ```bash
   firebase functions:list | findstr kakaoCustomAuth
   ```
2. **권한 확인** — 다음 단계(Phase B)에서 첫 호출 시 `auth/insufficient-permission`이 안 나야 함. 나오면 1-2 재실행.
3. **매핑 컬렉션** — 최초 카카오 로그인이 일어나면 Firestore에 `kakao_uid_map/{kakaoId}` 문서가 생기고 `uid`가 그때의 익명 uid와 같아야 함. (Phase B 통합 테스트 시 확인)

---

## 5. (선택 · 권장) Firestore 규칙 하드닝
`kakao_uid_map`은 함수(Admin SDK)만 쓰면 되므로 클라이언트 직접 쓰기를 막는다. `firestore.rules`에 추가:
```
match /kakao_uid_map/{kakaoId} {
  allow read, write: if false;   // Admin SDK만 (규칙 우회)
}
```
적용: `firebase deploy --only firestore:rules` (다른 규칙 변경과 충돌 없는지 확인 후).

---

## 6. 롤백
```bash
# 코드 되돌리기
git revert HEAD            # 또는 git reset --hard <savepoint 커밋>
# 배포된 함수 제거(원하면)
firebase functions:delete kakaoCustomAuth --region us-central1
```

---

## Phase B 선행 준비 (실장님 · 웹 · 병행 가능)
Phase A 배포와 무관하게 미리 해두면 Phase B가 빨라짐:
- **카카오 디벨로퍼스**(developers.kakao.com): 앱 생성 → 네이티브 앱키 복사 → 플랫폼에 Android 등록 + **디버그 키해시(1-3 출력값) 붙여넣기** → 카카오 로그인 활성화. (이메일 동의항목은 불필요 — 우리는 익명 uid에 바인딩하므로 이메일을 안 씀)
- **Firebase 콘솔** → Authentication → Sign-in method → **Google 사용 설정 ON** + 앱 SHA-1 등록.

> 이 둘은 Phase A(서버)에는 영향 없음. Phase B(클라이언트 카카오/구글 버튼 wiring) 때 필요.

## Phase B에 필요한 파일
클라이언트 wiring 지시문서를 쓰려면 **`main.dart`**(KakaoSdk.init·라우트 확인용)만 추가로 주시면 됨.