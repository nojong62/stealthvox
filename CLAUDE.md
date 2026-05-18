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

[StealthVox Roleplay 현재 대사 상단 고정 스크롤 방식 수정 지시문]

대상 파일:
- lib/custom_code/widgets/routine_mode_roleplay.dart

중요:
APK 빌드 명령은 실행하지 마라.
코드 수정과 flutter analyze/check 수준까지만 진행해라.

현재 문제:
롤플레이 대화 중 대사가 화면 아래까지 차면 현재 대사가 아래쪽에 남고, 이전 대사들이 화면 위에 계속 누적되는 느낌이다.

원하는 방식:
1. 현재 말하는 대사 묶음이 항상 화면 맨 위에서 시작해야 한다.
2. 현재 대사 전체가 위에서부터 잘 보여야 한다.
3. 다음 대사 묶음이 나오면 이전 대사는 자연스럽게 화면 위쪽 밖으로 밀려나가야 한다.
4. 메시지 데이터를 삭제하지 말고, 스크롤 위치만 새 현재 대사 기준으로 이동시켜라.

절대 수정하지 말 것:
- Deepgram STT 로직
- OpenAI 스트리밍 로직
- TTS 로직
- COMMIT_WAIT 로직
- 결제/타이머 로직
- Firestore 저장 구조
- 화면 전체 디자인 톤

수정 지침:

1. 기존 `_scrollToBottom()` 중심 방식을 일반 대화 진행에서 사용하지 마라.

기존:
_scrollToBottom();

수정:
새로 추가된 메시지 index를 기준으로 상단 정렬한다.

2. `_scrollToCurrentTop(int index)` 함수를 추가하거나 기존 `_scrollToCurrent(int index)`를 수정해라.

예시:

void _scrollToCurrentTop(int index) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scrollController.hasClients) return;
    final key = _itemKeys[index];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;

    Scrollable.ensureVisible(
      ctx,
      alignment: 0.02,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  });
}

3. 기존 `_scrollToCurrent()`에 alignment: 0.5가 있다면 사용하지 마라.
중앙 정렬이 아니라 상단 정렬이 목표다.

4. 아래 시점에서 반드시 현재 메시지를 상단으로 맞춰라.

- 유저 메시지가 새로 추가된 직후
- AI 메시지가 새로 추가된 직후
- AI 스트리밍 첫 유효 문장이 들어온 직후

5. AI 스트리밍 중 매 청크마다 스크롤하지 마라.
첫 유효 청크 시점에만 한 번 상단 정렬하고, 이후 텍스트 추가 중에는 반복 스크롤하지 마라.
화면 떨림을 막기 위함이다.

6. ListView padding을 조정해라.

권장:
final double bottomPad = MediaQuery.of(context).size.height * 0.55;
padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad)

이유:
현재 대사를 화면 상단에 붙였을 때 긴 문장도 화면 안에서 자연스럽게 보이도록 아래 여백을 확보하기 위함이다.

7. 메시지는 삭제하지 마라.
`_localMessages`는 그대로 유지하고, 스크롤만 새 현재 대사 위치로 이동시켜라.

8. 디버그 로그를 추가해라.

예:
_log('🧭 [SCROLL-TOP]', 'index=$index role=$role');

검증 기준:
1. 롤플레이 시작
2. AI 첫 대사가 화면 맨 위 근처에서 시작
3. 유저가 말하면 유저 대사 묶음이 화면 맨 위 근처로 이동
4. AI가 답하면 AI 대사 묶음이 다시 화면 맨 위 근처로 이동
5. 이전 대사는 위쪽 화면 밖으로 자연스럽게 넘어감
6. 현재 대사가 화면 아래쪽에 붙어서 남지 않음
7. 긴 대사도 화면 위에서부터 최대한 전체가 보임
8. flutter analyze에서 신규 에러 없음

작업 후 보고:
- 수정한 함수명
- `_scrollToBottom()` 사용 제거/유지 여부
- `_scrollToCurrentTop()` 적용 위치
- ListView padding 변경 여부
- flutter analyze 결과
를 간단히 보고해라.