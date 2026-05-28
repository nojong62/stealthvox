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

Claude Code 지시문 — 간단 버전

routine_mode_step_expand.dart에서 Step Expand 유저 첫 대사의 히스토리 저장 문제만 점검/수정해라.

현재 의도된 동작

Step Expand 진행 화면에서는 유저 첫 대사가 이렇게 보이는 것이 맞다.

I'm a little worried.

즉, 진행 화면에서는 첫 유저 대사의 한국어 원문:

조금 걱정돼.

가 안 보여도 정상이다.

하지만 히스토리에 저장될 때는 첫 유저 대사의 target과 original이 모두 저장되어야 한다.

targetText: I'm a little worried.
originalText: 조금 걱정돼.

그래야 ChatHistory 첫 페이지에서 다시 열었을 때:

I'm a little worried.
조금 걱정돼.

처럼 target + original이 모두 보여야 한다.

의심 원인

현재 Step Expand 진행 화면에서 original을 숨기기 위해 사용하는 값이, 히스토리 저장에도 그대로 쓰이는 것 같다.

특히 아래 같은 로직을 확인해라.

final String effectiveOriginal =
    (role == 'HOST_TEMP') ? '' : originalRaw;

이런 effectiveOriginal은 화면 표시용이어야 한다.
히스토리 저장 payload에는 절대 effectiveOriginal을 쓰면 안 된다.

히스토리 저장에는 반드시 실제 원문 값인 originalRaw 또는 originalText를 사용해야 한다.

수정 목표
Step Expand 진행 화면의 기존 표시 방식은 유지한다.
첫 유저 대사: target만 표시
이 부분은 고치지 마라.
히스토리 저장 시에는 original을 빈 값으로 만들지 마라.
화면에서 숨겨도 저장 데이터에는 original이 있어야 한다.
HOST_TEMP 때문에 화면에서 original을 숨기는 것은 괜찮다.
하지만 HOST_TEMP라는 이유로 저장 데이터의 original까지 삭제하면 안 된다.
수정 금지

아래는 건드리지 마라.

Box 7 엔진 코드
DeepgramV2VoiceManager
TtsQueueManager
ChunkedTtsFetcher
5턴 확장 구조
Part1/Part2 출력 형식
최종 Expanded Sentence 생성 방식
TTS/STT 로직
Step Expand 화면 UI 구조
검증

수정 후 아래를 확인해라.

Step Expand 진행 화면
첫 유저 대사는 target만 보여도 정상
히스토리 첫 페이지
같은 첫 유저 대사가 target + original로 보여야 함

예:

진행 화면:
I'm a little worried.

히스토리 첫 페이지:
I'm a little worried.
조금 걱정돼.
flutter analyze 또는 정적 점검만 실행해라.
APK/AAB 빌드는 하지 마라.