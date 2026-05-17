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

# Claude Code 지시문: Duo 초대 링크 상태 관리 수정 (3파일)

## 배경

Duo 초대 링크 클릭 시 아래 문제가 발생하고 있다:
1. 만료된 방 roomId가 SharedPreferences에 남아서 앱 재실행 시 죽은 방으로 계속 진입
2. 스텔스룸에서 Duo 자동 진입 후 뒤로가기하면 다시 Duo로 튀는 무한 루프 위험
3. `_joinAsGuest()` 실패 시 상태가 안 지워져서 좀비 roomId 잔류

핵심 원칙: **roomId는 1회 소비 토큰처럼 취급한다. 읽으면 즉시 지운다.**

---

## ⚙️ 작업 절차

### 1단계: Git
```bash
git status
git branch
git checkout -b fix/duo-invite-state-cleanup
git add -A
git commit -m "chore: backup before duo invite state cleanup"
```

### 2단계: 파일 확인
아래 3개 파일을 전체 읽고 현재 상태를 보고하라.
```
lib/app_state.dart
lib/custom_code/widgets/routine_mode_duo.dart
lib/custom_code/widgets/stealth_room_master.dart
```
파일이 없으면 즉시 중단하라.

### 3단계: 수정 계획 보고 (코드 수정 전)
아래 3개 파일의 수정 사항을 요약 보고 후 진행하라.

### 4단계: 코드 수정 (순서 엄수)
파일 1 → 2 → 3 순서대로 진행. 각 파일 수정 후 자가 검증.

### 5단계: 빌드 검증
```bash
flutter pub get
flutter analyze lib/app_state.dart \
  lib/custom_code/widgets/routine_mode_duo.dart \
  lib/custom_code/widgets/stealth_room_master.dart
flutter build apk --debug
```
에러 0개, 빌드 성공 필수.
오류 시 원인 분석 후 수정 (최대 3회).
3회 후에도 해결 안 되면 중단하고 보고.

### 6단계: Git 확인 및 커밋
```bash
git diff
git add -A
git commit -m "fix: duo invite state cleanup - prevent zombie roomId and auto-route loop"
```

### 7단계: 보고
- 수정된 파일, 핵심 변경, analyze 결과, build 결과, 남은 이슈

---

## ⚠️ 주의사항

1. 기존 정상 작동 기능을 깨지 말 것
2. FlutterFlow import 블록(`// DO NOT REMOVE`) 절대 수정 금지
3. 수정 대상이 아닌 함수는 건드리지 말 것
4. 불확실한 부분은 임의 삭제하지 말고 보고할 것
5. `_shareInviteCode()`, `_buildMenu()`, `build()` 등 기존 로직은 건드리지 않는다

---

## [파일 1] lib/app_state.dart — 3곳 수정

### 목적
`isGuestSession`과 `duoRoomId`를 SharedPreferences에 영속 저장하고,
`clearDuoInviteState()` 메서드를 추가한다.

### 변경 1-A: `initializePersistedState()` 내부에 2블록 추가

기존 코드를 찾아라:
```dart
    _safeInit(() {
      _inviterUid = prefs.getString('ff_inviterUid') ?? _inviterUid;
    });
  }
```

`_inviterUid` 블록 다음, 함수 닫는 `}` 바로 앞에 삽입:

```dart
    _safeInit(() {
      _isGuestSession = prefs.getBool('ff_isGuestSession') ?? _isGuestSession;
    });
    _safeInit(() {
      _duoRoomId = prefs.getString('ff_duoRoomId') ?? _duoRoomId;
    });
```

### 변경 1-B: `isGuestSession` setter 교체

기존:
```dart
  bool _isGuestSession = false;
  bool get isGuestSession => _isGuestSession;
  set isGuestSession(bool value) {
    _isGuestSession = value;
  }
```

교체:
```dart
  bool _isGuestSession = false;
  bool get isGuestSession => _isGuestSession;
  set isGuestSession(bool value) {
    _isGuestSession = value;
    prefs.setBool('ff_isGuestSession', value);
  }
```

### 변경 1-C: `duoRoomId` 블록 + `clearDuoInviteState()` 교체

기존 (클래스 마지막 부분):
```dart
  String _duoRoomId = '';
  String get duoRoomId => _duoRoomId;
  set duoRoomId(String value) {
    _duoRoomId = value;
  }
}
```

교체 (클래스 닫는 `}` 포함):
```dart
  String _duoRoomId = '';
  String get duoRoomId => _duoRoomId;
  set duoRoomId(String value) {
    _duoRoomId = value;
    prefs.setString('ff_duoRoomId', value);
  }

  /// Duo 초대 상태 일괄 초기화 (입장 시도 후 반드시 호출)
  void clearDuoInviteState() {
    _isGuestSession = false;
    _duoRoomId = '';
    prefs.setBool('ff_isGuestSession', false);
    prefs.setString('ff_duoRoomId', '');
    debugPrint('[AppState] clearDuoInviteState called');
  }
}
```

### 자가 검증 (파일 1)
```bash
grep -n "ff_isGuestSession\|ff_duoRoomId\|clearDuoInviteState" lib/app_state.dart
```
`ff_isGuestSession` 2회 이상, `ff_duoRoomId` 2회 이상, `clearDuoInviteState` 1회 이상.

---

## [파일 2] lib/custom_code/widgets/routine_mode_duo.dart — 2곳 수정

### 목적
`_joinAsGuest()` 실패 시에도 반드시 상태를 정리하여 좀비 roomId를 방지한다.
initState 게스트 체크 로직은 유지하되 clear 타이밍을 안전하게 한다.

### 변경 2-A: `_joinAsGuest()` 전체 교체

**기존** (줄 569~600):
```dart
  Future<void> _joinAsGuest(String roomId) async {
    try {
      _duoSessionRef =
          FirebaseFirestore.instance.collection('duo_sessions').doc(roomId);
      final snap = await _duoSessionRef!.get();
      if (!snap.exists) {
        debugPrint('[Duo] _joinAsGuest: session not found ($roomId)');
        return;
      }
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null || data['isDuoEnabled'] != true) {
        debugPrint('[Duo] _joinAsGuest: isDuoEnabled is not true ($roomId)');
        return;
      }
      await _duoSessionRef!.update({
        'isPartnerJoined': true,
        'partnerUid': FirebaseAuth.instance.currentUser?.uid,
        'partnerJoinedAt': FieldValue.serverTimestamp(),
      });
      FFAppState().isGuestSession = false;
      FFAppState().duoRoomId = '';
      if (mounted) {
        setState(() {
          _isConversationActive = true;
          _isPartnerOnline = true;
        });
      }
      _startWhisperRecording();
    } catch (e) {
      debugPrint('[Duo] Guest join error: $e');
    }
  }
```

**교체:**
```dart
  Future<void> _joinAsGuest(String roomId) async {
    // 초대 상태는 진입 시도 직전에 반드시 소비 (좀비 roomId 방지)
    FFAppState().clearDuoInviteState();

    try {
      _duoSessionRef =
          FirebaseFirestore.instance.collection('duo_sessions').doc(roomId);
      final snap = await _duoSessionRef!.get();
      if (!snap.exists) {
        debugPrint('[Duo] _joinAsGuest: session not found ($roomId)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('초대된 방을 찾을 수 없습니다.')),
          );
        }
        return;
      }
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null || data['isDuoEnabled'] != true) {
        debugPrint('[Duo] _joinAsGuest: isDuoEnabled is not true ($roomId)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이 방은 현재 사용할 수 없습니다.')),
          );
        }
        return;
      }

      final String? firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      final String guestUid =
          firebaseUid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';

      await _duoSessionRef!.update({
        'isPartnerJoined': true,
        'partnerUid': guestUid,
        'partnerJoinedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[Duo] _joinAsGuest success — guestUid: $guestUid, roomId: $roomId');

      if (mounted) {
        setState(() {
          _isConversationActive = true;
          _isPartnerOnline = true;
        });
      }
      _startWhisperRecording();
    } catch (e) {
      debugPrint('[Duo] Guest join error: $e');
    }
  }
```

핵심 변경:
- 함수 최상단에서 `clearDuoInviteState()` 즉시 호출 (성공/실패 무관하게 1회 소비)
- 실패 시 사용자에게 SnackBar로 안내
- 비로그인 게스트용 guestUid 폴백 추가

### 변경 2-B: `initState` 게스트 체크 로직 개선

**기존** (줄 106~111):
```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FFAppState().isGuestSession == true &&
          FFAppState().duoRoomId.isNotEmpty) {
        _joinAsGuest(FFAppState().duoRoomId);
      }
    });
```

**교체:**
```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // widget.roomId 우선, 없으면 FFAppState에서 읽기
      final String? pendingRoomId =
          (widget.roomId != null && widget.roomId!.isNotEmpty)
              ? widget.roomId
              : (FFAppState().isGuestSession &&
                      FFAppState().duoRoomId.isNotEmpty
                  ? FFAppState().duoRoomId
                  : null);
      if (pendingRoomId != null) {
        debugPrint('[Duo] initState — auto joining as guest, roomId: $pendingRoomId');
        _joinAsGuest(pendingRoomId);
      }
    });
```

### 자가 검증 (파일 2)
```bash
grep -n "clearDuoInviteState\|guestUid\|pendingRoomId\|찾을 수 없습니다\|사용할 수 없습니다" lib/custom_code/widgets/routine_mode_duo.dart
```
각 키워드 1회 이상 출력.

---

## [파일 3] lib/custom_code/widgets/stealth_room_master.dart — 2곳 수정

### 목적
초대 링크로 진입 시 메뉴 건너뛰고 Duo로 자동 이동하되,
roomId를 **읽자마자 즉시 소비**하여 뒤로가기 무한 루프를 방지한다.

### 변경 3-A: 상태 변수 1개 추가

**기존** (줄 43~44):
```dart
  // 0: 메뉴 화면, 1: Duo, 2: Clone, 3: Roleplay, 4: Expand
  int? _currentMode;
```

**교체:**
```dart
  // 0: 메뉴 화면, 1: Duo, 2: Clone, 3: Roleplay, 4: Expand
  int? _currentMode;

  // 초대 링크에서 소비한 roomId (1회용 — build에서 Duo 생성자에 전달)
  String? _pendingDuoRoomId;
```

### 변경 3-B: initState 교체

**기존** (줄 45~49):
```dart
  @override
  void initState() {
    super.initState();
    StealthRoomMaster.exitCurrentMode =
        () => setState(() => _currentMode = null);
  }
```

**교체:**
```dart
  @override
  void initState() {
    super.initState();
    StealthRoomMaster.exitCurrentMode =
        () => setState(() => _currentMode = null);

    // Duo 초대 링크 자동 진입 처리
    // roomId를 로컬 변수에 옮기고 FFAppState는 즉시 clear → 뒤로가기 루프 방지
    if (FFAppState().isGuestSession &&
        FFAppState().duoRoomId.isNotEmpty) {
      final String consumedRoomId = FFAppState().duoRoomId;
      FFAppState().clearDuoInviteState(); // 즉시 소비!
      debugPrint('[StealthRoom] Duo invite detected — roomId: $consumedRoomId');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _pendingDuoRoomId = consumedRoomId;
            _currentMode = 1;
          });
        }
      });
    }
  }
```

### 변경 3-C: build()에서 Duo 생성자에 roomId 전달

**기존** (줄 184~188):
```dart
    if (_currentMode == 1) {
      return RoutineModeDuo(
          key: const ValueKey('RoutineModeDuo'),
          width: widget.width,
          height: widget.height);
```

**교체:**
```dart
    if (_currentMode == 1) {
      return RoutineModeDuo(
          key: const ValueKey('RoutineModeDuo'),
          width: widget.width,
          height: widget.height,
          roomId: _pendingDuoRoomId);
```

주의: `_pendingDuoRoomId`는 초대 링크 진입 시에만 값이 있고,
일반 Duo Connect 카드 클릭 시에는 null이다. 이것이 의도된 동작이다.

### 자가 검증 (파일 3)
```bash
grep -n "_pendingDuoRoomId\|clearDuoInviteState\|consumedRoomId\|roomId:" lib/custom_code/widgets/stealth_room_master.dart
```
`_pendingDuoRoomId` 3회 이상, `clearDuoInviteState` 1회, `consumedRoomId` 2회.

---

## 수정 후 전체 흐름 검증

### 정상 케이스 (초대 링크 클릭)
```
링크 클릭
→ AppsFlyer → FFAppState.duoRoomId 저장
→ 앱 열림 → 로비 → ENTER
→ StealthRoom initState
→ duoRoomId 읽고 즉시 clear (1회 소비!)
→ _pendingDuoRoomId에 보관
→ _currentMode = 1 → Duo 위젯 생성 (roomId 전달)
→ Duo initState → _joinAsGuest(roomId) 실행
→ 성공 시 대화 시작 / 실패 시 SnackBar 안내
```

### 뒤로가기 케이스 (루프 방지 확인)
```
Duo 방 진입 후 뒤로가기
→ StealthRoom 메뉴로 돌아감
→ FFAppState.duoRoomId은 이미 '' (clear됨)
→ 자동 진입 조건 불충족
→ 메뉴 정상 표시 ✅
```

### 만료된 방 케이스 (좀비 roomId 방지 확인)
```
어제 링크 → roomId 저장됨
→ 오늘 앱 실행 → StealthRoom initState
→ duoRoomId 읽고 즉시 clear
→ Duo 진입 → _joinAsGuest 실행
→ Firestore 방 없음 → SnackBar "초대된 방을 찾을 수 없습니다"
→ 뒤로가기 → 메뉴 정상 ✅
→ FFAppState는 이미 깨끗 ✅
```

---

## 건드리지 않는 파일

- `appsflyermanager.dart` — 이번 작업 범위 아님
- `init_apps_flyer.dart` — 이번 작업 범위 아님
- `AndroidManifest.xml` — 이미 정상
- `MainActivity.kt` — 이미 정상
- `_shareInviteCode()` — 이번 작업 범위 아님

---

## 테스트 시나리오 (수정 후 확인)

### 테스트 1: 일반 모드 진입 (기존 기능 정상 확인)
1. 스텔스룸에서 Clone AI, Roleplay, Step Expand 각각 클릭
2. 정상 진입되는지 확인
3. 뒤로가기 시 메뉴로 돌아오는지 확인

### 테스트 2: Duo 일반 진입 (호스트)
1. 스텔스룸에서 Duo Connect 클릭
2. 정상 진입되는지 확인
3. 초대 버튼 클릭 → 링크 생성 확인

### 테스트 3: 초대 링크 자동 입장
1. 초대 링크를 나에게 전송
2. 링크 클릭
3. 메뉴 건너뛰고 바로 Duo 진입되는지 확인
4. 뒤로가기 시 메뉴로 돌아오는지 확인 (다시 Duo로 안 튀는지!)

### 테스트 4: 만료된 링크
1. 앱 완전 종료
2. 어제 링크 다시 클릭
3. SnackBar "초대된 방을 찾을 수 없습니다" 표시 확인
4. 메뉴에서 다른 모드 정상 진입 가능한지 확인