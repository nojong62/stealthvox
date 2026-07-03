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

# 지시문: remainingTime 레이스 컨디션 수정 — hasConfirmedZeroTime 캡슐화

## 배경
`remainingTimeLoaded` 도입 이후, 4개 지점에서 로딩 완료 여부를 확인하지 않고
`remainingTime <= 0`만으로 "시간 없음"을 판단해 Store로 잘못 라우팅하거나
과금 타이머 판단이 흔들리는 레이스 컨디션이 확인됨.

**해결 방향**: "확정된 0"인지 판단하는 로직을 `app_state.dart`의
getter 하나로 캡슐화해서, 4개 지점 + 향후 추가될 지점 모두
동일한 안전 규칙을 따르도록 한다.

## 대상 파일
- `lib/app_state.dart` (getter 추가)
- `lib/custom_code/widgets/lobby_master.dart:201`
- `lib/custom_code/widgets/chat_history_master.dart:3259`
- `lib/custom_code/actions/billing_ticker.dart:271`
- `lib/custom_code/actions/billing_ticker.dart:294`

---

## Phase 0 — Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before hasConfirmedZeroTime getter"
```

---

## Phase 1 — app_state.dart에 getter 추가

### 1-A: 확인

```bash
grep -n "remainingTimeLoaded" lib/app_state.dart -B 2 -A 5
```

### 1-B: 수정

`remainingTimeLoaded` getter/setter 바로 아래에 추가:

```dart
  /// Firestore fetch가 완료된 후 실제로 0(또는 그 이하)임이 확정된 경우에만 true.
  /// 로딩 중(remainingTimeLoaded == false)에는 절대 true가 되지 않는다.
  /// "시간이 없다"고 판단해 Store로 보내거나 과금 타이머를 멈추는 모든 곳은
  /// remainingTime <= 0 대신 이 getter를 사용해야 한다.
  bool get hasConfirmedZeroTime => remainingTimeLoaded && remainingTime <= 0;

  /// 로딩 완료 + 실제로 잔여 시간이 있는 경우에만 true.
  bool get hasConfirmedPositiveTime => remainingTimeLoaded && remainingTime > 0;
```

grep으로 정확한 삽입 지점을 확인한 뒤, 실제 코드 스타일(들여쓰기 등)에 맞춰 추가한다.

---

## Phase 2 — lobby_master.dart 수정

### 2-A: 확인

```bash
grep -n "remainingTime <= 0" lib/custom_code/widgets/lobby_master.dart -B 3 -A 3
```

### 2-B: str_replace

정확한 old_str은 실제 코드 확인 후 결정하되, 핵심 치환은:

```
appState.remainingTime <= 0
```
→
```
appState.hasConfirmedZeroTime
```

(라인 201 주변, `if (appState.remainingTime <= 0) { ... Store로 이동 ... }` 형태)

---

## Phase 3 — chat_history_master.dart 수정

### 3-A: 확인

```bash
grep -n "remainingTime <= 0" lib/custom_code/widgets/chat_history_master.dart -B 3 -A 3
```

### 3-B: str_replace

라인 3259 주변, 동일하게:
```
appState.remainingTime <= 0
```
→
```
appState.hasConfirmedZeroTime
```

---

## Phase 4 — billing_ticker.dart 수정 (2곳)

### 4-A: 확인

```bash
grep -n "remainingTime" lib/custom_code/actions/billing_ticker.dart -B 3 -A 3
```

### 4-B: 라인 271 근처 — resume 가능 여부 판단

```
FFAppState().remainingTime > 0
```
→
```
FFAppState().hasConfirmedPositiveTime
```

### 4-C: 라인 294 근처 — tick 차감 중단 판단

```
if (FFAppState().remainingTime <= 0) return;
```
→
```
if (FFAppState().hasConfirmedZeroTime) return;
```

⚠️ **주의**: 이 두 지점은 로비 라우팅과 성격이 다르다.
`hasConfirmedZeroTime`이 false인 상태(로딩 중)에서 tick이 계속 진행되면
아직 확정 안 된 상태에서 시간이 계속 깎일 수 있다.
실제 코드 문맥을 반드시 확인해서, "로딩 중에는 아예 tick 자체를 진행하지 않아야
하는지"도 함께 판단할 것. 필요하면 `if (!FFAppState().remainingTimeLoaded) return;`
가드를 tick 함수 최상단에 별도로 추가하는 것도 고려 (그 경우 실장에게 별도 보고).

---

## Phase 5 — 사후 검증

```bash
# 남은 위험 패턴이 있는지 재확인
grep -rn "remainingTime <= 0\|remainingTime > 0" lib/ --include="*.dart"
# Store 라우팅/과금 판단 관련 지점에서는 더 이상 나오지 않아야 함
# (단, lobby_master.dart:622의 색상 결정처럼 UI 스타일링 목적은 예외로 남을 수 있음 — 실장 확인)

grep -rn "hasConfirmedZeroTime\|hasConfirmedPositiveTime" lib/ --include="*.dart"
# app_state.dart 정의 2곳 + 사용처 4곳(또는 5곳, Phase 4 판단에 따라) 나와야 함
```

---

## Phase 6 — 빌드 검증

```bash
flutter analyze lib/app_state.dart lib/custom_code/widgets/lobby_master.dart lib/custom_code/widgets/chat_history_master.dart lib/custom_code/actions/billing_ticker.dart
dart format lib/app_state.dart
dart format lib/custom_code/widgets/lobby_master.dart
dart format lib/custom_code/widgets/chat_history_master.dart
dart format lib/custom_code/actions/billing_ticker.dart
```

⚠️ 각 파일 개별 format (폴더 대상 금지)

---

## Phase 7 — 커밋

```bash
git add -A
git commit -m "fix: prevent premature Store redirect and billing decisions before remainingTime loads"
```

---

## Phase 8 — 실기기 테스트 시나리오

1. 앱 데이터 완전 삭제
2. 구글 또는 카카오 로그인 → 로비 진입을 **여러 번 반복** (최소 5회, 로그아웃-재로그인 반복)
3. 매번 Store로 잘못 튕기지 않고 정상적으로 로비/체험이 뜨는지 확인
4. 정상적으로 시간이 0인 계정(실제 0)으로는 여전히 Store로 잘 유도되는지도 확인 (회귀 방지 확인)

---

## Phase 9 — 롤백

```bash
git revert HEAD
```