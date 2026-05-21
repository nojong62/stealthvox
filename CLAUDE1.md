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

# Claude Code 지시문 v3.9 — 한국어 주어 판별 강화 (Clone + Roleplay)

## 목적
GPT-4o-mini가 한국어 → 영어 번역 시 주어/목적어를 혼동하는 문제를 개선한다.
모델은 변경하지 않고, 시스템 프롬프트에 **한국어 조사 기반 판별 규칙(B)** + **틀리기 쉬운 패턴의 Few-shot 예시(C)**를 추가한다.

## 대상 파일 및 위치

| 파일 | 클래스 | 함수 | 줄 번호 (대략) |
|------|--------|------|----------------|
| `routine_mode_clone.dart` | `CloneBrain` | `streamUserTranslation` | 3379~3394 (sysPrompt 문자열) |
| `routine_mode_roleplay.dart` | `RoleplayBrain` | `streamUserTranslation` | 3348~3363 (sysPrompt 문자열) |

## 변경 원칙

1. **코드 구조는 일체 변경하지 않는다** — sysPrompt 문자열 내부의 텍스트만 수정
2. **기존 섹션은 모두 유지한다** — `[INTERNAL THINKING]`, `[OUTPUT RULES]` 등 기존 구조 보존
3. **두 개의 새 섹션을 `[INTERNAL THINKING]`과 `[OUTPUT RULES]` 사이에 삽입한다**
4. 따옴표/이스케이프 주의: 프롬프트 내부 영어 문자열은 큰따옴표(`"`) 사용. Dart 삼중따옴표(`'''` 또는 `"""`) 내부이므로 작은따옴표 이스케이프 문제 없는지 확인할 것

---

## 변경 ①: routine_mode_clone.dart — CloneBrain.streamUserTranslation

### 현재 코드 (삭제 대상)
```
[INTERNAL THINKING - do not output]
Step 1. CONTEXT CHECK: Review the conversation history to identify who is speaking, who is being addressed, and who/what is the current topic.
Step 2. SUBJECT RESTORATION: Identify any omitted subject, object, or pronoun in the current Korean input and restore them based on context.
Step 3. TRANSLATE: Produce natural, fluent $targetLang with explicit subjects (I, you, he, she, they, we).

[OUTPUT RULES]
```

### 교체할 코드
```
[INTERNAL THINKING - do not output]
Step 1. CONTEXT CHECK: Review the conversation history to identify who is speaking, who is being addressed, and who/what is the current topic.
Step 2. SUBJECT RESTORATION: Identify any omitted subject, object, or pronoun in the current Korean input and restore them based on context.
  Use these Korean grammar markers to determine roles:
  - ~이/가 = SUBJECT marker (doer of action): "엄마가 사줬어" → Mom bought it (Mom is subject)
  - ~은/는 = TOPIC marker (often the subject): "나는 갔어" → I went
  - ~한테/에게 = RECIPIENT marker (indirect object): "나한테 줬어" → gave it TO ME
  - ~을/를 = OBJECT marker (thing acted upon): "그걸 봤어" → saw THAT
  - Honorific ~(으)시 attaches to the SUBJECT's verb: "선생님이 오셨어" → The teacher came (teacher is subject, not me)
  - ~해줬어/해주셨어 = someone did something FOR someone else: the person before 가/이 is the doer
Step 3. TRANSLATE: Produce natural, fluent $targetLang with explicit subjects (I, you, he, she, they, we).

[COMMON MISTAKES - avoid these]
Korean: "걔가 나한테 전화했어" → CORRECT: He called me. WRONG: I called him.
Korean: "엄마가 용돈 줬어" → CORRECT: Mom gave me allowance. WRONG: I gave mom allowance.
Korean: "선생님이 칭찬해주셨어" → CORRECT: The teacher praised me. WRONG: I praised the teacher.
Korean: "친구가 요즘 바빠서 못 만나" → CORRECT: My friend is busy lately, so I can't meet him. WRONG: I'm busy lately...
The particle before the verb's doer (이/가) is ALWAYS the subject. Never swap subject and object.

[OUTPUT RULES]
```

---

## 변경 ②: routine_mode_roleplay.dart — RoleplayBrain.streamUserTranslation

### 현재 코드 (삭제 대상)
```
[INTERNAL THINKING - do not output]
Step 1. CONTEXT CHECK: Review conversation history.
Step 2. SUBJECT RESTORATION: The speaker is${userRole.isNotEmpty ? ' a "$userRole"' : ' the user'}. Identify and restore any omitted subject/pronoun from THEIR perspective.
Step 3. TRANSLATE: Produce natural $targetLang speech that fits${userRole.isNotEmpty ? ' the "$userRole" role' : ' the user'}.

[OUTPUT RULES]
```

### 교체할 코드
```
[INTERNAL THINKING - do not output]
Step 1. CONTEXT CHECK: Review conversation history.
Step 2. SUBJECT RESTORATION: The speaker is${userRole.isNotEmpty ? ' a "$userRole"' : ' the user'}. Identify and restore any omitted subject/pronoun from THEIR perspective.
  Use these Korean grammar markers to determine roles:
  - ~이/가 = SUBJECT marker (doer of action): "엄마가 사줬어" → Mom bought it (Mom is subject)
  - ~은/는 = TOPIC marker (often the subject): "나는 갔어" → I went
  - ~한테/에게 = RECIPIENT marker (indirect object): "나한테 줬어" → gave it TO ME
  - ~을/를 = OBJECT marker (thing acted upon): "그걸 봤어" → saw THAT
  - Honorific ~(으)시 attaches to the SUBJECT's verb: "선생님이 오셨어" → The teacher came (teacher is subject, not me)
  - ~해줬어/해주셨어 = someone did something FOR someone else: the person before 가/이 is the doer
Step 3. TRANSLATE: Produce natural $targetLang speech that fits${userRole.isNotEmpty ? ' the "$userRole" role' : ' the user'}.

[COMMON MISTAKES - avoid these]
Korean: "걔가 나한테 전화했어" → CORRECT: He called me. WRONG: I called him.
Korean: "엄마가 용돈 줬어" → CORRECT: Mom gave me allowance. WRONG: I gave mom allowance.
Korean: "선생님이 칭찬해주셨어" → CORRECT: The teacher praised me. WRONG: I praised the teacher.
Korean: "친구가 요즘 바빠서 못 만나" → CORRECT: My friend is busy lately, so I can't meet him. WRONG: I'm busy lately...
The particle before the verb's doer (이/가) is ALWAYS the subject. Never swap subject and object.

[OUTPUT RULES]
```

---

## 검증 체크리스트 (Claude Code가 완료 후 확인)

- [ ] Clone: sysPrompt 내부에 `[COMMON MISTAKES - avoid these]` 섹션이 존재하는가?
- [ ] Clone: `Step 2. SUBJECT RESTORATION:` 아래에 조사 마커 6줄이 들어갔는가?
- [ ] Roleplay: sysPrompt 내부에 `[COMMON MISTAKES - avoid these]` 섹션이 존재하는가?
- [ ] Roleplay: `Step 2. SUBJECT RESTORATION:` 아래에 조사 마커 6줄이 들어갔는가?
- [ ] 두 파일 모두 `[OUTPUT RULES]` 섹션이 기존 그대로 유지되는가?
- [ ] Dart 문법 에러 없음 (따옴표 이스케이프, 삼중따옴표 경계 확인)
- [ ] `$targetLang`, `$userRole` 등 Dart 변수 보간이 깨지지 않았는가?
- [ ] Roleplay의 `${userRole.isNotEmpty ? ...}` 삼항 표현식이 그대로 유지되는가?

## 토큰 영향 분석

추가되는 프롬프트 텍스트: 약 180 토큰 (각 모드당)
- 조사 마커 규칙: ~100 토큰
- Few-shot 틀린 예시: ~80 토큰
- GPT-4o-mini max_tokens=120은 그대로 유지 (출력 제한이므로 시스템 프롬프트 증가와 무관)
- 전체 요청 토큰이 약 180 증가하지만, 4o-mini의 128K 컨텍스트 대비 무시 가능

## 절대 건드리지 말 것

- sysPrompt 바깥의 Dart 코드 (http.Client, request, response 처리 등)
- `temperature`, `max_tokens`, `model` 파라미터
- `[EVAPORATE]` 관련 로직
- Box 7 (TtsQueueManager, DeepgramV2VoiceManager) 코드 전체