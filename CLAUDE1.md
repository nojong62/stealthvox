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

firebase-functions SDK 업그레이드 + Node.js 22 런타임 업그레이드 — 통합 지시서

Phase S: Savepoint
bashcd F:\flutter_project\stealth_vox
git status
git add -A
git commit -m "savepoint: before firebase-functions SDK and Node.js 22 upgrade"
git checkout -b chore/sdk-nodejs22-upgrade

Phase 0: 진단 (Diagnostics / Grep)
bash# 1. 현재 SDK 버전 및 런타임 설정 확인
cat firebase/functions/package.json

# 2. firebase.json 런타임 설정 확인
cat firebase/firebase.json | grep -i "runtime\|nodejs"

# 3. 로컬 Node 버전 확인
node --version

# 4. index.js에서 사용 중인 firebase-functions API 패턴 확인
#    (v4 → v7 마이그레이션 시 breaking change 있는 API 사용 여부 체크)
grep -n "require\('firebase-functions'\)\|from 'firebase-functions'\|functions\.https\.\|functions\.firestore\.\|functions\.config\(\)" firebase/functions/index.js

# 5. functions.config() 사용 여부 (v6부터 deprecated, 완전 제거 대상 — 있으면 마이그레이션 필요)
grep -n "functions.config()" firebase/functions/index.js

# 6. 현재 배포된 함수 목록 (몇 개나 영향받는지 파악)
firebase functions:list --project stealth-vox-3p3rq3
Codex는 아래 항목을 정리해서 보고할 것:

firebase-functions, firebase-admin 현재 버전 (정확한 숫자)
functions.config() 사용 여부 — 있다면 이건 v6부터 완전 제거된 API라 SDK 업그레이드 시 반드시 defineSecret/환경변수 방식으로 코드 수정이 필요하다는 점을 명확히 보고
functions.https.onCall, functions.firestore.document(...).onCreate 등 v1 문법(1세대 스타일)을 쓰는지, 아니면 이미 onCall, onDocumentCreated 같은 v2 문법을 쓰는지 — v1/v2 문법이 섞여 있으면 마이그레이션 범위가 커짐
로컬 Node 버전이 22 이상인지


Phase 1: 앵커 검증 및 마이그레이션 범위 확정
⚠️ 중요 확인 필요: Phase 0-2 결과 functions.config()가 사용 중이라면, 이건 단순 버전 번호 변경이 아니라 코드 마이그레이션 작업이 됩니다. REVENUECAT_WEBHOOK_SECRET은 이미 defineSecret()으로 되어 있다고 확인된 바 있어 이 부분은 안전해 보이지만, 다른 설정값이 functions.config()로 되어 있다면 별도 처리가 필요합니다.
Phase 0 보고 결과에 따라:

breaking change 없음 → 아래 Phase 2 그대로 진행
breaking change 있음(v1 문법, functions.config() 등) → Codex는 여기서 멈추고 구체적 목록을 실장님께 보고, 다음 지시서에서 마이그레이션 단계 추가


Phase 2: 편집
2-1. firebase-functions / firebase-admin SDK 업그레이드
bashcd firebase/functions
npm install firebase-functions@latest firebase-admin@latest --save
2-2. package.json 런타임 버전 변경
파일: firebase/functions/package.json
위치: "engines" 필드

"engines": { "node": "20" } 를
"engines": { "node": "22" } 로 변경
2-3. 로컬 Node 버전 확인 및 전환 (필요시)
로컬 Node 버전이 22 미만이면 nvm으로 전환:

nvm install 22
nvm use 22
node --version   # v22.x.x 확인

nvm 미설치 상태면 이 단계는 실행하지 말고 
"nvm 설치 필요" 보고 후 대기.
2-4. 의존성 재설치 및 로컬 문법 검증
bashrm -rf node_modules package-lock.json
npm install
node --check index.js

node --check는 문법 오류만 잡습니다. SDK v7의 실제 API breaking change는 이걸로 못 잡으니, Phase 1에서 확인한 functions.config() 등 사용 여부가 더 중요합니다.


Phase 3: Grep 검증
bashgrep -A 2 "\"engines\"" firebase/functions/package.json
grep -n "\"firebase-functions\"\|\"firebase-admin\"" firebase/functions/package.json
기대 결과: node: 22, firebase-functions/firebase-admin 최신 버전(^7.x, 관련 admin 버전) 확인.

Phase 4: 배포 (단계적 진행 — 필수)
⚠️ 전체 함수 절대 한 번에 배포하지 말 것.
bash# 1단계: 트래픽 적은 함수 1개만 먼저 배포 (예: queueParentConsentEmailOnUserWrite)
firebase deploy --project stealth-vox-3p3rq3 --only functions:queueParentConsentEmailOnUserWrite

# 배포 성공 확인 후 로그 체크
firebase functions:log --project stealth-vox-3p3rq3 --only queueParentConsentEmailOnUserWrite

# 2단계: 문제 없으면 나머지 함수 순차 배포 (전체 한번에 X, 핵심 함수군별로 나눠서)
firebase deploy --project stealth-vox-3p3rq3 --only functions
에러 발생 시 (특히 API 관련 에러, deprecated 경고): 즉시 중단하고 에러 전문을 실장님께 보고. 임의로 코드 수정하지 말 것.

Phase 5: 커밋
bashgit add -A
git commit -m "chore: upgrade firebase-functions/admin SDK and Node.js runtime to 22"
git push origin chore/sdk-nodejs22-upgrade
(전체 함수 배포 정상 확인 후 main 머지 권장)

롤백 절차
bash# 코드 롤백
git checkout main
git branch -D chore/sdk-nodejs22-upgrade

# 배포까지 진행했다면 이전 SDK/런타임으로 재배포
git checkout main -- firebase/functions/package.json firebase/functions/package-lock.json
cd firebase/functions && npm install
cd .. && firebase deploy --project stealth-vox-3p3rq3 --only functions

Phase 0~1 결과 나오면(특히 functions.config() 사용 여부), 마이그레이션 범위 확정해서 Phase 2를 필요시 보강해 드리겠습니다.