StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

 ⚙️ AI 작업 규칙
1. 복사붙여넣기: FlutterFlow 웹 에디터에 바로 적용할 수 있게 `import`와 클래스 구조 전체를 제공한다.
2. 디자인: `lib/flutter_flow/flutter_flow_theme.dart`의 테마 변수를 최우선으로 사용한다.
3. 작업 시작 전에 반드시 다음 순서로 진행해 주세요.
1. git status 확인
2. 현재 브랜치 확인
3. 새 작업 브랜치 생성
4. 현재 상태를 백업 커밋
5. 관련 파일 전체 분석
6. 수정 대상 파일과 수정 계획 먼저 요약
7. 코드 수정
8. flutter pub get 실행
9. flutter analyze 실행
10. flutter build apk 실행
11. 오류 발생 시 원인 분석 후 수정 반복
12. 최종적으로 git diff 확인
13. 수정된 파일 목록, 핵심 변경사항, 남은 이슈 보고
주의사항:
- 기존 정상 작동 기능을 깨지 말 것
- FlutterFlow generated code 구조를 함부로 대규모 변경하지 말 것
- 앱 실행/빌드 가능성을 최우선으로 할 것
- 불확실한 부분은 임의 삭제하지 말고 보고할 것

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문

# Claude Code 지시문: clearDuoInviteState() → 인라인 코드로 교체 (FlutterFlow 호환)

## 배경
`FFAppState().clearDuoInviteState()`는 FlutterFlow가 인식하지 못해 컴파일 에러 발생.
아래 인라인 코드로 전부 교체한다:
```dart
FFAppState().isGuestSession = false;
FFAppState().duoRoomId = '';
debugPrint('[AppState] duo invite state cleared');
```

---

## ⚙️ 작업 절차

### 1단계: Git
```bash
git status
git branch
git checkout -b fix/remove-clearDuoInviteState
git add -A
git commit -m "chore: backup before clearDuoInviteState inline replacement"
```

### 2단계: 현재 상태 확인
```bash
grep -n "clearDuoInviteState" \
  lib/app_state.dart \
  lib/custom_code/widgets/routine_mode_duo.dart \
  lib/custom_code/widgets/stealth_room_master.dart
```
각 파일에서 몇 줄에 있는지 확인하고 보고하라.

### 3단계: 코드 수정 (3개 파일)

---

## [파일 1] lib/app_state.dart

### 목적
`clearDuoInviteState()` 메서드 자체를 삭제한다.

아래 블록 전체를 찾아서 **삭제**한다:
```dart
  /// Duo 초대 상태 일괄 초기화 (입장 시도 후 반드시 호출)
  void clearDuoInviteState() {
    _isGuestSession = false;
    _duoRoomId = '';
    prefs.setBool('ff_isGuestSession', false);
    prefs.setString('ff_duoRoomId', '');
    debugPrint('[AppState] clearDuoInviteState called');
  }
```

### 자가 검증 (파일 1)
```bash
grep -n "clearDuoInviteState" lib/app_state.dart
```
**출력이 0줄**이어야 한다.

---

## [파일 2] lib/custom_code/widgets/routine_mode_duo.dart

### 목적
`_joinAsGuest()` 최상단의 `clearDuoInviteState()` 호출을 인라인으로 교체한다.

**기존:**
```dart
  Future<void> _joinAsGuest(String roomId) async {
    // 초대 상태는 진입 시도 직전에 반드시 소비 (좀비 roomId 방지)
    FFAppState().clearDuoInviteState();
```

**교체:**
```dart
  Future<void> _joinAsGuest(String roomId) async {
    // 초대 상태는 진입 시도 직전에 반드시 소비 (좀비 roomId 방지)
    FFAppState().isGuestSession = false;
    FFAppState().duoRoomId = '';
    debugPrint('[AppState] duo invite state cleared');
```

### 자가 검증 (파일 2)
```bash
grep -n "clearDuoInviteState\|duo invite state cleared" lib/custom_code/widgets/routine_mode_duo.dart
```
- `clearDuoInviteState` : **0회**
- `duo invite state cleared` : 1회 이상

---

## [파일 3] lib/custom_code/widgets/stealth_room_master.dart

### 목적
`initState`의 `clearDuoInviteState()` 호출을 인라인으로 교체한다.

**기존:**
```dart
      final String consumedRoomId = FFAppState().duoRoomId;
      FFAppState().clearDuoInviteState(); // 즉시 소비!
      debugPrint('[StealthRoom] Duo invite detected — roomId: $consumedRoomId');
```

**교체:**
```dart
      final String consumedRoomId = FFAppState().duoRoomId;
      FFAppState().isGuestSession = false;
      FFAppState().duoRoomId = '';
      debugPrint('[AppState] duo invite state cleared');
      debugPrint('[StealthRoom] Duo invite detected — roomId: $consumedRoomId');
```

### 자가 검증 (파일 3)
```bash
grep -n "clearDuoInviteState\|duo invite state cleared\|consumedRoomId" lib/custom_code/widgets/stealth_room_master.dart
```
- `clearDuoInviteState` : **0회**
- `duo invite state cleared` : 1회
- `consumedRoomId` : 2회 이상

---

## 4단계: 전체 검증
```bash
grep -rn "clearDuoInviteState" lib/
```
**출력이 0줄**이어야 한다. 한 줄이라도 남아있으면 찾아서 위 방식으로 교체하라.

---

## 5단계: 빌드 검증
```bash
flutter pub get
flutter analyze \
  lib/app_state.dart \
  lib/custom_code/widgets/routine_mode_duo.dart \
  lib/custom_code/widgets/stealth_room_master.dart
flutter build apk --debug
```
에러 0개, 빌드 성공 필수.
실패 시 원인 분석 후 수정 (최대 3회).

---

## 6단계: 커밋
```bash
git add -A
git commit -m "fix: replace clearDuoInviteState() with inline code for FlutterFlow compatibility"
git diff HEAD~1
```

---

## 7단계: 보고
- 수정된 파일 목록
- 각 파일 변경 줄 수
- flutter analyze 결과
- flutter build 결과
- 남은 이슈

---

## ⚠️ 주의사항
- 3개 파일 외 건드리지 않는다
- `_pendingDuoRoomId`, `_joinAsGuest`, `initState` 등 다른 로직은 수정하지 않는다
- FlutterFlow import 블록 건드리지 않는다
- 불확실한 부분은 보고하라