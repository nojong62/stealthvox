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

코드 확인상 롤플레이도 확장문장 만들 때 대화 상대를 실제 역할명으로 넣지 않고, transcript를 `User / AI`로 만들고 있습니다. 게다가 확장문장 프롬프트 자체도 **“user and an AI partner”**라고 되어 있어서 결과가 자연스럽게 “the AI explained…”로 나옵니다.

아래 지시문은 **클론 + 롤플레이 + 히스토리 재생성까지 통합 수정**하는 버전입니다.

---

## Codex 통합 수정 지시문

StealthVox에서 **Clone / Roleplay 모드의 Expanded Sentence / Polished Sentence가 상대를 “AI”라고 부르는 문제**를 통합 수정해 주세요.

수정 대상 파일:

* `lib/custom_code/widgets/routine_mode_clone.dart`
* `lib/custom_code/widgets/routine_mode_roleplay.dart`
* `lib/custom_code/widgets/chat_history_master.dart`

APK/AAB 빌드는 하지 마세요. 수정 후 `flutter analyze` 수준까지만 확인해 주세요.

---

# 1. 문제 정의

현재 Clone / Roleplay 모드에서 대화 종료 후 Expanded Sentence / Polished Sentence를 만들 때 상대가 실제 클론명 또는 역할명이 아니라 `AI`, `AI partner`, `assistant`처럼 표현됩니다.

예시 문제:

`The user complains about the repair mistake, while the AI apologizes and explains the issue.`

이건 앱 내부 구현 설명처럼 들리고, 실제 대화 복습 문장으로는 부자연스럽습니다.

Clone 모드에서는 상대를 **선택된 클론 이름**으로 써야 합니다.

예:

`The user complains about the repair mistake, while Comsuri apologizes and explains the issue.`

Roleplay 모드에서는 상대를 **설정된 역할명**으로 써야 합니다.

예:

`The customer complains about the wrong room, while the hotel clerk apologizes and offers to fix the booking.`

핵심 규칙:

* Clone / Roleplay 확장문장에서 상대를 `AI`, `assistant`, `chatbot`, `bot`으로 부르면 실패입니다.
* 상대가 실제 AI로 구현되어 있어도, 학습자에게 보여주는 문장에서는 **대화 속 인물/역할**로 표현해야 합니다.
* 단, 대화 주제 자체가 AI일 때만 일반 명사로 `AI`를 쓸 수 있습니다.

---

# 2. 공통 설계: partner label / user label 도입

Clone / Roleplay / History 공통으로 확장문장 생성 시 다음 개념을 사용하세요.

## A. userLabel

* Clone 기본값: `the user`
* Roleplay 기본값: `_scenarioUserRole`
* `_scenarioUserRole`이 없으면 `the user`

Roleplay 예:

* `customer`
* `angry husband`
* `guest`
* `passenger`
* `patient`

한국어 역할명이 들어오면 그대로 쓰되, 영어 문장에 자연스럽게 들어갈 수 있도록 필요하면 GPT 프롬프트에서 “use a natural English role label”로 처리하게 하세요.

## B. partnerLabel

Clone:

* 선택된 클론 이름
* 없으면 `the clone`

Roleplay:

* `_scenarioAiRole`
* 없으면 `the roleplay partner`

예:

* `hotel clerk`
* `angry spouse`
* `flight attendant`
* `doctor`
* `police officer`

절대 fallback을 `AI`로 두지 마세요.

---

# 3. `routine_mode_clone.dart` 수정

## A. 선택된 클론 이름 helper 추가

선택된 클론 이름을 안정적으로 반환하는 helper를 추가하세요.

우선순위:

1. `_selectedCloneId`가 있는 경우 `_clones`에서 해당 id의 `name`
2. 없으면 빈 문자열
3. 최종 fallback은 `the clone`

이 helper는 아래에서 공통 사용합니다.

* history 문서 생성
* transcript 생성
* expanded sentence prompt
* polished sentence prompt
* UI 표시

## B. `chat_history` 방 문서 생성 시 클론 정보 저장

`_ensureHistoryRef()`에서 새 방 문서 생성 시 다음 필드를 추가하세요.

* `mode`: `clone`
* `clone_id`
* `clone_name`
* `user_label`: `the user`
* `partner_label`: 클론 이름 또는 `the clone`
* `expand_schema_version`: 가능하면 생성 시점에는 비워도 되지만, 확장문장 생성 후에는 반드시 `named_partner_v1`

기존 필드는 삭제하지 마세요.

## C. 종료 시 transcript 생성 수정

현재 Clone 종료 시 transcript에서 `SYSTEM`을 `AI`로 바꾸는 부분이 있습니다.

수정 기준:

* `HOST` → `User` 또는 `the user`
* `SYSTEM` → 클론 이름 또는 `partner_label`
* `AI`라는 단어를 transcript 참여자명으로 쓰지 마세요.

## D. `CloneBrain.generateExpandedFromConversation()` 수정

함수 인자로 다음을 추가하세요.

* `userLabel`
* `partnerLabel`

프롬프트 핵심 규칙:

* This conversation is between `{userLabel}` and `{partnerLabel}`.
* `{partnerLabel}` is a named clone/persona, not “AI”.
* Never refer to `{partnerLabel}` as AI, assistant, chatbot, or bot.
* If the partner must be mentioned, use `{partnerLabel}`.
* Keep one sentence, 25–40 words.
* Keep about 5 breath groups.
* Each breath group should usually be 5–7 words.
* Do not add facts.

## E. `CloneBrain.polishSentence()` 수정

Polished 단계에서도 이름이 다시 AI로 바뀌면 안 됩니다.

프롬프트에 다음 규칙을 추가하세요.

* Preserve participant names and role labels.
* Do not replace the clone name with AI, assistant, chatbot, or bot.
* Same meaning only.
* No new facts.

## F. 저장 필드 추가

확장문장 저장 시 다음 필드를 함께 저장하세요.

* `expanded_sentence`
* `polished_sentence`
* `has_practice`: true
* `expand_source`: `exit`
* `expand_generated_at`
* `expand_user_label`
* `expand_partner_name`
* `expand_partner_type`: `clone`
* `expand_schema_version`: `named_partner_v1`

## G. UI 표시 수정

하단 또는 카드에 `Clone AI`라고 표시되는 부분은 클론 이름 중심으로 바꾸세요.

* 클론 이름 있으면: 클론 이름
* 없으면: `Clone`
* 사용자에게 보이는 라벨에서 `Clone AI`는 쓰지 마세요.

내부 변수명, 큐 이름, 로그 태그의 `AI`는 굳이 전부 바꾸지 않아도 됩니다. 사용자에게 보이는 문장과 history/expanded 생성 로직이 핵심입니다.

---

# 4. `routine_mode_roleplay.dart` 수정

## A. Roleplay partner label helper 추가

Roleplay 확장문장용 helper를 추가하세요.

partner label 우선순위:

1. `_scenarioAiRole`
2. `_RoleplayScenarioStore.aiRole`
3. `the roleplay partner`

user label 우선순위:

1. `_scenarioUserRole`
2. `_RoleplayScenarioStore.userRole`
3. `the user`

situation label도 있으면 같이 보존하세요.

* `_scenarioSituation`
* `_scenarioKeyword`

## B. `chat_history` 방 문서 생성 시 roleplay 정보 저장

`_ensureHistoryRef()`에서 새 방 문서 생성 시 다음 필드를 추가하세요.

* `mode`: `roleplay`
* `scenario_situation`
* `scenario_keyword`
* `user_role`
* `ai_role`
* `user_label`
* `partner_label`
* `expand_partner_type`: `roleplay`

기존 `room_name: "Roleplay Mode"`는 유지해도 됩니다.

## C. 종료 시 transcript 생성 수정

현재 종료 저장 로직에서 `_localMessages`를 transcript로 만들 때:

* `HOST` → `User`
* `SYSTEM` → `AI`

형태로 되어 있습니다.

이걸 다음처럼 바꾸세요.

* `HOST` → user label 또는 user role
* `SYSTEM` → partner label 또는 ai role
* 절대 `SYSTEM`을 `AI`로 쓰지 마세요.

예:

`Customer: I booked a room, but the hotel says it is missing.`
`Hotel clerk: I’m sorry, let me check the booking right away.`

## D. `RoleplayBrain.generateExpandedFromConversation()` 수정

현재 프롬프트에 `between the user and an AI partner`가 들어 있습니다. 이 표현을 제거하세요.

함수 인자로 다음을 추가하세요.

* `userLabel`
* `partnerLabel`
* 필요하면 `situation`

프롬프트 핵심 규칙:

* This is a roleplay conversation between `{userLabel}` and `{partnerLabel}`.
* `{partnerLabel}` is the role being played, not “AI”.
* Never call `{partnerLabel}` AI, assistant, chatbot, or bot.
* If the partner must be mentioned, use `{partnerLabel}` or a natural role phrase.
* Use the roleplay situation only if it is supported by the transcript.
* Keep one sentence, 25–40 words.
* About 5 meaning units.
* 5–7 words per breath group.
* Spoken, natural English.
* No added facts.

## E. `RoleplayBrain.polishSentence()` 수정

Polished 단계에도 다음 규칙 추가:

* Preserve role names and participant labels.
* Do not replace role names with AI, assistant, chatbot, or bot.
* Same meaning only.
* No new facts.

## F. 저장 필드 추가

Roleplay 종료 시 expanded/polished 저장과 함께 다음 필드를 저장하세요.

* `expanded_sentence`
* `polished_sentence`
* `has_practice`: true
* `expand_source`: `exit`
* `expand_generated_at`
* `expand_user_label`
* `expand_partner_name`
* `expand_partner_type`: `roleplay`
* `expand_schema_version`: `named_partner_v1`

## G. 사용자에게 보이는 Roleplay UI 라벨 정리

현재 화면 일부에 `AI`, `AI Roleplay`, `AI 역할` 같은 표현이 있습니다.

모두 바꿀 필요는 없지만, 사용자가 실제 연습 중 보는 영역에서는 가능한 한 역할 중심으로 바꾸세요.

권장:

* `AI 역할` → `상대 역할`
* `AI Roleplay` → `Roleplay`
* 대화 카드의 작은 `AI` 라벨 → `_scenarioAiRole` 또는 `Partner`
* 내부 로그/변수명은 유지 가능

핵심은 Expanded / Polished 문장에서는 절대 `AI`가 상대명으로 나오지 않게 하는 것입니다.

---

# 5. `chat_history_master.dart` 수정

히스토리에서 Expanded Sentence 버튼을 누르면, 기존 저장값을 그대로 쓰거나 fallback으로 새로 생성합니다. 여기서도 같은 문제가 반복됩니다.

## A. history 문서에서 partner label 읽기

`_buildExpandFromConversation()`에서 history 문서를 읽을 때 다음 필드를 확보하세요.

공통:

* `mode`
* `room_name`
* `user_label`
* `partner_label`
* `expand_user_label`
* `expand_partner_name`
* `expand_partner_type`
* `expand_schema_version`

Clone 전용:

* `clone_id`
* `clone_name`

Roleplay 전용:

* `scenario_situation`
* `scenario_keyword`
* `user_role`
* `ai_role`

## B. 모드별 label 결정 규칙

Clone:

1. `partner_label`
2. `clone_name`
3. `expand_partner_name`
4. `clone_id`가 있으면 `users/{uid}/clones/{clone_id}`에서 name 조회
5. `the clone`

Clone user label:

1. `user_label`
2. `expand_user_label`
3. `the user`

Roleplay:

partner label 우선순위:

1. `partner_label`
2. `ai_role`
3. `expand_partner_name`
4. `the roleplay partner`

user label 우선순위:

1. `user_label`
2. `user_role`
3. `expand_user_label`
4. `the user`

Step Expand:

* 기존 로직 유지
* 단, clone/roleplay용 label 규칙을 step_expand에 강제로 적용하지 마세요.

## C. fallback transcript 생성 로직 수정

현재 `_buildExpandFromConversation()` fallback에서 `_tutorLines`를 transcript로 만들 때 `HOST`를 `AI`, 나머지를 `User`로 바꾸는 위험한 매핑이 있습니다.

이 부분을 반드시 수정하세요.

Clone / Roleplay 기준:

* 저장된 실제 발화 role이 `HOST`면 user label
* 저장된 실제 발화 role이 `SYSTEM`이면 partner label
* `USER` / `AI` 등 튜터링용 변환 role이나 `_swapRoles` 기준을 쓰지 마세요.
* 확장문장 생성용 transcript는 “튜터링에서 누가 연습하느냐”가 아니라 “원래 대화에서 누가 말했느냐”를 기준으로 해야 합니다.

중요:

* `_swapRoles`
* `_isAiTurn()`
* 튜터링 역할 선택 상태

이것들은 확장문장 생성 transcript에 영향을 주면 안 됩니다.

## D. 기존 cached expanded 재사용 조건 수정

현재는 `expanded_sentence`가 있으면 우선 사용합니다. 이러면 이미 “AI”로 잘못 생성된 문장이 계속 살아남습니다.

Clone / Roleplay 모드에서는 다음 조건이면 기존 expanded를 무시하고 재생성하세요.

* `expand_schema_version`이 `named_partner_v1`이 아님
* `expand_partner_name`이 현재 partner label과 다름
* `expand_partner_type`이 현재 mode와 맞지 않음
* expanded/polished 안에서 상대를 `the AI`, `AI`, `assistant`, `chatbot`, `bot`으로 부른 흔적이 있음

단, 마지막 조건은 보조 조건으로만 쓰세요. 대화 주제 자체가 AI일 수 있기 때문입니다. 가장 중요한 기준은 `expand_schema_version`입니다.

## E. `_generateExpandedFromConversation()` 수정

현재 프롬프트에 `between the user and an AI partner`가 있습니다. 제거하세요.

함수 인자로 다음을 추가하세요.

* `userLabel`
* `partnerLabel`
* `mode`
* 필요하면 `situation`

프롬프트 핵심 규칙:

* For clone mode: conversation is between `{userLabel}` and `{partnerLabel}`, a named clone/persona.
* For roleplay mode: conversation is between `{userLabel}` and `{partnerLabel}`, a roleplay character.
* `{partnerLabel}` is not AI.
* Never call `{partnerLabel}` AI, assistant, chatbot, or bot.
* Use `{partnerLabel}` or a natural role phrase when referring to the partner.
* Keep one sentence, 25–40 words.
* About 5 breath groups.
* 5–7 words per breath group.
* No added facts.

## F. `_polishExpandedSentence()` 수정

Polished prompt에도 다음 규칙 추가:

* Preserve participant names, clone names, and role labels.
* Do not replace them with AI, assistant, chatbot, or bot.
* Same meaning only.
* No new facts.

## G. 재생성 후 history 문서 업데이트

재생성 후 다음 필드를 반드시 업데이트하세요.

* `expanded_sentence`
* `polished_sentence`
* `has_practice`: true
* `expand_source`: `history_regenerated` 또는 `fallback`
* `expand_generated_at`
* `expand_user_label`
* `expand_partner_name`
* `expand_partner_type`: `clone` 또는 `roleplay`
* `expand_schema_version`: `named_partner_v1`

---

# 6. 절대 건드리지 말 것

* BillingTicker
* RevenueCat
* Usage Log
* Auto Pause
* VAD / Deepgram / TTS 큐 구조
* Step Expand의 기본 대화 흐름
* APK/AAB 빌드 명령

내부 변수명이나 로그에 있는 `AI`를 전부 바꾸려 하지 마세요. 너무 큰 리팩터링이 됩니다. 이번 수정 범위는 **사용자에게 보이는 문장, history 저장 메타데이터, expanded/polished 생성 프롬프트와 transcript 매핑**입니다.

---

# 7. 테스트 기준

## Clone 테스트

클론 이름: `컴수리` 또는 `Comsuri`

잘못된 결과:

`The user complains about the repair issue, while the AI apologizes and promises to check it.`

정상 결과:

`The user complains about the repair issue, while Comsuri apologizes, explains the situation, and promises to check it.`

## Roleplay 테스트

상황: `호텔 예약 누락`
내 역할: `customer`
상대 역할: `hotel clerk`

잘못된 결과:

`The user complains about the missing reservation, while the AI apologizes and checks the booking.`

정상 결과:

`The customer complains about the missing reservation, while the hotel clerk apologizes, checks the booking, and offers another option.`

## History 테스트

1. 기존에 `AI`가 들어간 expanded 기록 열기
2. Expanded Sentence 버튼 누르기
3. `expand_schema_version`이 없거나旧버전이면 재생성되는지 확인
4. 새 문장에 `AI`, `assistant`, `chatbot`, `bot`이 상대 지칭으로 나오지 않는지 확인
5. 새 필드 `expand_partner_name`, `expand_partner_type`, `expand_schema_version` 저장 확인

---

이 통합 수정이 맞습니다. Clone은 **클론 이름**, Roleplay는 **역할 이름**으로 가야 합니다.
생활영어 느낌으로도 `the AI apologized`보다 `the hotel clerk apologized`가 훨씬 자연스럽고, 실제 상황 훈련처럼 들립니다.
