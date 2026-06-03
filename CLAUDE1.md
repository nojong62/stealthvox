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

지시문: Expanded / Polished Sentence 의미단위 분할 기준 통일

현재 StealthVox의 Step Expand, Clone, Roleplay 3모드 모두 expanded_sentence와 polished_sentence를 생성한다.
이제 History Practice3에서 확장 문장과 Polished 문장을 읽을 때, 의미단위는 반드시 한 호흡에 말할 수 있는 5~7단어 정도로 끊어야 한다.

너무 길게 끊으면 사용자가 한숨에 따라 말하기 어렵고, 너무 짧게 끊으면 영어 리듬이 깨진다.

핵심 수정 목표

chat_history_master.dart의 의미단위 분할 로직을 3모드 공통 기준으로 수정한다.

현재 Expanded Sentence는 _buildChunks() 안에서 _fetchUserTurnCount()로 HOST 메시지 개수를 가져와서 _splitSentenceByTurns(sentence, n)에 넘기고 있다.
이 방식은 더 이상 적합하지 않다.

이제 의미단위 개수는 HOST 메시지 수가 아니라, 문장 자체의 단어 수와 호흡 단위를 기준으로 결정해야 한다.

수정 대상 1: Expanded Sentence 분할

파일: chat_history_master.dart

현재 구조:

_buildChunks(sentence)
_fetchUserTurnCount()
_splitSentenceByTurns(sentence, n)
_buildChunksLegacyList(sentence)

수정 방향:

_fetchUserTurnCount()를 Expanded Sentence 의미단위 분할 기준으로 사용하지 말 것.
_splitSentenceByTurns(sentence, n)의 “정확히 n개로 나누기” 방식을 폐기하거나 보조용으로만 남길 것.
새 기준은 다음과 같다.

의미단위 기준:

기본 목표: 한 청크 5~7단어
허용 범위: 4~8단어
가능하면 8단어를 넘기지 말 것
2~3단어짜리 너무 짧은 조각은 앞뒤 청크와 병합
전치사구, to부정사구, 관계절, because/when/while/although/if 절, and/but/so 앞뒤를 우선 분할 기준으로 사용
문법적으로 자연스러운 호흡이 단어 수보다 우선이지만, 8단어 초과는 다시 나눌 것
최종 결과는 List<String>이며, 각 항목이 Practice3에서 한 번에 AI가 읽고 사용자가 따라 읽는 단위가 되어야 함

예시:

문장:
“I wanted to practice English every day because I felt nervous when speaking with foreigners, but I slowly became more confident after using the app.”

좋은 분할:

I wanted to practice English every day
because I felt nervous
when speaking with foreigners
but I slowly became more confident
after using the app

나쁜 분할:

I wanted to practice English every day because I felt nervous when speaking with foreigners
but I slowly became more confident after using the app
수정 대상 2: GPT 분할 프롬프트 변경

_splitSentenceByTurns()를 계속 사용할 경우, 함수 목적을 바꿔라.

기존:
“Split into exactly n meaningful chunks”

변경:
“Split into natural speaking chunks of 5–7 words each”

프롬프트 요구사항:

Return ONLY a JSON array of strings.
Each chunk should be a natural breath group for speaking practice.
Target 5–7 words per chunk.
Never exceed 8 words unless absolutely unavoidable.
Avoid chunks shorter than 3 words unless it is a very natural phrase.
Prefer splitting at commas, conjunctions, relative clauses, prepositional phrases, infinitive phrases, and adverbial clauses.
Do not rewrite the sentence.
Do not omit or add words.
Preserve the original word order.

중요:

GPT가 분할한 결과도 그대로 믿지 말고, 후처리 검증을 추가한다.

검증 규칙:

9단어 이상 청크가 있으면 규칙 기반으로 다시 분할 시도
1~2단어 청크가 있으면 앞 또는 뒤 청크와 병합
결과가 비어 있거나 문장 누락이 의심되면 fallback 사용
수정 대상 3: Fallback 분할 강화

_buildChunksLegacyList(sentence)도 5~7단어 기준을 반영하도록 수정한다.

현재는 쉼표, 접속사, 관계사 등을 기준으로 나누지만 단어 수 상한이 약하다.
다음 후처리 단계를 추가한다.

8단어 초과 청크는 내부에서 다시 분할한다.
우선 분할 위치:
comma 뒤
because / when / while / although / if / since / after / before 앞
who / which / that / where / when 앞
to + 동사 앞
and / but / so 앞
전치사구 시작점: for, with, about, after, before, in, on, at 등
그래도 8단어를 넘으면 6단어 근처에서 가장 자연스러운 지점으로 분할한다.
2단어 이하 조각은 앞뒤와 병합한다.
최종 청크 평균이 5~7단어에 가깝도록 정리한다.
수정 대상 4: Polished Sentence 분할도 동일 기준 적용

파일: chat_history_master.dart

현재 Polished 문장은 _splitPolishedIntoUnits()에서 따로 분할하고 있다.

수정 방향:

Polished도 Expanded와 같은 “5~7단어 한 호흡” 기준을 적용한다.
가능하면 Expanded와 Polished가 서로 다른 분할 함수를 쓰지 않도록 공통 유틸 함수로 통합한다.
_splitPolishedIntoUnits()는 삭제하거나 내부에서 공통 분할 함수를 호출하도록 바꾼다.
Polished 문장이라고 해서 2~3개 큰 덩어리로만 나누면 안 된다.
Polished도 사용자가 따라 말하는 문장이므로 5~7단어 단위로 잘라야 한다.
수정 대상 5: 캐시 버전 갱신

현재 의미단위 분할 결과가 디스크 캐시에 저장된다.

분할 기준이 바뀌면 기존 캐시가 계속 사용될 위험이 있다.
따라서 chunk cache key에 버전을 추가하거나 기존 캐시 파일명을 변경한다.

예:

기존: chunk_split_${roomId}_${variant}_$hash.json
변경 방향: chunk_split_v2_${roomId}_${variant}_$hash.json

목표:

기존의 잘못 잘린 청크 캐시가 다시 불러와지지 않도록 한다.
수정 대상 6: 3모드 생성 프롬프트 보강

아래 파일들의 Expanded Sentence 생성 프롬프트도 보강한다.

routine_mode_step_expand.dart
routine_mode_clone.dart
routine_mode_roleplay.dart
필요하면 chat_history_master.dart 안의 _generateExpandedFromConversation()도 동일하게 보강

현재는 “about 5 meaning units” 정도만 명시되어 있다.
이제 다음 조건을 추가한다.

Expanded Sentence 생성 조건:

ONE single sentence
25–40 words 정도 유지
about 5 meaning units
each meaning unit should be speakable in one breath, usually 5–7 words
use commas or natural connectors to make breath groups clear
do not create a sentence with one very long clause
common spoken English only

주의:

여기서 문장 자체를 여러 문장으로 나누면 안 된다.
문장은 하나로 유지하되, 나중에 Practice3에서 5~7단어 의미단위로 잘릴 수 있도록 자연스러운 쉼표와 연결어를 포함한다.

최종 기대 결과

Step Expand, Clone, Roleplay 3모드에서 생성된 Expanded Sentence와 Polished Sentence가 History Practice3에 들어갔을 때:

한 청크가 대체로 5~7단어
최대 8단어를 거의 넘지 않음
너무 짧은 1~2단어 조각 없음
사용자가 한숨에 듣고 따라 말하기 쉬움
Expanded와 Polished 모두 같은 기준으로 분할됨
기존 HOST 메시지 개수에 따라 의미단위 수가 결정되지 않음
수정 후 확인 테스트

다음 문장으로 테스트한다.

“I wanted to practice English every day because I felt nervous when speaking with foreigners, but I slowly became more confident after using the app.”

기대 청크 예시:

I wanted to practice English every day
because I felt nervous
when speaking with foreigners
but I slowly became more confident
after using the app

또 다른 테스트:

“After talking with the AI, I realized that I could explain my thoughts more clearly if I practiced small sentences every day.”

기대 청크 예시:

After talking with the AI
I realized that I could explain
my thoughts more clearly
if I practiced small sentences
every day

이 기준으로 chat_history_master.dart의 의미단위 분할 로직을 3모드 공통 Practice3 기준으로 정리해 달라.