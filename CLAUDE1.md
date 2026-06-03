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

Claude Code 지시문
변경 1: "Tap your role icon" 텍스트 → 시스템 사운드로 교체
파일: chat_history_master.dart
[A] _showRoleSelectBubble() 수정 (약 651줄)
아래 함수를 찾아:
dartvoid _showRoleSelectBubble() {
    if (!mounted) return;
    setState(() => _showRoleBubble = true);
    _roleBubbleTimer?.cancel();
    _roleBubbleTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _showRoleBubble = false);
    });
  }
setState(() => _showRoleBubble = true); 바로 아래에 다음 한 줄 추가:
dartHapticFeedback.mediumImpact();

HapticFeedback은 이미 import 'package:flutter/services.dart'로 임포트되어 있음. 별도 임포트 불필요.


[B] _buildRoleSpeechBubble() 텍스트 제거 (약 4739~4751줄)
아래 함수 전체를:
dartWidget _buildRoleSpeechBubble() {
    return const Text(
      "Tap your role icon",
      style: TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.none,
        shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
      ),
    );
  }
다음으로 교체 (빈 위젯 반환):
dartWidget _buildRoleSpeechBubble() {
    return const SizedBox.shrink();
  }

변경 2: "✨ Expanded Sentence" 버튼 이모지 제거
파일: chat_history_master.dart
약 4708~4710줄 ElevatedButton.icon의 label 텍스트에서 이모지 제거:
dart// 변경 전
_isBuildingExpand ? "불러오는 중..." : "✨ Expanded Sentence",

// 변경 후
_isBuildingExpand ? "불러오는 중..." : "Expanded Sentence",