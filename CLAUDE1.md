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

# 📋 최종 커밋 + 검증 — Claude Code 지시서

> **사전 조건:** `firebase deploy --only functions` 완료 (실장 수동, 1단계)
> **이 지시서 범위:** Git 커밋 + 정적 검증만. 실제 앱 실행 테스트는 불가 (기기 필요) → 체크리스트로 별도 안내.

---

## 1. 현재 상태 확인

```powershell
cd F:\flutter_project\stealth_vox
git status
git branch --show-current
```

현재 브랜치(`claude1-part-b-20260613` 등)와 변경된 파일 목록을 보여줄 것.

---

## 2. 변경 파일 diff 요약 확인

아래 파일들이 이번 작업에서 수정된 대상입니다. 각각 `git diff --stat`으로 변경 라인 수만 확인:

```powershell
git diff --stat -- lib/custom_code/widgets/stealth_room_master.dart lib/custom_code/widgets/lobby_master.dart lib/custom_code/widgets/store_master.dart lib/custom_code/widgets/intro_master.dart firebase/functions/index.js firebase/firestore.rules
```

---

## 3. 최종 정적 검증 (배포 후 재확인)

### 3-1. Flutter 전체 analyze (변경 파일만)

```powershell
flutter analyze lib/custom_code/widgets/stealth_room_master.dart lib/custom_code/widgets/lobby_master.dart lib/custom_code/widgets/store_master.dart lib/custom_code/widgets/intro_master.dart
```

`error` 키워드 포함 라인이 없는지 확인. (warning/info는 무시)

### 3-2. index.js 문법 + export 재확인

```powershell
node --check firebase\functions\index.js
grep -c "exports.onUserDeleted" firebase\functions\index.js
grep -c "exports.deductRemainingTime" firebase\functions\index.js
grep -c "exports.revenueCatWebhook" firebase\functions\index.js
grep -c "remaining_seconds" firebase\functions\index.js
grep -c "recursiveDelete" firebase\functions\index.js
```

기대값: 위 3개 export 각 1, `remaining_seconds` 0, `recursiveDelete` 1.

### 3-3. Firestore Rules 컴파일 확인 (배포는 이미 됐으므로 재확인만)

```powershell
type firebase\firestore.rules | Select-String "allow read, write: if true"
```

→ 결과가 **없어야** 함 (전체 개방 규칙 제거 확인).

---

## 4. Git 커밋

위 3번 검증이 모두 통과하면 커밋:

```powershell
git add -A
git commit -m "Phase 2: 서버전용 증액 + Firestore Rules 강화 + 백그라운드/Store pause + 계정탈퇴 데이터 완전삭제 + Anonymous 계정연결"
```

커밋 해시와 변경 파일 수를 보고할 것.

---

## 5. 커밋 후 보고 형식

```
브랜치: <branch명>
커밋 해시: <hash>
변경 파일: <N>개
3-1 analyze: error 0개 ✅/❌
3-2 index.js: <표>
3-3 rules: "if true" 없음 ✅/❌
```

---

## ⚠️ 이 지시서가 하지 않는 것 (실장 수동 진행)

아래는 Claude Code가 할 수 없으므로 **실장님이 직접** 진행:

| # | 항목 | 방법 |
|---|------|------|
| 1 | `flutter build appbundle` | PowerShell에서 직접 빌드 |
| 2 | Google Play 내부 테스트 업로드 | Play Console |
| 3 | 앱 실행 후 1분 대화 → `remainingTime` 60초 감소 확인 | Firebase Console에서 `users/{uid}.remainingTime` 관찰 |
| 4 | 대화 중 백그라운드 전환 → 시간 안 줄어드는지 확인 | 앱을 홈으로 보냈다가 복귀 |
| 5 | Store 화면 진입 후 30초 대기 → `remainingTime` 변화 없음 확인 | Firebase Console |
| 6 (선택) | 테스트 계정으로 회원탈퇴 → `users/{uid}` 문서 + 하위 컬렉션 전체 삭제 확인 | Firebase Console Firestore |

---

## 🔄 롤백

```powershell
git reset --soft HEAD~1   # 커밋만 취소, 변경사항은 유지
# 또는
git restore <file>          # 특정 파일만 되돌리기
```

functions 배포 롤백은 이전 버전 재배포 필요 — 문제 발생 시 보고.