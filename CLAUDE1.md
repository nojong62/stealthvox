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

파일: routine_mode_duo.dart
함수: _uploadMyMessage

[삭제 대상]
시작: 566행  Future<void> _uploadMyMessage(String raw, String srcLang) async {
끝:   579행    }     (← _uploadMyMessage 메서드 닫는 중괄호)

[교체 코드 — 메서드 전체]
  Future<void> _uploadMyMessage(String raw, String srcLang) async {
    if (_duoSessionRef == null || raw.trim().isEmpty) return;
    try {
      // 🆕 내 메시지 doc id를 업로드 전에 _processedMsgIds에 선등록한다.
      //    → 리스너(605행)가 내 발화를 항상 스킵하므로, 내 글이 절대
      //      상대(SYSTEM/좌측) 말풍선으로 되돌아오지 않는다. 역할/계정 무관.
      final docRef = _duoSessionRef!.collection('messages').doc();
      _processedMsgIds.add(docRef.id);
      await docRef.set({
        'senderUid': _myUid,
        'senderRole': _myRole,
        'text': raw,
        'srcLang': srcLang,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Duo] upload message error: $e');
    }
  }

[건드리지 말 것] Box 7, 612행 역할 필터(백업으로 그대로 둠), _processRelayPipeline 렌더 로직.
[검증]
  1) flutter analyze 0 에러
  2) grep -n "_processedMsgIds.add(docRef.id)" → 1건 확인
  3) 두 폰에서 번갈아 4턴 이상 발화 → 각 폰에서 내 글=우측, 상대 글=좌측으로 좌우 교대 유지되는지 확인