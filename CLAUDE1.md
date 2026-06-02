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

A 지시문 — Phase 1 cache-write 보완 패치

전제: Phase 1 지시문(지난 턴)이 먼저 적용된 상태여야 합니다. 이 패치는 그 안의 _buildExpandFromConversation() 메서드만 손봅니다. (Phase 1 미적용이면 Phase 1 먼저 적용 후 이 패치를 적용할 것.)

대상 파일: lib/.../chat_history_master.dart
절대 보존: Box 7, _buildChunks(), _goToChunkPractice(), _generateExpandedFromConversation(), _polishExpandedSentence() — 건드리지 말 것. 아래 두 곳만 교체.

패치 1) 방 문서 fetch에서 mode / room_name도 함께 읽기
찾기 (고유):
dart      // 1순위: 방 문서에 이미 저장된 expanded/polished
      String expanded = "";
      String polished = "";
      try {
        final snap = await widget.historyDoc.get();
        final d = snap.data();
        expanded = (d?['expanded_sentence'] as String?)?.trim() ?? "";
        polished = (d?['polished_sentence'] as String?)?.trim() ?? "";
      } catch (e) {
        debugPrint("[buildExpand] doc fetch $e");
      }
교체:
dart      // 1순위: 방 문서에 이미 저장된 expanded/polished (+ mode/room_name 확보)
      String expanded = "";
      String polished = "";
      String existingMode = "";
      String roomName = "";
      try {
        final snap = await widget.historyDoc.get();
        final d = snap.data();
        expanded = (d?['expanded_sentence'] as String?)?.trim() ?? "";
        polished = (d?['polished_sentence'] as String?)?.trim() ?? "";
        existingMode = (d?['mode'] as String?)?.trim() ?? "";
        roomName = (d?['room_name'] as String?)?.trim() ?? "";
      } catch (e) {
        debugPrint("[buildExpand] doc fetch $e");
      }

패치 2) cache-write에 has_practice + mode stamp 추가
찾기 (고유):
dart        // 캐시 저장 — mode가 clone/roleplay이므로 라우터가 Step Expand로 오인하지 않음
        try {
          await widget.historyDoc.update({
            'expanded_sentence': expanded,
            if (polished.isNotEmpty) 'polished_sentence': polished,
          });
        } catch (e) {
          debugPrint("[buildExpand] cache write $e");
        }
교체:
dart        // 캐시 저장 — has_practice + mode stamp(없으면 room_name으로 추론)로
        // 재입장 시 라우터가 expanded만 있는 모호한 방을 Step Expand로 오인하지 않게 보장
        String stampMode = existingMode;
        if (stampMode.isEmpty) {
          if (roomName == "Clone Mode") {
            stampMode = "clone";
          } else if (roomName == "Roleplay Mode") {
            stampMode = "roleplay";
          } else {
            stampMode = "clone"; // 안전 기본값: step_expand만 아니면 Tutor로 라우팅됨
          }
        }
        try {
          await widget.historyDoc.update({
            'expanded_sentence': expanded,
            if (polished.isNotEmpty) 'polished_sentence': polished,
            'has_practice': true,
            'expand_source': 'fallback',
            'expand_generated_at': FieldValue.serverTimestamp(),
            if (existingMode.isEmpty) 'mode': stampMode,
          });
        } catch (e) {
          debugPrint("[buildExpand] cache write $e");
        }

적용 후 검증
bashflutter analyze
grep -c "String existingMode" lib/**/chat_history_master.dart        # 1
grep -c "'has_practice': true" lib/**/chat_history_master.dart        # 1 이상
grep -c "if (existingMode.isEmpty) 'mode': stampMode" lib/**/chat_history_master.dart   # 1
롤백: 두 블록을 원래 형태로 되돌리면 원복.

이 패치의 효과는 명확합니다. mode가 없는 구버전 roleplay 방에서 fallback 생성이 일어나도, 캐시 시점에 room_name으로 mode를 추론해 박아두므로 재입장 시 라우터가 절대 Step Expand로 오인하지 않습니다. 동시에 has_practice: true로 버튼 노출 조건도 안정화됩니다.
검증 결과(특히 flutter analyze 클린 + grep 카운트) 보고해 주시면, 이어서 B 지시문 = Phase 2(clone) + Phase 3(roleplay) 를 드리겠습니다. B에는 리뷰에서 확정된 4가지(roleplay _ensureHistoryRef에 mode:'roleplay' 추가 / _handleAutoSaveAndExit에서 오버레이+생성 / dispose는 최소 저장만 / has_practice:true 저장)가 모두 들어갑니다.