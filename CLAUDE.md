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

# Claude Code 지시문: 스텔스룸 → Duo 자동 라우팅 추가

## 작업 절차

### 1단계: Git 상태 확인 및 브랜치
```bash
git status
git branch
git checkout -b fix/stealth-room-duo-auto-route
git add -A
git commit -m "chore: backup before stealth room duo auto-route fix"
```

### 2단계: 파일 확인
```bash
grep -n "initState\|_currentMode\|exitCurrentMode" lib/custom_code/widgets/stealth_room_master.dart
```
아래 패턴이 보여야 한다:
- `initState` 1회
- `_currentMode` 여러 회
- `exitCurrentMode` 2회

파일이 없으면 중단하고 보고하라.

### 3단계: 코드 수정 (1곳만)

아래 기존 코드를 찾아라:
```dart
  @override
  void initState() {
    super.initState();
    StealthRoomMaster.exitCurrentMode =
        () => setState(() => _currentMode = null);
  }
```

아래로 교체한다:
```dart
  @override
  void initState() {
    super.initState();
    StealthRoomMaster.exitCurrentMode =
        () => setState(() => _currentMode = null);

    // Duo 초대 링크로 진입한 경우 메뉴 없이 바로 Duo로 이동
    if (FFAppState().isGuestSession &&
        FFAppState().duoRoomId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _currentMode = 1);
        }
      });
    }
  }
```

### 4단계: 자가 검증
```bash
grep -n "isGuestSession\|duoRoomId\|addPostFrameCallback" lib/custom_code/widgets/stealth_room_master.dart
```
세 키워드 모두 1회 이상 출력되어야 한다.

### 5단계: 빌드 검증
```bash
flutter pub get
flutter analyze lib/custom_code/widgets/stealth_room_master.dart
flutter build apk --debug
```
에러 0개, 빌드 성공 필수.
오류 시 원인 분석 후 수정 반복 (최대 3회).

### 6단계: 최종 커밋
```bash
git add -A
git commit -m "fix: auto-route to Duo when guest invite link is opened"
git diff HEAD~1
```

### 7단계: 보고
- 수정된 파일 및 변경 내용
- flutter analyze 결과
- flutter build apk 결과
- 남은 이슈

---

## 주의사항
- `stealth_room_master.dart` 외 다른 파일은 건드리지 않는다
- `_buildMenu()`, `_switchMode()`, `build()` 등 기존 로직은 절대 수정하지 않는다
- FlutterFlow import 블록(`// DO NOT REMOVE`) 건드리지 않는다
- 불확실한 부분은 임의 수정하지 말고 보고한다