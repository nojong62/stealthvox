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

# 이용약관/개인정보처리방침 URL 반영 — Codex 지시서

---

## Phase S: Savepoint

```bash
cd F:\flutter_project\stealth_vox
git status
git add -A
git commit -m "savepoint: before terms/privacy URL insertion"
git checkout -b fix/terms-privacy-url
```

---

## Phase 0: 진단 (Diagnostics / Grep)

```bash
# 1. TODO 플레이스홀더 전체 위치 확인
grep -rn "TODO.*이용약관\|TODO.*개인정보\|TODO.*terms\|TODO.*privacy" lib/ --include="*.dart"

# 2. 혹시 다른 표기(약관, 방침 관련 문자열) 남아있는지 추가 확인
grep -rln "이용약관\|개인정보처리방침" lib/ --include="*.dart"
```

**Codex는 아래 항목을 보고할 것:**
1. TODO 플레이스홀더가 있는 정확한 파일명 + 줄 번호 전체 목록 (몇 군데인지)
2. 각 위치가 어떤 형태로 쓰여있는지 (예: `Uri.parse("TODO")`, `onTap: () {}` 등 코드 패턴)

---

## Phase 1: 앵커 검증

Phase 0에서 나온 각 TODO 위치에 대해 grep 매치가 정확히 1건씩인지 확인 후 진행.

---

## Phase 2: 편집 (파일별 하단→상단)

각 TODO 위치마다 아래 URL로 치환:

```
이용약관 URL:
https://docs.google.com/document/d/1KE4xrb63SDw1ZkiNQ_wxQjH7iyY6msTuVtazCTnR7KY/edit

개인정보처리방침 URL:
https://docs.google.com/document/d/1qz1aCx6ZcxCkANFUSvbnE18H2-SbEhPUWlvZw27-DAQ/edit
```

```
파일: lib/【치환필요: Phase 0에서 찾은 각 파일 경로】
위치: 【치환필요: 해당 줄 번호】

기존 TODO 플레이스홀더 문자열을 위 URL 중 해당하는 것으로 정확히 치환.
링크가 실행 중 열리는 방식(url_launcher 등)이 이미 구현되어 있다면 
URL 문자열만 교체하고 로직은 건드리지 말 것.
만약 아직 탭 이벤트 자체가 구현 안 되어 있다면 (TODO가 단순 placeholder text인 경우),
기존 파일 내 다른 외부 링크 열기 패턴(url_launcher launchUrl 등)을 
동일하게 재사용해서 탭 시 브라우저로 열리도록 구현.
```

---

## Phase 3: Grep 검증

```bash
grep -rn "TODO.*이용약관\|TODO.*개인정보\|TODO.*terms\|TODO.*privacy" lib/ --include="*.dart"
```

기대 결과: 매치 0건 (전부 실제 URL로 치환 완료).

```bash
grep -rn "docs.google.com/document/d/1KE4xrb63\|docs.google.com/document/d/1qz1aCx6" lib/ --include="*.dart"
```

기대 결과: 각 URL이 코드에 정확히 반영된 위치 확인.

---

## Phase 4: 포맷 및 정적 분석

```bash
dart format lib/【수정한 모든 파일】
flutter analyze
```

변경 파일 기준 새 error 없는지 확인.

---

## Phase 5: 커밋

```bash
git add -A
git commit -m "fix: insert terms of service and privacy policy URLs"
git checkout main
git merge fix/terms-privacy-url
git push origin main
```

> 단순 URL 치환이고 리스크 낮은 작업이라 바로 main 머지 진행해도 무방합니다.

---

## 롤백 절차

```bash
git checkout main
git branch -D fix/terms-privacy-url
```

---

Phase 0 진단 결과 나오면(TODO가 몇 군데인지), 필요하면 Phase 2를 파일별로 세분화해서 다시 정리해 드리겠습니다.