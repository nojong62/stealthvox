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

routine_mode_step_expand.dart 에 "과거 유저 발화를 첫 질문의 씨앗으로 삼는" 기능을 추가합니다.

[동작 요약]
- 세션 첫 질문(turnNumber 0) 생성 시:
  1) 과거 chat_history 중 mode가 'step_expand' 또는 'clone'인 방의 유저(HOST) 발화를 모아 한 줄 무작위 선택
  2) 씨앗 있음 → "지난번에 '...'라고 했었지, 그때 왜 그렇게 느꼈어?" 식 회상형 첫 질문
  3) 씨앗 없음(신규 회원) → "앞으로 다른 모드 대화가 여기 재료가 될 거야, 너는 어떻게 생각해?" 식 온보딩 첫 질문
  4) 조회 실패/타임아웃 → 기존 뉴스 소재 방식으로 안전 폴백
- 5턴 확장·최종 합성·Part1/Part2 포맷은 기존 그대로.

[절대 건드리지 말 것]
- 5턴 구조, 최종 합성, Part1/Part2 포맷, grammarHint, LAYER 1, EMOTIONAL DEPTH RULE, GO DEEPER 등 턴 1~4 로직
- Box 7 엔진(DeepgramV2VoiceManager, TtsQueueManager, ChunkedTtsFetcher)
- 온도(STEP1 0.9 / STEP2 0.7)
- 기존 뉴스 소재 생성 로직 (폴백으로 그대로 유지)

──────────────────────────────────────────────
[수정 1] State 클래스에 과거 발화 조회 함수 신설
──────────────────────────────────────────────

_startSessionWithAiQuestion() 함수 정의 바로 위에 아래 메서드를 새로 추가합니다.
(FirebaseFirestore, FirebaseAuth 는 파일 상단에서 이미 import되어 있음 — 없으면 추가)

  // 🌱 [SEED] 과거 step_expand/clone 방의 유저(HOST) 발화 한 줄을 무작위로 가져온다.
  //   - 실패/없음이면 null 반환 → 호출부에서 기존 뉴스 소재 방식으로 폴백
  //   - 유저 발화만 사용(role == 'HOST'), 너무 짧은 발화(5단어 미만) 제외
  //   - 지금 만들고 있는 방(_myHistoryRef)은 제외
  Future<String?> _fetchRandomPastUserLine() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final historySnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .where('mode', whereIn: ['step_expand', 'clone'])
          .limit(20)
          .get()
          .timeout(const Duration(seconds: 4));

      final List<String> candidates = [];
      for (final roomDoc in historySnap.docs) {
        // 지금 만들고 있는 방은 건너뜀
        if (_myHistoryRef != null && roomDoc.reference.id == _myHistoryRef!.id) {
          continue;
        }
        final msgSnap = await roomDoc.reference
            .collection('messages')
            .where('role', isEqualTo: 'HOST')
            .limit(10)
            .get()
            .timeout(const Duration(seconds: 4));

        for (final m in msgSnap.docs) {
          final d = m.data();
          final String line =
              (d['translated_text'] ?? d['original_text'] ?? '')
                  .toString()
                  .trim();
          // 너무 짧은 발화 제외 (5단어 미만)
          if (line.isEmpty) continue;
          if (line.split(RegExp(r'\s+')).length < 5) continue;
          candidates.add(line);
        }
      }

      if (candidates.isEmpty) return null;
      candidates.shuffle();
      return candidates.first;
    } catch (e) {
      _log('🌱 [SEED]', '과거 발화 조회 실패 → 폴백: $e');
      return null;
    }
  }

──────────────────────────────────────────────
[수정 2] _startSessionWithAiQuestion() 의 첫 질문 호출부 수정
──────────────────────────────────────────────

기존 (turnNumber: 0 으로 streamGrammarQuestion 호출하는 부분):

    final aiStream = StepExpandBrain.streamGrammarQuestion(
      apiKey: _openAiKey,
      contextStr: '',
      turnNumber: 0,
      maxTurns: MAX_TURNS,
      myTarget: targetLangName,
      myNative: nativeLangName,
      isOpening: true,
    );

이것을 아래로 교체 (앞에 씨앗 조회 한 줄 추가 + seedUserLine 파라미터 전달):

    // 🌱 [SEED] 첫 질문 씨앗: 과거 유저 발화 한 줄 (없으면 null → 뉴스 소재 폴백)
    final String? seedLine = await _fetchRandomPastUserLine();
    if (!mounted || !_isConversationActive) return;

    final aiStream = StepExpandBrain.streamGrammarQuestion(
      apiKey: _openAiKey,
      contextStr: '',
      turnNumber: 0,
      maxTurns: MAX_TURNS,
      myTarget: targetLangName,
      myNative: nativeLangName,
      isOpening: true,
      seedUserLine: seedLine,
    );

⚠️ 주의: seedLine 조회는 await이므로, 이 줄 위쪽에서 이미 'SYSTEM' 빈 버블을 add한 뒤
   aiIdx를 잡는 기존 순서는 그대로 유지할 것. (버블 생성 → await seed → 스트리밍 시작 순서)
   만약 seed await 도중 화면 이탈 가능성 때문에 mounted 체크가 필요하면 위 코드처럼 가드를 둔다.

──────────────────────────────────────────────
[수정 3] streamGrammarQuestion 시그니처에 seedUserLine 파라미터 추가
──────────────────────────────────────────────

streamGrammarQuestion 함수 선언부의 파라미터 목록에 아래를 추가 (기존 isOpening 옆):

    String? seedUserLine,

──────────────────────────────────────────────
[수정 4] isOpening 프롬프트에 씨앗 분기 추가
──────────────────────────────────────────────

isOpening == true 블록 안에서, 첫 질문 생성 프롬프트를 만들기 직전에 seedUserLine 분기를 넣는다.
기존 뉴스 소재(STEP1/STEP2) 로직 전체를 아래 조건으로 감싼다:

- seedUserLine 이 null 이 아니고 비어있지 않으면 → 아래 [SEED 프롬프트] 또는 [신규 회원 프롬프트] 사용
- seedUserLine 이 null 이면 → 기존 뉴스 소재 STEP1/STEP2 로직 그대로 실행 (폴백)

isOpening 블록 맨 앞에서 분기:

      if (isOpening) {
        // ── 🌱 씨앗 분기 ──────────────────────────────────────────────
        final bool hasSeed =
            seedUserLine != null && seedUserLine.trim().isNotEmpty;

        if (hasSeed) {
          // [SEED 프롬프트] 과거 유저 발화를 회상시키는 첫 질문
          final String seedSysPrompt = '''
You are a warm, curious English conversation coach starting a NEW session.
The user previously said this in an earlier conversation:
"${seedUserLine.trim()}"

Open by gently bringing up what they said before, then ask ONE light question
that invites them to expand on the FEELING, REASON, or STORY behind it.
This question will become the seed of a sentence-expansion exercise.

RULES:
- Output ONE question only, 8 to 14 words, warm and natural.
- Reference their past words naturally (e.g. "Last time you mentioned ... —").
- Go DEEPER than the surface words: ask about why, how they felt, or what it meant.
- The user should be able to answer in 1-3 words, and that answer should attach to a growing sentence.
- Do NOT use markdown. Keep any reference to their words as plain text.

OUTPUT FORMAT - STRICT:
Output EXACTLY two parts separated by ONE empty line.
PART 1: Your English question.
PART 2: A natural $myNative conversational translation of PART 1.''';

          // ↓↓↓ 기존 STEP2 스트리밍 요청과 동일한 방식으로 호출하되 system content만 seedSysPrompt 사용.
          //     temperature 0.7, stream true, max_tokens 는 약간 늘려 60 권장 (회상 문장이 더 길어서).
          //     (기존 STEP2 요청 코드를 복사해 system content와 max_tokens만 교체)
          // → 여기서 seedSysPrompt 로 OpenAI 스트리밍을 돌리고 yield 한 뒤 return; 하여
          //    아래 뉴스 소재 로직(STEP1/STEP2)으로 내려가지 않게 한다.

        } else if (/* 과거 발화도 없고, 신규 회원으로 간주할 조건 */ false) {
          // 이 분기는 호출부에서 seedUserLine=null 일 때 신규/기존을 구분하지 않으므로
          // 신규 회원 멘트는 아래 [수정 5]에서 별도 처리 (seedUserLine 가 특수값일 때).
        }

        // seedUserLine == null → 기존 뉴스 소재 STEP1/STEP2 로직 실행 (폴백, 변경 없음)
        ... 기존 코드 그대로 ...
      }

⚠️ 구현 노트: 기존 isOpening 블록의 OpenAI 스트리밍 호출 코드(http 요청 + 청크 파싱 + yield)는
   그대로 재사용한다. seed 분기에서는 그 호출의 system content를 seedSysPrompt로,
   max_tokens를 60으로만 바꿔 동일하게 스트리밍하고 return 한다.
   STEP1(뉴스 소재 0.9) 호출은 seed 분기에서는 건너뛴다.

──────────────────────────────────────────────
[수정 5] 신규 회원(과거 발화 전무) 온보딩 첫 질문 처리
──────────────────────────────────────────────

호출부(_fetchRandomPastUserLine)가 null을 반환하면 현재는 뉴스 소재로 폴백한다.
신규 회원에게 "앞으로 다른 모드가 재료가 된다"는 온보딩 멘트를 주려면,
_fetchRandomPastUserLine 의 결과가 null 일 때 호출부에서 한 번 더 구분한다:

수정 2의 호출부를 아래처럼 보강:

    final String? seedLine = await _fetchRandomPastUserLine();
    if (!mounted || !_isConversationActive) return;

    // 신규 회원(과거 step_expand/clone 발화 전무) 여부 판단
    final bool isNewcomer = seedLine == null && await _hasNoPastHistory();

    final aiStream = StepExpandBrain.streamGrammarQuestion(
      apiKey: _openAiKey,
      contextStr: '',
      turnNumber: 0,
      maxTurns: MAX_TURNS,
      myTarget: targetLangName,
      myNative: nativeLangName,
      isOpening: true,
      seedUserLine: seedLine,
      isNewcomer: isNewcomer,
    );

그리고 _hasNoPastHistory() 헬퍼를 _fetchRandomPastUserLine 아래에 추가:

  // 과거 chat_history 방이 하나도 없으면 true (신규 회원 판단)
  Future<bool> _hasNoPastHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 3));
      return snap.docs.isEmpty;
    } catch (_) {
      return false;
    }
  }

streamGrammarQuestion 시그니처에 bool isNewcomer = false 파라미터도 추가하고,
isOpening 블록에서 hasSeed=false && isNewcomer=true 이면 아래 [신규 회원 프롬프트]로 스트리밍:

          final String newcomerSysPrompt = '''
You are a warm, friendly English conversation coach greeting a brand-new user
who has not had any conversations yet.

Briefly and warmly explain (in your ONE opening question) that as they chat in
the other modes (roleplay, clone, etc.), those conversations will later become
the material for sentence-expansion practice here. Then ask what they think,
or what they would like to talk about first.

RULES:
- Output ONE warm, inviting question, 10 to 16 words.
- Friendly and encouraging, never robotic.
- The user should be able to answer in 1-3 words to get started.
- Do NOT use markdown. Plain text only.

OUTPUT FORMAT - STRICT:
Output EXACTLY two parts separated by ONE empty line.
PART 1: Your English opening question.
PART 2: A natural $myNative conversational translation of PART 1.''';

[검증]
1. dart analyze → 에러 0 (특히 ''' 블록 내 ${} 보간, 따옴표 정상)
2. grep -c "_fetchRandomPastUserLine" → 최소 2 (정의 1 + 호출 1)
3. grep -c "seedUserLine" → 최소 3 (시그니처 + 분기 + 호출)
4. grep -c "newcomerSysPrompt" → 1
5. grep -c "whereIn: \['step_expand', 'clone'\]" → 1 (모드 필터 확인)
6. grep "markdown" → seed/newcomer 프롬프트에 "Do NOT use markdown" 포함 확인 (URL 마크다운 금지 룰 준수)
7. 기존 뉴스 소재 STEP1(temperature 0.9) 폴백 로직이 seedUserLine==null 경로에 그대로 남아있는지 확인
8. Box 7 클래스에 diff 변경 0 확인
9. 실제 시나리오 점검: (a) 과거 발화 있는 유저 → 회상형, (b) 신규 회원 → 온보딩형, (c) Firestore 오류 → 뉴스 소재 폴백