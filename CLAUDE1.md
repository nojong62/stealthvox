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

클로드코드 수정 지시문
Clone 히스토리 AI original_text 누락 문제 수정

대상 파일:

lib/custom_code/widgets/routine_mode_clone.dart

문제 설명

클론 모드에서 대화 화면에는 AI 대사의 타겟 글자 + 오리지널 글자가 정상 표시된다.
하지만 히스토리에 들어가면 AI 두 번째 대사부터 original_text가 사라진다.

현재 확인된 문제 지점:

_handleFinalTranscript() 내부에서 일반 턴의 AI 응답 저장 시, systemLine을 만들 때 AI의 original_text가 빈 문자열로 저장되고 있다.

현재 구조상 문제:

translated_text에는 AI 타겟 문장이 들어간다.
그런데 original_text에는 빈 값이 들어간다.
그래서 히스토리에서는 AI의 오리지널 글자가 표시되지 않는다.

중요 개념:

오리지널 언어 = 사용자가 사용하는 언어. 예: 한국어.
타겟 언어 = 사용자가 배우려는 언어. 예: 영어.
유저 대사는 Deepgram STT 원문을 바탕으로 GPT가 타겟문과 오리지널 표시문을 만든다.
AI 대사는 Deepgram을 거치지 않는다.
AI 대사는 GPT가 처음부터 타겟문과 오리지널문을 직접 생성하거나, 최소한 저장 전에 같은 의미의 오리지널 언어 문장을 확정해야 한다.
AI 쪽을 “역번역”이라고 부르지 마라. AI는 자기 대사를 만드는 것이므로 AI bilingual response, 즉 타겟문 + 오리지널문 동시 생성/저장 구조로 봐야 한다.
수정 목표

AI 일반 턴에서도 첫 오프너처럼 AI의 original_text가 반드시 저장되게 수정하라.

히스토리 저장 시 구조는 항상 아래 기준을 지켜라.

role: SYSTEM
translated_text: AI가 말하는 타겟 언어 문장
original_text: 같은 의미의 오리지널 언어 문장

예:

타겟 언어가 영어, 오리지널 언어가 한국어인 경우
translated_text: “How do you think you did on the test?”
original_text: “시험은 어느 정도 본 것 같아?”
구체 수정 지시
_handleFinalTranscript() 내부 STEP 7 Firestore 저장 직전 로직을 수정한다.
현재 systemLine에서 original_text가 빈 문자열로 들어가는 부분을 제거한다.
AI 응답 스트리밍이 끝나고 aiTargetText가 확정된 뒤, 저장 전에 AI 오리지널 문장을 확정한다.
현재 파일에 있는 CloneBrain.generateCleanOriginal() 함수는 이름과 주석이 “역번역”처럼 되어 있지만, 실제 목적은 타겟문에 대응하는 오리지널 언어 표시문 생성이다.
일단 함수명을 바꾸지 않아도 되지만, 주석과 로그에서는 “AI 역번역”이라는 표현을 쓰지 말고 AI original 생성, AI original_text 생성, AI bilingual original 생성 같은 표현으로 바꿔라.
aiTargetText.trim()이 비어 있지 않으면 저장 전에 AI original 문장을 생성해서 aiOriginalText 변수에 담는다.
UI에도 동일한 aiOriginalText를 반영한다.
systemLine 생성 시 반드시 다음 구조가 되게 한다.
role: SYSTEM
original_text: aiOriginalText
translated_text: aiTargetText
_saveTurnToFirestore([hostLine, systemLine])와 _saveHistoryMessages([hostLine, systemLine]) 양쪽 모두 같은 systemLine을 사용해야 한다.
첫 AI 오프너 _generateAndPlayAiOpener()는 이미 AI original을 생성해서 저장하는 구조가 있으므로, 일반 턴도 그 방식과 일관되게 맞춘다.
AI original 생성이 실패한 경우에도 앱이 멈추면 안 된다.
실패 시에는 최소한 빈 값 대신 안전한 fallback을 넣어라.
단, 가능하면 빈 문자열 저장은 피한다.

유저 쪽 hostLine.original_text도 확인한다.
현재 유저 original이 UI에는 나중에 들어가고, 저장 시점에는 아직 비어 있을 가능성이 있다.
유저 original은 정책상 다음 중 하나로 통일한다.

Deepgram이 인식한 오리지널 언어 원문을 저장하거나,
GPT가 정리한 오리지널 표시문을 저장한다.

단, 어떤 방식을 쓰든 hostLine.original_text가 저장 시점에 비어 있지 않게 보장한다.

APK/AAB 빌드 명령은 실행하지 마라.
코드 수정과 flutter analyze 또는 관련 파일 정적 체크까지만 진행하라.
검증 기준
클론 대화 화면에서 AI 첫 대사뿐 아니라 두 번째, 세 번째 AI 대사도 타겟 글자와 오리지널 글자가 함께 보여야 한다.
히스토리에 들어갔을 때 AI 두 번째 대사부터도 오리지널 글자가 사라지지 않아야 한다.
Firestore의 chat_history/messages에서 role: SYSTEM 문서의 original_text가 빈 문자열이면 안 된다.
translated_text에는 타겟 언어 문장이 들어가야 한다.
original_text에는 오리지널 언어 문장이 들어가야 한다.
AI TTS 재생 순서, 화면 스크롤, 유저 TTS 후 AI TTS 전환 구조는 변경하지 않는다.
첫 오프너 저장 구조와 일반 AI 턴 저장 구조가 동일한 필드 정책을 가져야 한다.
핵심 요약

이번 문제는 AI가 오리지널 문장을 못 만드는 문제가 아니라,
일반 턴 저장 시 SYSTEM.original_text를 빈 문자열로 저장하는 문제다.

AI는 Deepgram 기반 역번역 대상이 아니다.
AI는 GPT가 자기 대사를 만들 때 타겟 언어 문장과 오리지널 언어 문장을 함께 확정해서 저장해야 한다.