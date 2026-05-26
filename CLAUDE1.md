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

아래 파일을 수정해 주세요: routine_mode_clone.dart

──────────────────────────────────────
[변경 1] 클론 이름 hintText 교체
──────────────────────────────────────
위치: _showCloneDashboard() → Tab 1 → 클론 이름 TextField

찾을 텍스트:
  hintText: "예: 민준이",

교체할 텍스트:
  hintText: "예: 클론(카톡 이름)",


──────────────────────────────────────
[변경 2] 카톡 붙여넣기 박스 hintText 교체
──────────────────────────────────────
위치: 동일 Tab 1 → 클론 특징 TextField

찾을 텍스트:
  hintText: "나와의 관계, 성격이나 특별한 말투 등",

교체할 텍스트:
  hintText: "상대방과 이어서 말하고 싶은 카톡 대화를 PC에서 복사해서 붙여 넣기 합니다. - 대화 순서 그대로",


──────────────────────────────────────
[변경 3] 키보드 올라올 때 Create Clone 버튼이 가리는 문제 수정
──────────────────────────────────────
위치: _showCloneDashboard() → Tab 1 전체를 감싸는 SingleChildScrollView

현재 Tab 1이 아래와 같이 구성되어 있음:
  SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
    child: Column( ... ),
  )

이것을 아래처럼 교체:
  Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(ctx).viewInsets.bottom,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column( ... ),  // 기존 Column 내용 그대로 유지
    ),
  )

단, Dialog의 mainAxisSize가 MainAxisSize.min 이므로
Column의 mainAxisSize도 MainAxisSize.min 으로 설정되어 있는지 확인 후
없으면 추가.


──────────────────────────────────────
[변경 4] 클론 삭제 기능 추가
──────────────────────────────────────

▶ 4-A. _deleteCloneInFirestore() 메서드 추가
_updateCloneInFirestore() 메서드 바로 아래에 다음 메서드를 삽입:

  Future<void> _deleteCloneInFirestore(String cloneId) async {
    final ref = _clonesRef();
    if (ref == null || cloneId.isEmpty) return;
    try {
      await ref.doc(cloneId).delete();
    } catch (e) {
      _log('❌ [CLONE-DELETE]', '클론 삭제 실패: $e');
    }
  }


▶ 4-B. Select 탭 ListTile trailing에 삭제 버튼 추가
위치: _showCloneDashboard() → Tab 0 ListView → ListTile trailing → Row → children

현재 trailing Row의 children 마지막에 edit IconButton이 있음:
  IconButton(
    icon: const Icon(Icons.edit_outlined, color: Colors.white38, size: 18),
    onPressed: () { ... _showEditCloneDialog ... },
    ...
  ),

edit IconButton 바로 뒤에 아래 삭제 버튼을 추가:

  IconButton(
    icon: const Icon(Icons.delete_outline,
        color: Color(0xFFEF4444), size: 18),
    onPressed: () async {
      // 확인 다이얼로그
      final confirm = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF2C2C2E),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          title: const Text('클론 삭제',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(
            '"${clone['name']}" 클론을 삭제하시겠어요?\n삭제 후 복구가 불가능합니다.',
            style: const TextStyle(
                color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소',
                  style: TextStyle(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('삭제',
                  style: TextStyle(color: Color(0xFFEF4444))),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      final deleteId = clone['id'] as String;
      await _deleteCloneInFirestore(deleteId);

      setState(() {
        _clones.removeWhere((c) => c['id'] == deleteId);
        // 삭제된 클론이 현재 선택 중이면 선택 해제
        if (_selectedCloneId == deleteId) {
          _selectedCloneId = '';
          _selectedCloneContext = '';
          _localMessages.clear();
        }
      });
      setStateDialog(() {});
    },
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
  ),