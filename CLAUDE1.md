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

# 지시문: 오인식·불만 발화 → 직전 대사 삭제 후 재질문/재대답 (3개 모드)

## 0. 목적

유저가 **재진술 없이 불만만 말하는 경우**를 새로 처리한다.

| 불만 유형 | 신규 마커 | 동작 |
|---|---|---|
| "내 말이 그런 뜻이 아니야" / "잘못 들었어(적었어)" | `[MISHEARD]` | 잘못 적힌 직전 교환 삭제 → 스텝익스팬드: "아, 제가 잘못 들었네요. 다시 질문할게요." + 새 질문 낭독 / 프리톡·롤플레이: "다시 한 번 말씀해 주세요." + 재청취 |
| "무슨 질문(대답)이 그래" 등 AI 발화 자체 불만 | `[DISSATISFIED]` | 스텝익스팬드: 기존 구현 유지(신호어만 보강) / 프리톡·롤플레이: **신규** — 거절된 AI 응답만 삭제 → "그럼 다시 대답해 볼게요." + 같은 유저 발화에 다른 응답 재생성·낭독 |

기존 `[CORRECTION]`(재진술 포함 정정)은 **우선순위 최상위로 유지, 로직 무변경**.

## 1. 절대 규칙

1. **Box 7 무수정**: `TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`, `HybridTtsPlayer` 클래스 본문은 절대 수정 금지. 본 지시문의 변경은 모드 파이프라인 핸들러와 Brain(Box 7-1) 프롬프트에만 국한된다.
2. **작업 대상 경로**: `F:\flutter_project\stealth_vox\lib\custom_code\widgets\` 의 3개 파일. `lib\custom_code\임시\` 폴더는 절대 건드리지 말 것.
3. URL을 마크다운 링크로 변환 금지. 프롬프트 문자열 내 따옴표 이스케이프 주의(기존 스타일 유지).
4. 각 파일 내 수정은 **아래(큰 줄 번호) → 위(작은 줄 번호)** 순서로 진행해 줄 번호 밀림을 방지한다.
5. 시작 전 세이브포인트: `git add -A && git commit -m "savepoint before MISHEARD/DISSATISFIED"`
6. 아래 줄 번호는 참고용이다. **str_replace 앵커(OLD 블록)가 정확히 1회 일치하는지 grep으로 먼저 확인**하고, 일치하지 않으면 작업을 중단하고 보고할 것.

---

# 파일 A: routine_mode_step_expand.dart (수정 9건, 아래→위)

## A-1. [DISSATISFIED] 신호어 보강

- 위치: 약 4686행, `- Output [DISSATISFIED] when the user expresses...` 로 시작하는 한 줄 내부 일부 교체

OLD (부분 문자열, 파일 내 1회 존재 확인: `grep -c '질문 바꿔' 파일` → 1):
```
Signs: "다른 질문 해줘" / "그 질문 싫어" / "질문 바꿔" / "별로야"
```

NEW:
```
Signs: "다른 질문 해줘" / "그 질문 싫어" / "질문 바꿔" / "무슨 질문이 그래" / "별로야"
```

## A-2. [RESTATE] 예외 목록에 MISHEARD 분기 추가

- 위치: 약 4653행 (`- Only a single referent ...` 줄) 바로 다음에 한 줄 삽입

OLD:
```
- Only a single referent (who / what) is unclear but the rest is fine  ->  use [CLARIFY] instead.
```

NEW:
```
- Only a single referent (who / what) is unclear but the rest is fine  ->  use [CLARIFY] instead.
${disableCorrection ? "" : "- The user is ONLY complaining that they were misheard or misunderstood, without restating the content  ->  use [MISHEARD] instead."}
```

## A-3. correctionBlock에 [CASE MISHEARD] 추가

- 위치: 약 4575~4585행 (`final String correctionBlock = disableCorrection` 시작 ~ `"아니" etc.""";` 끝) 블록 전체 교체

OLD:
```dart
      final String correctionBlock = disableCorrection
          ? "Never output [CORRECTION]. Treat the input as normal content."
          : """[CASE CORRECTION] — Check this FIRST, but only when History contains at least one 'User:' line
The user is correcting the AI's misunderstanding of a previous answer.
Signs:
- Starts with correction signals: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST 'User:' line in History (not new story info)
- The user is essentially saying "that's not what I said — what I said was X"
If this is a correction, output EXACTLY: [CORRECTION]
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.""";
```

NEW:
```dart
      final String correctionBlock = disableCorrection
          ? "Never output [CORRECTION] or [MISHEARD]. Treat the input as normal content."
          : """[CASE CORRECTION] — Check this FIRST, but only when History contains at least one 'User:' line
The user is correcting the AI's misunderstanding of a previous answer.
Signs:
- Starts with correction signals: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST 'User:' line in History (not new story info)
- The user is essentially saying "that's not what I said — what I said was X"
If this is a correction, output EXACTLY: [CORRECTION]
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.

[CASE MISHEARD] — Check this SECOND, only when History contains at least one 'User:' line
The user is COMPLAINING that their previous words were misheard or misunderstood, WITHOUT restating what they actually said.
Signs:
- The utterance is essentially ONLY a complaint: "내 말이 그런 뜻이 아니야" / "그런 뜻 아니야" / "내 말은 그게 아니야" / "잘못 들었어" / "잘못 적었어" / "잘못 알아들었네" / "that's not what I meant" / "you misheard me" / "you got my words wrong"
- AND it contains NO restated content (no actual answer, no new story info).
If this is a bare mishearing complaint, output EXACTLY: [MISHEARD]
If the complaint INCLUDES the corrected content, use [CORRECTION] instead.""";
```

## A-4. misheard 핸들러 삽입

- 위치: 약 2049~2052행, `[CORRECTION]` 핸들러 끝(`_processRelayPipeline(finalTranscript, isCorrectionRetry: true); / return; / }`)과 약 2054행 `// ❓ [CLARIFY] ...` 주석 사이에 삽입

OLD:
```dart
        // 정정된 발화로 해당 턴 재처리 (재진입이므로 [CORRECTION] 재감지 안 함)
        _processRelayPipeline(finalTranscript, isCorrectionRetry: true);
        return;
      }

      // ❓ [CLARIFY] 유저 발화 주어/목적어 모호 → AI 되묻기 버블 + TTS + STT 재시작
```

NEW:
```dart
        // 정정된 발화로 해당 턴 재처리 (재진입이므로 [CORRECTION] 재감지 안 함)
        _processRelayPipeline(finalTranscript, isCorrectionRetry: true);
        return;
      }

      // 🙉 [MISHEARD] 유저가 "잘못 들었어/그런 뜻 아니야"만 말함 (재진술 없음)
      //   → 잘못 적힌 직전 HOST를 지우고, 직전 SYSTEM(나쁜 질문)은 _handleRetryQuestion이 교체.
      //   "아, 제가 잘못 들었네요. 다시 질문할게요." 멘트 + 정리된 문맥으로 새 질문 생성
      if (misheard) {
        // 지울 직전 교환이 없으면 (1번째 턴) 일반 재질문으로 폴백
        if (_turnCounter < 2) {
          _turnCounter--;
          if (mounted) {
            setState(() {
              _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
              if (hostIndex < _localMessages.length) {
                _localMessages.removeAt(hostIndex);
              }
            });
          }
          await _handleRetryQuestion(contextStr, targetLangName,
              isMisheard: true);
          return;
        }
        _turnCounter -= 2; // 불만 턴 + 잘못 적힌 턴 카운트 취소
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            // 방금 생성한 불만 HOST 버블 제거
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
            // 잘못 적힌 직전 HOST(유저 발화) 제거
            // (직전 SYSTEM 질문은 _handleRetryQuestion이 교체하므로 여기서 안 지움)
            final lastHostIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'HOST');
            if (lastHostIdx != -1) _localMessages.removeAt(lastHostIdx);
          });
          _scrollToBottom();
        }
        // 삭제 후 남은 메시지로 문맥 재구성 (잘못 적힌 발화/나쁜 질문이 새 질문에 재주입되는 것 방지)
        var cleanMsgs = _localMessages.where((m) {
          if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
          final target = (m['target'] ?? '').toString().trim();
          return target.isNotEmpty && target != '...';
        }).toList();
        if (cleanMsgs.length > 10)
          cleanMsgs = cleanMsgs.sublist(cleanMsgs.length - 10);
        // 마지막 SYSTEM(잘못 적힌 발화 기반의 나쁜 질문)은 문맥에서 제외
        final lastBadSysIdx =
            cleanMsgs.lastIndexWhere((m) => m['role'] == 'SYSTEM');
        if (lastBadSysIdx != -1) cleanMsgs.removeAt(lastBadSysIdx);
        final List<String> cleanLines = [];
        String cleanLatestExpanded = '';
        for (final m in cleanMsgs) {
          final t = (m['target'] ?? '').toString().trim();
          if (m['role'] == 'HOST') {
            final idx = t.indexOf('\n\n');
            final expanded = idx < 0
                ? t
                : (t.substring(idx + 2).trim().isNotEmpty
                    ? t.substring(idx + 2).trim()
                    : t.substring(0, idx).trim());
            cleanLines.add("User: $expanded");
            cleanLatestExpanded = expanded;
          } else {
            cleanLines.add("AI: $t");
          }
        }
        String cleanContextStr = cleanLines.join("\n");
        if (cleanLatestExpanded.isNotEmpty) {
          cleanContextStr +=
              "\n\n[Most recent expanded sentence to grow from]: $cleanLatestExpanded";
        }
        await _handleRetryQuestion(cleanContextStr, targetLangName,
            isMisheard: true);
        return;
      }

      // ❓ [CLARIFY] 유저 발화 주어/목적어 모호 → AI 되묻기 버블 + TTS + STT 재시작
```

## A-5. 스트림 루프에 [MISHEARD] 감지 추가

- 위치: 약 1893~1899행, `[CORRECTION]` 감지 블록 바로 뒤에 삽입

OLD:
```dart
        // 정정 감지: 유저가 AI의 오해를 바로잡는 경우
        // → 직전 HOST(오해된 유저 발화) + SYSTEM(잘못된 AI 응답) 삭제 후 정정 발화로 재시작
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 HOST+SYSTEM 삭제 후 재시작');
          break;
        }
```

NEW:
```dart
        // 정정 감지: 유저가 AI의 오해를 바로잡는 경우
        // → 직전 HOST(오해된 유저 발화) + SYSTEM(잘못된 AI 응답) 삭제 후 정정 발화로 재시작
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 HOST+SYSTEM 삭제 후 재시작');
          break;
        }

        // 🙉 [MISHEARD] 잘못 들었다는 불만만 (재진술 없음) → 직전 교환 삭제 후 재질문
        if (!isCorrectionRetry && userTargetText.contains("[MISHEARD]")) {
          misheard = true;
          _log('🙉 [MISHEARD]', '오인식 불만 감지 → 직전 교환 삭제 후 재질문');
          break;
        }
```

## A-6. bool 플래그 추가

- 위치: 약 1860행

OLD:
```dart
      bool corrected = false; // 유저가 AI의 오해를 정정하는 경우 → 직전 HOST+SYSTEM 쌍 삭제 후 재시작
```

NEW:
```dart
      bool corrected = false; // 유저가 AI의 오해를 정정하는 경우 → 직전 HOST+SYSTEM 쌍 삭제 후 재시작
      bool misheard = false; // 잘못 들었다는 불만만 (재진술 없음) → 직전 교환 삭제 후 재질문
```

## A-7. _handleRetryQuestion: isRetry 계산 수정

- 위치: 약 1647행

OLD:
```dart
      isRetry: !isDifferent,
```

NEW:
```dart
      isRetry: !isDifferent && !isMisheard,
```

## A-8. _handleRetryQuestion: 안내 멘트 분기

- 위치: 약 1625행

OLD:
```dart
    phraseTts.addText(isDifferent ? "그럼 다른 질문 드릴게요." : "다시 질문할게요.");
```

NEW:
```dart
    phraseTts.addText(isMisheard
        ? "아, 제가 잘못 들었네요. 다시 질문할게요."
        : (isDifferent ? "그럼 다른 질문 드릴게요." : "다시 질문할게요."));
```

## A-9. _handleRetryQuestion: 시그니처에 isMisheard 추가

- 위치: 약 1611~1613행

OLD:
```dart
  Future<void> _handleRetryQuestion(String contextStr, String targetLangName,
      {bool isDifferent = false}) async {
    _log('🔄 [RETRY]', isDifferent ? '다른 질문 모드 진입' : '재질문 모드 진입');
```

NEW:
```dart
  Future<void> _handleRetryQuestion(String contextStr, String targetLangName,
      {bool isDifferent = false, bool isMisheard = false}) async {
    _log(
        '🔄 [RETRY]',
        isMisheard
            ? '오인식 재질문 모드 진입'
            : (isDifferent ? '다른 질문 모드 진입' : '재질문 모드 진입'));
```

---

# 파일 B: routine_mode_free_talk.dart (수정 7건, 아래→위)

## B-1. streamFreeTalkResponse 프롬프트에 거절 응답 회피 규칙 주입

- 위치: 약 3364행

OLD:
```
- If the audio is garbled or impossible to make out (a speech recognition error), politely ask them to repeat in $myTarget.
```

NEW:
```
- If the audio is garbled or impossible to make out (a speech recognition error), politely ask them to repeat in $myTarget.$rejectedBlock
```

## B-2. streamFreeTalkResponse 시그니처 + rejectedBlock 정의

- 위치: 약 3340~3349행

OLD:
```dart
  static Stream<String> streamFreeTalkResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String myTarget,
    String level = "Intermediate",
  }) async* {
    final client = http.Client();
    try {
      final sysPrompt =
```

NEW:
```dart
  static Stream<String> streamFreeTalkResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String myTarget,
    String level = "Intermediate",
    String rejectedReply = '',
  }) async* {
    final client = http.Client();
    try {
      final String rejectedBlock = rejectedReply.trim().isEmpty
          ? ""
          : "\n- IMPORTANT: The user disliked your previous reply: \"${rejectedReply.trim()}\". Give a COMPLETELY DIFFERENT reply this time — different angle, different wording. Do NOT repeat or rephrase it.";
      final sysPrompt =
```

## B-3. correctionBlock에 [CASE MISHEARD] + [CASE DISSATISFIED] 추가

- 위치: 약 3166~3175행 블록 전체 교체

OLD:
```dart
      final String correctionBlock = disableCorrection
          ? "Never output [CORRECTION]. Treat the input as normal content to translate."
          : '''[CASE CORRECTION] — Check this FIRST, only when the conversation history contains at least one "User:" line.
The user is correcting the AI's misunderstanding or mishearing of their PREVIOUS utterance.
Signs:
- Starts with a correction signal: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST "User:" line in the history, NOT new information.
- The user is essentially saying "that's not what I said — what I said was X."
If this is a correction, output EXACTLY: [CORRECTION]  (and nothing else)
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.''';
```

NEW:
```dart
      final String correctionBlock = disableCorrection
          ? "Never output [CORRECTION] or [MISHEARD]. Treat the input as normal content to translate."
          : '''[CASE CORRECTION] — Check this FIRST, only when the conversation history contains at least one "User:" line.
The user is correcting the AI's misunderstanding or mishearing of their PREVIOUS utterance.
Signs:
- Starts with a correction signal: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST "User:" line in the history, NOT new information.
- The user is essentially saying "that's not what I said — what I said was X."
If this is a correction, output EXACTLY: [CORRECTION]  (and nothing else)
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.

[CASE MISHEARD] — Check this SECOND, only when the history contains at least one "User:" line.
The user is COMPLAINING that their previous words were misheard or misunderstood, WITHOUT restating what they actually said.
Signs: "내 말이 그런 뜻이 아니야" / "그런 뜻 아니야" / "내 말은 그게 아니야" / "잘못 들었어" / "잘못 적었어" / "잘못 알아들었네" / "that's not what I meant" / "you misheard me" / "you got my words wrong"
- AND the utterance contains NO restated content (no actual new statement).
If so, output EXACTLY: [MISHEARD]  (and nothing else)
If the complaint INCLUDES the corrected content, use [CORRECTION] instead.

[CASE DISSATISFIED] — Check this THIRD, only when the history contains at least one "AI:" line.
The user is complaining about the AI's LAST reply itself and wants a different one.
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해봐" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
Do NOT output this when the user is simply answering negatively (e.g., "아니, 안 갔어" is a valid negative answer).
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)''';
```

## B-4. CORRECTION-GUARD를 3개 태그로 확장

- 위치: 약 1184~1185행

OLD:
```dart
      if (userTargetText.contains('[CORRECTION]')) {
        userTargetText = userTargetText.replaceAll('[CORRECTION]', '').trim();
```

NEW:
```dart
      if (userTargetText.contains('[CORRECTION]') ||
          userTargetText.contains('[MISHEARD]') ||
          userTargetText.contains('[DISSATISFIED]')) {
        userTargetText = userTargetText
            .replaceAll('[CORRECTION]', '')
            .replaceAll('[MISHEARD]', '')
            .replaceAll('[DISSATISFIED]', '')
            .trim();
```

## B-5. misheard + dissatisfiedReply 핸들러 삽입

- 위치: 약 1176~1181행, `[CORRECTION]` 핸들러 끝과 CORRECTION-GUARD 주석 사이에 삽입

OLD:
```dart
        unawaited(
            _processRelayPipeline(finalTranscript, isCorrectionRetry: true));
        return;
      }

      // 🛡️ [CORRECTION-GUARD] 태그가 번역 결과로 화면/TTS에 남는 것 차단
```

NEW:
```dart
        unawaited(
            _processRelayPipeline(finalTranscript, isCorrectionRetry: true));
        return;
      }

      // 🙉 [MISHEARD] 잘못 들었다는 불만만 → 직전 교환(잘못 적힌 발화+틀린 응답) 삭제 후 재청취
      if (misheard) {
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex); // 불만 HOST 버블 제거
            }
            _removeLastExchange(); // 직전 HOST(잘못 적힌 발화)+SYSTEM(틀린 응답) 제거
          });
          _scrollToBottom();
        }
        // 장기기억에서도 직전 교환 제거 (잘못 적힌 발화가 문맥으로 재주입되는 것 방지)
        if (_recentHistory.length >= 2) {
          _recentHistory.removeRange(
              _recentHistory.length - 2, _recentHistory.length);
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final misheardTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        misheardTts.addText("아, 제가 잘못 들었네요. 다시 한 번 말씀해 주세요.");
        int misheardTicks = 0;
        while ((misheardTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++misheardTicks > 200) break;
        }
        skipFinallyRestart = true;
        _isPipelineRunning = false;
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // 🟠 [DISSATISFIED] AI 직전 응답에 대한 불만 → 직전 SYSTEM만 삭제하고 같은 발화에 다시 대답
      if (dissatisfiedReply) {
        String rejectedReply = '';
        String lastUserTarget = '';
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex); // 불만 HOST 버블 제거
            }
            final lastSysIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'SYSTEM');
            if (lastSysIdx != -1) {
              rejectedReply =
                  (_localMessages[lastSysIdx]['target'] ?? '').toString();
              _localMessages.removeAt(lastSysIdx); // 거절된 AI 응답 제거
            }
            final lastHostIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'HOST');
            if (lastHostIdx != -1) {
              lastUserTarget =
                  (_localMessages[lastHostIdx]['target'] ?? '').toString();
            }
          });
          _scrollToBottom();
        }
        // 장기기억에서 거절된 assistant 항목만 제거 (유저 발화는 유지)
        if (_recentHistory.isNotEmpty &&
            _recentHistory.last['role'] == 'assistant') {
          _recentHistory.removeLast();
        }
        // 다시 대답할 유저 발화가 없으면 재청취로 폴백
        if (lastUserTarget.trim().isEmpty) {
          _ttsQueueManager.stop();
          skipFinallyRestart = true;
          _isPipelineRunning = false;
          await _speakRetryAndListen();
          return;
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        // 안내 멘트 (GPT 재생성과 병렬 재생)
        final regenPhraseTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        regenPhraseTts.addText("그럼 다시 대답해 볼게요.");
        // 거절된 응답을 제외한 문맥 재구성
        String regenContextStr;
        if (_recentHistory.isNotEmpty) {
          regenContextStr = _recentHistory
              .map((m) =>
                  '${m['role'] == 'user' ? 'User' : 'AI'}: ${m['content']}')
              .join('\n');
        } else {
          var regenMsgs = _localMessages.where((m) {
            if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
            final target = (m['target'] ?? '').toString().trim();
            return target.isNotEmpty && target != '...';
          }).toList();
          if (regenMsgs.length > 10)
            regenMsgs = regenMsgs.sublist(regenMsgs.length - 10);
          regenContextStr = regenMsgs
              .map((m) =>
                  "${m['role'] == 'HOST' ? 'User' : 'AI'}: ${m['target']}")
              .join("\n");
        }
        // 새 AI 응답 버블 + 스트리밍 재생성
        if (mounted) {
          setState(() => _localMessages
              .add({'role': 'SYSTEM', 'target': '', 'original': ''}));
          _scrollToBottom();
        }
        final int regenAiIndex = _localMessages.length - 1;
        final regenTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        String regenText = "";
        final regenStream = FreeTalkBrain.streamFreeTalkResponse(
          apiKey: _openAiKey,
          userTargetText: lastUserTarget,
          contextStr: regenContextStr,
          myTarget: targetLangName,
          level: _freeTalkLevel,
          rejectedReply: rejectedReply,
        );
        await for (final chunk in regenStream) {
          regenText += chunk;
          if (mounted && regenAiIndex < _localMessages.length) {
            setState(
                () => _localMessages[regenAiIndex]['target'] = regenText);
          }
        }
        // 안내 멘트가 재생되는 동안 생성이 끝나므로 통문장 1회 발사로 단순 처리
        final String regenClean = _cleanText(regenText.trim());
        if (regenClean.isNotEmpty) regenTts.addText(regenClean);
        // 한국어 original 백그라운드 생성 + 장기기억 반영
        if (regenText.trim().isNotEmpty) {
          FreeTalkBrain.generateCleanOriginal(
                  apiKey: _openAiKey, englishText: regenText)
              .then((cleanKorean) {
            if (mounted && _localMessages.length > regenAiIndex) {
              setState(() =>
                  _localMessages[regenAiIndex]['original'] = cleanKorean);
            }
          });
          _recentHistory.add({'role': 'assistant', 'content': regenText});
          while (_recentHistory.length > 4) _recentHistory.removeAt(0);
        }
        int regenTicks = 0;
        while ((regenPhraseTts.pendingRequests > 0 ||
                regenTts.pendingRequests > 0 ||
                _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++regenTicks > 400) break;
        }
        skipFinallyRestart = true;
        _isPipelineRunning = false;
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // 🛡️ [CORRECTION-GUARD] 태그가 번역 결과로 화면/TTS에 남는 것 차단
```

## B-6. 스트림 루프에 감지 2개 추가

- 위치: 약 1128~1133행, `[CORRECTION]` 감지 블록 바로 뒤에 삽입

OLD:
```dart
        // 🔄 [CORRECTION] 정정 감지 (재진입 시 무시)
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 교환 삭제 후 재시작');
          break;
        }
```

NEW:
```dart
        // 🔄 [CORRECTION] 정정 감지 (재진입 시 무시)
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 교환 삭제 후 재시작');
          break;
        }
        // 🙉 [MISHEARD] 잘못 들었다는 불만만 (재진술 없음)
        if (!isCorrectionRetry && userTargetText.contains("[MISHEARD]")) {
          misheard = true;
          _log('🙉 [MISHEARD]', '오인식 불만 감지 → 직전 교환 삭제 후 재청취');
          break;
        }
        // 🟠 [DISSATISFIED] AI 직전 응답에 대한 불만 → 다른 대답 재생성
        if (userTargetText.contains("[DISSATISFIED]")) {
          dissatisfiedReply = true;
          _log('🟠 [DISSATISFIED]', '응답 불만 감지 → 직전 응답 삭제 후 재대답');
          break;
        }
```

## B-7. bool 플래그 2개 추가

- 위치: 약 1116~1117행

OLD:
```dart
      bool evaporated = false;
      bool corrected = false; // 유저가 AI의 오해를 정정 → 직전 교환 삭제 후 재처리
```

NEW:
```dart
      bool evaporated = false;
      bool corrected = false; // 유저가 AI의 오해를 정정 → 직전 교환 삭제 후 재처리
      bool misheard = false; // 잘못 들었다는 불만만 (재진술 없음) → 직전 교환 삭제 후 재청취
      bool dissatisfiedReply = false; // AI 직전 응답 불만 → 직전 응답 삭제 후 재대답
```

---

# 파일 C: routine_mode_roleplay.dart (수정 5건, 아래→위)

## C-1. streamRoleplayResponse: rejectedReply 규칙 연결

- 위치: 약 3843행 (sysPrompt 마지막 줄)

OLD:
```dart
          '- If the user\'s input is completely unintelligible (speech recognition error), output EXACTLY: [RETRY]';
```

NEW:
```dart
          '- If the user\'s input is completely unintelligible (speech recognition error), output EXACTLY: [RETRY]' +
          (rejectedReply.trim().isEmpty
              ? ''
              : '\n- IMPORTANT: The user disliked your previous reply: "${rejectedReply.trim()}". Give a COMPLETELY DIFFERENT in-character reply this time — different angle, different wording. Do NOT repeat or rephrase it.');
```

## C-2. streamRoleplayResponse 시그니처에 파라미터 추가

- 위치: 약 3816~3824행

OLD:
```dart
  static Stream<String> streamRoleplayResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String situation,
    required String aiRole,
    required String userRole,
    required String myTarget,
  }) async* {
```

NEW:
```dart
  static Stream<String> streamRoleplayResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String situation,
    required String aiRole,
    required String userRole,
    required String myTarget,
    String rejectedReply = '',
  }) async* {
```

## C-3. streamUserTranslation 프롬프트에 [CASE MISHEARD] + [CASE DISSATISFIED] 삽입

- 위치: 약 3648~3651행, CORRECTION 블록 끝과 `[INTERNAL THINKING]` 사이

OLD:
```
If this is a correction, output EXACTLY: [CORRECTION]  (and nothing else)
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.

[INTERNAL THINKING - do not output]
```

NEW:
```
If this is a correction, output EXACTLY: [CORRECTION]  (and nothing else)
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.

[CASE MISHEARD] — Check this SECOND, only when the history contains at least one "User:" line.
The user is COMPLAINING that their previous words were misheard or misunderstood, WITHOUT restating what they actually said.
Signs: "내 말이 그런 뜻이 아니야" / "그런 뜻 아니야" / "내 말은 그게 아니야" / "잘못 들었어" / "잘못 적었어" / "잘못 알아들었네" / "that's not what I meant" / "you misheard me" / "you got my words wrong"
- AND the utterance contains NO restated content (no actual new statement).
If so, output EXACTLY: [MISHEARD]  (and nothing else)
If the complaint INCLUDES the corrected content, use [CORRECTION] instead.

[CASE DISSATISFIED] — Check this THIRD, only when the history contains at least one "AI:" line.
The user is stepping OUT of the roleplay to complain about the AI's LAST reply itself and wants a different one.
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해봐" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
Do NOT output this when the user is answering negatively IN CHARACTER (e.g., refusing an offer inside the roleplay is a valid in-character answer).
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)

[INTERNAL THINKING - do not output]
```

## C-4. misheard + dissatisfiedReply 핸들러 삽입

- 위치: 약 1226~1231행, `[CORRECTION]` 핸들러 끝과 `// ❓ [CLARIFY]` 주석 사이에 삽입

OLD:
```dart
        // 정정된 발화로 재처리 (재진입이므로 [CORRECTION] 재감지 안 함)
        _processRelayPipeline(finalTranscript, isCorrectionRetry: true);
        return;
      }

      // ❓ [CLARIFY] 유저 발화 주어/목적어 모호 → In-Character 되묻기 + STT 재시작
```

NEW:
```dart
        // 정정된 발화로 재처리 (재진입이므로 [CORRECTION] 재감지 안 함)
        _processRelayPipeline(finalTranscript, isCorrectionRetry: true);
        return;
      }

      // 🙉 [MISHEARD] 잘못 들었다는 불만만 → 직전 교환 삭제 후 재청취
      if (misheard) {
        _turnCounter--; // finally의 마이크 재시작 가드 차단 (수동 재시작)
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex); // 불만 HOST 버블 제거
            }
            _removeLastExchange(); // 직전 HOST(잘못 적힌 발화)+SYSTEM(틀린 응답) 제거
          });
          if (_localMessages.isNotEmpty) _scrollToBottom();
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final misheardTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        misheardTts.addText("아, 제가 잘못 들었네요. 다시 한 번 말씀해 주세요.");
        int misheardTicks = 0;
        while ((misheardTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++misheardTicks > 200) break;
        }
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // 🟠 [DISSATISFIED] AI 직전 응답 불만 → 직전 SYSTEM만 삭제하고 같은 발화에 다시 대답
      if (dissatisfiedReply) {
        _turnCounter--; // finally의 마이크 재시작 가드 차단 (수동 재시작)
        String rejectedReply = '';
        String lastUserTarget = '';
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex); // 불만 HOST 버블 제거
            }
            final lastSysIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'SYSTEM');
            if (lastSysIdx != -1) {
              rejectedReply =
                  (_localMessages[lastSysIdx]['target'] ?? '').toString();
              _localMessages.removeAt(lastSysIdx); // 거절된 AI 응답 제거
            }
            final lastHostIdx =
                _localMessages.lastIndexWhere((m) => m['role'] == 'HOST');
            if (lastHostIdx != -1) {
              lastUserTarget =
                  (_localMessages[lastHostIdx]['target'] ?? '').toString();
            }
          });
          if (_localMessages.isNotEmpty) _scrollToBottom();
        }
        // 다시 대답할 유저 발화가 없으면 재청취로 폴백
        if (lastUserTarget.trim().isEmpty) {
          _ttsQueueManager.stop();
          _speakRetryAndListen();
          return;
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        // 안내 멘트 (GPT 재생성과 병렬 재생)
        final regenPhraseTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        regenPhraseTts.addText("그럼 다시 대답해 볼게요.");
        // 거절된 응답을 제외한 문맥 재구성
        var regenMsgs = _localMessages.where((m) {
          if (m['role'] != 'HOST' && m['role'] != 'SYSTEM') return false;
          final target = (m['target'] ?? '').toString().trim();
          return target.isNotEmpty && target != '...';
        }).toList();
        if (regenMsgs.length > 10)
          regenMsgs = regenMsgs.sublist(regenMsgs.length - 10);
        final String regenContextStr = regenMsgs
            .map((m) =>
                "${m['role'] == 'HOST' ? 'User' : 'AI'}: ${m['target']}")
            .join("\n");
        // 새 AI 응답 버블 + 스트리밍 재생성
        if (mounted) {
          setState(() => _localMessages
              .add({'role': 'SYSTEM', 'target': '', 'original': ''}));
          _scrollToBottom();
        }
        final int regenAiIndex = _localMessages.length - 1;
        final regenTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        String regenText = "";
        final regenStream = RoleplayBrain.streamRoleplayResponse(
          apiKey: _openAiKey,
          userTargetText: lastUserTarget,
          contextStr: regenContextStr,
          situation: _scenarioSituation,
          aiRole: _scenarioAiRole,
          userRole: _scenarioUserRole,
          myTarget: targetLangName,
          rejectedReply: rejectedReply,
        );
        await for (final chunk in regenStream) {
          regenText += chunk;
          if (regenText.contains('[RETRY]')) break;
          if (mounted && regenAiIndex < _localMessages.length) {
            setState(
                () => _localMessages[regenAiIndex]['target'] = regenText);
          }
        }
        // [RETRY] 가드: 재생성도 실패하면 버블 제거 후 재청취 폴백
        if (regenText.contains('[RETRY]') || regenText.trim().isEmpty) {
          if (mounted && regenAiIndex < _localMessages.length) {
            setState(() => _localMessages.removeAt(regenAiIndex));
          }
          _speakRetryAndListen();
          return;
        }
        // 안내 멘트가 재생되는 동안 생성이 끝나므로 통문장 1회 발사로 단순 처리
        final String regenClean = _cleanText(regenText.trim());
        if (regenClean.isNotEmpty) regenTts.addText(regenClean);
        // 한국어 original 백그라운드 생성
        RoleplayBrain.generateCleanOriginal(
                apiKey: _openAiKey, englishText: regenText)
            .then((cleanKorean) {
          if (mounted && _localMessages.length > regenAiIndex) {
            setState(() =>
                _localMessages[regenAiIndex]['original'] = cleanKorean);
          }
        });
        int regenTicks = 0;
        while ((regenPhraseTts.pendingRequests > 0 ||
                regenTts.pendingRequests > 0 ||
                _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++regenTicks > 400) break;
        }
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }

      // ❓ [CLARIFY] 유저 발화 주어/목적어 모호 → In-Character 되묻기 + STT 재시작
```

## C-5. 스트림 루프 감지 2개 + bool 2개 추가

### C-5a. 감지 (위치: 약 1182~1187행, CORRECTION 감지 뒤)

OLD:
```dart
        // 🔄 [CORRECTION] 정정 감지 (재진입 시 무시)
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 교환 삭제 후 재시작');
          break;
        }
```

NEW:
```dart
        // 🔄 [CORRECTION] 정정 감지 (재진입 시 무시)
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 교환 삭제 후 재시작');
          break;
        }
        // 🙉 [MISHEARD] 잘못 들었다는 불만만 (재진술 없음)
        if (!isCorrectionRetry && userTargetText.contains("[MISHEARD]")) {
          misheard = true;
          _log('🙉 [MISHEARD]', '오인식 불만 감지 → 직전 교환 삭제 후 재청취');
          break;
        }
        // 🟠 [DISSATISFIED] AI 직전 응답에 대한 불만 → 다른 대답 재생성
        if (userTargetText.contains("[DISSATISFIED]")) {
          dissatisfiedReply = true;
          _log('🟠 [DISSATISFIED]', '응답 불만 감지 → 직전 응답 삭제 후 재대답');
          break;
        }
```

### C-5b. bool (위치: 약 1169~1171행)

OLD:
```dart
      bool evaporated = false;
      bool clarified = false; // 주어/목적어 모호 → AI 되묻기
      bool corrected = false; // 유저가 AI의 오해를 정정 → 직전 교환 삭제 후 재처리
```

NEW:
```dart
      bool evaporated = false;
      bool clarified = false; // 주어/목적어 모호 → AI 되묻기
      bool corrected = false; // 유저가 AI의 오해를 정정 → 직전 교환 삭제 후 재처리
      bool misheard = false; // 잘못 들었다는 불만만 (재진술 없음) → 직전 교환 삭제 후 재청취
      bool dissatisfiedReply = false; // AI 직전 응답 불만 → 직전 응답 삭제 후 재대답
```

---

# 검증

작업 디렉터리 `F:\flutter_project\stealth_vox` 에서:

```bash
# 1) 마커 배치 확인 — 기대값과 다르면 중단하고 보고
grep -c "CASE MISHEARD" lib/custom_code/widgets/routine_mode_step_expand.dart    # 1
grep -c "CASE MISHEARD" lib/custom_code/widgets/routine_mode_free_talk.dart      # 1
grep -c "CASE MISHEARD" lib/custom_code/widgets/routine_mode_roleplay.dart       # 1
grep -c "CASE DISSATISFIED" lib/custom_code/widgets/routine_mode_free_talk.dart  # 1
grep -c "CASE DISSATISFIED" lib/custom_code/widgets/routine_mode_roleplay.dart   # 1
grep -c "misheard = true" lib/custom_code/widgets/routine_mode_step_expand.dart  # 1
grep -c "misheard = true" lib/custom_code/widgets/routine_mode_free_talk.dart    # 1
grep -c "misheard = true" lib/custom_code/widgets/routine_mode_roleplay.dart     # 1
grep -c "if (misheard)" lib/custom_code/widgets/routine_mode_step_expand.dart    # 1
grep -c "if (misheard)" lib/custom_code/widgets/routine_mode_free_talk.dart      # 1
grep -c "if (misheard)" lib/custom_code/widgets/routine_mode_roleplay.dart       # 1
grep -c "if (dissatisfiedReply)" lib/custom_code/widgets/routine_mode_free_talk.dart  # 1
grep -c "if (dissatisfiedReply)" lib/custom_code/widgets/routine_mode_roleplay.dart   # 1
grep -c "isMisheard" lib/custom_code/widgets/routine_mode_step_expand.dart       # 6
grep -c "rejectedReply" lib/custom_code/widgets/routine_mode_free_talk.dart      # 6
grep -c "rejectedReply" lib/custom_code/widgets/routine_mode_roleplay.dart       # 6

# 2) Box 7 무변경 확인 — 결과가 비어 있어야 함
git diff --stat | grep -i "deepgram\|tts_queue" || echo "OK"

# 3) 정적 분석 — 신규 에러 0이어야 함
flutter analyze
```

# 실기기 테스트 체크리스트

1. **스텝익스팬드**: 2턴 이상 진행 → "내 말 잘못 적었어"라고 말함 → 잘못 적힌 내 발화 버블 + 그 뒤 AI 질문이 사라지고, "아, 제가 잘못 들었네요. 다시 질문할게요." 후 새 질문 낭독 → 새 질문에 답하면 확장 문장이 잘못 적힌 내용 없이 이어지는지 확인.
2. **스텝익스팬드 1턴째**: 첫 질문에 답한 척하다 "잘못 들었어" → 폴백으로 재질문되는지.
3. **스텝익스팬드 기존 기능 회귀**: "다른 질문 해줘"([DISSATISFIED]), "아니 그게 아니라 ~라고 했어"([CORRECTION]) 모두 기존대로 동작하는지.
4. **프리톡**: 대화 중 "그런 뜻 아니야"만 말함 → 직전 교환 삭제 + "다시 한 번 말씀해 주세요" → 재발화에 정상 대답. / "무슨 대답이 그래" → 내 발화는 남고 AI 대답만 교체("그럼 다시 대답해 볼게요." + 새 대답 낭독), 새 대답이 이전과 다른 내용인지.
5. **롤플레이**: 4번과 동일 시나리오 + 재생성 대답이 캐릭터를 유지하는지.
6. 각 모드에서 `[MISHEARD]`/`[DISSATISFIED]` 태그 텍스트가 화면이나 TTS로 새지 않는지.

# 알려진 트레이드오프 (이번 범위 외)

기존 [CORRECTION]과 동일하게, 화면·문맥에서 삭제된 교환이 **이미 Firestore에 저장된 경우 히스토리에는 남는다**. 재생성된 새 대답도 별도 저장하지 않는다(중복 저장 방지). Firestore 히스토리 동기화는 별도 작업으로 분리.

# 롤백

```bash
git restore lib/custom_code/widgets/routine_mode_step_expand.dart lib/custom_code/widgets/routine_mode_free_talk.dart lib/custom_code/widgets/routine_mode_roleplay.dart
# 또는 커밋 후라면
git revert <해당 커밋 해시>
```