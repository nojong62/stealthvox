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

routine_mode_step_expand.dart 의 Box 7-1-C streamGrammarQuestion 프롬프트(삼중따옴표 ''' 블록 내부)를 수정합니다.
목표: AI가 유저 대답의 "처음 나온 표면 단어"를 기계적으로 되받지 말고,
(1) 정말 궁금한 점을 자연스럽게 묻거나 (2) 말 밑에 깔린 감정·맥락을 읽어 한 차원 깊이 들어가서,
결국 유저가 "더 말하고 싶어지게" 만드는 유도 질문을 하게 한다.
단, 항상 감정선만 따라가라는 뜻은 아니다 — 궁금증과 감정맥락을 상황에 맞게 섞는다.

[절대 건드리지 말 것]
- 5턴 구조, 최종 합성(isFinalTurn), Part1/Part2 출력 포맷, OUTPUT FORMAT - STRICT
- [EMOTIONAL DEPTH RULE], [CONTEXT-FIRST RULE], [OUTPUT RULES — STRICT] 금지목록, [SENTENCE GROWTH LENS]
- grammarHint 4턴 텍스트, 온도(STEP1 0.9 / STEP2 0.7)
- Box 7 엔진 (DeepgramV2VoiceManager, TtsQueueManager)
- 작은따옴표가 그대로 들어간 삼중따옴표 ''' 문자열 형식 유지 (절대 \' 이스케이프로 바꾸지 말 것)

──────────────────────────────────────────────
[수정 1] LAYER 1 ②③ 교체 — "쉬운 디테일 하나 잡기"를 "표면 단어 금지 + 한 차원 위로"로
──────────────────────────────────────────────

기존 ②③ 두 줄:

② Of that feeling/motivation, what is the SINGLE detail they would most naturally enjoy adding next? (You are a curious friend following their heart, not collecting required data.)
③ See the [TURN GOAL] below only as a soft lens — a direction that often fits, NOT a target you must extract. If following the user's real feeling points elsewhere, follow the feeling.

이것을 아래로 교체:

② DO NOT just grab the first or most concrete noun in their answer and ask "what kind of X?" — that is shallow keyword-echoing and makes the user feel interrogated.
   Instead, go ONE level deeper than the surface words: their reason, motivation, mood, memory, hope, or the meaning behind what they said. Ask what a genuinely curious friend would actually wonder about.
③ Balance two moves — do not always use the same one:
   (a) GENUINE CURIOSITY: ask the real, specific thing you'd want to know about their situation.
   (b) EMOTIONAL CONTEXT: read the feeling under their words and gently follow it.
   Use whichever makes the user WANT to keep talking. The [TURN GOAL] below is only a soft lens, never a target you must extract.

──────────────────────────────────────────────
[수정 2] QUESTION PRINCIPLES 2번 교체
──────────────────────────────────────────────

기존:
2. Pick the ONE detail from the user's last answer that is easiest to expand on.

교체:
2. Do not echo the easiest surface word. Go one level deeper — into the reason, feeling, meaning, or memory behind it — and ask what genuinely makes you curious, so the user feels invited to open up.

──────────────────────────────────────────────
[수정 3] 새 섹션 [GO DEEPER, NOT WIDER] 추가
──────────────────────────────────────────────

[QUESTION PRINCIPLES — MANDATORY] 블록 바로 뒤, [SENTENCE GROWTH LENS] 바로 앞에 아래 섹션을 삽입:

[GO DEEPER, NOT WIDER]
"Wider" = staying on the same surface noun the user just said (shallow, robotic).
"Deeper" = moving to the feeling, reason, meaning, or story underneath it (what a real friend asks).
Examples of the SHIFT you must make:
- User: "I want good food for fall."
  WIDER (bad): "What kind of food do you like?"
  DEEPER (good): "What does fall food remind you of?" / "What makes fall feel special to you?"
- User: "I called my old friend."
  WIDER (bad): "What is your friend's name?"
  DEEPER (good): "What made you think of them today?"
- User: "I went hiking last weekend."
  WIDER (bad): "Which mountain did you hike?"
  DEEPER (good): "What did you need to get away from?" / "How did it clear your head?"
RULE: After drafting your question, check — am I just naming their noun again (WIDER)? If yes, rewrite it to go DEEPER.
BUT keep balance: a deeper question must still be light, answerable in 1–3 words, and its answer must still attach to the growing sentence. Never become abstract or therapy-like.

──────────────────────────────────────────────
[수정 4] EXAMPLE FLOW 교체 — "단어 캐묻기" 예시를 "궁금증+감정맥락 점프" 예시로
──────────────────────────────────────────────

기존 [EXAMPLE FLOW] 블록 전체 (AI : Are there any specific tasks... 부터
  → Checking my emails this morning, ... last year. 까지)를 아래로 교체:

[EXAMPLE FLOW]
(Notice: each question goes DEEPER — into feeling, reason, or meaning — not just naming the last noun.)
AI : What's something you're looking forward to lately?
User: A trip to Busan.
  → I'm looking forward to a trip to Busan.
AI : What made you pick Busan this time?
User: I needed the ocean.
  → I'm looking forward to a trip to Busan because I needed the ocean.
AI : What does the ocean do for you?
User: It calms me down after work stress.
  → I'm looking forward to a trip to Busan because I needed the ocean, which calms me down after work stress.
AI : What's been weighing on you most?
User: Too many deadlines piling up.
  → I'm looking forward to a trip to Busan because I needed the ocean to calm me down, since too many deadlines have been piling up.

[검증]
1. dart analyze → 에러 0 (특히 ''' 블록 내 따옴표/괄호 정상)
2. grep -c "GO DEEPER, NOT WIDER" routine_mode_step_expand.dart → 1
3. grep -c "shallow keyword-echoing" → 1 (LAYER 1 ② 삽입 확인)
4. grep -c "Pick the ONE detail from the user" → 0 (옛 QUESTION PRINCIPLES 2 제거 확인)
5. grep -c "I remembered to call Alex" → 0 (옛 EXAMPLE FLOW 제거 확인)
6. grep -c "a trip to Busan" → 최소 1 (새 EXAMPLE FLOW 삽입 확인)
7. grep -c "EMOTIONAL DEPTH RULE" → 2 (기존 유지 확인)
8. grep -c "OUTPUT FORMAT - STRICT" → 변경 전과 동일한 횟수 (포맷 섹션 보존 확인)
9. grep "\\\\'" 로 ''' 블록 안에 잘못된 \' 이스케이프가 새로 생기지 않았는지 확인
10. Box 7 클래스(TtsQueueManager, DeepgramV2VoiceManager)에 diff 변경 0 확인