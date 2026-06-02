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

## Claude Code 지시문

파일:
`lib/custom_code/widgets/routine_mode_step_expand.dart`

목표:
Step Expand의 시작 방식을 **AI가 먼저 질문하는 구조**에서 **유저가 먼저 기본 문장을 제안하는 구조**로 되돌린다.

핵심 요구사항:

1. **대화 방식, 5턴 확장 패턴, 문장 확장 로직, Part1/Part2 구조, 히스토리 저장 구조는 절대 건드리지 않는다.**
2. 바꿀 것은 오직 **세션 첫 발화 진입 방식**이다.
3. 기존처럼 AI가 먼저 주제 질문을 만들면 안 된다.
4. 세션 시작 시 AI는 다음 안내문만 말하고 대기한다.

문구:

> 대화하면서 문장을 늘려가고 싶은 기본 문장을 하나 제안해 주세요.

5. 이 안내문은 “질문 생성”이 아니라 “시작 안내”다.
6. 안내문 재생 후 바로 STT를 시작해서 유저의 첫 기본 문장을 기다린다.
7. 유저가 말한 첫 문장을 기존 파이프라인으로 그대로 보내서, 이후 Step Expand의 기존 5턴 확장 흐름이 계속 진행되게 한다.

---

## 수정할 부분

### 1. `_fetchKeys()` 수정

현재 흐름:

* Firebase Remote Config 키 로드
* 키 로드 완료 후 `_startSessionWithAiQuestion()` 호출
* AI가 먼저 개방형 질문 생성

이 구조를 제거한다.

변경 방향:

* 키 로드 완료 후 `_startSessionWaitingForUserSeed()` 같은 새 시작 함수 호출
* 이 함수는 AI 질문 생성 API를 호출하지 않는다.
* 안내문 TTS만 재생하고 STT를 시작한다.

주의:

* `_fetchKeys()` 안의 주석 `키 로드 완료 → AI가 먼저 개방형 질문 발화` 같은 문구도 삭제하거나 변경한다.
* 예: `키 로드 완료 → 시작 안내 후 유저 기본 문장 대기`

---

### 2. `_startSessionWithAiQuestion()` 제거 또는 대체

현재 함수는 다음 일을 하고 있다.

* SYSTEM 버블 생성
* `StepExpandBrain.streamGrammarQuestion(... isOpening: true)` 호출
* AI 오프닝 질문 생성
* AI 질문 TTS 재생
* 재생 완료 후 STT 시작

이 함수는 더 이상 맞지 않는다.

변경 방향:

함수명을 새 구조에 맞게 바꾼다.

권장 이름:

`_startSessionWaitingForUserSeed()`

기능:

* `_resetIdleTimer()`
* `_isConversationActive = true`
* 안내문을 화면에 표시할지 여부는 선택 가능하나, 표시한다면 SYSTEM 안내 버블로만 표시
* 이 안내문은 Firestore 대화 턴으로 저장하지 않는다.
* OpenAI 질문 생성 API 호출 금지
* TTS로 아래 안내문만 재생

> 대화하면서 문장을 늘려가고 싶은 기본 문장을 하나 제안해 주세요.

* TTS 완료 후 `_startDeepgramListening()` 호출
* 유저 첫 발화가 들어오면 기존 `_commitTranscriptAndRunPipeline()` 또는 현재 연결된 기존 파이프라인이 그대로 처리하게 한다.

중요:

* 유저의 첫 문장이 `_turnCounter == 0` 상태에서 들어가야 한다.
* 이 첫 문장이 Step Expand의 “기본 seed 문장”이 된다.
* 이후 AI는 기존 `streamGrammarQuestion()`의 일반 턴 질문 로직을 사용해서 문장을 확장한다.

---

### 3. `streamGrammarQuestion()`의 `isOpening` 분기 제거

현재 `StepExpandBrain.streamGrammarQuestion()` 안에 `isOpening = true`일 때 AI가 뉴스/일상 소재를 골라 첫 질문을 생성하는 분기가 있다.

이제 필요 없다.

삭제 대상:

* `isOpening` 파라미터
* `bool isOpening = false` 주석 중 “세션 첫 시작 — AI가 먼저 개방형 질문”
* `if (isOpening) { ... }` 전체 분기
* 68k.news 또는 GPT로 오프닝 주제/질문을 만드는 로직
* “AI가 먼저 개방형 질문” 관련 주석
* “첫 질문 이후 유저 대답부터 문장 확장 시작” 같은 AI-first 설명

주의:

* 일반 턴 질문 생성 로직은 절대 삭제하지 않는다.
* 턴 1~MAX_TURNS에서 유저 문장을 더 자연스럽게 확장하기 위한 질문 생성 프롬프트는 그대로 유지한다.
* 최종 확장문장 생성, Polished Sentence 생성, Part1/Part2 출력 규칙도 그대로 유지한다.

---

### 4. 새 주제 / 리셋 / Suggest New Sentence 흐름 수정

현재 아래 위치들이 `_startSessionWithAiQuestion()`을 다시 호출한다.

* 5턴 완료 후 새 주제 시작
* 리셋 버튼
* 진행 중 새 주제
* `_suggestNewSentence()` 끝부분

모두 새 시작 함수로 교체한다.

변경 전 의미:

* 새 주제 시작 → AI가 먼저 질문

변경 후 의미:

* 새 주제 시작 → 안내문 재생 → 유저 기본 문장 대기

즉, 모든 재시작 지점은 다음 흐름으로 통일한다.

`_resetSession()`
→ `_startSessionWaitingForUserSeed()`

주석도 함께 수정한다.

예:

* `AI 먼저 질문` 삭제
* `유저 기본 문장 대기` 또는 `시작 안내 후 유저 seed 문장 대기`로 변경

---

### 5. 설계 원칙 주석 수정

현재 상단 주석에 다음 취지의 내용이 있다.

* AI가 먼저 말한다
* AI-First
* 개방형 질문 원칙
* 세션 시작 시 AI가 개방형 질문을 먼저 생성·발화
* 유저는 듣다가 대답

이 내용은 전부 현재 목표와 반대이므로 삭제 또는 수정한다.

새 설계 원칙:

* Step Expand는 유저가 먼저 기본 문장을 제안한다.
* AI는 시작 안내만 하고 대기한다.
* 유저의 첫 문장이 확장 seed가 된다.
* 이후 AI는 기존 5턴 확장 패턴대로 짧은 유도 질문을 한다.
* 대화 패턴과 확장 로직은 기존 유지.

---

### 6. 침묵/망설임 폴백 문구 정리

현재 침묵 타이머 주석과 로그가 “첫 질문 침묵” 기준으로 되어 있다.

변경 방향:

* “첫 질문 침묵”이 아니라 “기본 문장 입력 대기 중 침묵”으로 표현 변경
* 폴백 문구도 질문 재생 후 대기하는 느낌이 아니라, 유저가 기본 문장을 말하도록 부드럽게 안내하는 느낌으로 변경

예:

> 짧아도 괜찮아요. 먼저 떠오르는 기본 문장을 하나 말해 주세요.

주의:

* 침묵 폴백 자체는 유지해도 된다.
* 단, 다시 AI 질문을 생성하면 안 된다.

---

### 7. 절대 건드리지 말 것

아래는 수정 금지:

* 기존 5턴 확장 구조
* MAX_TURNS
* `_runPipeline` 계열 처리
* 유저 발화 STT 처리
* 유저 문장 → target/original 생성 로직
* Part1/Part2 분리 규칙
* Firestore 저장 구조
* History 저장 구조
* Polished Sentence 생성
* Practice 모드
* 스크롤 방식
* TTS 큐 구조
* 문장 확장 프롬프트 중 “턴별 유도 질문” 로직

이번 수정은 **첫 발화의 주도권만 AI에서 유저로 돌리는 작업**이다.

---

## 기대 동작

수정 후 Step Expand 진입 시:

1. 화면 진입
2. API 키 로드
3. AI가 딱 한 번 안내

> 대화하면서 문장을 늘려가고 싶은 기본 문장을 하나 제안해 주세요.

4. AI는 대기
5. 마이크/STT 자동 시작
6. 유저가 예를 들어 “I want to travel.”이라고 말함
7. 이 문장이 첫 seed가 됨
8. 이후 기존 Step Expand 방식 그대로 AI가 짧은 유도 질문을 하며 문장을 늘려감
9. 5턴 완료 후 기존처럼 Expanded Sentence / Polished Sentence / Practice 흐름 유지

---

## 검증 기준

수정 후 반드시 확인:

1. Step Expand 진입 직후 AI가 뉴스/일상 주제 질문을 하지 않아야 한다.
2. 첫 안내문은 정확히 다음 문장이어야 한다.

> 대화하면서 문장을 늘려가고 싶은 기본 문장을 하나 제안해 주세요.

3. 안내문 후 STT가 자동 시작되어야 한다.
4. 유저 첫 발화가 첫 seed 문장으로 처리되어야 한다.
5. 이후 AI의 유도 질문/확장 패턴은 기존과 동일해야 한다.
6. 새 주제, 리셋, Suggest New Sentence 후에도 AI 질문이 아니라 같은 안내문으로 시작해야 한다.
7. `flutter analyze`에서 새 error가 없어야 한다.
8. APK/AAB 빌드 명령은 실행하지 말고, 코드 수정과 analyze/check까지만 진행한다.

---

핵심은 이겁니다: **AI가 “무슨 이야기를 해볼까요?”라고 주제를 던지는 앱이 아니라, 유저가 “내가 늘리고 싶은 기본 문장”을 먼저 던지고 AI가 그 문장을 확장해주는 앱**으로 되돌리는 수정입니다.
