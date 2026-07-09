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

# usage log 식별자 보강 — `billing_ticker` sessionDocId/roomId 연결 지시서

---

## Phase S: Savepoint

```bash
cd F:\flutter_project\stealth_vox
git status
git add -A
git commit -m "savepoint: before billing_ticker session identifier linking"
git checkout -b fix/billing-ticker-session-identifiers
```

---

## Phase 0: 진단 (Diagnostics / Grep)

```bash
# 1. billing_ticker 정의 및 사용처 전체 확인
grep -rn "billing_ticker\|billingTicker" lib/ --include="*.dart"

# 2. billing_ticker가 기록하는 필드 구조 확인 (현재 sessionDocId/roomId 누락 여부)
grep -n "class BillingTicker\|sessionDocId\|roomId" lib/【치환필요: billing_ticker 파일 경로】

# 3. 각 모드 파일에서 BillingTicker를 호출/초기화하는 지점 전부 확인
grep -rln "BillingTicker(" lib/ --include="*.dart"

# 4. 각 모드 파일에서 sessionDocId/roomId가 이미 변수로 존재하는지 확인
grep -rn "sessionDocId\|roomId" lib/custom_code/widgets/routine_mode_*.dart

# 5. billing_ticker가 최종적으로 Firestore/함수 어디에 로그를 남기는지 확인
grep -n "usage_log\|usageLog\|logUsageSession\|FirebaseFirestore.*add\|FirebaseFirestore.*set" lib/【치환필요: billing_ticker 파일 경로】
```

**Codex는 아래 항목을 정리해서 보고할 것:**
1. `billing_ticker` 클래스/함수의 정확한 파일 경로 + 생성자 시그니처 (현재 파라미터 목록)
2. `BillingTicker(...)` 호출부가 있는 **모드 파일 전체 목록** (Anyone, Routine, 기타 모드별로 몇 개인지)
3. 각 모드 파일 내에서 `sessionDocId`(대화방/세션 문서 ID)와 `roomId`가 이미 존재하는 변수명인지, 아니면 새로 가져와야 하는지 — 파일별로 다를 수 있으므로 각각 확인
4. 최종적으로 usage log가 저장되는 Firestore 컬렉션명 및 현재 문서 구조 (지금 `sessionDocId`/`roomId` 필드가 비어있는지, 아예 없는지)

---

## Phase 1: 앵커 검증

Phase 0 결과 기반으로 아래를 확정:

1. **BillingTicker 생성자 수정 지점** — `sessionDocId`, `roomId`를 선택적(nullable) 파라미터로 추가할지, 필수 파라미터로 바꿀지 결정. 기존 호출부가 많으면(모드 파일 여러 개) **선택적 파라미터로 추가**해서 한 파일씩 순차 연결하는 게 안전합니다(한 번에 전부 필수로 바꾸면 컴파일 에러가 모드 파일 개수만큼 터짐).
2. **모드 파일별 연결 지점** — 각 모드 파일에서 `BillingTicker(...)` 호출하는 정확한 줄

⚠️ **확인 필요 (실장님 판단):** Phase 0-2에서 모드 파일이 몇 개나 나오는지에 따라 이번에 전부 다 연결할지, 우선순위 모드(Anyone 등 트래픽 많은 것)부터 할지 정할 수 있습니다. Phase 0 보고 받으시면 범위 다시 정하는 게 좋습니다.

---

## Phase 2: 편집 (파일별 하단→상단)

### 2-1. BillingTicker 클래스에 필드 추가

```
파일: lib/【치환필요: billing_ticker 파일 경로】

생성자에 다음 파라미터 추가 (nullable, 기본값 null):
  String? sessionDocId,
  String? roomId,

Firestore/usage_log 기록 로직 부분에서 이 값들을 함께 저장하도록 수정.
null인 경우에도 에러 없이 필드 자체를 생략하거나 null로 기록되도록 처리
(기존 호출부가 아직 값을 안 넘기는 동안 깨지지 않게 하기 위함).
```

### 2-2. 모드 파일별 연결 (Phase 0-2/3 결과 목록 순서대로 반복)

```
파일: lib/custom_code/widgets/【치환필요: 각 모드 파일명】
위치: 【치환필요: BillingTicker(...) 호출 줄】

BillingTicker(...) 호출부에 아래 두 인자 추가:
  sessionDocId: 【치환필요: 해당 파일 내 세션 문서 ID 변수명】,
  roomId: 【치환필요: 해당 파일 내 room ID 변수명】,

만약 해당 변수가 파일 내에 없다면, 세션 생성/입장 시점에서 
받아온 ID를 상위에서 전달받도록 필드 추가 후 연결.
(이 경우는 파일별로 구조가 다를 수 있어 Codex가 자체 판단하지 말고 
해당 파일명과 함께 실장님께 보고 후 진행)
```

> 모드 파일이 여러 개면 **한 파일 수정 → grep 검증 → 다음 파일** 순서로 진행하도록 Codex에게 명시해 주세요. 한 번에 여러 파일을 몰아서 고치면 어디서 깨졌는지 추적이 어렵습니다.

---

## Phase 3: Grep 검증 (파일별로 매 수정 후 실행)

```bash
grep -n "sessionDocId\|roomId" lib/custom_code/widgets/【수정한 파일명】
```

기대 결과: `BillingTicker(...)` 호출부에 두 인자가 정확히 연결되어 있는지 확인.

---

## Phase 4: 포맷 및 정적 분석

```bash
dart format lib/【치환필요: billing_ticker 경로】
dart format lib/custom_code/widgets/【수정한 모든 모드 파일】
flutter analyze
```

변경 파일 기준으로 새 error 없는지 확인 (기존 FlutterFlow warning 655건은 무시).

---

## Phase 5: 커밋

```bash
git add -A
git commit -m "fix: link sessionDocId/roomId to billing_ticker usage logs"
git push origin fix/billing-ticker-session-identifiers
```

(전체 모드 파일 다 연결 안 하고 일부만 했다면 main 머지는 나머지 파일까지 마친 뒤 진행 권장)

---

## 롤백 절차

```bash
git checkout main
git branch -D fix/billing-ticker-session-identifiers
```

---

Phase 0 보고 받으시면, 모드 파일이 몇 개나 나오는지에 따라 Phase 2를 파일별로 쪼개서 다시 드릴 수 있습니다. 필요하시면 알려주세요.