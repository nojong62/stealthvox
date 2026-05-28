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

routine_mode_step_expand.dart 파일의 Box 7-1-C streamGrammarQuestion 프롬프트를 수정합니다.
기존 대화 구성 형식(5턴 확장, Part1/Part2, 최종합성, OUTPUT FORMAT 등)은 일절 변경하지 않습니다.
Box 7 엔진 코드도 절대 건드리지 않습니다.

[수정 1] — [CONTEXT-FIRST RULE] 바로 뒤, [QUESTION PRINCIPLES] 바로 앞에 새 섹션 삽입

[CONTEXT-FIRST RULE — MANDATORY CHECK] 블록의 마지막 줄:
- Always build on the MOST RECENT user statement. Never repeat ground already covered.

이 줄 뒤에, [QUESTION PRINCIPLES — MANDATORY] 시작 전에, 아래 텍스트를 삽입합니다:

[EMOTIONAL DEPTH RULE — HIGHEST PRIORITY]
Before applying any TURN GOAL, check whether the user's LAST answer clearly expresses loss of interest, motivation, enjoyment, or willingness to engage.

Trigger this rule only when the user's last answer means something like:
- "Nothing interests me."
- "I don't find anything interesting."
- "I don't care about much these days."
- "Nothing feels fun."
- "I don't feel like talking."
- "흥미로운 게 없어."
- "관심 있는 게 없어."
- "요즘 재미있는 게 없어."
- "딱히 말하고 싶은 게 없어."

Do NOT trigger this rule for a vague "I don't know", "maybe", "그냥", or "모르겠어" unless the surrounding context clearly shows emotional withdrawal or loss of interest.

If this rule is triggered, OVERRIDE the normal TURN GOAL and instead:
1. Do NOT repeat or rephrase the same topic question. Asking "what else interests you?" after "nothing interests me" is robotic and tone-deaf.
2. Treat the user's disinterest as the story itself.
3. Pivot gently into cause, change, timing, loss, contrast, or recent emotional context.
4. Do not sound like a therapist. Keep the question casual, warm, and sentence-building friendly.
5. The question must still be 5–8 words, open-ended, and answerable in 1–3 words.
6. The user's short answer should still attach naturally to the growing sentence.

Use ONE of these pivot strategies, varying each time:
- CAUSE PROBE: "What made everything feel dull?" / "What drained your interest lately?"
- TIMING PROBE: "When did things start feeling flat?" / "When did this feeling begin?"
- LOSS PROBE: "What did you enjoy before?" / "What changed for you recently?"
- CONTRAST PROBE: "What last made you feel excited?" / "When did you last feel curious?"
- SOFT EVENT PROBE: "What took the spark away?" / "What happened before this feeling started?"

[EXAMPLE — EMOTIONAL PIVOT]
AI : What's been on your mind lately?
User: Nothing really. (별로 없어.)
  → Nothing has really been on my mind.
AI : When did things start feeling flat?  ← TIMING PROBE (NOT: "What kind of things interest you?")
User: Since I moved here alone. (여기 혼자 이사 온 뒤로.)
  → Nothing has really been on my mind since I moved here alone.
AI : What did you enjoy before? ← LOSS PROBE
User: Having someone to talk to. (얘기할 사람이 있었던 거.)
  → I haven't felt interested in much since I moved here alone, because I miss having someone to talk to.
AI : Who did you talk to most? ← natural follow-up
User: My college roommate. (대학 룸메이트.)
  → I haven't felt interested in much since I moved here alone, because I miss talking to my college roommate.


[수정 2] — grammarHint 턴 1 텍스트에 감정 우선 규칙 한 줄 추가

기존 turnNumber == 1 grammarHint (약 4570줄 부근):

'GOAL: Draw out a REASON or CAUSE behind the user\'s core statement.\n'
'Invite the user to share WHY — warmly and lightly, without naming grammar. '
'A short answer like "because I was tired" should attach smoothly to the growing sentence.'

이것을 아래로 교체합니다:

'GOAL: Draw out a REASON or CAUSE behind the user\'s core statement.\n'
'If the user clearly expressed loss of interest, motivation, enjoyment, or willingness to engage, treat that emotion as the cause to explore (see [EMOTIONAL DEPTH RULE]).\n'
'Invite the user to share WHY — warmly and lightly, without naming grammar. '
'A short answer like "because I was tired" should attach smoothly to the growing sentence.'


[검증]
1. dart analyze 로 문법 에러 없는지 확인
2. grep -c "EMOTIONAL DEPTH RULE" 로 정확히 2회 나오는지 확인 (섹션 제목 1회 + grammarHint 참조 1회)
3. grep -c "EMOTIONAL PIVOT" 로 예시 블록이 정확히 1회 삽입되었는지 확인
4. grep -c "QUESTION PRINCIPLES" 로 기존 섹션이 그대로 1회 있는지 확인
5. grep -c "SENTENCE GROWTH LENS" 로 기존 섹션이 그대로 1회 있는지 확인
6. grep -c "OUTPUT FORMAT" 로 기존 포맷 섹션이 변경 없이 존재하는지 확인
7. grep "What did you used to" 로 문법 오류 문장이 없는지 확인 (0회여야 함)
8. Box 7 관련 클래스(DeepgramV2VoiceManager, TtsQueueManager, ChunkedTtsFetcher)에 변경이 없는지 diff로 확인