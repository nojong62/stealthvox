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

# StepExpand 첫 질문 = 프리톡 기록 기반 + 프리톡 연한 안내 (v1)

> 목표 ① StepExpand 세션 시작 시, 저장된 **프리톡 유저 발화**에서 주제를 골라 **기본 문장을 유도하는 첫 질문**을 AI가 먼저 던진다. 기록 없으면 **지금처럼** 고정 안내로 시작.
> 목표 ② 프리톡 기반 질문이 나갈 때는 "기본 문장 말하세요" 안내를 **생략**(질문이 그 역할 대체).
> 목표 ③ 변주는 **입력 랜덤화 + 최근 안 쓴 방 우선**으로 — 온도는 0.2 유지.
> 목표 ④ 질문은 **타겟 언어로 발화 + 타겟/오리지널 자막**(다른 AI 발화와 동일). 타겟==오리지널이면 타겟만.
> 목표 ⑤ 프리톡 화면 빈 채팅 영역에 **연한 안내문** 추가.

대상 파일: `routine_mode_step_expand.dart`, `routine_mode_free_talk.dart`.
적용 원칙: 텍스트 앵커 기준(줄번호는 드리프트 가능). Box 7·파이프라인 무변경.

---

## STEP 1 — `routine_mode_free_talk.dart` : 빈 화면 연한 안내

`_buildChatList()` 전체 교체.

before:
```dart
  Widget _buildChatList() {
    final double bottomPad = MediaQuery.of(context).size.height * 0.55;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
      itemCount: _localMessages.length,
      itemBuilder: (context, idx) {
        _itemKeys[idx] ??= GlobalKey();
        return Container(
            key: _itemKeys[idx], child: _buildTextBlock(_localMessages[idx]));
      },
    );
  }
```
after:
```dart
  Widget _buildChatList() {
    final double bottomPad = MediaQuery.of(context).size.height * 0.55;
    return Stack(
      children: [
        // 🆕 바탕 연한 안내 (대화 시작 전에만 표시)
        if (_localMessages.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                '타겟 언어로만 프리톡 하려면\n타겟과 오리지널 언어를 같게 하세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.18),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
          itemCount: _localMessages.length,
          itemBuilder: (context, idx) {
            _itemKeys[idx] ??= GlobalKey();
            return Container(
                key: _itemKeys[idx],
                child: _buildTextBlock(_localMessages[idx]));
          },
        ),
      ],
    );
  }
```

---

## STEP 2 — `routine_mode_step_expand.dart`

### 2A. (신규) `StepExpandBrain.streamFreeTalkSeedQuestion` — 온도 0.2

`StepExpandBrain` 클래스 안, `streamOpeningFallbackQuestion` 메서드 **바로 위(또는 아래)** 에 추가.
출력 계약은 기존 질문들과 동일: **타겟 텍스트 → `\n\n` → 오리지널(모국어) 자막**. 타겟==모국어면 타겟만.

```dart
  // ==================================================================
  // 📦 streamFreeTalkSeedQuestion — 프리톡 기록 기반 첫 질문 (온도 0.2)
  // ------------------------------------------------------------------
  // 유저의 과거 프리톡 발화 몇 개를 받아, 그중 한 주제로 "기본 문장(seed)"을
  // 유도하는 질문 1개를 타겟 언어로 생성. 변주는 입력 랜덤화로 확보(온도 0.2).
  // 출력: <타겟 질문>\n\n<모국어 번역>  (타겟==모국어면 타겟만)
  // ==================================================================
  static Stream<String> streamFreeTalkSeedQuestion({
    required String apiKey,
    required String myTarget,
    required List<String> snippets,
    String myNative = '',
  }) async* {
    final client = http.Client();
    try {
      final String snippetsBlock =
          snippets.map((s) => '- $s').join('\n');
      final String sameLangNote = (myNative.isNotEmpty && myNative == myTarget)
          ? 'NOTE: $myTarget and the user\'s language are the same — output ONLY the question, with NO blank line and NO translation.\n'
          : '';

      final String sysPrompt = 'You are a Step Expand grammar coach opening a session.\n'
          'The user has had earlier free-talk conversations. Here are a few things they said before:\n'
          '$snippetsBlock\n'
          '\n'
          'Choose ONE of these topics and ask ONE short, friendly opening question — in $myTarget — '
          'that naturally leads the user to say a simple basic sentence about it. '
          'That basic sentence becomes the SEED they will expand.\n'
          '\n'
          '[RULES]\n'
          '- Reference their past topic naturally so it feels personal (e.g. "Last time you mentioned ...").\n'
          '- The question must invite a short, simple statement — NOT yes/no, NOT a list.\n'
          '- Middle-school level vocabulary. Warm and conversational.\n'
          '- Do NOT give meta-instructions like "make a sentence" or "expand". Just ask the question.\n'
          '- ONE question only, under 25 words.\n'
          '$sameLangNote'
          '\n'
          '[OUTPUT FORMAT — follow EXACTLY]\n'
          '- First: the question in $myTarget only.\n'
          '- Then a blank line (two newlines).\n'
          '- Then: the same question translated into $myNative.\n'
          '- No labels, no quotes, no prefixes.';

      final request = http.Request(
        'POST',
        Uri.parse('https://api.openai.com/v1/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      });
      request.body = jsonEncode({
        'model': 'gpt-4o-mini',
        'stream': true,
        'temperature': 0.2,
        'max_tokens': 160,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content':
                'Ask your opening question now (output in the exact format above).',
          },
        ],
      });

      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ') && line != 'data: [DONE]') {
          try {
            final delta =
                jsonDecode(line.substring(6))['choices'][0]['delta']['content'];
            if (delta != null) yield delta.toString();
          } catch (_) {}
        }
      }
    } catch (_) {
    } finally {
      client.close();
    }
  }
```

---

### 2B. (신규) `_fetchFreeTalkUserSnippets` — 프리톡 유저 발화 수집 + 중복 회피

상태 클래스(`_RoutineModeStepExpandState`) 안, `_startSessionWaitingForUserSeed` **바로 위**에 추가.

```dart
  // 🆕 프리톡 기록에서 유저(HOST) 발화 2~3개를 랜덤 샘플로 가져온다.
  //   - 최근 chat_history를 받아 client-side로 free_talk만 필터 (복합 인덱스 회피)
  //   - 최근에 안 쓴 방 우선 (SharedPreferences로 중복 회피)
  //   - 기록 없으면 빈 리스트 → 호출부에서 고정 안내로 폴백
  Future<List<String>> _fetchFreeTalkUserSnippets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    try {
      final roomsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .orderBy('created_at', descending: true)
          .limit(30)
          .get();
      final freeTalkRooms = roomsSnap.docs
          .where((d) => ((d.data()['mode'] ?? '').toString()) == 'free_talk')
          .take(5)
          .toList();
      if (freeTalkRooms.isEmpty) return [];

      // 중복 회피: 최근에 안 쓴 방 우선
      final prefs = await SharedPreferences.getInstance();
      final usedKey = 'freetalk_seed_used_${user.uid}';
      final used = Set<String>.from(prefs.getStringList(usedKey) ?? []);
      var pool = freeTalkRooms.where((d) => !used.contains(d.id)).toList();
      if (pool.isEmpty) {
        pool = List.of(freeTalkRooms);
        await prefs.remove(usedKey); // 전부 소진 → 이력 초기화
      }
      pool.shuffle();
      final room = pool.first;
      final newUsed = Set<String>.from(prefs.getStringList(usedKey) ?? [])
        ..add(room.id);
      await prefs.setStringList(usedKey, newUsed.toList());

      // 해당 방의 HOST(유저) 발화 수집 (원문 우선, 없으면 번역문)
      final msgSnap = await room.reference.collection('messages').get();
      final hostTexts = msgSnap.docs
          .where((d) => ((d.data()['role'] ?? '').toString()) == 'HOST')
          .map((d) {
            final data = d.data();
            final orig = (data['original_text'] ?? '').toString().trim();
            final tgt = (data['translated_text'] ?? '').toString().trim();
            return orig.isNotEmpty ? orig : tgt;
          })
          .where((s) => s.isNotEmpty)
          .toList();
      if (hostTexts.isEmpty) return [];

      hostTexts.shuffle();
      return hostTexts.take(3).toList(); // 2~3개 랜덤 샘플
    } catch (e) {
      _log('⚠️ [FT-SEED]', 'fetch 실패: $e');
      return [];
    }
  }
```

---

### 2C. (신규) `_generateAndPlayFreeTalkSeedQuestion` — AI 질문 버블 + 타겟 TTS

상태 클래스 안, `_fetchFreeTalkUserSnippets` 바로 아래에 추가.
렌더 방식은 기존 그래머 질문 경로(HybridTtsPlayer `onChunk`/`onStreamEnd`)와 동일.

```dart
  // 🆕 프리톡 기반 첫 질문을 AI 버블로 렌더 + 타겟 TTS 재생 (그래머 질문과 동일 패턴)
  Future<void> _generateAndPlayFreeTalkSeedQuestion(
      List<String> snippets) async {
    final String targetLangName = FFAppState().targetLang.isNotEmpty
        ? FFAppState().targetLang
        : 'English';
    final String nativeLangName =
        FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : '';

    if (mounted) {
      setState(() {
        _localMessages.add({'role': 'SYSTEM', 'target': '', 'original': ''});
      });
      _scrollToBottom();
    }
    final int aiIdx = _localMessages.length - 1;

    final aiStream = StepExpandBrain.streamFreeTalkSeedQuestion(
      apiKey: _openAiKey,
      myTarget: targetLangName,
      myNative: nativeLangName,
      snippets: snippets,
    );

    final questionTts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      'nova',
      isUser: false,
      onLog: _log,
    );
    final HybridTtsPlayer questionHybridTts = HybridTtsPlayer(
      apiKey: _openAiKey,
      voice: 'nova',
      onLog: _log,
    );
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    String aiText = "";
    String aiOriginal = "";
    String aiBuffer = "";
    bool hasDoubleNewline = false;

    await for (final chunk in aiStream) {
      if (!hasDoubleNewline) {
        aiText += chunk;
        aiBuffer += chunk;
        if (aiText.contains('\n\n')) {
          hasDoubleNewline = true;
          final sepIdx = aiText.indexOf('\n\n');
          final afterSep = aiText.substring(sepIdx + 2);
          aiText = aiText.substring(0, sepIdx);
          final bufSepIdx = aiBuffer.indexOf('\n\n');
          if (bufSepIdx >= 0) aiBuffer = aiBuffer.substring(0, bufSepIdx);
          if (afterSep.isNotEmpty) aiOriginal += afterSep;
        } else {
          if (!questionHybridTts.firstChunkFired) {
            final cutIdx =
                questionHybridTts.onChunk(aiBuffer, questionTts, _swTTS);
            if (cutIdx >= 0) aiBuffer = aiBuffer.substring(cutIdx);
          }
        }
      } else {
        aiOriginal += chunk; // Part2 (모국어) — TTS 금지
      }
      if (mounted && aiIdx < _localMessages.length) {
        setState(() {
          _localMessages[aiIdx]['target'] = aiText;
          _localMessages[aiIdx]['original'] = aiOriginal;
        });
      }
      _scrollToBottom();
    }

    await questionHybridTts.onStreamEnd(
      fullSentence: aiText.trim(),
      remainderBuffer: aiBuffer,
      fetcher: questionTts,
      swSpeechEnd: _swTTS,
    );

    int ticks = 0;
    while (questionTts.pendingRequests > 0 || _ttsQueueManager.isBusy) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 300) break;
    }
  }
```

---

### 2D. (교체) `_startSessionWaitingForUserSeed` — 프리톡 분기

메서드 전체 교체. 프리톡 기록 있으면 2C로 질문(안내 생략), 없으면 기존 고정 안내.

before:
```dart
  Future<void> _startSessionWaitingForUserSeed() async {
    if (_openAiKey.isEmpty || !mounted) return;
    if (_isSessionComplete) return;
    _resetIdleTimer();
    _isConversationActive = true;
    if (mounted) setState(() {});

    // 시작 안내 TTS 재생 (OpenAI 질문 생성 API 호출 없음)
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    final ChunkedTtsFetcher tts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      'nova',
      isUser: false,
      onLog: _log,
    );
    tts.addText('대화하면서 문장을 늘려가고 싶은 기본 문장을 하나 제안해 주세요.');

    // TTS 재생 완료 대기 (최대 10초)
    int ticks = 0;
    while ((tts.pendingRequests > 0 || _ttsQueueManager.isBusy) && mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 200) break;
    }

    // 안내 완료 → STT 자동 시작 (유저 기본 문장 대기)
    if (mounted && _isConversationActive && !_isSessionComplete) {
      _startDeepgramListening();
    }
  }
```
after:
```dart
  Future<void> _startSessionWaitingForUserSeed() async {
    if (_openAiKey.isEmpty || !mounted) return;
    if (_isSessionComplete) return;
    _resetIdleTimer();
    _isConversationActive = true;
    if (mounted) setState(() {});

    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    // 🆕 프리톡 기록 기반 첫 질문 (있으면) — 없으면 고정 안내
    final List<String> ftSnippets = await _fetchFreeTalkUserSnippets();

    if (ftSnippets.isNotEmpty && mounted && _isConversationActive) {
      // 프리톡 주제로 AI가 먼저 질문 → "기본 문장 말하세요" 안내 생략
      await _generateAndPlayFreeTalkSeedQuestion(ftSnippets);
    } else {
      // 기존: 고정 안내 TTS
      final ChunkedTtsFetcher tts = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        'nova',
        isUser: false,
        onLog: _log,
      );
      tts.addText('대화하면서 문장을 늘려가고 싶은 기본 문장을 하나 제안해 주세요.');
      int ticks = 0;
      while ((tts.pendingRequests > 0 || _ttsQueueManager.isBusy) && mounted) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (++ticks > 200) break;
      }
    }

    // 안내/질문 완료 → STT 자동 시작 (유저 기본 문장 대기)
    if (mounted && _isConversationActive && !_isSessionComplete) {
      _startDeepgramListening();
    }
  }
```

---

## 3. 검증

```powershell
cd F:\flutter_project\stealth_vox
$s = 'lib\custom_code\widgets\routine_mode_step_expand.dart'
$f = 'lib\custom_code\widgets\routine_mode_free_talk.dart'

# StepExpand 신규 심볼
Select-String -Path $s -Pattern 'streamFreeTalkSeedQuestion'    | Measure-Object   # 정의1 + 호출1 = 2
Select-String -Path $s -Pattern '_fetchFreeTalkUserSnippets'    | Measure-Object   # 정의1 + 호출1 = 2
Select-String -Path $s -Pattern '_generateAndPlayFreeTalkSeedQuestion' | Measure-Object  # 정의1 + 호출1 = 2
Select-String -Path $s -Pattern "'temperature': 0.2" | Measure-Object              # 신규 메서드 포함 (>=1)
Select-String -Path $s -Pattern "mode.*free_talk|isEqualTo|free_talk" | Measure-Object

# 프리톡 안내
Select-String -Path $f -Pattern '타겟과 오리지널 언어를 같게' | Measure-Object        # 1

flutter analyze
```

기능 확인:
- 프리톡 기록 **있을 때** StepExpand 진입 → AI가 과거 주제로 타겟 언어 질문 먼저(자막 동반), "기본 문장 말하세요" 안내 안 나옴. 재진입 시 다른 방/발화로 질문이 **매번 달라짐**.
- 프리톡 기록 **없을 때** → 기존처럼 "대화하면서 문장을 늘려가고 싶은 기본 문장을 하나 제안해 주세요" 고정 안내.
- 타겟==오리지널 언어면 질문이 타겟만(자막 없음).
- 프리톡 화면 대화 시작 전 빈 영역에 연한 안내문 표시 → 대화 시작되면 사라짐.

---

## 4. 롤백

- StepExpand: 추가한 3개(`streamFreeTalkSeedQuestion`, `_fetchFreeTalkUserSnippets`, `_generateAndPlayFreeTalkSeedQuestion`) 삭제 + `_startSessionWaitingForUserSeed` before 블록으로 복귀.
- Free Talk: `_buildChatList` before 블록으로 복귀.
- Firestore/RevenueCat/Cloud Functions: **변경 없음**(읽기 전용 조회 + SharedPreferences만 사용).

> 참고: 프리톡 방 조회는 `orderBy('created_at')` 단일 필드 + client-side `mode` 필터라 **복합 인덱스 불필요**. 메시지도 전체 조회 후 `role=='HOST'` client-side 필터라 인덱스 불필요.