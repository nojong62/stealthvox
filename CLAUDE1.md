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

# 부모 동의 이메일 발송 — Codex 지시서 (확장 설치 완료 반영)

## Phase S: Savepoint

```bash
cd F:\flutter_project\stealth_vox
git status
git add -A
git commit -m "savepoint: before parental consent email trigger function"
git checkout -b feat/parental-consent-email
```

---

## Phase 0: 진단

```bash
# 1. 부모 동의 Firestore 저장 로직 위치 확인
grep -rn "parental\|parent_consent\|parentConsent" lib/ --include="*.dart"

# 2. 부모 이메일 필드명 확인
grep -rn "parentEmail\|parent_email\|guardianEmail" lib/ --include="*.dart"

# 3. 저장 컬렉션 확인
grep -rn "collection(['\"].*consent" lib/ --include="*.dart"

# 4. 기존 mail 확장 사용 사례 있는지 확인 (참고용 패턴)
grep -rn "collection(['\"]mail['\"]" firebase/functions/*.js lib/ 2>/dev/null

# 5. 만 14세 미만 판별 → 부모 동의 플로우 분기 로직 확인
grep -rn "birthYear\|만.*14세\|isMinor" lib/ --include="*.dart"
```

**Codex는 아래 항목을 보고할 것:**
1. 부모 동의 정보 저장 컬렉션명 + 문서 구조 (부모 이메일 필드명 특정)
2. 이 저장이 일어나는 정확한 파일 + 함수
3. 자녀 닉네임/이름 필드명 (템플릿에 넣을 항목)

---

## Phase 1: 앵커 검증

Phase 0 결과 기반으로, 동의 컬렉션의 `onCreate`를 감지하는 Cloud Function 추가 위치(`firebase/functions/index.js` 최하단)를 확정.

---

## Phase 2: 실행

### 2-1. ~~확장 설치~~ → 완료됨, 건너뜀

확인된 기존 설정:
- Email documents collection: `mail`
- Default FROM: `StealthVox <nisiekorea@gmail.com>`
- Authentication: UsernamePassword (SMTP URI 설정 완료)

### 2-2. 이메일 템플릿 문서 생성 (Firestore `mail_templates` 컬렉션)

```
Firestore 콘솔에서 mail_templates/parental_consent 문서 생성:

{
  subject: "[StealthVox] 자녀 회원가입 부모 동의 요청",
  html: "<본문: 자녀 닉네임, 서비스 소개 1줄, 안내 문구>"
}
```

> 문구 초안 필요하시면 별도로 작성해 드리겠습니다.

### 2-3. 트리거 Cloud Function 추가

```
파일: firebase/functions/index.js
위치: 파일 최하단

【치환필요: Phase 0에서 확인된 정확한 컬렉션명】 컬렉션에 onCreate 트리거 추가:

- 새로 생성된 동의 문서에서 부모 이메일 필드(【치환필요: 정확한 필드명】) 추출
- mail 컬렉션에 아래 구조로 문서 add():
  {
    to: [부모이메일],
    template: {
      name: "parental_consent",
      data: { childNickname: 【필드명】 }
    }
  }
- 에러 핸들링: 필드 없거나 형식 이상 시 logger.error 후 종료 (throw 금지)
```

---

## Phase 3: Grep 검증

```bash
grep -n "onCreate\|mail_templates" firebase/functions/index.js
```

---

## Phase 4: 배포 및 실측 테스트

```bash
cd firebase
firebase deploy --project stealth-vox-3p3rq3 --only functions:【신규함수명】
```

배포 후 동의 컬렉션에 테스트 문서 수동 추가 → `mail` 컬렉션에 문서 생성 확인 → 실제 메일함 도착 확인.

---

## Phase 5: 커밋

```bash
git add -A
git commit -m "feat: trigger parental consent email on Firestore document creation"
git push origin feat/parental-consent-email
```

(main 머지는 실제 발송 테스트 확인 후 진행 권장)

---

## 롤백 절차

```bash
git checkout main
git branch -D feat/parental-consent-email
```

---

Phase 0 진단 결과 나오면 필드명 확정해서 Phase 2-3 마무리해 드리겠습니다.