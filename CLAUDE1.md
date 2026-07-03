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
- 완료후 관리자가 APK 라고 적으면, 날자와 시간이 이름에 들어간 APK만들어 줘. 

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# 지시문: 체험(_startTrial) 시 라우터 자동 리다이렉트 억제

## 배경
`GoRouter`의 `refreshListenable: appStateNotifier` 구조상, `/` 경로(Intro)에
머무른 채로 `signInAnonymously()`가 실행되면 `appStateNotifier.loggedIn`이
true로 바뀌고, 초기 라우트 builder(`appStateNotifier.loggedIn ? LobbyWidget() : IntroWidget()`)가
재평가되어 자동으로 LobbyWidget으로 교체됨. 이 때문에 `_enterTrialAnyone()`의
명시적 `pushNamed('StealthRoom')`이 무시되고 체험 버튼이 Lobby(0시간)로 새는 현상 발생.

**해결**: `AppStateNotifier`에 이미 존재하는 1회성 억제 스위치
`updateNotifyOnAuthChange(false)`를 익명 로그인 직전에 호출하여,
이번 인증 상태 변화가 라우터에 전달되지 않도록 한다.

## 대상 파일
- `lib/custom_code/widgets/intro_master.dart`

---

## Phase 0 — Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before trial routing redirect suppression fix"
```

---

## Phase 1 — 정확한 삽입 위치 확인

```bash
grep -n "_startTrial\|signInAnonymously" lib/custom_code/widgets/intro_master.dart -B 2 -A 10
```

`_startTrial()` 함수 내부에서 `FirebaseAuth.instance.signInAnonymously()`를
호출하는 정확한 줄을 찾는다 (지난번 수정으로 non-anonymous 세션 처리 분기가
추가되었으므로, 그 로직과 겹치지 않게 위치 확인).

## Phase 2 — AppStateNotifier import 확인

```bash
grep -n "^import" lib/custom_code/widgets/intro_master.dart | grep -i "app_state_notifier\|nav.dart\|flutter_flow"
```

`AppStateNotifier` 클래스가 이미 import되어 있는지 확인. 없다면 적절한
import 구문을 추가해야 한다 (파일 위치: `lib/flutter_flow/nav/nav.dart` 또는
해당 클래스가 정의된 파일 경로를 grep으로 재확인).

```bash
grep -rn "class AppStateNotifier" lib/ --include="*.dart"
```

## Phase 3 — 수정

`signInAnonymously()` 호출 직전에 한 줄 추가:

```dart
AppStateNotifier.instance.updateNotifyOnAuthChange(false);
await FirebaseAuth.instance.signInAnonymously();
```

정확한 old_str/new_str은 Phase 1에서 확인한 실제 코드에 맞춰 작성한다.
예시 형태:

```
old_str:
      await FirebaseAuth.instance.signInAnonymously();

new_str:
      AppStateNotifier.instance.updateNotifyOnAuthChange(false);
      await FirebaseAuth.instance.signInAnonymously();
```

⚠️ **주의**: 지난번 수정으로 `_startTrial()` 안에 non-anonymous 세션일 때
signOut 후 signInAnonymously하는 분기가 있다. `signInAnonymously()` 호출이
2곳(또는 조건부 1곳)일 수 있으므로, **모든 signInAnonymously() 호출 직전**에
동일하게 `updateNotifyOnAuthChange(false)`를 추가해야 한다. grep으로 호출
지점이 몇 개인지 먼저 정확히 센 뒤 적용할 것.

```bash
grep -c "signInAnonymously()" lib/custom_code/widgets/intro_master.dart
```

---

## Phase 4 — 사후 검증

```bash
grep -n "updateNotifyOnAuthChange\|signInAnonymously" lib/custom_code/widgets/intro_master.dart
```
`updateNotifyOnAuthChange(false)` 호출 횟수가 `signInAnonymously()` 호출
횟수와 일치하는지 확인 (각 익명 로그인 앞에 빠짐없이 붙었는지).

---

## Phase 5 — 빌드 검증

```bash
flutter analyze lib/custom_code/widgets/intro_master.dart
dart format lib/custom_code/widgets/intro_master.dart
```

⚠️ 단일 파일만 format

---

## Phase 6 — 커밋

```bash
git add -A
git commit -m "fix: suppress router auto-redirect during trial anonymous sign-in"
```

---

## Phase 7 — 실기기 테스트 시나리오

1. 앱 데이터 완전 삭제 → 재실행 → 체험 버튼 클릭 → **언어선택 화면이 뜨는지** (Lobby로 새지 않는지) 확인
2. 로그아웃 → 앱 안 끄고 체험 클릭 → 정상 동작 유지 확인 (회귀 없는지)
3. 로그아웃 → 앱 강제 종료 → 재시작 → 체험 클릭 → 이번엔 언어선택으로 정상 진행되는지 확인 (기존 cold start 버그 재현 여부)
4. 정식 회원(카카오/구글) 로그인은 여전히 정상적으로 Lobby로 가는지 확인 (`updateNotifyOnAuthChange`가 자동으로 다시 true로 복원되므로 문제없어야 함 — 회귀 확인 차원)

이번엔 반드시 **cold start 케이스(3번)를 여러 번 반복**해서 확인할 것 — 지난번 수정이 이 케이스에서 효과가 없었던 전례가 있음.

---

## Phase 8 — 롤백

```bash
git revert HEAD
```