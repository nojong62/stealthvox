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

지금 바로 실행 가능한 **전체 지시서**입니다 — placeholder(【치환필요】)는 기존 컨벤션대로 Codex가 Phase 0 grep으로 스스로 찾아 채우는 방식입니다.

---

# trialCompleted 발동 시점 수정 — Codex 지시서 (최종)

## Phase S: Savepoint

```bash
cd F:\flutter_project\stealth_vox
git status
git add -A
git commit -m "savepoint: before trialCompleted trigger point migration"
git checkout -b fix/trial-completed-trigger-point
```

---

## Phase 0: 진단 (Diagnostics / Grep)

```bash
# 1. trialCompleted 전체 사용처 검색 (파일:줄번호:내용 형태로 전체 출력)
grep -rn "trialCompleted" lib/ --include="*.dart"

# 2. 현재 값을 true로 설정하는 지점만 추출
grep -rn "trialCompleted.*=.*true" lib/ --include="*.dart"

# 3. routine_mode_anyone.dart 파일 경로 확정 및 구조 확인
find lib/ -iname "*routine_mode_anyone*"
grep -n "class \|void \|Future\|Timer\|dispose\|_endSession\|_completeSession\|onTimerComplete\|remainingTime" lib/【치환필요: 위 find 결과로 확정된 경로】

# 4. 타이머 자연 만료를 판단하는 정확한 콜백/조건문 위치 확인
grep -n "Timer.periodic\|onFinish\|timerFinished\|remainingTime <= 0\|remainingTime == 0" lib/【치환필요: routine_mode_anyone.dart 경로】
```

**Codex는 아래 항목을 정리해서 보고할 것:**
1. `trialCompleted = true`가 **현재** 설정되는 정확한 파일명 + 줄 번호 + 함수명 (회원가입 처리 쪽)
2. `trialCompleted` 저장 방식 — Firestore 필드인지 FFAppState 로컬 필드인지, 정확한 경로/필드명
3. `routine_mode_anyone.dart`에서 **타이머가 자연 만료되는 시점**(중간 이탈이 아닌, 카운트다운이 0이 되는 시점)을 처리하는 정확한 함수명 + 줄 번호
4. 위 3번 함수가 이미 Firestore/FFAppState에 다른 값을 쓰고 있는지 (있다면 같은 패턴 재사용)

---

## Phase 1: 앵커 검증

Phase 0 보고 내용을 기반으로, 아래 두 앵커에 대해 grep 결과가 **정확히 1건**인지 확인:

- **제거 앵커**: 회원가입 로직 내 `trialCompleted = true` 설정 코드
- **추가 앵커**: `routine_mode_anyone.dart` 내 타이머 자연 만료 처리 함수

1건이 아니면 (즉 동일 패턴이 여러 곳에 있으면) 즉시 중단하고 실장님께 스크린샷/전체 목록 보고 후 지시 대기.

---

## Phase 2: 파일별 하단→상단 편집

### 2-1. 기존 발동 지점 제거 (회원가입 파일)

```
파일: lib/【치환필요: Phase 0-1에서 확정된 회원가입 파일 경로】
위치: 【확인필요: Phase 0-1 줄 번호】

기존 "trialCompleted = true" 설정 라인을 제거.
완전 삭제하지 말고 아래처럼 주석으로 대체하여 이력 남길 것:

// trialCompleted trigger moved to routine_mode_anyone.dart (Anyone 1-min timer natural expiry)
// see: fix/trial-completed-trigger-point branch
```

### 2-2. Anyone 1분 타이머 자연 만료 지점에 추가 (신규 발동 지점)

```
파일: lib/【치환필요: routine_mode_anyone.dart 경로】
위치: 【확인필요: 타이머 자연 만료(카운트다운 0 도달) 처리 함수 내부】

조건: 반드시 "타이머가 자연 만료(0초 도달)"된 경우에만 실행.
사용자가 중도 이탈(화면 나가기, 뒤로가기 등)한 경우는 절대 트리거되지 않도록 
기존 dispose()/이탈 처리 로직과는 별개 위치에 작성할 것.

Phase 0-2에서 확인한 것과 동일한 저장 방식(Firestore 필드 경로 또는 
FFAppState 필드)으로 trialCompleted 값을 true로 설정.

기존 코드가 snapshots() 리스너 기반 update()를 쓰고 있다면 동일 패턴 사용.
일회성 .get()/.set() 방식이면 기존 패턴 그대로 유지.
```

---

## Phase 3: Grep 검증

```bash
grep -rn "trialCompleted" lib/ --include="*.dart"
```

**기대 결과:**
- 회원가입 파일: `= true` 설정 없음 (주석만 존재)
- `routine_mode_anyone.dart`: `= true` 설정 정확히 1건 (타이머 자연 만료 조건 내부)

---

## Phase 4: 포맷 + 정적 분석

```bash
dart format lib/【치환필요: 회원가입 파일 경로】
dart format lib/【치환필요: routine_mode_anyone.dart 경로】
flutter analyze
```

`flutter analyze` 결과에 새로운 에러/경고 없어야 함. 있으면 즉시 보고.

---

## Phase 5: 커밋

```bash
git add -A
git commit -m "fix: move trialCompleted trigger from signup to Anyone timer natural expiry"
```

---

## 롤백 절차

```bash
git checkout main
git branch -D fix/trial-completed-trigger-point
```

---

Codex가 Phase 0 결과 보고하면, 그걸 붙여서 저한테 주시면 Phase 1~2가 실제로 정확한 지점을 가리키는지 제가 검증해 드리겠습니다.

