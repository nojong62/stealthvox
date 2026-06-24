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

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문

# StepExpand 첫질문 안내문 삭제 + 팝업 힌트 문구 수정

## 사전 준비
```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before step_expand text fix"
```

## 대상 파일
`lib/custom_code/routine_mode_step_expand.dart`

---

## Phase 1: 정확한 문자열 위치 확인 (먼저 실행)

```bash
grep -n "하고 싶은 이야기" lib/custom_code/routine_mode_step_expand.dart
```
→ 예상: 1건. AI 첫 질문 시스템 프롬프트 또는 메시지 조합부에 포함.

```bash
grep -n "합성 문장" lib/custom_code/routine_mode_step_expand.dart
```
→ 예상: 1건. 팝업 힌트 텍스트.

**두 grep 결과를 확인한 후 아래 수정 진행.**

---

## Phase 2: 수정 (2건)

### 수정 1 — AI 첫질문의 "하고 싶은 이야기~" 안내문 삭제

grep 결과에서 "하고 싶은 이야기" 가 포함된 줄을 확인한다.
해당 문자열이 포함된 **줄 전체** 또는 **해당 안내 문장 부분**을 삭제한다.

- 만약 `\n하고 싶은 이야기가 있으시면 먼저 말씀해 주세요.` 형태라면 → `\n하고 싶은 이야기가 있으시면 먼저 말씀해 주세요.` 부분만 제거
- 만약 별도 줄로 연결(예: `+ '\n하고 싶은 이야기...'`)되어 있다면 → 해당 연결 부분 제거

**핵심: "하고 싶은 이야기가 있으시면 먼저 말씀해 주세요." 또는 유사 변형이 최종 AI 메시지에 포함되지 않도록 완전 제거.**

### 수정 2 — 팝업 힌트 문구 변경

grep 결과에서 "합성 문장"이 포함된 줄을 확인한다.

```
str_replace:
OLD: 질문과 다른 합성 문장을 말하셔도 됩니다.
NEW: 질문과 다른 씨앗 문장을 말씀하셔도 됩니다.
```

> 주의: "말하셔도" → "말씀하셔도" 로도 변경됨 (존댓말 통일).

---

## Phase 3: 검증

```bash
grep -c "하고 싶은 이야기" lib/custom_code/routine_mode_step_expand.dart
```
→ 기대값: **0**

```bash
grep -n "씨앗 문장" lib/custom_code/routine_mode_step_expand.dart
```
→ 기대값: **1건**, "질문과 다른 씨앗 문장을 말씀하셔도 됩니다."

```bash
grep -c "합성 문장" lib/custom_code/routine_mode_step_expand.dart
```
→ 기대값: **0**

```bash
dart format lib/custom_code/routine_mode_step_expand.dart
flutter analyze lib/custom_code/routine_mode_step_expand.dart
```

---

## 롤백
```bash
git checkout HEAD -- lib/custom_code/routine_mode_step_expand.dart
```