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

[절대 건드리지 말 것]
- 5턴 대화 구조, 최종 합성(isFinalTurn) 로직, Part1/Part2 출력 포맷
- 최종 합성의 문법 다양성 요구 (Causal/Relative/Concessive/Conditional 2개 이상)
- 기존 [EMOTIONAL DEPTH RULE] 섹션, [CONTEXT-FIRST RULE], [OUTPUT FORMAT], [EXAMPLE FLOW]
- STEP 1 뉴스 소재 생성 로직 (temperature 0.9 부분)
- Box 7 엔진 클래스 (DeepgramV2VoiceManager, TtsQueueManager, ChunkedTtsFetcher)


[수정 1] — 오프닝 질문 생성 STEP 2의 temperature 0.2 → 0.7

isOpening 블록 안에서, openingSysPrompt를 보내는 openReq.body의 jsonEncode 부분을 찾습니다.
(STEP 1 뉴스 소재 생성의 temperature 0.9가 아니라, 그 아래 STEP 2 질문 생성 부분입니다.
 messages에 openingSysPrompt가 들어가고 max_tokens가 30인 요청입니다.)

기존:
        openReq.body = jsonEncode({
          'model': 'gpt-4o-mini',
          'stream': true,
          'temperature': 0.2,
          'max_tokens': 30,
          'messages': [
            {'role': 'system', 'content': openingSysPrompt},
            {'role': 'user', 'content': 'Go.'},
          ],
        });

수정 (temperature만 0.7로):
        openReq.body = jsonEncode({
          'model': 'gpt-4o-mini',
          'stream': true,
          'temperature': 0.7,
          'max_tokens': 30,
          'messages': [
            {'role': 'system', 'content': openingSysPrompt},
            {'role': 'user', 'content': 'Go.'},
          ],
        });

⚠️ 주의: STEP 1 뉴스 소재 생성의 temperature 0.9는 절대 건드리지 마세요. 오직 위 STEP 2(max_tokens 30) 요청의 0.2만 0.7로 바꿉니다.


[수정 2] — grammarHint 4턴 전체 교체 ("추출 목표" → "느낌 따라가기 렌즈")

기존 grammarHint 전체 블록 (turnNumber == 1 ? ... : '... attach naturally.'; 까지):

      final String grammarHint = turnNumber == 1
          ? 'GOAL: Draw out a REASON or CAUSE behind the user\'s core statement.\n'
              'If the user clearly expressed loss of interest, motivation, enjoyment, or willingness to engage, treat that emotion as the cause to explore (see [EMOTIONAL DEPTH RULE]).\n'
              'Invite the user to share WHY — warmly and lightly, without naming grammar. '
              'A short answer like "because I was tired" should attach smoothly to the growing sentence.'
          : turnNumber == 2
              ? 'GOAL: Draw out a PERSON or THING involved in the user\'s story.\n'
                  'Ask who or what was part of it — keep it light and curious. '
                  'A short answer like "my friend Jisu" should attach naturally as a relative clause.'
              : turnNumber == 3
                  ? 'GOAL: Draw out a CONTRAST or UNEXPECTED element.\n'
                      'Gently ask about something surprising, hard, or different from expectations. '
                      'A short answer like "even though I was nervous" should attach naturally.'
                  : 'GOAL: Draw out a CONDITION or SPECIFIC SITUATION.\n'
                      'Ask when it happens or what triggers it — keep it gentle and open. '
                      'A short answer like "when I have free time" should attach naturally.';

이것을 아래로 전체 교체합니다:

      final String grammarHint = turnNumber == 1
          ? 'FOCUS: Follow the FEELING or MOTIVATION behind what the user just said.\n'
              'Silently guess WHY this matters to them or how they feel about it, then ask a light question that follows that thread — not a question that extracts a fixed answer.\n'
              'If the user clearly expressed loss of interest, motivation, enjoyment, or willingness to engage, follow that emotion instead (see [EMOTIONAL DEPTH RULE]).\n'
              'Their short answer (e.g. "because it was fun", "I was just curious") should attach smoothly to the growing sentence.'
          : turnNumber == 2
              ? 'FOCUS: Follow the PERSON, PLACE, or THING that seems to matter most in their story.\n'
                  'Guess what detail they would naturally want to share more about, and ask about that — gently and curiously, never like a checklist.\n'
                  'Their short answer (e.g. "my friend Jisu", "at the cafe") should attach naturally to the growing sentence.'
              : turnNumber == 3
                  ? 'FOCUS: Follow how they FELT or what stood out to them.\n'
                      'Guess the emotion or the surprising/memorable part behind their last answer, and ask about it lightly. Do not force a contrast — let it emerge from their feeling.\n'
                      'Their short answer (e.g. "it was a relief", "even though I was nervous") should attach naturally to the growing sentence.'
                  : 'FOCUS: Follow where their story is naturally heading — a moment, a situation, or what it means to them.\n'
                      'Guess what they would enjoy adding, and invite it gently and openly.\n'
                      'Their short answer (e.g. "when I have free time", "after work") should attach naturally to the growing sentence.';


[수정 3] — LAYER 1 추론 순서 재배치 (감정·동기 추측을 1순위로)

기존 LAYER 1 블록:

LAYER 1 — INTERNAL REASONING (never output, work silently):
Before writing your question, think through:
① What is the GOAL this turn? (See [TURN GOAL] below)
② Look at the growing sentence in History. What ONE detail is still missing?
   - A reason / cause (because / since)
   - A person or thing involved (who / which)
   - A contrast or unexpected element (although / despite)
   - A condition or situation (if / when)
③ Of the user's LAST answer, what is the SINGLE easiest detail to follow up on?
④ What is the most natural, low-pressure 5–8-word question that picks up that one detail?
   - Can a quiet or hesitant person still answer in 1–3 words?
   - Does it avoid pressure words ("Why did you do that?", "Explain your reason")?
   - Does it avoid yes/no answers?
⑤ Does the question flow from the user's LAST statement and avoid already-covered ground?
NEVER reveal this reasoning in the output.

이것을 아래로 전체 교체합니다:

LAYER 1 — INTERNAL REASONING (never output, work silently):
Before writing your question, think through — in THIS order:
① FEELING FIRST: Read the user's LAST answer. What is the person likely thinking, feeling, or caring about underneath it? What motivated them to say it? Follow THAT thread.
② Of that feeling/motivation, what is the SINGLE detail they would most naturally enjoy adding next? (You are a curious friend following their heart, not collecting required data.)
③ See the [TURN GOAL] below only as a soft lens — a direction that often fits, NOT a target you must extract. If following the user's real feeling points elsewhere, follow the feeling.
④ What is the most natural, low-pressure 5–8-word question that picks up that one detail?
   - Can a quiet or hesitant person still answer in 1–3 words?
   - Does it avoid pressure words ("Why did you do that?", "Explain your reason")?
   - Does it avoid yes/no answers?
⑤ Does the question flow from the user's LAST statement and avoid already-covered ground?
   The user's short answer should still attach naturally to the growing sentence (this never changes).
NEVER reveal this reasoning in the output.


[검증]
1. dart analyze 로 문법 에러(특히 작은따옴표 이스케이프) 없는지 확인
2. grep -c "FOCUS: Follow" 로 새 grammarHint가 정확히 4회 나오는지 확인
3. grep -c "FEELING FIRST" 로 LAYER 1 재배치가 정확히 1회 들어갔는지 확인
4. grep -c "Draw out a REASON" 로 옛 grammarHint가 완전히 사라졌는지 확인 (0회여야 함)
5. grep -c "EMOTIONAL DEPTH RULE" 로 기존 섹션이 그대로 2회 유지되는지 확인
6. grep -c "OUTPUT FORMAT" 로 출력 포맷 섹션이 변경 없이 유지되는지 확인
7. grep "temperature.*0.9" 로 STEP 1 뉴스 소재 생성 온도가 그대로 0.9인지 확인 (변경되면 안 됨)
8. Box 7 클래스(DeepgramV2VoiceManager, TtsQueueManager)에 변경이 없는지 diff로 확인