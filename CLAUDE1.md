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

# Claude Code 지시문: Duo 초대 흐름 안정화 (v1)

## 배경
정식 앱에서 신규 사용자가 초대 링크 → 설치 → Duo 자동 진입하는 흐름에서, FFAppState 초대 상태를 Firestore 성공 확인 전에 삭제하여 실패 시 재시도가 불가능한 문제가 있다. 파싱 방어코드 부족 및 실패 시 UI 복귀 누락도 함께 수정한다.

## 수정 대상 파일 (4개)
1. `stealth_room_master.dart`
2. `routine_mode_duo.dart`
3. `intro_master.dart`
4. `lobby_master.dart`

## 절대 규칙
- Box 7 (TtsQueueManager, DeepgramV2VoiceManager) 코드는 절대 수정하지 않는다
- URL을 마크다운 링크 형태 `[text](url)`로 변환하지 않는다
- 작은따옴표 이스케이프 에러(`\'`) 주의 — 프롬프트 문자열은 큰따옴표 또는 삼중따옴표 사용
- 수정하지 않는 코드는 원본 그대로 유지한다

---

## 변경 블록 ①: stealth_room_master.dart — 초대 상태 삭제 제거

### 위치
`initState()` 내부, 53~69줄 부근

### 현재 코드 (삭제 대상 포함)
```dart
    // Duo 초대 링크 자동 진입 처리
    // roomId를 로컬 변수에 옮기고 FFAppState는 즉시 clear → 뒤로가기 루프 방지
    if (FFAppState().isGuestSession &&
        FFAppState().duoRoomId.isNotEmpty) {
      final String consumedRoomId = FFAppState().duoRoomId;
      FFAppState().isGuestSession = false;
      FFAppState().duoRoomId = '';
      debugPrint('[AppState] duo invite state cleared');
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
```

### 교체 코드
```dart
    // Duo 초대 링크 자동 진입 처리
    // FFAppState 초대 상태는 여기서 지우지 않음 — _joinAsGuest 성공 후에만 삭제
    if (FFAppState().isGuestSession &&
        FFAppState().duoRoomId.isNotEmpty) {
      final String consumedRoomId = FFAppState().duoRoomId;
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
```

### 변경 요약
- `FFAppState().isGuestSession = false;` 삭제
- `FFAppState().duoRoomId = '';` 삭제
- `debugPrint('[AppState] duo invite state cleared');` 삭제
- 주석을 "여기서 지우지 않음 — _joinAsGuest 성공 후에만 삭제"로 변경
- 나머지 로직(consumedRoomId 추출, postFrameCallback, setState)은 그대로 유지

---

## 변경 블록 ②: routine_mode_duo.dart — 초대 상태 삭제를 성공 후로 이동

### 위치 A: `_joinAsGuest()` 함수 내부, 583~635줄 부근

### 현재 코드
```dart
  Future<void> _joinAsGuest(String roomId) async {
    // 초대 상태는 진입 시도 직전에 반드시 소비 (좀비 roomId 방지)
    FFAppState().isGuestSession = false;
    FFAppState().duoRoomId = '';
    debugPrint('[AppState] duo invite state cleared');

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

### 교체 코드
```dart
  Future<void> _joinAsGuest(String roomId) async {
    // 초대 상태는 여기서 지우지 않음 — Firestore 업데이트 성공 후에만 삭제
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
          StealthRoomMaster.exitCurrentMode?.call();
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
          StealthRoomMaster.exitCurrentMode?.call();
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

      // 입장 성공 후에만 초대 상태 정리 (3개 세트)
      FFAppState().isGuestSession = false;
      FFAppState().duoRoomId = '';
      FFAppState().pendingInviteType = '';
      debugPrint('[AppState] duo invite state cleared (after successful join)');

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연결 중 오류가 발생했습니다. 다시 시도해주세요.')),
        );
        StealthRoomMaster.exitCurrentMode?.call();
      }
    }
  }
```

### 변경 요약
- 함수 시작부의 FFAppState 삭제 3줄 제거 (585~587줄)
- Firestore `update()` 성공 직후(621줄 뒤)에 3개 세트 삭제 이동:
  - `FFAppState().isGuestSession = false;`
  - `FFAppState().duoRoomId = '';`
  - `FFAppState().pendingInviteType = '';` ← 신규 추가
- 실패 분기 3곳(snap 없음, isDuoEnabled 아님, catch)에 `StealthRoomMaster.exitCurrentMode?.call()` 추가 → 메뉴 복귀
- catch 블록에 사용자용 SnackBar 추가

---

## 변경 블록 ③: intro_master.dart — roomId 파싱에 duo_room_id 후보 추가

### 위치
`_handleInviteDeepLink()` 내부, 113~118줄 부근

### 현재 코드
```dart
    final String? roomId = params['deep_link_sub2']?.toString() ??
        deepLinkData['deep_link_sub2']?.toString() ??
        params['room_id']?.toString() ??
        deepLinkData['room_id']?.toString() ??
        params['roomId']?.toString() ??
        params['af_sub2']?.toString();
```

### 교체 코드
```dart
    final String? roomId = params['deep_link_sub2']?.toString() ??
        deepLinkData['deep_link_sub2']?.toString() ??
        params['room_id']?.toString() ??
        deepLinkData['room_id']?.toString() ??
        params['duo_room_id']?.toString() ??
        deepLinkData['duo_room_id']?.toString() ??
        params['duoRoomId']?.toString() ??
        deepLinkData['duoRoomId']?.toString() ??
        params['roomId']?.toString() ??
        params['af_sub2']?.toString();
```

### 변경 요약
- `params['roomId']` 앞에 4줄 추가:
  - `params['duo_room_id']`
  - `deepLinkData['duo_room_id']`
  - `params['duoRoomId']`
  - `deepLinkData['duoRoomId']`
- 기존 후보 순서는 유지하되, `duo_room_id` 계열을 `room_id` 바로 뒤에 배치

---

## 변경 블록 ④: lobby_master.dart — roomId 파싱에 duo_room_id 후보 추가

### 위치
`_handleInviteDeepLink()` 내부, 207~212줄 부근

### 현재 코드
```dart
    final String? roomId = params['deep_link_sub2']?.toString() ??
        deepLinkData['deep_link_sub2']?.toString() ??
        params['room_id']?.toString() ??
        deepLinkData['room_id']?.toString() ??
        params['roomId']?.toString() ??
        params['af_sub2']?.toString();
```

### 교체 코드
```dart
    final String? roomId = params['deep_link_sub2']?.toString() ??
        deepLinkData['deep_link_sub2']?.toString() ??
        params['room_id']?.toString() ??
        deepLinkData['room_id']?.toString() ??
        params['duo_room_id']?.toString() ??
        deepLinkData['duo_room_id']?.toString() ??
        params['duoRoomId']?.toString() ??
        deepLinkData['duoRoomId']?.toString() ??
        params['roomId']?.toString() ??
        params['af_sub2']?.toString();
```

### 변경 요약
- 블록 ③과 동일한 4줄 추가
- 위치만 lobby_master.dart의 해당 함수

---

## 검증 체크리스트

Claude Code가 수정 완료 후 아래 항목을 확인해야 한다:

1. **StealthRoom initState에서 FFAppState 삭제 코드가 없어졌는지 확인**
   - `FFAppState().isGuestSession = false` 가 initState 안에 없어야 함
   - `FFAppState().duoRoomId = ''` 가 initState 안에 없어야 함

2. **Duo _joinAsGuest에서 삭제 위치가 update() 성공 직후인지 확인**
   - `_duoSessionRef!.update({...})` 다음 줄에 3개 세트가 와야 함
   - 함수 시작부에 삭제 코드가 없어야 함

3. **pendingInviteType 정리가 추가되었는지 확인**
   - `FFAppState().pendingInviteType = '';` 가 isGuestSession, duoRoomId와 함께 있어야 함

4. **실패 분기 3곳에 exitCurrentMode 호출이 있는지 확인**
   - `!snap.exists` 분기
   - `isDuoEnabled != true` 분기
   - `catch (e)` 블록

5. **Intro와 Lobby 양쪽에서 roomId 파싱에 duo_room_id, duoRoomId가 추가되었는지 확인**
   - 각 파일의 `_handleInviteDeepLink` 함수 내부

6. **컴파일 에러 없는지 확인**
   - `StealthRoomMaster.exitCurrentMode` 는 이미 static nullable 함수로 선언되어 있으므로 import만 확인
   - routine_mode_duo.dart 상단 import에 stealth_room_master 관련 import가 있는지 확인 (같은 index.dart에서 가져오므로 추가 import 불필요)

---

## 이 지시문에서 수정하지 않는 것

- AppsFlyerManager 공용화 (4순위 — 구조 변경이 크므로 별도 작업)
- Box 7 통신 엔진 전체
- Duo 모드의 Whisper/TTS/오디오 관련 코드
- Intro/Lobby의 UI 코드
- createDuoInviteLink 함수 (링크 생성 쪽은 현재 문제 없음)