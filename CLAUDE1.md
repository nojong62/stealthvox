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

## 핵심 원인

1. **“질문이 뭐 그래?”가 `[DISSATISFIED]`로 안 잡히고 `[RESTATE]`로 잡힘**

   * 현재 프롬프트에서 `[DISSATISFIED]` 규칙은 아래쪽에 있고, `[RESTATE]` 관련 “맥락 불일치” 검사가 먼저 강하게 작동합니다.
   * 그래서 “질문이 뭐 그래?”를 **질문 불만**이 아니라 **맥락 안 맞는 말**로 판단했고, 그 결과 확인 멘트가 나왔습니다.

2. **설령 `[DISSATISFIED]`로 잡혀도 현재 `_handleRetryQuestion()`이 안내 멘트를 먼저 말함**

   * 현재 코드에는 `isDifferent == true`일 때도 `"그럼 다른 질문 드릴게요."`를 TTS로 말하게 되어 있습니다.
   * 실장님이 원하는 동작은 **그 말도 하지 말고 바로 새 질문만 하는 것**입니다.

3. **첫 질문 히스토리 섞기 로직도 약함**

   * 현재는 FreeTalk 기록이 있을 때만 Roleplay 기록을 가져옵니다.
   * 즉 FreeTalk가 비어 있으면 Roleplay 기록은 아예 무시됩니다.
   * 또 `mode == free_talk`, `mode == roleplay`로 딱 맞는 값만 찾기 때문에 실제 저장값이 조금만 다르면 기록을 못 가져옵니다.

아래는 코덱스에 그대로 줄 지시문입니다.

# Codex 지시문 — Step Expand 질문 불만 처리 + 첫 질문 히스토리 시드 개선

대상 파일:
`lib/custom_code/widgets/routine_mode_step_expand.dart`

## 목표

Step Expand에서 유저가 AI 질문이 마음에 안 든다고 말하면, AI는 확인 질문이나 안내 멘트를 하지 않는다.

예:

* “질문이 뭐 그래?”
* “그 질문 별로야”
* “다른 거 물어봐”
* “뭐야 그게”
* “그건 좀 아닌데”
* “재미없어”
* “별론데”

이런 발화는 `[RESTATE]`나 `[GARBLED]`가 아니라 반드시 `[DISSATISFIED]`로 처리한다.

처리 결과:

1. 방금 유저의 불만 발화 버블은 화면에서 제거한다.
2. 직전 AI 질문 버블도 제거한다.
3. “방금 … 라고 말씀하신 건가요?” 같은 확인 멘트 금지.
4. “그럼 다른 질문 드릴게요.” 같은 안내 멘트도 금지.
5. 곧바로 이전 질문과 전혀 다른 새 질문만 생성하고 TTS로 재생한다.
6. 턴 카운트는 불만 발화를 하나의 학습 턴으로 계산하지 않는다.
7. Firestore 히스토리에도 불만 발화와 제거된 질문이 저장되면 안 된다.

---

## 1. `[DISSATISFIED]` 판정 우선순위 수정

`StepExpandBrain.streamUserTranslation()`의 시스템 프롬프트에서 현재 `[RESTATE]` 관련 검사가 `[DISSATISFIED]`보다 강하게 작동하고 있다.

수정 방향:

* `[DISSATISFIED]` 판정을 `[RELEVANCE CHECK]`, `[RESTATE GUARD]`보다 먼저 수행하도록 프롬프트 구조를 바꾼다.
* “질문이 뭐 그래?”, “무슨 질문이 그래?”, “뭐야 그게?”, “그 질문 이상해”, “그 질문 별로야”, “다른 질문 해줘”, “다른 거 물어봐”, “그건 좀”, “재미없어”, “별론데”는 무조건 `[DISSATISFIED]`로 출력하도록 명시한다.
* `[DISSATISFIED]`는 “유저가 대답을 거절하거나 부정 답변을 한 것”과 구분해야 한다.

  * 정상 부정 답변 예: “아니, 안 갔어”, “별로 안 좋아해”, “그건 없어”가 질문에 대한 자연스러운 답이면 정상 번역.
  * 질문 자체에 대한 불만 예: “그 질문 별로야”, “질문이 뭐 그래?”, “다른 거 물어봐”는 `[DISSATISFIED]`.

추가로 모델 판정만 믿지 말고, `_processRelayPipeline()` 초반에 raw Korean transcript 기준의 로컬 fast-lane 판정도 추가한다.

추가할 helper 개념:

* `_isQuestionDissatisfactionRaw(String text)`
* 이 함수는 finalTranscript 원문에서 질문 불만 표현을 감지한다.
* 감지되면 `streamUserTranslation()` 호출 전에 바로 dissatisfied 처리 루트로 보낸다.
* 단, “아니, 안 갔어”, “별로 안 좋아해”처럼 질문에 대한 정상 부정 답변은 잡지 않도록 “질문”, “물어봐”, “뭐야”, “그게”, “다른 거”, “별로야”, “재미없어”, “이상해” 등 질문 대상 표현이 있는 경우 위주로 판정한다.

---

## 2. `_handleRetryQuestion()`에서 불만 처리 시 안내 멘트 금지

현재 `_handleRetryQuestion()`은 `isDifferent == true`일 때도 `"그럼 다른 질문 드릴게요."`를 TTS로 먼저 말한다.

수정 방향:

* `_handleRetryQuestion()`에 `speakIntro` 또는 `silentReplace` 같은 옵션을 추가한다.
* `[DISSATISFIED]` 처리에서는 이 옵션을 사용해 intro phrase TTS를 완전히 건너뛴다.
* 이때 AI가 내는 소리는 오직 새 질문 TTS뿐이어야 한다.

기대 로그:

* 불만 감지 후 `"그럼 다른 질문 드릴게요."` TTS 로그가 없어야 한다.
* `"방금, 질문이 뭐 그래?, 라고 말씀하신 건가요?"` TTS 로그도 없어야 한다.
* 곧바로 새 AI 질문의 `[TTS-01] [AI] addText:`만 나와야 한다.

---

## 3. `[DISSATISFIED]` 분기에서 contextStr도 정리

현재 dissatisfied 분기에서는 UI에서 유저 불만 버블만 제거한 뒤 `_handleRetryQuestion(contextStr, ..., isDifferent: true)`를 호출한다.

문제:

* `contextStr`에는 이미 직전 AI 질문이 포함되어 있다.
* UI에서는 직전 AI 질문을 지워도, 새 질문 생성 프롬프트에는 거절당한 질문이 남아 있을 수 있다.
* 그래서 새 질문이 이전 질문과 비슷해질 위험이 있다.

수정 방향:

* dissatisfied 분기에서 새 질문 생성 전에 clean context를 다시 만든다.
* clean context에는 다음을 포함하지 않는다.

  1. 방금 유저 불만 발화
  2. 직전 AI 질문, 즉 거절당한 SYSTEM 질문
* 그 이전의 정상 HOST/SYSTEM 대화 흐름은 유지한다.
* clean context를 `_handleRetryQuestion()`에 전달한다.
* `streamGrammarQuestion()`의 `isDifferent == true` 프롬프트도 강화한다.

  * “Rejected question must be treated as banned.”
  * “Do not ask about the same object/action/time/reason.”
  * “Choose a different emotional or situational angle.”

---

## 4. RESTATE 확인 멘트와 질문 불만을 분리

현재 “질문이 뭐 그래?”가 `[RESTATE]`로 가면서 아래 멘트가 나온다.

`방금, 질문이 뭐 그래?, 라고 말씀하신 건가요? 맞다면 그대로 다시 한 번 말해 주세요.`

이 동작은 질문 불만 상황에서는 절대 나오면 안 된다.

수정 방향:

* `[RESTATE]`는 정말 “유저가 AI 질문과 무관한 새 내용을 말했지만 질문 불만은 아닌 경우”에만 사용한다.
* 질문 자체를 평가하거나 거부하는 표현은 무조건 `[DISSATISFIED]`.
* 로컬 fast-lane 판정에서 dissatisfied가 true이면 RESTATE/GARBLED 루트보다 우선 처리한다.

테스트 문장:

* “질문이 뭐 그래?” → `[DISSATISFIED]`
* “그 질문 별로야” → `[DISSATISFIED]`
* “다른 거 물어봐” → `[DISSATISFIED]`
* “뭐야 그게” → `[DISSATISFIED]`
* “아니, 안 갔어” → 정상 답변
* “별로 안 좋아해” → 질문에 대한 답이면 정상 답변
* “커피 한 잔 마시면서 기다리지” → 정상 답변

---

## 5. 첫 질문 히스토리 시드 로직 개선

현재 `_startSessionWaitingForUserSeed()`에서:

* FreeTalk snippets를 먼저 가져온다.
* FreeTalk snippets가 있을 때만 Roleplay snippets를 가져온다.
* FreeTalk snippets가 없으면 Roleplay snippets는 무시된다.
* 첫 질문 생성도 `ftSnippets.isNotEmpty`일 때만 실행된다.

이 구조를 바꾼다.

수정 방향:

1. FreeTalk와 Roleplay를 독립적으로 가져온다.

   * FreeTalk가 없어도 Roleplay가 있으면 Roleplay 기반 첫 질문을 생성한다.
   * Roleplay가 없어도 FreeTalk가 있으면 FreeTalk 기반 첫 질문을 생성한다.
   * 둘 다 있으면 두 소스를 자연스럽게 섞는다.
   * 둘 다 없을 때만 기존 고정 안내문으로 폴백한다.

2. mode 필터를 엄격한 단일 문자열 비교에서 alias 기반으로 확장한다.

   * FreeTalk 후보 예:

     * `free_talk`
     * `freetalk`
     * `freeTalk`
     * `ai_free_talk`
     * `free_talk_mode`
   * Roleplay 후보 예:

     * `roleplay`
     * `role_play`
     * `routine_mode_roleplay`
   * 실제 저장값을 확인해서 필요한 alias를 추가한다.

3. role 필터도 실제 저장 스키마를 확인해 robust하게 만든다.

   * 현재는 `role == HOST`만 가져온다.
   * 실제 다른 모드에서 `speaker_role`, `sender`, `user`, `host` 등 다른 필드명을 쓰는지 확인한다.
   * Roleplay/FreeTalk 메시지 저장 구조에 맞게 fallback을 추가한다.

4. 메시지 필드도 fallback을 둔다.

   * 현재는 `original_text`, `translated_text`만 본다.
   * 실제 저장 필드가 `original`, `target`, `text`, `message`, `content` 등일 수 있으므로 확인 후 fallback을 추가한다.

5. 한 방에서만 뽑지 말고 최근 여러 방에서 섞는다.

   * FreeTalk 최근 2~3개 방에서 유저 발화 후보 수집.
   * Roleplay 최근 2~3개 방에서 유저 발화 후보 수집.
   * 필러 제거 후 FreeTalk 1~2개 + Roleplay 1개 정도를 최종 seed로 사용.
   * Roleplay 발화는 실제 사용자 사실이 아니라 “주제/분위기/상황 각도”로만 사용한다.

6. seed fetch 로그를 추가한다.

   * `[SEED-FT] rooms=..., candidates=..., picked=...`
   * `[SEED-RP] rooms=..., candidates=..., picked=...`
   * `[SEED-MIX] ft=..., rp=..., source=freeTalk+roleplay/freeTalkOnly/roleplayOnly/fallback`
   * 이 로그로 실제 히스토리를 가져오는지 바로 확인 가능해야 한다.

---

## 6. `streamFreeTalkSeedQuestion()` 프롬프트 강화

현재 프롬프트는 “섞어도 되고, 이상하면 한쪽만 골라라”에 가깝다. 그래서 Roleplay가 들어와도 실제 질문에 반영이 약할 수 있다.

수정 방향:

* 함수명을 꼭 바꿀 필요는 없지만, 의미상 FreeTalk-only가 아니라 HistorySeedQuestion으로 동작하게 한다.
* 프롬프트에서 source를 명확히 구분한다.

  * FreeTalk snippets: 실제 사용자 관심사 후보
  * Roleplay snippets: 실제 사실이 아닌 상황/역할/분위기 힌트
* 둘 다 있을 때:

  * “Use FreeTalk as the main personal-interest signal.”
  * “Use Roleplay only to shape the situation, tone, or practical angle.”
  * “Create a blended everyday question that does not reveal the source.”
* 한쪽만 있을 때:

  * 해당 소스만 기반으로 자연스러운 첫 질문 생성.
* 출력은 기존처럼 유지:

  * target question
  * blank line
  * native translation

---

## 7. 기대 동작 테스트

테스트 1 — 질문 불만:

1. AI: `What do you enjoy most about that time?`
2. User: `질문이 뭐 그래?`
3. 기대:

   * 유저 버블 제거
   * 직전 AI 질문 제거
   * 확인 멘트 없음
   * “그럼 다른 질문 드릴게요” 없음
   * 바로 완전히 다른 새 질문 재생

테스트 2 — 정상 부정 답변:

1. AI: `Did you go there with friends?`
2. User: `아니, 안 갔어.`
3. 기대:

   * `[DISSATISFIED]` 아님
   * 정상 번역/확장 진행

테스트 3 — Roleplay only:

1. FreeTalk 기록 없음
2. Roleplay 기록 있음
3. 기대:

   * 고정 안내문으로 가지 않음
   * Roleplay theme 기반 첫 질문 생성

테스트 4 — FreeTalk + Roleplay:

1. 둘 다 기록 있음
2. 기대:

   * seed 로그에 ft/rp 둘 다 표시
   * 질문이 FreeTalk 관심사 + Roleplay 상황 각도를 자연스럽게 섞음

테스트 5 — 저장:

* 불만 발화와 삭제된 질문은 chat_history/messages에 저장되지 않아야 한다.
* 정상 새 질문부터 이후 대화만 저장되어야 한다.

---

## 검증

수정 후 아래를 확인한다.

1. `flutter analyze`에서 새 error 없음.
2. 테스트 로그에서 “질문이 뭐 그래?” 입력 시:

   * `[DISSATISFIED]` 로그가 나와야 함.
   * `[RESTATE]` 로그가 나오면 실패.
   * 확인 멘트 TTS가 나오면 실패.
   * “그럼 다른 질문 드릴게요” TTS가 나오면 실패.
3. 첫 질문 시작 시:

   * `[SEED-FT]`, `[SEED-RP]`, `[SEED-MIX]` 로그로 실제 히스토리 사용 여부 확인.

정리하면, 지금은 **불만 판정은 프롬프트 아래쪽에 있고, RESTATE가 먼저 먹는 구조**라서 생긴 문제입니다. 그리고 `[DISSATISFIED]`로 잡혀도 기존 함수가 안내 멘트를 말하게 되어 있으니, **불만 처리 전용 “조용히 질문 교체” 루트**를 만들어야 합니다.
