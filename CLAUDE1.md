StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

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

씨앗 기능이 항상 뉴스 소재로 폴백되는 버그를 수정합니다.
원인: 씨앗 조회는 chat_history 방 문서에서 'mode' 필드로 필터하는데,
'mode' 필드는 sessions 컬렉션에만 저장되고 chat_history 방 문서에는 없어서 쿼리 결과가 항상 0개였음.

해결 (A+B 병행):
  A) 앞으로 만드는 chat_history 방 문서에 'mode' 필드를 박는다. (step_expand, clone 양쪽)
  B) 씨앗 조회는 'mode' 필터를 제거하고, mode 또는 room_name 둘 다로 판정하여 기존 방까지 커버한다.

대상 파일: routine_mode_step_expand.dart, routine_mode_clone.dart

[절대 건드리지 말 것]
- sessions 컬렉션 저장 로직 (거기 'mode'는 그대로 둠 — 훈련 분석용)
- 5턴 구조, 최종 합성, Part1/Part2, Box 7 엔진
- 씨앗 프롬프트(seedSysPrompt, newcomerSysPrompt) 텍스트 자체

──────────────────────────────────────────────
[수정 A-1] routine_mode_step_expand.dart — _ensureHistoryRef 방 생성에 mode 추가
──────────────────────────────────────────────

기존 (chat_history 방 set):
      await _myHistoryRef!.set({
        'created_at': FieldValue.serverTimestamp(),
        'room_name': "Step.Ex Mode",
        'is_pinned': false,
        'msg_count': 0
      });

교체:
      await _myHistoryRef!.set({
        'created_at': FieldValue.serverTimestamp(),
        'room_name': "Step.Ex Mode",
        'mode': 'step_expand',
        'is_pinned': false,
        'msg_count': 0
      });

──────────────────────────────────────────────
[수정 A-2] routine_mode_clone.dart — _ensureHistoryRef 방 생성에 mode 추가
──────────────────────────────────────────────

기존:
      await _myHistoryRef!.set({
        'created_at': FieldValue.serverTimestamp(),
        'room_name': "Clone Mode",
        'is_pinned': false,
        'msg_count': 0
      });

교체:
      await _myHistoryRef!.set({
        'created_at': FieldValue.serverTimestamp(),
        'room_name': "Clone Mode",
        'mode': 'clone',
        'is_pinned': false,
        'msg_count': 0
      });

──────────────────────────────────────────────
[수정 B] routine_mode_step_expand.dart — _fetchRandomPastUserLine 조회 로직을 mode+room_name 병행 판정으로 교체
──────────────────────────────────────────────

기존 (whereIn 쿼리 부분):
      final historySnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .where('mode', whereIn: ['step_expand', 'clone'])
          .limit(20)
          .get()
          .timeout(const Duration(seconds: 4));

      final List<String> candidates = [];
      for (final roomDoc in historySnap.docs) {
        if (_myHistoryRef != null && roomDoc.reference.id == _myHistoryRef!.id) {
          continue;
        }

교체 (mode 필터 제거 → 최근순 가져온 뒤 클라이언트에서 mode/room_name 둘 다로 판정):
      // 🔧 [SEED-FIX] mode 필드가 없는 과거 방까지 커버하기 위해
      //   서버 필터 없이 최근 방을 가져와 클라이언트에서 mode 또는 room_name으로 판정
      final historySnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .orderBy('created_at', descending: true)
          .limit(30)
          .get()
          .timeout(const Duration(seconds: 4));

      bool _isSeedSourceRoom(Map<String, dynamic> data) {
        final String mode = (data['mode'] ?? '').toString();
        final String roomName = (data['room_name'] ?? '').toString();
        // A 경로: mode 필드가 박힌 새 방
        if (mode == 'step_expand' || mode == 'clone') return true;
        // B 경로: mode 없는 기존 방 → room_name으로 판정
        if (roomName.contains('Step.Ex') || roomName.contains('Clone')) {
          return true;
        }
        return false;
      }

      final List<String> candidates = [];
      for (final roomDoc in historySnap.docs) {
        if (_myHistoryRef != null && roomDoc.reference.id == _myHistoryRef!.id) {
          continue;
        }
        // step_expand / clone 방만 씨앗 소스로 사용
        if (!_isSeedSourceRoom(roomDoc.data())) continue;

(이후 msgSnap 조회 ~ candidates.add ~ shuffle ~ return 부분은 기존 그대로 유지)

⚠️ 주의: orderBy('created_at') 사용 시 created_at 필드가 없는 초기 방은 결과에서 빠질 수 있다.
   만약 dart analyze나 런타임에서 인덱스/정렬 문제가 나면, orderBy를 제거하고 단순 .limit(30).get() 으로 바꾼다.
   (정렬은 필수 아님 — 어차피 candidates.shuffle()로 무작위 선택하므로)

──────────────────────────────────────────────
[수정 B-2] routine_mode_step_expand.dart — SEED 진단 로그 추가 (동작 확인용)
──────────────────────────────────────────────

_fetchRandomPastUserLine 의 candidates 판정 직후, return 직전에 진단 로그 한 줄 추가:

기존:
      if (candidates.isEmpty) return null;
      candidates.shuffle();
      return candidates.first;

교체:
      _log('🌱 [SEED]', '씨앗 후보 ${candidates.length}개 수집됨');
      if (candidates.isEmpty) return null;
      candidates.shuffle();
      _log('🌱 [SEED]', '선택된 씨앗: "${candidates.first}"');
      return candidates.first;

[검증]
1. dart analyze (두 파일) → 에러 0
2. step_expand: grep -c "'mode': 'step_expand'" → 2 (sessions 1 + chat_history 1)
3. clone: grep -c "'mode': 'clone'" → 2 (sessions 1 + chat_history 1)
4. step_expand: grep -c "_isSeedSourceRoom" → 2 (정의 1 + 호출 1)
5. step_expand: grep -c "whereIn: \['step_expand', 'clone'\]" → 0 (옛 서버필터 제거 확인)
6. step_expand: grep -c "씨앗 후보" → 1 (진단 로그 확인)
7. 런타임 테스트:
   (a) 과거 step_expand/clone 방 있고 5단어+ 발화 있음 → 로그 "씨앗 후보 N개" + 회상형 질문 출력
   (b) 신규 회원(방 0개) → 온보딩형 질문
   (c) Firestore 오류 → 뉴스 소재 폴백
8. Box 7 클래스 diff 변경 0 확인