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

1만 8천 개면 확실히 정리가 필요합니다. 지시서 드립니다.

---

# node_modules Git 추적 제거 지시서

## Phase S: Savepoint

```bash
cd F:\flutter_project\stealth_vox
git status
git add -A
git commit -m "savepoint: before removing node_modules from git tracking"
git checkout -b chore/gitignore-node-modules
```

---

## Phase 0: 진단

```bash
# node_modules가 정확히 어느 경로들에서 추적되는지 전체 확인
git ls-files | grep node_modules | sed 's|/node_modules/.*||' | sort -u

# 현재 .gitignore 내용 확인 (루트 + firebase)
cat .gitignore
cat firebase/.gitignore 2>/dev/null
echo "---firebase/functions---"
cat firebase/functions/.gitignore 2>/dev/null
```

**Codex는 보고할 것:** `node_modules`가 `firebase/functions/` 외에 다른 경로(예: 루트, 다른 하위 프로젝트)에도 있는지.

---

## Phase 1: .gitignore 수정

```
파일: .gitignore (루트, 없으면 새로 생성)

파일 끝에 추가:
node_modules/
**/node_modules/
```

```
파일: firebase/functions/.gitignore (없으면 새로 생성)

node_modules/
```

---

## Phase 2: Git 추적에서만 제거 (실제 파일은 유지)

```bash
git rm -r --cached firebase/functions/node_modules
```

> `--cached`가 핵심입니다. 로컬 디스크의 실제 `node_modules` 폴더는 그대로 남고, git 추적 대상에서만 빠집니다. 삭제 아닙니다.

Phase 0에서 다른 경로에도 node_modules가 있었다면 그 경로도 동일하게:
```bash
git rm -r --cached 【치환필요: 다른 node_modules 경로】
```

---

## Phase 3: 검증

```bash
git status
# node_modules 관련 파일들이 "deleted" 상태로 잔뜩 나와야 정상 (실제 삭제 아님, staged 상태)

git ls-files | grep node_modules | wc -l
# 0이어야 함
```

로컬에 파일이 실제로 남아있는지 확인:
```bash
ls firebase/functions/node_modules | head -5
# 파일들 정상적으로 보여야 함
```

---

## Phase 4: 커밋

```bash
git add -A
git commit -m "chore: stop tracking node_modules, add to gitignore"
git push origin chore/gitignore-node-modules
```

---

## Phase 5: main 병합

```bash
git checkout main
git merge chore/gitignore-node-modules
git push origin main
```

---

## 주의사항 (Codex에게 전달)

- 이 작업 이후 다른 브랜치에서 작업하다 `git checkout`으로 이 브랜치를 오갈 때, node_modules가 사라진 것처럼 보이면 `npm install`로 재생성하면 됩니다 (정상 동작, 걱정할 필요 없음).
- `git rm -r --cached`는 절대 `git clean` 이나 `rm -rf`와 혼동하면 안 됩니다 — 실제 파일 삭제 명령이 아닙니다.

---

## 롤백 절차

```bash
git checkout main
git branch -D chore/gitignore-node-modules
```