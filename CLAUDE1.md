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

# 지시문: remainingTime 로딩 상태 정석 구현 (remainingTimeLoaded 플래그)

## 배경
현재 `FFAppState._remainingTime` 기본값이 10000(초)으로 하드코딩되어,
로비 진입 시 Firestore fetch가 완료되기 전까지 잘못된 숫자가 화면에 표시됨.
단순히 기본값을 0으로 바꿔도, fetch 완료 전 짧게 "00:00"이 표시됐다가
실제값으로 바뀌는 문제는 남음 — 사용자에게 "확정된 숫자"처럼 보이는 문제.

**해결 방향**: `remainingTime`의 타입은 그대로 두고(다른 9개 파일 영향 없음),
별도의 `remainingTimeLoaded` boolean 플래그를 추가해서
"아직 안 불러옴" 상태를 명시적으로 구분한다.

## 대상 파일
- `lib/app_state.dart`
- `lib/custom_code/widgets/lobby_master.dart`
- `lib/auth/firebase_auth/firebase_auth_manager.dart` (로그아웃 시 리셋)

---

## Phase 0 — Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before remainingTimeLoaded state"
```

---

## Phase 1 — app_state.dart에 플래그 추가

### 1-A: 확인

```bash
grep -n "_remainingTime" lib/app_state.dart -B 2 -A 5
```

### 1-B: 수정

```
파일: lib/app_state.dart

old_str:
  /// 남은 시간 (초)
  int _remainingTime = 10000;
  int get remainingTime => _remainingTime;
  set remainingTime(int value) {
    _remainingTime = value;
  }

new_str:
  /// 남은 시간 (초)
  int _remainingTime = 0;
  int get remainingTime => _remainingTime;
  set remainingTime(int value) {
    _remainingTime = value;
  }

  /// remainingTime이 Firestore로부터 최초 로드 완료되었는지 여부.
  /// false인 동안 UI는 숫자 대신 로딩 표시를 해야 한다.
  bool _remainingTimeLoaded = false;
  bool get remainingTimeLoaded => _remainingTimeLoaded;
  set remainingTimeLoaded(bool value) {
    _remainingTimeLoaded = value;
  }
```

⚠️ 실제 코드 구조가 예상과 다르면(예: getter/setter 스타일이 다르면),
동일한 의미(기본값 0 + 별도 loaded 플래그)를 유지하는 선에서 구조에 맞게 적용.

---

## Phase 2 — lobby_master.dart: fetch 전후로 플래그 설정

### 2-A: 확인

```bash
grep -n "_initializeLobbyData\|remainingTime" lib/custom_code/widgets/lobby_master.dart -B 2 -A 8
```

`_initializeLobbyData()` 함수 안에서 `LobbyBrain.getRemainingTime(...)` 호출
전후 지점을 정확히 파악한다.

### 2-B: 수정 방향

`_initializeLobbyData()` 함수 시작 부분에서:
```dart
FFAppState().remainingTimeLoaded = false;
```

Firestore fetch 성공 후, `FFAppState().remainingTime = serverRemainingTime;`
바로 다음 줄에:
```dart
FFAppState().remainingTimeLoaded = true;
```

fetch가 실패하는 catch 블록이 있다면, 거기서도 (기존 값을 0으로 유지한 채)
`remainingTimeLoaded = true`로 설정할지 여부를 판단한다.
**권장**: 실패 시에도 `true`로 설정하되 에러 스낵바를 띄워서,
무한 로딩 상태로 남지 않도록 한다. (실제 코드 구조 확인 후 적용)

### 2-C: UI 표시 부분 수정

"REMAINING TIME" 숫자를 표시하는 위젯 코드를 찾는다:

```bash
grep -n "REMAINING TIME\|remainingTime" lib/custom_code/widgets/lobby_master.dart
```

해당 텍스트/타이머 위젯을:
```dart
FFAppState().remainingTimeLoaded
    ? Text(formattedRemainingTime)  // 기존 시간 포맷팅 로직 유지
    : SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
```
형태로 조건부 렌더링하도록 감싼다. (기존 스타일/색상 유지, 로딩 위젯만 추가)

⚠️ 실제 위젯 구조(FFAppState 감시 방식이 Provider/ChangeNotifier인지 setState인지)에 맞춰
로딩 상태 변경 시 화면이 리빌드되도록 확인할 것.

---

## Phase 3 — 로그아웃 시 플래그 리셋

```bash
grep -n "remainingTime = 0" lib/auth/firebase_auth/firebase_auth_manager.dart -B 2 -A 2
grep -n "remainingTime = 0" lib/custom_code/widgets/lobby_master.dart -B 2 -A 2
```

이전에 로그아웃 시 `FFAppState().remainingTime = 0` 추가했던 두 지점 각각에
바로 아래 줄로 추가:
```dart
FFAppState().remainingTimeLoaded = false;
```

이렇게 해야 재로그인 시 다시 로딩 상태부터 시작한다.

---

## Phase 4 — 사후 검증

```bash
grep -rn "remainingTimeLoaded" lib/ --include="*.dart"
```
- `app_state.dart`에 정의 1곳
- `lobby_master.dart`에 false 설정, true 설정, UI 조건부 렌더링 (최소 3곳)
- `firebase_auth_manager.dart`에 false 리셋 1곳
총 5곳 이상 나와야 정상.

---

## Phase 5 — 빌드 검증

```bash
flutter analyze lib/app_state.dart lib/custom_code/widgets/lobby_master.dart lib/auth/firebase_auth/firebase_auth_manager.dart
dart format lib/app_state.dart
dart format lib/custom_code/widgets/lobby_master.dart
dart format lib/auth/firebase_auth/firebase_auth_manager.dart
```

⚠️ 각 파일 개별로 format (폴더 대상 금지)

---

## Phase 6 — 커밋

```bash
git add -A
git commit -m "feat: add remainingTimeLoaded flag for proper loading state in Lobby"
```

---

## Phase 7 — 실기기 테스트 시나리오

1. 로그아웃 → 재로그인 → 로비 진입 순간, 숫자 대신 로딩 스피너가 짧게 보이는지 확인
2. 로딩 끝나면 실제 Firestore 값으로 정확히 표시되는지 확인
3. 대화방 사용 후 로비 복귀 시에도 값이 정확히 반영되는지 확인 (기존 정상 동작 유지 여부)

---

## Phase 8 — 롤백

```bash
git revert HEAD
```