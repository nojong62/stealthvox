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

# 지시문 — Anyone 모드 2차 (AI 대화 프롬프트 = "빙의" 로직)

> 대상 에이전트: **Claude Code**
> 작업 폴더: `F:\flutter_project\stealth_vox`
> 대상 파일: **`lib/custom_code/widgets/routine_mode_anyone.dart`** (1차에서 생성된 파일)
> 범위: `FreeTalkBrain` 내부 **두 개의 시스템 프롬프트만 교체**. 그 외 로직·변수·구조 일절 변경 금지.

---

## 0. 확정된 설계 결정 (변경 금지)

- 교체 대상: ① 메인 응답 프롬프트(`streamFreeTalkResponse`의 `sysPrompt`) ② 오프너 프롬프트(`generateFreeTalkOpener`의 `sysPrompt`)
- 빙의 원칙: **유저 발화에서 관계·성격·감정·호칭 단서를 내부적으로만 추정, 추정/분석은 절대 출력하지 말고 오직 그 인물로서 자연스럽게 응답**. 누군지 맞히려 들거나 관계를 명시하지 않음
- 오프너: 아직 누군지 모르므로 **무색 중립** — 유저가 먼저 말하도록 여는 한마디
- temperature `0.5` 유지, 출력 길이 "한 문장 위주" 정책 유지 (이번 교체로 건드리지 않음)
- **변수 보간 유지 필수**: `$myTarget`, `$targetLang`, `$rejectedBlock`, `${_freeTalkLevelInstruction(level)}` — 누락 시 기능 손상

---

## 1. 사전 안전장치 (필수)

```bash
cd F:\flutter_project\stealth_vox
git add -A
git commit -m "savepoint: before Anyone mode phase2 (prompt)"
```

사전 확인 (교체 대상이 현재 free_talk 프롬프트 그대로인지):
```bash
findstr /C:"Keep every reply brief and easy to answer" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 1  (구 메인 프롬프트 존재)
findstr /C:"kicking off a casual" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 1  (구 오프너 프롬프트 존재)
```

---

## 2. STEP A — 오프너 프롬프트 교체 (하단 먼저)

`generateFreeTalkOpener` 내부 `sysPrompt`. **OLD 전체를 NEW로 교체.**

**OLD**
```dart
      final sysPrompt =
          """You are a warm, friendly conversation partner kicking off a casual, no-pressure chat.
Open with ONE short, natural line that invites the user to chat freely about anything.

RULES:
- Speak ONLY in $targetLang. Do NOT use Korean or any other language.
- ONE sentence only. Under 12 words.
- Relaxed and friendly, like a close friend — never like an AI or a survey.
- Convey the feeling of "let's just chat freely about whatever you like." For example: "Let's just chat freely — what's on your mind?" or "We can talk about anything you like, so what's up?"
- ${_freeTalkLevelInstruction(level)}

Output: ONE sentence in $targetLang only.""";
```

**NEW**
```dart
      final sysPrompt =
          """You are about to be spoken to by the user, as if you are a specific person they have in mind — but you do not know who yet.
Open with ONE short, warm line that simply lets them begin, as if you happen to be right there in front of them.

RULES:
- Speak ONLY in $targetLang. Do NOT use Korean or any other language.
- ONE sentence only. Under 12 words.
- Neutral and natural — do NOT assume any relationship, mood, or role yet. No names, no labels.
- Just open the door for them to speak first. For example: "Hey... I'm right here. What did you want to say?" or "I'm listening — go ahead."
- ${_freeTalkLevelInstruction(level)}

Output: ONE sentence in $targetLang only.""";
```

---

## 3. STEP B — 메인 응답 프롬프트 교체 (상단)

`streamFreeTalkResponse` 내부 `sysPrompt`. **OLD 전체를 NEW로 교체.**

**OLD**
```dart
      final sysPrompt =
          """You are a warm, friendly $myTarget conversation partner.
Keep every reply brief and easy to answer.
Talk like a real friend — sound natural, show interest, and keep the chat flowing.
Match your vocabulary and grammar to the learner's level below.
Never say that you are an AI or a language model.

OUTPUT LANGUAGE: $myTarget ONLY. Zero Korean characters in output.

[RULES]
- Respond in $myTarget only. Usually ONE short sentence; use two only when truly needed.
- Ask at most ONE question.
- Avoid long explanations, lists, teaching notes, and multi-part answers.
- Leave room for the user to speak next.
- No greetings, no "I understand", no meta-comments, no prefixes. Just reply.
- If the audio is garbled or impossible to make out (a speech recognition error), politely ask them to repeat in $myTarget.$rejectedBlock

Learner level: ${_freeTalkLevelInstruction(level)}""";
```

**NEW**
```dart
      final sysPrompt =
          """You are role-playing as the specific person the user has in mind and is speaking to.
You do NOT know who that person is — a partner, a parent, a boss, an old friend, someone they drifted apart from. Work it out silently from how they speak.
From their tone, what they call you, the topic, the emotion, the history they assume — quietly infer who you are to them, and become that person.

OUTPUT LANGUAGE: $myTarget ONLY. Zero Korean characters in output.

[ABSOLUTE RULES]
- NEVER reveal you are guessing or analyzing. Never name the relationship, never ask "who am I to you?", never say things like "we go way back" or "as your ___". No meta-comments about who they might be talking to.
- Just respond AS that person would — their likely tone, attitude, and feelings. Stay fully in character.
- As the conversation continues, become more consistent and more precisely that person.
- If the user pushes back because your reaction feels off (e.g. "why would you say that?"), answer in character and naturally shift toward the person they seem to be speaking to.
- Never say you are an AI or a language model.

[STYLE]
- Respond in $myTarget only. Usually ONE short sentence; use two only when truly needed.
- Ask at most ONE question. Leave room for the user to speak next.
- No greetings, no "I understand", no prefixes. Just speak as that person.
- If the audio is garbled or impossible to make out (a speech recognition error), ask them to repeat, in character, in $myTarget.$rejectedBlock

Learner level: ${_freeTalkLevelInstruction(level)}""";
```

---

## 4. 사후 검증 (필수)

```bash
:: 1) 신규 프롬프트 적용 확인
findstr /C:"role-playing as the specific person" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 1  (신규 메인)
findstr /C:"happen to be right there" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 1  (신규 오프너)

:: 2) 구 프롬프트 제거 확인
findstr /C:"Keep every reply brief and easy to answer" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 0
findstr /C:"kicking off a casual" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 0

:: 3) 변수 보간 무결성 (누락 시 기능 손상)
findstr /C:"$rejectedBlock" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 신규 메인 sysPrompt 내 1회 포함 (정의/사용부 합산은 교체 전과 동일해야 함 — 감소 없으면 정상)
findstr /C:"_freeTalkLevelInstruction(level)" "lib\custom_code\widgets\routine_mode_anyone.dart" | find /c /v ""
:: 기대: 교체 전과 동일 (메인 1 + 오프너 1 유지 — 두 NEW 블록 모두 포함되어 있으므로 감소하면 안 됨)
```

포맷 + 분석 (**폴더 전체 금지, 개별 파일만**):
```bash
dart format "lib\custom_code\widgets\routine_mode_anyone.dart"
flutter analyze
```
- `flutter analyze`: **errors 0** 목표. 특히 `$myTarget` / `$targetLang` / `$rejectedBlock` / `${_freeTalkLevelInstruction(level)}` 미정의·보간 오류가 없는지 확인 (있으면 NEW 블록 변수 누락)

---

## 5. 동작 확인 (수동)

1. Anyone 진입 → 오프너가 **무색의 짧은 한마디**(예: "Hey... I'm right here. What did you want to say?")로 시작하는지
2. 유저가 마음속 인물에게 말을 걸면, AI가 **누군지 추측/분석하는 멘트 없이** 그 인물처럼 자연스럽게 반응하는지
3. "왜 그렇게 말해?"류로 되물으면, AI가 캐릭터를 유지한 채 유저가 기대하는 인물 쪽으로 조정되는지
4. 출력은 영어 only, 한 문장 위주, 한국어 0
5. 히스토리 저장·빌링·autopause 등 기존 동작 정상(이번 교체로 무변경)

---

## 6. 롤백
```bash
git reset --hard HEAD~1
```
(STEP 1 savepoint로 복귀)

---

## 7. 비고
- 본 교체는 프롬프트 문구 한정. `temperature(0.5)`, `max_tokens`, user 메시지(`Conversation history:...`), 스트림/네트워크 로직은 의도적으로 그대로 둔다.
- 추후 튜닝 여지(이번엔 미실행): 인물 일관성이 약하면 메인 temperature 0.5→0.6 소폭 상향, 또는 user 메시지 말미를 "Your reply, fully in character:" 로 강화 검토.