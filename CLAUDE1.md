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

# 수정 지시문: 카카오 로그인 후 로비 잔여시간 00:00 플래시 수정

## 증상
- 로그아웃 → 카카오 로그인 → 로비에서 잔여시간이 **00:00으로 잠깐 표시**된 후, 다른 방 이동 시 정상 복구
- Google 로그인은 정상 (플래시 없음)

## 원인
`lobby_master.dart`의 `_initializeLobbyData()`가 **`remainingTimeLoaded = false`를 무조건 리셋**하여, `_grantSignupBonusIfPossible()`에서 이미 세팅된 올바른 값을 덮어쓴다. Firestore 조회가 완료될 때까지 UI가 00:00을 표시한다.

## 수정 대상 파일
- `lib/custom_code/widgets/lobby_master.dart` (1곳)

---

## Phase 1: Git Savepoint

```powershell
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before kakao lobby time flash fix"
```

---

## Phase 2: Grep Anchor Validation

```powershell
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern "FFAppState\(\)\.remainingTimeLoaded = false;" | Measure-Object | Select-Object -ExpandProperty Count
```

**기대값: 1** (line 123 한 곳)

```powershell
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern "isLoading = true;" | Measure-Object | Select-Object -ExpandProperty Count
```

**기대값: 1 이상** (최소 line 122)

---

## Phase 3: str_replace 편집

### Edit 1: `_initializeLobbyData`에서 `remainingTimeLoaded = false` 리셋 제거 + 디버그 로그 추가

**파일:** `lib/custom_code/widgets/lobby_master.dart`

**BEFORE:**
```dart
  Future<void> _initializeLobbyData() async {
    setState(() {
      isLoading = true;
      FFAppState().remainingTimeLoaded = false;
    });
    try {
      // 1. DB 통신 분리: 서버 시간 및 남은 시간 동기화
      int? serverRemainingTime =
          await LobbyBrain.getRemainingTime(FirebaseAuth.instance.currentUser);
      if (mounted) {
        setState(() {
          if (serverRemainingTime != null) {
            FFAppState().remainingTime = serverRemainingTime;
          }
          FFAppState().remainingTimeLoaded = true;
        });
      }
```

**AFTER:**
```dart
  Future<void> _initializeLobbyData() async {
    final alreadyLoaded = FFAppState().remainingTimeLoaded;
    debugPrint('[Lobby] _initializeLobbyData enter, alreadyLoaded=$alreadyLoaded, remainingTime=${FFAppState().remainingTime}');
    setState(() {
      isLoading = true;
    });
    try {
      // 1. DB 통신 분리: 서버 시간 및 남은 시간 동기화
      int? serverRemainingTime =
          await LobbyBrain.getRemainingTime(FirebaseAuth.instance.currentUser);
      debugPrint('[Lobby] Firestore remainingTime=$serverRemainingTime');
      if (mounted) {
        setState(() {
          if (serverRemainingTime != null) {
            FFAppState().remainingTime = serverRemainingTime;
          }
          FFAppState().remainingTimeLoaded = true;
        });
      }
```

---

## Phase 4: Grep 검증

### 4-1. 삭제 확인 — `remainingTimeLoaded = false` 가 lobby_master에서 0건

```powershell
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern "remainingTimeLoaded = false" | Measure-Object | Select-Object -ExpandProperty Count
```

**기대값: 0**

### 4-2. 추가 확인 — `alreadyLoaded` 변수 존재

```powershell
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern "alreadyLoaded" | Measure-Object | Select-Object -ExpandProperty Count
```

**기대값: 2** (선언 1 + debugPrint 1)

### 4-3. 추가 확인 — `remainingTimeLoaded = true` 유지

```powershell
Select-String -Path "lib\custom_code\widgets\lobby_master.dart" -Pattern "remainingTimeLoaded = true" | Measure-Object | Select-Object -ExpandProperty Count
```

**기대값: 2** (try 블록 내 1 + catch 블록 내 1)

---

## Phase 5: 빌드 & 포맷

```powershell
dart format lib\custom_code\widgets\lobby_master.dart
flutter analyze
```

---

## Phase 6: 커밋 & 푸시

```powershell
git add -A && git commit -m "fix: remove remainingTimeLoaded=false reset in _initializeLobbyData to prevent 00:00 flash on Kakao login"
git push origin main
```

---

## Phase 7: 롤백 절차

```powershell
git revert HEAD --no-edit
git push origin main
```

---

## 검증 시나리오 (실장 수동 테스트)

1. **카카오 로그인 테스트:** 로그아웃 → 카카오 로그인 → 로비 진입 시 잔여시간이 **00:00 없이 즉시 정상 표시**되는지 확인
2. **Google 로그인 테스트:** 로그아웃 → Google 로그인 → 로비 진입 시 잔여시간 정상 표시 (기존 동작 유지)
3. **신규 가입 테스트:** 새 계정으로 가입 → `grantSignupBonus` 후 로비 진입 → 보너스 시간 즉시 표시
4. **adb logcat 확인:** `[Lobby] _initializeLobbyData enter` 로그에서 `alreadyLoaded=true` 확인