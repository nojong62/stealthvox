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

# 지시문: 트라이얼 공부방 종료 → 회원가입(카톡 로그인) 모드 직행

## 개요
현재 공부방(TrialStudyPage) 1분 종료 후 `Store` 화면으로 이동하는데,
이를 `intro_master.dart`의 회원가입 모드(Screen 3-2, `_isSignupMode=true` 뷰 — 카카오톡/구글 로그인 버튼)로 바로 이동하도록 변경한다.

## 설계 방향
- 라우터에 파라미터를 넘기는 방식(nav 파일 수정 필요) 대신, 이미 쓰고 있는 `TrialFlowState` 싱글톤에
  **1회성(consume-once) 플래그**를 추가해서 재사용한다.
- `trial_study_page.dart`에서 Intro로 넘어가기 직전 플래그를 세팅 → `intro_master.dart`의 `initState`에서
  플래그를 소비(consume)하여 `_isSignupMode = true`로 시작하고, 기존 `_checkEntryStatus()`(익명 로그인 유저를
  Lobby로 튕겨버리는 로직) 호출 자체를 건너뛴다. → 별도의 로그인 상태 분기 수정 없이 문제 해결.
- 관련 없는 파일(라우터/nav, `_checkEntryStatus` 내부 로직)은 건드리지 않는다.

## 수정 파일 (4개)
1. `lib/custom_code/widgets/trial/trial_flow_state.dart` — 플래그 필드 + 메서드 2개 추가
2. `lib/custom_code/widgets/trial/trial_study_page.dart` — onTimeUp에서 플래그 세팅 + 목적지 `Intro`로 변경
3. `lib/custom_code/widgets/trial/trial_study_timer_overlay.dart` — 안내 문구 "Moving to Store..." → 수정
4. `lib/custom_code/widgets/intro_master.dart` — initState에서 플래그 소비 분기

---

## Phase 0 — Savepoint

```bash
cd F:\flutter_project\stealth_vox
git add -A
git commit -m "savepoint: 트라이얼 종료 후 회원가입모드 직행 작업 전"
```

## Phase 1 — grep 앵커 사전 검증 (각 기대값 1)

```bash
grep -n "int step = 0;" lib/custom_code/widgets/trial/trial_flow_state.dart
grep -n "TrialFlowState.instance.advanceTo(4);" lib/custom_code/widgets/trial/trial_study_page.dart
grep -n "context.pushReplacementNamed('Store');" lib/custom_code/widgets/trial/trial_study_page.dart
grep -n "'Moving to Store...'," lib/custom_code/widgets/trial/trial_study_timer_overlay.dart
grep -n "WidgetsBinding.instance.addPostFrameCallback((_) => _checkEntryStatus());" lib/custom_code/widgets/intro_master.dart
```

모두 1이 아니면 여기서 중단하고 실장님께 보고.

---

## Phase 2 — str_replace 수정 (파일별 bottom-to-top)

### 2-1. `trial_flow_state.dart`

**edit A (아래쪽 먼저) — 플래그 소비 메서드 추가 (`advanceTo` 뒤, 클래스 닫는 `}` 앞)**

old_str:
```dart
  void advanceTo(int newStep) {
    step = newStep;
    saveToAppState();
  }
}
```

new_str:
```dart
  void advanceTo(int newStep) {
    step = newStep;
    saveToAppState();
  }

  /// 트라이얼 종료 후 Intro 진입 시 회원가입 모드로 바로 시작하도록 요청.
  /// 1회성(consume-once) 플래그 — 소비되는 즉시 false로 리셋됨.
  void requestSignupOnEntry() {
    _forceSignupOnEntry = true;
  }

  bool consumeSignupOnEntry() {
    final requested = _forceSignupOnEntry;
    _forceSignupOnEntry = false;
    return requested;
  }
}
```

**edit B (위쪽) — 플래그 필드 선언**

old_str:
```dart
  DocumentReference? myHistoryRef;
  int step = 0;
```

new_str:
```dart
  DocumentReference? myHistoryRef;
  int step = 0;
  bool _forceSignupOnEntry = false;
```

---

### 2-2. `trial_study_page.dart`

old_str:
```dart
            TrialFlowState.instance.advanceTo(4);
              context.pushReplacementNamed('Store');
```

new_str:
```dart
            TrialFlowState.instance.advanceTo(4);
              TrialFlowState.instance.requestSignupOnEntry();
              context.pushReplacementNamed('Intro');
```

> ⚠️ 원본 파일의 들여쓰기(스페이스 개수)를 그대로 유지할 것. `view`로 재확인 후 old_str 복사 권장.

---

### 2-3. `trial_study_timer_overlay.dart`

old_str:
```dart
              Text(
                'Moving to Store...',
                style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
              ),
```

new_str:
```dart
              Text(
                'Moving to sign up...',
                style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
              ),
```

---

### 2-4. `intro_master.dart`

old_str:
```dart
    AppsFlyerManager.duoInviteSignal.addListener(_onDuoInviteSignal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEntryStatus());
    _initPromoPopup();
```

new_str:
```dart
    AppsFlyerManager.duoInviteSignal.addListener(_onDuoInviteSignal);
    if (TrialFlowState.instance.consumeSignupOnEntry()) {
      _isSignupMode = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkEntryStatus());
    }
    _initPromoPopup();
```

(`TrialFlowState`는 이미 `import 'trial/trial_flow_state.dart';`로 import되어 있음 — import 추가 불필요.)

---

## Phase 3 — 사후 grep 검증

```bash
grep -n "_forceSignupOnEntry" lib/custom_code/widgets/trial/trial_flow_state.dart   # 기대: 3
grep -n "requestSignupOnEntry\|consumeSignupOnEntry" lib/custom_code/widgets/trial/trial_flow_state.dart   # 기대: 4 (선언2+정의2 내부호출포함)
grep -n "pushReplacementNamed('Intro')" lib/custom_code/widgets/trial/trial_study_page.dart   # 기대: 1
grep -n "pushReplacementNamed('Store')" lib/custom_code/widgets/trial/trial_study_page.dart   # 기대: 0
grep -n "Moving to sign up" lib/custom_code/widgets/trial/trial_study_timer_overlay.dart   # 기대: 1
grep -n "consumeSignupOnEntry()" lib/custom_code/widgets/intro_master.dart   # 기대: 1
```

## Phase 4 — 검증

```bash
flutter analyze lib/custom_code/widgets/trial/trial_flow_state.dart
flutter analyze lib/custom_code/widgets/trial/trial_study_page.dart
flutter analyze lib/custom_code/widgets/trial/trial_study_timer_overlay.dart
flutter analyze lib/custom_code/widgets/intro_master.dart

dart format lib/custom_code/widgets/trial/trial_flow_state.dart
dart format lib/custom_code/widgets/trial/trial_study_page.dart
dart format lib/custom_code/widgets/trial/trial_study_timer_overlay.dart
dart format lib/custom_code/widgets/intro_master.dart
```

## Phase 5 — 롤백

```bash
git log --oneline -5   # savepoint 해시 확인
git reset --hard <savepoint_해시>
```
(이미 push된 경우: `git revert <이번_커밋_해시>`)

---



