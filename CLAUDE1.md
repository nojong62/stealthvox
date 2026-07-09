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

# Node.js 20 → 22 런타임 업그레이드 지시서

---

**먼저 짚어드릴 점:** 지원 종료가 10월 30일이라 아직 여유가 있어 보이지만, 실제로는 **미리 해두는 게 맞는 이유**가 있습니다 — Firebase Functions는 런타임 종료일이 지나면 자동으로 강제 마이그레이션되거나 배포가 막힐 수 있어서, 트래픽 있는 상태에서 급하게 하는 것보다 지금처럼 여유 있을 때 검증하며 넘어가는 게 안전합니다. Node 20 → **Node 22**(현재 Firebase가 지원하는 최신 LTS)로 바로 가는 걸 권장드립니다.

---

## Phase S: Savepoint

```bash
cd F:\flutter_project\stealth_vox
git status
git add -A
git commit -m "savepoint: before Node.js 20 to 22 runtime upgrade"
git checkout -b chore/nodejs-22-upgrade
```

---

## Phase 0: 진단 (Diagnostics / Grep)

```bash
# 1. 현재 Functions 런타임 버전 명시 위치 확인
cat firebase/functions/package.json | grep -A 2 "\"engines\""

# 2. firebase.json에 런타임 관련 설정 있는지 확인
cat firebase/firebase.json | grep -i "runtime\|nodejs"

# 3. 현재 로컬 Node 버전 확인 (개발 환경과 배포 환경 버전 불일치 여부 체크)
node --version

# 4. firebase-functions, firebase-admin SDK 버전 확인 (Node 22 호환성 체크용)
cat firebase/functions/package.json | grep -A 5 "\"dependencies\""

# 5. 현재 배포된 함수들의 실제 런타임 확인
firebase functions:list --project stealth-vox-3p3rq3
```

**Codex는 아래 항목을 정리해서 보고할 것:**
1. `package.json`의 `engines.node` 현재 값 (예: `"20"`)
2. `firebase-functions`, `firebase-admin` SDK 현재 버전 (Node 22와 호환되는 최소 버전인지 확인 필요 — `firebase-functions`는 4.x대는 Node 22 미지원일 수 있어 5.x 이상 필요할 가능성 있음)
3. 로컬 개발 환경 Node 버전이 22 이상인지 (아니라면 로컬 Node 버전도 업그레이드 필요 — nvm 사용 권장)
4. 함수 개수 및 이름 목록 (배포 시 한 번에 몇 개나 마이그레이션되는지 파악용)

---

## Phase 1: 앵커 검증

⚠️ **중요 확인 필요 (실장님 판단):** Phase 0-2에서 `firebase-functions` SDK 버전이 낮게(예: 4.9.0) 나올 가능성이 높습니다. 이전 대화에서 이미 "firebase-functions SDK 업그레이드"가 별도 기술부채 항목으로 남아있었는데, **Node 22로 올리려면 SDK 업그레이드가 선행되어야 할 수도 있습니다.** 즉 이번 작업이 사실상 두 항목을 묶어서 처리하게 될 가능성이 있다는 뜻입니다.

Phase 0 결과 보고 받으시면, SDK 버전이 Node 22와 호환 안 되는 걸로 나올 경우 이 지시서에 SDK 업그레이드 단계를 추가해서 다시 드리겠습니다. 우선 아래는 **SDK가 이미 호환된다는 전제**로 작성했습니다.

---

## Phase 2: 편집

### 2-1. package.json 런타임 버전 변경

```
파일: firebase/functions/package.json
위치: "engines" 필드

"engines": { "node": "20" } 를
"engines": { "node": "22" } 로 변경
```

### 2-2. 로컬 Node 버전 확인 및 전환 (필요시)

```
로컬 Node 버전이 22 미만이면 nvm으로 전환 필요:

nvm install 22
nvm use 22
node --version   # v22.x.x 확인

nvm 미설치 상태라면 이 단계는 Codex가 직접 하지 말고 
실장님께 "nvm 설치 필요" 보고 후 대기.
```

### 2-3. 의존성 재설치 및 로컬 빌드 검증

```
cd firebase/functions
rm -rf node_modules package-lock.json
npm install
node --check index.js
```

---

## Phase 3: Grep 검증

```bash
grep -A 2 "\"engines\"" firebase/functions/package.json
```

기대 결과: `"node": "22"` 확인.

---

## Phase 4: 배포 (단계적 진행 — 중요)

⚠️ **전체 함수를 한 번에 배포하지 말 것.** 먼저 트래픽 적은 함수 1개로 테스트 배포한 뒤 문제 없으면 전체 배포하는 순서로 진행합니다.

```bash
# 1단계: 테스트 함수 1개만 배포 (예: 최근 만든 queueParentConsentEmailOnUserWrite)
firebase deploy --project stealth-vox-3p3rq3 --only functions:queueParentConsentEmailOnUserWrite

# 배포 성공 + 로그 정상 확인 후:
firebase functions:log --project stealth-vox-3p3rq3 --only queueParentConsentEmailOnUserWrite

# 2단계: 문제 없으면 전체 배포
firebase deploy --project stealth-vox-3p3rq3 --only functions
```

**배포 중 에러 발생 시 (특히 SDK 호환성 에러):** 즉시 중단하고 에러 메시지 전체를 실장님께 보고. 임의로 SDK 버전을 올리거나 코드를 수정하지 말 것.

---

## Phase 5: 커밋

```bash
git add -A
git commit -m "chore: upgrade Firebase Functions runtime from Node.js 20 to 22"
git push origin chore/nodejs-22-upgrade
```

(전체 함수 배포까지 정상 확인된 후 main 머지 권장 — 배포 자체가 검증이므로 머지는 마지막에)

---

## 롤백 절차

```bash
# 코드 롤백
git checkout main
git branch -D chore/nodejs-22-upgrade

# 배포까지 진행했다면 이전 버전으로 재배포 필요
git checkout main -- firebase/functions/package.json
cd firebase && firebase deploy --project stealth-vox-3p3rq3 --only functions
```

---

Phase 0 결과 나오면, SDK 버전 호환성 여부 확인해서 필요시 Phase 2를 보강해 드리겠습니다.