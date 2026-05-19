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

routine_mode_step_expand.dart 수정 지시문

목표:
Step Expand의 기존 대화 형식/UI/턴 처리/TTS/Firestore 저장 구조는 절대 변경하지 말고,
AI 질문 생성 방식과 문장 확장 프롬프트만 개선한다.

중요:
이 파일에는 이미 Step Expand 형식이 구현되어 있다.
형식은 다음과 같다.

1. 첫 턴은 유저 발화를 단순 번역하여 기본 문장으로 사용한다.
2. 2턴부터는 유저 새 답변을 Part1로 표시하고, 기존 문장에 새 정보를 붙인 확장 문장을 Part2로 표시한다.
3. Part1과 Part2는 빈 줄(\n\n)로 구분한다.
4. Part2만 TTS로 읽는다.
5. AI 질문은 영어 Part1 + 한국어 Part2 형식으로 출력한다.
6. 5턴이 끝나면 AI 질문 없이 최종 Expanded Sentence를 표시하고 낭독한다.
7. 이후 Polished Sentence를 자동 생성하고 낭독한다.

절대 변경 금지:
- _processRelayPipeline()의 전체 흐름
- _localMessages 구조
- _turnCounter / MAX_TURNS 처리
- HOST / SYSTEM role 구조
- Part1 + \n\n + Part2 출력 형식
- TTS 큐 처리
- Firestore 저장 구조
- Expanded Sentence / Polished Sentence 자동 흐름

수정 대상:
- StepExpandBrain.streamGrammarQuestion()의 system prompt
- 필요 시 StepExpandBrain.streamUserTranslation()의 system prompt 일부

수정 방향:
기존의 문법 유도형 질문 방식에 “대화 전문가형 유도 방식”을 추가한다.

AI 질문 생성 원칙:
1. AI는 상담사처럼 길게 설명하지 않는다.
2. AI는 공감 문장을 길게 말하지 않는다.
3. AI는 유저를 분석하거나 평가하지 않는다.
4. AI는 유저의 마지막 답변에서 가장 말하기 쉬운 단서 하나만 잡는다.
5. 질문은 5~8단어의 짧은 영어 질문으로 만든다.
6. 질문은 반드시 유저의 다음 답변이 기존 확장 문장에 붙을 수 있게 설계한다.
7. 질문은 부담 없는 방향이어야 한다.
8. “왜 그랬나요?”처럼 압박이 큰 질문은 피하고, “What part feels hardest?”처럼 가볍게 묻는다.
9. 유저가 소극적이어도 한 단어 또는 짧은 구로 답할 수 있게 질문한다.
10. 단, 질문은 너무 단순한 예/아니오 질문이 되면 안 된다.

대화 전략:
- 첫 1~2턴은 유저가 편하게 말할 수 있도록 넓고 부드러운 질문을 한다.
- 유저의 첫 유의미한 답변을 기본 문장으로 삼는다.
- 이후 매 턴 유저 답변을 이전 확장 문장에 자연스럽게 누적한다.
- 5턴 후 최종 확장 문장과 Polished Sentence를 만든다.

출력 형식은 기존 코드와 반드시 동일하게 유지한다.