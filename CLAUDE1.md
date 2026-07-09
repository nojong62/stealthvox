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

# 배포 정리 (orphan 함수 삭제 + 브랜치 merge) — SDK 업그레이드 선행 작업

## Phase 1: `claimWelcomeBonus` Firebase에서 삭제

```bash
cd F:\flutter_project\stealth_vox\firebase

firebase functions:delete claimWelcomeBonus --project stealth-vox-3p3rq3 --force
```

삭제 후 확인:
```bash
firebase functions:list --project stealth-vox-3p3rq3 | grep claimWelcomeBonus
```
결과 없어야 정상.

---

## Phase 2: `feat/parental-consent-email` 브랜치를 현재 작업 브랜치에 반영

```bash
cd F:\flutter_project\stealth_vox

# 현재 SDK 업그레이드 브랜치(chore/sdk-nodejs22-upgrade)로 이동
git checkout chore/sdk-nodejs22-upgrade

# main에 먼저 병합해두는 게 순서상 깔끔함 (부모 동의 기능은 이미 검증/배포 완료된 것이므로)
git checkout main
git merge feat/parental-consent-email
git push origin main

# 그 다음 SDK 업그레이드 브랜치를 최신 main 기준으로 재정렬
git checkout chore/sdk-nodejs22-upgrade
git rebase main
```

> `git rebase main`이 충돌 없이 끝나야 정상입니다. 충돌 발생 시 Codex는 임의로 해결하지 말고 충돌 파일명과 내용을 그대로 보고 후 대기.

---

## Phase 3: 정리 후 재검증

```bash
grep -n "claimWelcomeBonus\|queueParentConsentEmailOnUserWrite" firebase/functions/index.js
firebase functions:list --project stealth-vox-3p3rq3
```

**기대 결과:**
- `claimWelcomeBonus`: 코드에도 배포 목록에도 없음
- `queueParentConsentEmailOnUserWrite`: 코드(index.js)에도 있고 배포 목록에도 있음 — 이제 일치

---

## Phase 4: 커밋

```bash
git add -A
git commit -m "chore: sync branch with parental consent email merge, remove orphaned claimWelcomeBonus" --allow-empty
```

(변경사항이 rebase/merge로만 반영되어 실제 diff 없을 수 있음 — 그 경우 커밋 생략 가능, Codex가 `git status`로 판단)

---

이 정리가 끝나면 로컬 코드와 Firebase 배포 상태가 일치하니, **이전에 드린 SDK 업그레이드 지시서(Phase 0부터)를 이 정리된 브랜치 위에서 이어서 진행**하시면 됩니다. v1 API import 경로 수정(`require('firebase-functions/v1')`)이 필요하다는 점만 다시 참고해 주세요.