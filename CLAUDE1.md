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

# 지시문: 보호자 동의 링크 보안 강화 — uid 링크 제거 + 1회성 토큰 방식으로 교체

## 목표

현재 StealthVox Firebase Functions에 이미 보호자 동의 이메일 함수가 들어가 있다.

현재 문제:
- `sendParentConsentEmail`이 이메일 링크를 만들 때 `confirmParentConsent?uid=<uid>` 형식으로 uid를 직접 노출한다.
- `confirmParentConsent`는 query의 uid만 있으면 `users/{uid}.parentConsentPending = false`로 바꾼다.
- 이 방식은 링크 위조가 가능하므로 보호자 동의 처리로는 부적절하다.

이번 작업 목표:
1. uid 직접 링크 방식을 제거한다.
2. 32바이트 이상 랜덤 토큰 기반 동의 링크로 교체한다.
3. `parent_consent_tokens/{token}` 컬렉션을 사용한다.
4. 보호자가 링크를 클릭하면 토큰 검증 후 서버에서만 `parentConsentPending: false`로 업데이트한다.
5. 기존 앱 호출부 `sendParentConsentEmail(parentEmail)`은 최대한 그대로 유지한다.

---

## 현재 프로젝트 구조

- Functions 파일: `functions/index.js`
- Runtime: Node.js 20
- Module style: CommonJS
- Firebase Functions SDK: firebase-functions v4.x
- Firebase Admin SDK: firebase-admin v11.x
- Region: 기존 함수들과 동일하게 `us-central1`
- `firebase.json` functions source: `functions`
- Email Extension은 이미 설치 완료
- Firestore `mail` 컬렉션 테스트 발송 성공 확인됨
- `mail` 문서 구조는 아래와 같아야 함:

mail/{autoId}
- to: array
- message: map
  - subject: string
  - html 또는 text: string

---

## 반드시 수정할 함수

현재 `functions/index.js` 맨 아래에 있는 두 함수를 교체/강화한다.

1. `sendParentConsentEmail`
2. `confirmParentConsent`

현재 함수명은 앱에서 이미 호출 중일 수 있으므로 함수명은 유지한다.

---

## 중요한 기존 앱 연동

앱 쪽 `intro_master.dart`는 14세 미만일 때 아래 흐름을 이미 수행한다.

1. `users/{uid}`에 저장:
   - birthYear
   - parentEmail
   - parentConsentPending: true

2. Firebase Callable:
   - region: us-central1
   - function name: sendParentConsentEmail
   - parameter: { parentEmail: parentEmail }

따라서 이번 작업에서는 앱 쪽 함수명과 파라미터를 바꾸지 말 것.

---

## 새 Firestore 컬렉션

### parent_consent_tokens/{token}

문서 ID 자체를 랜덤 토큰으로 사용한다.

필드:
- uid: string
- parentEmail: string
- status: string
  - pending
  - approved
  - expired
  - revoked
- createdAt: server timestamp
- expiresAt: timestamp
- approvedAt: timestamp | null
- consumedCount: number
- approvedIpHash: string | null
- userAgent: string | null
- mailDocId: string | null

토큰 요구:
- Node.js crypto 사용
- `crypto.randomBytes(32).toString("hex")` 권장
- query에는 token만 넣는다.
- uid는 링크에 넣지 않는다.

---

## sendParentConsentEmail 요구사항

### 타입

기존과 동일:
- `functions.region("us-central1").https.onCall`

### 입력

기존과 동일:
- `{ parentEmail: string }`

### 인증

- context.auth 필수
- uid는 `context.auth.uid`에서만 가져온다.

### 검증

1. `parentEmail`이 string인지 확인
2. 간단한 이메일 형식 검증 추가
3. `users/{uid}` 문서를 조회한다.
4. 사용자의 `parentConsentPending`이 true인지 확인한다.
   - 이미 false라면 `{ sent: false, alreadyApproved: true }` 반환
5. user 문서의 `parentEmail`과 callable 입력 parentEmail이 다르면:
   - user 문서에 parentEmail이 없으면 merge 저장 가능
   - 이미 다른 parentEmail이 있으면 보안상 `permission-denied` 또는 `failed-precondition` 에러 반환
   - 단, 기존 운영 흐름을 깨지 않도록 판단 근거를 로그로 남긴다.

### 토큰 생성

1. 기존 pending token 재사용 여부는 다음 기준으로 처리한다.
   - 같은 uid, same parentEmail, status == pending, expiresAt > now 인 토큰이 이미 있으면 재사용 가능
   - 구현이 복잡하면 매번 새 토큰 생성해도 됨
   - 단, 새 토큰 생성 시 같은 uid의 기존 pending token은 `revoked`로 바꿔도 됨
2. token 생성:
   - `const crypto = require("crypto");` 추가
   - `const token = crypto.randomBytes(32).toString("hex");`
3. 만료 시간:
   - 기본 7일 후
   - `expiresAt = Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000)`

### 동의 URL

기존 uid URL 제거.

새 URL:

`https://us-central1-${projectId}.cloudfunctions.net/confirmParentConsent?token=${encodeURIComponent(token)}`

projectId는 기존 코드 방식 유지:
- `process.env.GCLOUD_PROJECT || "stealth-vox-3p3rq3"`

### token 문서 생성

`parent_consent_tokens/{token}` 문서를 생성한다.

필수 필드:
- uid
- parentEmail
- status: "pending"
- createdAt: serverTimestamp
- expiresAt
- approvedAt: null
- consumedCount: 0
- approvedIpHash: null
- userAgent: null

### mail 문서 생성

기존 Email Extension 구조 유지.

주의:
- `to`는 반드시 array로 저장한다.
- 현재 테스트 성공 구조와 동일하게 `to: [parentEmail]` 사용.
- `message.html` 사용 가능.
- `createdAt` 추가 유지 가능.

메일 제목:
`StealthVox - 자녀 가입 동의 요청`

메일 본문 필수 포함:
- StealthVox 보호자 동의 안내
- 만 14세 미만 사용자는 보호자 동의가 필요하다는 안내
- “동의합니다” 버튼
- 동의 URL 텍스트 대체 링크
- 본인이 요청하지 않았다면 무시하라는 문구
- 링크는 7일 후 만료된다는 문구

메일 문서 생성 후 token 문서에 `mailDocId`를 merge 업데이트한다.

### 반환값

성공 시:
- `{ sent: true }`

가능하면 디버그용으로 token 자체는 반환하지 말 것.
로그에도 전체 token을 찍지 말고 앞 6~8자만 찍을 것.

---

## confirmParentConsent 요구사항

### 타입

기존과 동일:
- `functions.region("us-central1").https.onRequest`

### 입력

GET:
`?token=<TOKEN>`

uid query는 더 이상 받지 않는다.
기존 `?uid=` 방식은 거부해야 한다.

### 처리 순서

1. GET 외 요청은 405 HTML 반환
2. token query 확인
3. token이 없으면 “유효하지 않은 동의 링크입니다” HTML 반환
4. `parent_consent_tokens/{token}` 문서 조회
5. 문서가 없으면 “유효하지 않은 동의 링크입니다” HTML 반환
6. expiresAt 확인
   - 현재 시간보다 과거이면 token status를 `expired`로 update
   - “동의 링크가 만료되었습니다. 앱에서 다시 요청해 주세요.” HTML 반환
7. status가 `approved`이면
   - “이미 동의가 완료되었습니다.” HTML 반환
8. status가 `pending`이 아니면
   - “사용할 수 없는 동의 링크입니다.” HTML 반환
9. token 문서의 uid로 `users/{uid}` 조회
10. user 문서가 없으면
   - “사용자 정보를 찾을 수 없습니다.” HTML 반환
11. Firestore transaction으로 아래를 함께 처리

users/{uid}:
- parentConsentPending: false
- parentConsentGrantedAt: serverTimestamp
- parentConsentMethod: "email_link"
- parentConsentEmail: parentEmail
- updatedAt: serverTimestamp

parent_consent_tokens/{token}:
- status: "approved"
- approvedAt: serverTimestamp
- consumedCount: increment(1)
- userAgent: req.headers["user-agent"] || null
- approvedIpHash: IP 원문 저장 금지. 가능하면 sha256 hash 저장. 어렵다면 null 유지.

12. 성공 HTML 반환

---

## HTML 응답 요구사항

JSON을 반환하지 말고 모바일 브라우저용 HTML을 반환한다.

공통 스타일:
- UTF-8
- viewport meta
- 가운데 카드
- StealthVox 브랜드명
- 검은/다크 계열 또는 현재 메일 버튼 색상과 어울리는 정갈한 스타일
- 외부 이미지 사용 금지

페이지 종류:
1. 성공:
   - 제목: 보호자 동의가 완료되었습니다
   - 본문: StealthVox 자녀 계정 이용 동의가 완료되었습니다. 이제 앱에서 정상 이용할 수 있습니다.
2. 이미 완료:
   - 제목: 이미 동의가 완료되었습니다
3. 만료:
   - 제목: 동의 링크가 만료되었습니다
   - 본문: 앱에서 보호자 동의 메일을 다시 요청해 주세요.
4. 잘못된 링크:
   - 제목: 유효하지 않은 동의 링크입니다
5. 서버 오류:
   - 제목: 일시적인 오류가 발생했습니다

중복 HTML을 줄이기 위해 `renderConsentPage(title, message, type)` 같은 helper 함수를 `index.js` 안에 추가해도 된다.

---

## 추가 보안 요구

1. `confirmParentConsent`에서 uid query를 절대 신뢰하지 말 것.
2. token 전체를 로그에 찍지 말 것.
3. parentEmail 전체 로그도 가능하면 최소화하라.
4. 클라이언트가 `parentConsentPending`을 직접 false로 만들 수 없도록 Firestore rules 확인이 필요하다.
5. 이번 작업에서 rules 파일이 있으면 확인만 하고, 필요 변경안은 별도 보고하라. 실제 rules 변경은 최소화한다.

---

## 배포 전 확인

아래 명령이 가능해야 한다.

- `cd functions`
- `npm install` 필요 여부 확인
- `npm run lint`가 현재 프로젝트에서 실패할 수 있으면 실패 원인을 보고하되, 이번 변경과 무관한 기존 lint는 구분하라.
- Firebase Functions deploy 명령 제안:

`firebase -P stealth-vox-3p3rq3 deploy --only functions:sendParentConsentEmail,functions:confirmParentConsent`

주의:
firebase.json은 functions codebase 구조를 쓰고 있으므로, 실제 배포 명령에서 codebase 지정이 필요한지 현재 CLI 기준으로 확인하고 보고하라.

---

## 테스트 절차

### 테스트 1: 보호자 이메일 발송

1. 테스트 계정으로 로그인
2. users/{uid}에 아래 값 확인:
   - parentEmail
   - parentConsentPending: true
3. 앱 또는 Functions shell에서 `sendParentConsentEmail({ parentEmail })` 호출
4. Firestore 확인:
   - `parent_consent_tokens` 문서 생성
   - `mail` 문서 생성
5. Gmail 수신 확인

### 테스트 2: 링크 클릭

1. 이메일의 동의 링크 클릭
2. HTML 성공 페이지 확인
3. Firestore 확인:
   - users/{uid}.parentConsentPending == false
   - parentConsentGrantedAt 존재
   - parentConsentMethod == "email_link"
   - parent_consent_tokens/{token}.status == "approved"

### 테스트 3: 같은 링크 재클릭

1. 같은 링크 다시 클릭
2. “이미 동의가 완료되었습니다” 페이지 표시
3. Firestore 값이 깨지지 않아야 함

### 테스트 4: 잘못된 token

1. URL token 일부를 바꿔 접속
2. “유효하지 않은 동의 링크입니다” 페이지 표시

### 테스트 5: 만료 token

1. expiresAt을 과거로 바꾼 테스트 token 생성
2. 링크 클릭
3. “동의 링크가 만료되었습니다” 페이지 표시
4. token status가 expired로 변경되는지 확인

---

## 반드시 보고할 것

작업 완료 후 아래를 보고하라.

1. 수정한 파일 목록
2. 삭제/교체한 기존 위험 로직 설명
3. 새 token 컬렉션 구조
4. 배포 명령어
5. 테스트 방법
6. 앱 쪽 변경 필요 여부
7. Firestore rules에서 추가로 막아야 할 필드 목록

---

## 완료 기준

아래가 모두 만족되면 완료다.

1. 보호자 이메일 링크에 uid가 노출되지 않는다.
2. 링크에는 token만 포함된다.
3. token 검증 성공 시에만 users/{uid}.parentConsentPending이 false가 된다.
4. 이미 승인된 링크 재클릭이 안전하게 처리된다.
5. 만료/잘못된 링크가 한국어 HTML 페이지로 표시된다.
6. 기존 앱의 `sendParentConsentEmail(parentEmail)` 호출 방식은 깨지지 않는다.
7. `mail` Extension 구조는 기존 성공 구조를 그대로 사용한다.