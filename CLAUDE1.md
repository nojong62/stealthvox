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

[작업 목적]
클론/롤플레이의 한글 역할·이름·상황 라벨이 확장문장(expanded)·세련문장(polished)에 한글 그대로 박히는 문제를 수정한다. 6개 프롬프트를 "라벨을 영어로 변환 + 한글 금지" 규칙으로 교체하고, chat_history의 캐시 가드에 한글 감지 거부를 추가해 기존 방도 자동 재생성되게 한다.

[공통 주의]
- Box 7(TtsQueueManager, DeepgramV2VoiceManager) 절대 미접촉.
- 프롬프트 문자열은 기존 삼중따옴표(""" """) 유지. URL/마크다운 링크 생성 금지.
- 아래 각 편집은 해당 함수 안의 `final sysPrompt = """` 부터 그 문자열을 닫는 `""";` 까지(한 statement)만 교체한다. 함수의 나머지(http 호출 등)는 건드리지 않는다.
- 줄 번호는 대략값이며, 각 함수 이름과 앵커 문자열로 위치를 확정할 것.


───────────────────────────────────────────
편집 1/7 — routine_mode_clone.dart
함수: CloneBrain.generateExpandedFromConversation (대략 3739줄~)
삭제 구간: 3751줄 `      final sysPrompt = """You are an English speaking coach.`
        ~ 3771줄 `- Output exactly ONE sentence. No quotes, no prefixes, no explanation.""";`
교체 후(전체):
      final sysPrompt = """You are an English speaking coach.
You are given a short conversation transcript.
This conversation is between $safeUserLabel and $safePartnerLabel.
$safePartnerLabel is a named clone/persona, not AI.
Your job: compose ONE long, natural English sentence that synthesizes the overall
content and gist of the WHOLE conversation.

[RULES]
- Never refer to $safePartnerLabel as AI, assistant, chatbot, or bot.
- If the partner must be mentioned, use $safePartnerLabel.
- If any name, role label, or situation appears in Korean, render it in natural English (translate role or description phrases to their English equivalent; romanize real personal names). Never copy Korean text into the sentence.
- The final sentence must be 100% English and must NOT contain any Korean (Hangul) characters.
- It must be ONE single sentence (do not split it into multiple sentences).
- Keep it 25–40 words.
- Build it from about 5 meaning units joined with varied grammatical connectives
  (because, so, while, which, after, even though, and, etc.).
- Each meaning unit should be speakable in one breath, usually 5–7 words.
- Use commas or natural connectors to make breath groups clear.
- Do not create a sentence with one very long clause.
- Natural, speakable rhythm — common spoken English only.
- Capture the overall situation/idea of the conversation, not just one line.
- Common everyday vocabulary only. Do not add facts not in the transcript.
- Output exactly ONE sentence. No quotes, no prefixes, no explanation.""";


───────────────────────────────────────────
편집 2/7 — routine_mode_clone.dart
함수: CloneBrain.polishSentence (대략 3809줄~)
삭제 구간: 3818줄 `      final sysPrompt = """You are an English speaking coach.`
        ~ 3831줄 `- Exactly ONE sentence. No explanation, no quotes, no prefixes.""";`
교체 후(전체):
      final sysPrompt = """You are an English speaking coach.
Rewrite the given long English sentence as ONE "easy but elegant" spoken sentence.

[GOALS]
- Natural spoken rhythm (not written/academic)
- Common vocabulary (no SAT words, no bookish phrases)
- Smooth flow (pause-friendly, commas for breath)
- Same meaning as the original (do not add new facts)
- Easier to pronounce and say out loud
- Render every participant name, clone name, role label, and situation in English (translate role or description phrases; romanize real personal names). Never keep Korean text.
- The final sentence must be 100% English and must NOT contain any Korean (Hangul) characters.
- Do not replace $safePartnerLabel with AI, assistant, chatbot, or bot.

[OUTPUT]
- Exactly ONE sentence. No explanation, no quotes, no prefixes.""";


───────────────────────────────────────────
편집 3/7 — routine_mode_roleplay.dart
함수: RoleplayBrain.generateExpandedFromConversation (대략 3468줄~)
삭제 구간: 3485줄 `      final sysPrompt = """You are an English speaking coach.`
        ~ 3506줄 `- Output exactly ONE sentence. No quotes, no prefixes, no explanation.""";`
교체 후(전체):
      final sysPrompt = """You are an English speaking coach.
You are given a short roleplay conversation transcript.
This is a roleplay conversation between $safeUserLabel and $safePartnerLabel.
$safePartnerLabel is the role being played, not AI.
$situationLine
Your job: compose ONE long, natural English sentence that synthesizes the overall
content and gist of the WHOLE conversation.

[RULES]
- Never call $safePartnerLabel AI, assistant, chatbot, or bot.
- If the partner must be mentioned, use $safePartnerLabel or a natural role phrase.
- If any name, role label, or situation appears in Korean, render it in natural English (translate role or description phrases to their English equivalent; romanize real personal names). Never copy Korean text into the sentence.
- The final sentence must be 100% English and must NOT contain any Korean (Hangul) characters.
- It must be ONE single sentence (do not split it into multiple sentences).
- Keep it 25–40 words.
- Build it from about 5 meaning units joined with varied grammatical connectives
  (because, so, while, which, after, even though, and, etc.).
- Each meaning unit should be speakable in one breath, usually 5–7 words.
- Use commas or natural connectors to make breath groups clear.
- Do not create a sentence with one very long clause.
- Natural, speakable rhythm — common spoken English only.
- Capture the overall situation/idea of the conversation, not just one line.
- Common everyday vocabulary only. Do not add facts not in the transcript.
- Output exactly ONE sentence. No quotes, no prefixes, no explanation.""";


───────────────────────────────────────────
편집 4/7 — routine_mode_roleplay.dart
함수: RoleplayBrain.polishSentence (대략 3544줄~)
삭제 구간: 3554줄 `      final sysPrompt = """You are an English speaking coach.`
        ~ 3567줄 `- Exactly ONE sentence. No explanation, no quotes, no prefixes.""";`
교체 후(전체):
      final sysPrompt = """You are an English speaking coach.
Rewrite the given long English sentence as ONE "easy but elegant" spoken sentence.

[GOALS]
- Natural spoken rhythm (not written/academic)
- Common vocabulary (no SAT words, no bookish phrases)
- Smooth flow (pause-friendly, commas for breath)
- Same meaning as the original (do not add new facts)
- Easier to pronounce and say out loud
- Render every participant name, role label, and situation in English (translate role or description phrases; romanize real personal names). Never keep Korean text.
- The final sentence must be 100% English and must NOT contain any Korean (Hangul) characters.
- Do not replace $safePartnerLabel with AI, assistant, chatbot, or bot.

[OUTPUT]
- Exactly ONE sentence. No explanation, no quotes, no prefixes.""";


───────────────────────────────────────────
편집 5/7 — chat_history_master.dart
함수: _generateExpandedFromConversation (대략 5901줄~)
삭제 구간: 5922줄 `      final sysPrompt = """You are an English speaking coach.`
        ~ 5943줄 `- Output exactly ONE sentence. No quotes, no prefixes, no explanation.""";`
교체 후(전체):
      final sysPrompt = """You are an English speaking coach.
You are given a short conversation transcript.
$modeLine
$safePartnerLabel is not AI.
$situationLine
Your job: compose ONE long, natural English sentence that synthesizes the overall
content and gist of the WHOLE conversation.

[RULES]
- Never call $safePartnerLabel AI, assistant, chatbot, or bot.
- Use $safePartnerLabel or a natural role phrase when referring to the partner.
- If any name, role label, or situation appears in Korean, render it in natural English (translate role or description phrases to their English equivalent; romanize real personal names). Never copy Korean text into the sentence.
- The final sentence must be 100% English and must NOT contain any Korean (Hangul) characters.
- It must be ONE single sentence (do not split it into multiple sentences).
- Keep it 25–40 words.
- Build it from about 5 meaning units joined with varied grammatical connectives
  (because, so, while, which, after, even though, and, etc.).
- Each meaning unit should be speakable in one breath, usually 5–7 words.
- Use commas or natural connectors to make breath groups clear.
- Do not create a sentence with one very long clause.
- Natural, speakable rhythm — common spoken English only.
- Capture the overall situation/idea of the conversation, not just one line.
- Common everyday vocabulary only. Do not add facts not in the transcript.
- Output exactly ONE sentence. No quotes, no prefixes, no explanation.""";


───────────────────────────────────────────
편집 6/7 — chat_history_master.dart
함수: _polishExpandedSentence (대략 5983줄~)
삭제 구간: 5991줄 `      final sysPrompt = """You are an English speaking coach.`
        ~ 6014줄 `- Just the polished sentence.""";`
교체 후(전체):
      final sysPrompt = """You are an English speaking coach.
The user has built a long English sentence through step-by-step expansion.
Your job: Rewrite it as ONE "easy but elegant" spoken English sentence.

[GOALS]
- Natural spoken rhythm (not written/academic)
- Common vocabulary (no SAT words, no bookish phrases)
- Smooth flow (pause-friendly, commas for breath)
- Same meaning as the original (do not add new facts)
- Slightly more elegant/polished than the original
- Easier to pronounce and say out loud
- Render every participant name, clone name, role label, and situation in English (translate role or description phrases; romanize real personal names). Never keep Korean text.
- The final sentence must be 100% English and must NOT contain any Korean (Hangul) characters.
- Do not replace $safePartnerLabel with AI, assistant, chatbot, or bot.

[AVOID]
- Big academic words
- Formal written phrases
- Complex nested clauses that are hard to speak
- Adding information not in the original

[OUTPUT]
- Exactly ONE sentence.
- No explanation, no quotes, no prefixes.
- Just the polished sentence.""";


───────────────────────────────────────────
편집 7/7 — chat_history_master.dart
함수: _canUseCachedNamedPartnerExpand (대략 5881줄~5899)
삭제 구간: 5881줄 `  bool _canUseCachedNamedPartnerExpand(`
        ~ 5899줄 `  }`   (함수 전체)
교체 후(전체):
  bool _canUseCachedNamedPartnerExpand(
    Map<String, dynamic>? data,
    String expanded,
    String polished,
    Map<String, String> labels,
  ) {
    // 🆕 [HANGUL-GUARD] 캐시된 확장/세련문장에 한글이 섞여 있으면 거부 → 재생성 유도
    final hangul = RegExp(r'[\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F]');
    if (hangul.hasMatch('$expanded $polished')) return false;
    final mode = labels['mode'] ?? '';
    if (mode != 'clone' && mode != 'roleplay') return expanded.isNotEmpty;
    if (_historyString(data, 'expand_schema_version') != 'named_partner_v1') {
      return false;
    }
    if (_historyString(data, 'expand_partner_type') != mode) return false;
    final savedPartner = _historyString(data, 'expand_partner_name');
    if (savedPartner.isNotEmpty && savedPartner != labels['partnerLabel']) {
      return false;
    }
    if (_mentionsGenericAiPartner('$expanded $polished')) return false;
    return expanded.isNotEmpty;
  }


───────────────────────────────────────────
[검증]
1) flutter analyze → 에러 0 목표
2) grep -c "must NOT contain any Korean" routine_mode_clone.dart      → 2
3) grep -c "must NOT contain any Korean" routine_mode_roleplay.dart   → 2
4) grep -c "must NOT contain any Korean" chat_history_master.dart     → 2
5) grep -c "Preserve participant names" routine_mode_clone.dart       → 0
6) grep -c "Preserve role names" routine_mode_roleplay.dart           → 0
7) grep -c "Preserve participant names, clone names" chat_history_master.dart → 0
8) grep -n "HANGUL-GUARD" chat_history_master.dart                    → 1줄