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

# 수정 지시문 — Free Talk / Roleplay / Step Expand (5건)

## 작업 전 필수
```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "save-point: before 3-mode UX patch (dissatisfied/seed/silence)"
```

**대상 파일 (lib/custom_code/widgets/ 폴더만. lib/custom_code/임시/ 절대 금지):**
1. `lib/custom_code/widgets/routine_mode_step_expand.dart` (변경 가장 많음)
2. `lib/custom_code/widgets/routine_mode_free_talk.dart`
3. `lib/custom_code/widgets/routine_mode_roleplay.dart`

**절대 규칙:**
- Box 7 클래스(`TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`, `HybridTtsPlayer`) 내부는 한 줄도 수정 금지.
- 모든 URL은 순수 텍스트 유지. 마크다운 링크 변환 금지.
- 프롬프트 내 영어 문자열에 작은따옴표 이스케이프(`\'`) 발생하지 않도록 작성된 코드를 그대로 사용할 것 (아래 코드에는 어퍼스트로피가 없도록 이미 작성됨).
- 각 파일 내 편집은 **아래→위(줄번호 큰 곳부터)** 순서로 진행.
- 줄번호는 참고용 근사치. **반드시 anchor 문자열로 위치를 확정**한 뒤 편집할 것.

---

# 파일 1: routine_mode_step_expand.dart (편집 22건, 아래→위)

## [S-1] 시드 질문 프롬프트 교체 (약 5435~5440줄)

**찾기 (anchor):**
```dart
          'Choose ONE of these topics and ask ONE short, friendly opening question — in $myTarget — '
          'that naturally leads the user to say a simple basic sentence about it. '
          'That basic sentence becomes the SEED they will expand.\n'
```

**교체:**
```dart
          'Use these snippets ONLY as quiet inspiration to sense what the user cares about. '
          'Then create ONE completely NEW, short, friendly opening question — in $myTarget — '
          'that naturally leads the user to say a simple basic sentence. '
          'That basic sentence becomes the SEED they will expand.\n'
```

## [S-2] 시드 질문 RULES 첫 줄 교체 (약 5440줄)

**찾기 (anchor):**
```dart
          '- Reference their past topic naturally so it feels personal (e.g. "Last time you mentioned ...").\n'
```

**교체 (1줄 → 3줄):**
```dart
          '- NEVER mention or quote the past conversation. Do NOT say "Last time you mentioned" or "You said before". Ask as if you simply sense what is on the mind of the user.\n'
          '- IGNORE any snippet that is contentless filler, agreement, or a transition phrase (e.g. short replies like yes, okay, right, so, hmm). Pick only a snippet that contains a concrete topic — an activity, place, person, plan, or opinion.\n'
          '- If NO snippet has real substance, ignore them all and ask a simple, warm everyday-life question instead. Never quote a content-free phrase back to the user.\n'
```

## [S-3] DISSATISFIED 감지 신호 확장 (약 4776줄)

**찾기 (anchor):**
```dart
- Output [DISSATISFIED] when the user expresses dissatisfaction, complaint, or rejection about the AI's QUESTION itself (not about the topic). Signs: "다른 질문 해줘" / "그 질문 싫어" / "질문 바꿔" / "무슨 질문이 그래" / "별로야" / "그건 좀" / "다른 거 물어봐" / "change the question" / "ask something else" / "I don't like that question". Do NOT output [DISSATISFIED] when the user is simply answering negatively (e.g., "아니, 안 갔어" = a valid negative answer)."""
```

**교체:**
```dart
- Output [DISSATISFIED] when the user expresses dissatisfaction, complaint, or rejection about the AI's QUESTION itself (not about the topic). Signs: "다른 질문 해줘" / "그 질문 싫어" / "질문 바꿔" / "무슨 질문이 그래" / "별로야" / "그건 좀" / "다른 거 물어봐" / "change the question" / "ask something else" / "I don't like that question". MILD signs ALSO count: "별로네" / "별로다" / "음 그건 좀" / "에이" / "그런 거 말고" / "딴 거 없어" / "재미없어" / "이상하네" / "뭐야 그게" / "meh" / "not really" / "hmm, not that one". Even slight or indirect displeasure aimed at the QUESTION itself counts. Do NOT output [DISSATISFIED] when the user is simply answering negatively (e.g., "아니, 안 갔어" = a valid negative answer)."""
```

## [S-4] RULES의 RESTATE 출력 규칙 — GARBLED 분리 (약 4774줄)

**찾기 (anchor):**
```dart
- If the input is off-context or too garbled to interpret safely (see [RESTATE GUARD]), output EXACTLY: [RESTATE] — never guess and never invent content the user did not say.
```

**교체:**
```dart
- If the input is CLEAR but off-context (see [RESTATE GUARD]), output EXACTLY: [RESTATE]. If it is too GARBLED to interpret safely, output EXACTLY: [GARBLED]. Never guess and never invent content the user did not say.
```

## [S-5] RESTATE 대조 예시 — 인식불가 케이스 태그 교체 (약 4763~4766줄)

**찾기 (anchor):**
```dart
Input: uh the the it muh suh buh uh  (no recoverable meaning)
Output: [RESTATE]
```

**교체:**
```dart
Input: uh the the it muh suh buh uh  (no recoverable meaning)
Output: [GARBLED]
```

## [S-6] RESTATE GUARD 케이스 분리 + 확인 재진입 무력화 (약 4733~4745줄)

**찾기 (anchor — 블록 전체):**
```dart
[RESTATE GUARD] — hold the center; never invent content
Stay anchored to the AI's LAST question and the growing sentence. If you cannot do that safely, ask the user to say it again instead of guessing.
Output EXACTLY: [RESTATE]  in these cases:
1. RELEVANCE MISMATCH: The input is clear but does not answer the AI's last question, switches to an unrelated subject, or contradicts established facts (see [RELEVANCE CHECK] above).
2. OFF-CONTEXT: The user clearly tried to answer, but the utterance does not connect to the AI's last question and cannot be attached to the growing sentence (and it is NOT a correction of a previous answer).
3. UNRELIABLE PRONUNCIATION: The text is garbled badly enough that the CORE meaning is genuinely uncertain, so translating it would require inventing what the user "probably" meant.
Do NOT output [RESTATE] when:
```

**교체:**
```dart
[RESTATE GUARD] — hold the center; never invent content
Stay anchored to the AI's LAST question and the growing sentence. If you cannot do that safely, ask the user to say it again instead of guessing.
Output EXACTLY: [RESTATE]  in these cases (the speech itself is CLEAR):
1. RELEVANCE MISMATCH: The input is clear but does not answer the AI's last question, switches to an unrelated subject, or contradicts established facts (see [RELEVANCE CHECK] above).
2. OFF-CONTEXT: The user clearly tried to answer, but the utterance does not connect to the AI's last question and cannot be attached to the growing sentence (and it is NOT a correction of a previous answer).
Output EXACTLY: [GARBLED]  in this case ONLY (the speech itself is NOT clear):
3. UNRELIABLE PRONUNCIATION: The text is garbled badly enough that the CORE meaning is genuinely uncertain, so translating it would require inventing what the user "probably" meant.
${disableRestate ? "OVERRIDE — the user has just re-stated after a confirmation question. NEVER output [RESTATE] this turn. Translate or attach the input normally even if it still seems off-topic. ([GARBLED] is still allowed if truly unintelligible.)" : ""}
Do NOT output [RESTATE] or [GARBLED] when:
```

## [S-7] streamUserTranslation 시그니처에 disableRestate 추가 (약 4647~4652줄)

**찾기 (anchor):**
```dart
  static Stream<String> streamUserTranslation({
    required String apiKey,
    required String textOriginal,
    required String targetLang,
    required String contextStr,
    bool disableCorrection = false,
  }) async* {
```

**교체:**
```dart
  static Stream<String> streamUserTranslation({
    required String apiKey,
    required String textOriginal,
    required String targetLang,
    required String contextStr,
    bool disableCorrection = false,
    bool disableRestate = false,
  }) async* {
```

## [S-8] restated 핸들러 교체 — 오프토픽 확인질문(음성만) vs 진짜 안들림 분기 (약 2168~2206줄)

**삭제 범위:** 약 2168줄 `      // 🔁 [RESTATE] 유저 발화가 맥락에 어긋나거나 발음이 불확실 → AI 질문은 그대로 두고 다시 말하기 요청` 부터 약 2206줄 `      }` (restated 블록의 닫는 중괄호, 바로 다음 줄이 `      // ✅ 정상 발화 통과 → 연속 RESTATE 카운터 초기화`) 까지.

**찾기 (anchor — 블록 전체, 정확히 일치해야 함):**
```dart
      // 🔁 [RESTATE] 유저 발화가 맥락에 어긋나거나 발음이 불확실 → AI 질문은 그대로 두고 다시 말하기 요청
      //   - 턴 카운터 원복(이번 시도 무효 → 다음 발화가 같은 턴으로 재진입)
      //   - 방금 만든 빈 HOST 버블만 제거. 이전의 좋은 맥락(SYSTEM 질문 포함)은 절대 삭제 안 함
      //   - 같은 턴에서 2회 연속이면 "더 짧고 쉬운 문장" 유도 멘트로 전환
      if (restated) {
        _turnCounter--;
        final int restateCount = ++_consecutiveRestateCount;
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
          _scrollToBottom();
        }
        final String restatePhrase = restateCount >= 2
            ? "조금 더 짧고 쉬운 문장으로 말해 주실래요?"
            : "방금 건 살짝 놓쳤어요. 다시 한 번만요.";
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final restateTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        restateTts.addText(restatePhrase);
        int waitTicks = 0;
        while ((restateTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++waitTicks > 200) break;
        }
        // 같은 AI 질문 그대로 유지 → 질문 재생성 없이 STT만 재시작
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }
```

**교체 (블록 전체):**
```dart
      // 🔁 [RESTATE/GARBLED] AI 질문은 그대로 두고 재청취
      //   - [GARBLED] 진짜 안 들림 → "다시 말씀해 주세요" (2회 연속이면 더 쉬운 문장 유도)
      //   - [RESTATE] 또렷하지만 오프토픽 → 들은 내용 그대로 음성으로만 확인 질문 (버블 없음)
      //     → _restateConfirmPending=true → 다음 발화는 RESTATE 검사 없이 그대로 수용
      //   - 턴 카운터 원복(이번 시도 무효 → 다음 발화가 같은 턴으로 재진입)
      //   - 방금 만든 빈 HOST 버블만 제거. 이전의 좋은 맥락(SYSTEM 질문 포함)은 절대 삭제 안 함
      if (restated || garbled) {
        _turnCounter--;
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
          _scrollToBottom();
        }
        String checkPhrase;
        if (garbled) {
          // 진짜 안 들린 경우에만 "다시 말씀해 주세요"
          final int restateCount = ++_consecutiveRestateCount;
          checkPhrase = restateCount >= 2
              ? "조금 더 짧고 쉬운 문장으로 말해 주실래요?"
              : "잘 안 들렸어요. 다시 말씀해 주세요.";
        } else {
          // 또렷하지만 오프토픽 → 그런 뜻인지 음성으로만 확인. 글자(버블)로는 남기지 않음
          _restateConfirmPending = true;
          final String heard = finalTranscript.trim();
          checkPhrase =
              "방금, $heard, 라고 말씀하신 건가요? 맞다면 그대로 다시 한 번 말씀해 주세요.";
        }
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final restateTts = ChunkedTtsFetcher(
          _openAiKey,
          _ttsQueueManager,
          'nova',
          isUser: false,
          onLog: _log,
        );
        restateTts.addText(checkPhrase);
        int waitTicks = 0;
        while ((restateTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++waitTicks > 200) break;
        }
        // 같은 AI 질문 그대로 유지 → 질문 재생성 없이 STT만 재시작
        if (mounted && _isConversationActive) _startDeepgramListening();
        return;
      }
```

## [S-9] 스트림 파싱 — GARBLED 감지 추가, 확인 재진입 시 RESTATE→GARBLED 강등 (약 1922~1927줄)

**찾기 (anchor):**
```dart
        // 다시 말하기 감지: 맥락 어긋남 OR 발음 불확실 → 같은 AI 질문 유지하고 재청취
        if (userTargetText.contains("[RESTATE]")) {
          restated = true;
          _log('🔁 [RESTATE]', '맥락 불일치/발음 불확실 → 같은 질문 유지, 다시 말하기 요청');
          break;
        }
```

**교체:**
```dart
        // 다시 말하기 감지: [RESTATE]=또렷하지만 오프토픽 / [GARBLED]=진짜 안 들림
        // 확인 재진입(isRestateConfirm) 중 모델이 또 [RESTATE]를 내면 GARBLED로 강등 → 확인 루프 방지
        if (userTargetText.contains("[RESTATE]")) {
          if (isRestateConfirm) {
            garbled = true;
            _log('👂 [GARBLED]', '확인 재진입 중 RESTATE 재발 → 다시 말하기 요청으로 강등');
          } else {
            restated = true;
            _log('🔁 [RESTATE]', '맥락 불일치 → 음성으로만 확인 질문 후 재청취');
          }
          break;
        }
        if (userTargetText.contains("[GARBLED]")) {
          garbled = true;
          _log('👂 [GARBLED]', '발음 불확실 → 다시 말하기 요청');
          break;
        }
```

## [S-10] garbled 플래그 선언 추가 (약 1869줄)

**찾기 (anchor):**
```dart
      bool restated = false; // 맥락 어긋남/발음 불확실 → 같은 AI 질문 유지하고 다시 말하기 요청
```

**교체:**
```dart
      bool restated = false; // 또렷하지만 오프토픽 → 음성으로만 확인 질문 후 재청취
      bool garbled = false; // 진짜 발음 불확실 → "다시 말씀해 주세요" 요청
```

## [S-11] 콜사이트 — disableRestate 전달 (약 1852~1858줄)

**찾기 (anchor):**
```dart
      final userStream = StepExpandBrain.streamUserTranslation(
        apiKey: _openAiKey,
        textOriginal: finalTranscript,
        targetLang: targetLangName,
        contextStr: contextStr,
        disableCorrection: isCorrectionRetry,
      );
```

**교체:**
```dart
      final userStream = StepExpandBrain.streamUserTranslation(
        apiKey: _openAiKey,
        textOriginal: finalTranscript,
        targetLang: targetLangName,
        contextStr: contextStr,
        disableCorrection: isCorrectionRetry,
        disableRestate: isRestateConfirm,
      );
```

## [S-12] 파이프라인 시작부 — 확인 플래그 소비 (약 1739~1745줄)

**찾기 (anchor):**
```dart
  Future<void> _processRelayPipeline(String finalTranscript,
      {bool isCorrectionRetry = false}) async {
    _resetIdleTimer();
    _turnCounter++;
    final int currentTurnId = _turnCounter;
```

**교체:**
```dart
  Future<void> _processRelayPipeline(String finalTranscript,
      {bool isCorrectionRetry = false}) async {
    _resetIdleTimer();
    // [RESTATE-CONFIRM] 직전 턴에서 오프토픽 확인 질문을 했다면, 이번 발화는 RESTATE 검사 없이 수용
    final bool isRestateConfirm = _restateConfirmPending;
    _restateConfirmPending = false;
    _turnCounter++;
    final int currentTurnId = _turnCounter;
```

## [S-13] Box 5-SILENCE 블록 전체 삭제 (약 1558~1607줄)

**삭제 범위:** 약 1558줄 `// ====================================================================` (바로 아래 줄이 `// 📦 [Box 5-SILENCE: 첫 질문 침묵/망설임 폴백]`) 부터 약 1607줄 `  }` (`_handleOpeningSilenceFallback` 함수의 닫는 중괄호, 바로 다음이 빈 줄 + `// ====================================================================` + `// 📦 [Box 5-RETRY: 재질문 처리]` 헤더) 까지.

**찾기 (anchor — 블록 전체 삭제, new_str은 빈 문자열):**
```dart
// ====================================================================
// 📦 [Box 5-SILENCE: 첫 질문 침묵/망설임 폴백]
// ====================================================================
  /// 기본 문장 입력 대기 중 침묵 시 "짧아도 괜찮아요" 안내 문구 (다시 AI 질문 생성 안 함)
  String _getSilenceFallbackPhrase(String targetLang) {
    return '짧아도 괜찮아요. 먼저 떠오르는 기본 문장을 하나 말해 주세요.';
  }

  /// 턴 0(기본 문장 입력 대기) 중 7초 침묵 감지 → 부드럽게 안내 후 계속 대기
  Future<void> _handleOpeningSilenceFallback() async {
```
부터 해당 함수의 닫는 `  }` 까지 **함수 2개 + 헤더 주석 3줄 전체 삭제**. (함수 끝 anchor: `      _startDeepgramListening();` → `    }` → `  }` 로 끝나며, 그 다음 블록은 `[Box 5-RETRY: 재질문 처리]` 헤더)

## [S-14] _stopMicAndProcess 내 타이머 취소 삭제 (약 1470~1473줄)

**찾기 (anchor):**
```dart
  void _stopMicAndProcess(String transcript) async {
    _resetIdleTimer();
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final clean = transcript.trim();
```

**교체:**
```dart
  void _stopMicAndProcess(String transcript) async {
    _resetIdleTimer();
    final clean = transcript.trim();
```

## [S-15] 침묵 타이머 시작 블록 삭제 (약 1457~1465줄)

**찾기 (anchor — new_str은 빈 문자열로 삭제):**
```dart

    // 🌱 턴 0(기본 문장 입력 대기 중)에서만 침묵/망설임 타이머 시작 — 폴백 발화 후 재설정 방지
    if (_turnCounter == 0 && _isConversationActive && !_silenceFallbackFired) {
      _silenceTimer?.cancel();
      _silenceTimer = Timer(
        const Duration(seconds: OPENING_SILENCE_SEC),
        _handleOpeningSilenceFallback,
      );
      _log('⏱️ [SILENCE-01]', '기본 문장 침묵 타이머 시작 (${OPENING_SILENCE_SEC}초)');
    }
```

## [S-16] onTranscriptUpdate 내 타이머 취소 블록 삭제 (약 1436~1441줄)

**찾기 (anchor):**
```dart
      onTranscriptUpdate: (transcript) {
        _swDeepgram.reset();
        _swDeepgram.start();
        // 유저가 말을 시작하는 순간 침묵 타이머 취소 (7초 경계 발화 보호)
        if (_silenceTimer != null) {
          _silenceTimer!.cancel();
          _silenceTimer = null;
          _log('⏱️ [SILENCE-CANCEL]', '발화 감지 → 침묵 타이머 취소');
        }
      },
```

**교체:**
```dart
      onTranscriptUpdate: (transcript) {
        _swDeepgram.reset();
        _swDeepgram.start();
      },
```

## [S-17] _stopEverything 내 타이머 취소 삭제 (약 1393~1394줄)

**찾기 (anchor):**
```dart
    _commitTimer?.cancel();
    _commitTimer = null;
    _pendingTranscript = '';
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _voiceManager?.dispose();
```

**교체:**
```dart
    _commitTimer?.cancel();
    _commitTimer = null;
    _pendingTranscript = '';
    _voiceManager?.dispose();
```

## [S-18] _suggestNewSentence 내 플래그 리셋 삭제 (약 839줄)

**찾기 (anchor — _suggestNewSentence 함수 내부, `_startSessionWaitingForUserSeed()` 호출 직전 블록):**
```dart
        _showStudyRoomPrompt = false;
        _silenceFallbackFired = false;
      });
    }
    _startSessionWaitingForUserSeed(); // 시작 안내 후 유저 seed 문장 대기
```

**교체:**
```dart
        _showStudyRoomPrompt = false;
      });
    }
    _startSessionWaitingForUserSeed(); // 시작 안내 후 유저 seed 문장 대기
```

## [S-19] 또 다른 리셋 지점 삭제 (약 805줄)

[S-18] 적용 후 `grep -n "_silenceFallbackFired = false;"` 로 남은 1곳(약 805줄, `_showStudyRoomPrompt = false;` 바로 아래)을 확인하고 해당 줄 1줄만 삭제.

**찾기 (anchor):**
```dart
        _showStudyRoomPrompt = false;
        _silenceFallbackFired = false;
      });
    }
  }
```

**교체:**
```dart
        _showStudyRoomPrompt = false;
      });
    }
  }
```

## [S-20] 세션 시작부 주석 수정 (약 500~502줄)

**찾기 (anchor):**
```dart
    // 안내/질문 완료  STT 즉시 시작 (유저 기본 문장 대기)
    // 🔧 [MIC-INSTANT] 8초 딜레이 제거  AI 말 끝나자마자 마이크 ON.
    // 침묵 시 안내는 _startDeepgramListening() 내부의 7초 타이머가 담당.
```

**교체:**
```dart
    // 안내/질문 완료  STT 즉시 시작 (유저 기본 문장 대기)
    // 🔧 [MIC-INSTANT] 8초 딜레이 제거  AI 말 끝나자마자 마이크 ON.
    // 침묵 시 별도 안내 멘트 없이 그대로 대기 (침묵 폴백 제거됨).
```

## [S-21] 시드 스니펫 필러/길이 필터 추가 (약 367~370줄)

**찾기 (anchor):**
```dart
      if (hostTexts.isEmpty) return [];

      hostTexts.shuffle();
      return hostTexts.take(3).toList(); // 2~3개 랜덤 샘플
```

**교체:**
```dart
      if (hostTexts.isEmpty) return [];

      // 🧹 필러/연결어 발화 제외 — 구체적 내용이 있는 발화만 시드 후보로
      const fillerPatterns = [
        '네', '응', '예', '그래', '맞아', '맞아요', '좋아', '좋아요',
        '오케이', 'ok', 'okay', '음', '어', '아', '그래서', '그러니까',
        '그렇구나', '알겠어', '알겠습니다', 'yes', 'yeah', 'sure', 'right',
        'thank you', 'thanks',
      ];
      bool isFiller(String s) {
        final t = s.replaceAll(RegExp(r'[\s\.,!?~…]'), '').toLowerCase();
        if (t.length < 6) return true; // 너무 짧으면 내용 없음으로 간주
        return fillerPatterns.contains(t);
      }

      final contentTexts = hostTexts.where((s) => !isFiller(s)).toList();
      if (contentTexts.isEmpty) return []; // 내용 발화 없음 → 고정 안내로 폴백

      // 내용이 풍부한(긴) 발화 우선 풀 구성 후 랜덤 샘플
      contentTexts.sort((a, b) => b.length.compareTo(a.length));
      final seedPool = contentTexts.take(8).toList()..shuffle();
      return seedPool.take(3).toList(); // 2~3개 샘플
```

## [S-22] 멤버 필드 추가/삭제 (약 142~144줄, 208줄)

**(a) 추가 — 찾기 (anchor, 약 208줄):**
```dart
  int _consecutiveRestateCount = 0; // 같은 턴 연속 RESTATE 횟수 (2 이상이면 더 쉬운 문장 유도)
```

**교체:**
```dart
  int _consecutiveRestateCount = 0; // 같은 턴 연속 GARBLED 횟수 (2 이상이면 더 쉬운 문장 유도)
  bool _restateConfirmPending = false; // 오프토픽 확인 질문 후 다음 발화는 RESTATE 검사 없이 수용
```

**(b) 삭제 — 찾기 (anchor, 약 142~144줄):**
```dart
  Timer? _silenceTimer; // 기본 문장 입력 대기 중 침묵/망설임 감지 타이머
  static const int OPENING_SILENCE_SEC = 7; // 침묵 판정 대기 시간(초) — 유저 망설임 7초 대기
  bool _silenceFallbackFired = false; // 폴백 발화 후 재타이머 방지 플래그
```
→ 3줄 전체 삭제 (new_str 빈 문자열).

## 파일 1 검증
```bash
grep -c "_silenceTimer" lib/custom_code/widgets/routine_mode_step_expand.dart        # 기대값: 0
grep -c "_silenceFallbackFired" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 0
grep -c "_handleOpeningSilenceFallback" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 0
grep -c "OPENING_SILENCE_SEC" lib/custom_code/widgets/routine_mode_step_expand.dart   # 기대값: 0
grep -c "_getSilenceFallbackPhrase" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 0
grep -c "Last time you mentioned" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 0
grep -c "\[GARBLED\]" lib/custom_code/widgets/routine_mode_step_expand.dart           # 기대값: 7 (프롬프트5 + 클라이언트2)
grep -c "_restateConfirmPending" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 4
grep -c "disableRestate" lib/custom_code/widgets/routine_mode_step_expand.dart         # 기대값: 3
grep -c "isRestateConfirm" lib/custom_code/widgets/routine_mode_step_expand.dart       # 기대값: 4
```
※ 기대값과 ±1 차이 나면 적용 누락/중복 여부를 sed -n 으로 해당 구간 직접 확인할 것.

---

# 파일 2: routine_mode_free_talk.dart (편집 2건, 아래→위)

## [F-1] Advanced 레벨 지침 교체 — 품위/고급 어휘만, 길이 증가 금지 (약 3532~3536줄)

**찾기 (anchor):**
```dart
      case "Advanced":
        return "ADVANCED (CEFR C1-C2). Speak exactly like an educated native adult. "
            "Freely use idioms, phrasal verbs, colloquial slang, and witty or nuanced expressions. "
            "Use varied grammar such as conditionals, relative clauses, and perfect tenses. "
            "Do not simplify anything.";
```

**교체:**
```dart
      case "Advanced":
        return "ADVANCED (CEFR C1-C2). Speak like a refined, well-educated native adult. "
            "Use sophisticated, precise vocabulary and elegant, polished expressions. "
            "Refined idioms and nuanced word choice are welcome; NO slang, NO vulgar or overly casual wording. "
            "Use varied grammar such as conditionals, relative clauses, and perfect tenses. "
            "CRITICAL: Elevate WORD CHOICE only. NEVER make replies longer — keep the exact same brevity as the other levels (usually ONE short sentence).";
```

## [F-2] DISSATISFIED 감지 신호 확장 (약 3367~3372줄)

**찾기 (anchor):**
```dart
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해줘" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
More signs (question complaints): "뭐라고 물었어" / "뭐라고 물은 거야" / "다시 물어봐" / "제대로 다시 물어봐" / "질문 다시 해줘" / "다른 질문 해줘" / "what did you ask" / "ask me again" / "ask a different question"
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)'''
```

**교체:**
```dart
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해줘" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
More signs (question complaints): "뭐라고 물었어" / "뭐라고 물은 거야" / "다시 물어봐" / "제대로 다시 물어봐" / "질문 다시 해줘" / "다른 질문 해줘" / "what did you ask" / "ask me again" / "ask a different question"
More signs (MILD dissatisfaction — these ALSO count): "별로네" / "별로다" / "음 그건 좀" / "에이" / "그런 거 말고" / "딴 거 없어" / "재미없어" / "이상하네" / "뭐야 그게" / "meh" / "not really" / "hmm, not that one"
Even slight or indirect displeasure aimed at the AI's last reply or question counts as [DISSATISFIED].
Do NOT confuse this with a negative ANSWER to the question (e.g., "아니, 안 갔어" = a valid answer, NOT dissatisfaction).
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)'''
```

## 파일 2 검증
```bash
grep -c "colloquial slang" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 0
grep -c "MILD dissatisfaction" lib/custom_code/widgets/routine_mode_free_talk.dart # 기대값: 1
grep -c "NEVER make replies longer" lib/custom_code/widgets/routine_mode_free_talk.dart # 기대값: 1
```

---

# 파일 3: routine_mode_roleplay.dart (편집 1건)

## [R-1] DISSATISFIED 감지 신호 확장 (약 3823~3828줄)

**찾기 (anchor):**
```dart
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해줘" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
Do NOT output this when the user is answering negatively IN CHARACTER (e.g., refusing an offer inside the roleplay is a valid in-character answer).
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)
```

**교체:**
```dart
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해줘" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
More signs (MILD dissatisfaction — these ALSO count when clearly aimed at the AI reply itself, OUT of character): "별로네" / "별로다" / "음 그건 좀" / "에이" / "그런 거 말고" / "재미없어" / "이상하네" / "뭐야 그게" / "meh" / "not really" / "hmm, not that one"
Even slight or indirect displeasure aimed at the AI's last reply counts.
Do NOT output this when the user is answering negatively IN CHARACTER (e.g., refusing an offer inside the roleplay is a valid in-character answer).
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)
```

## 파일 3 검증
```bash
grep -c "MILD dissatisfaction" lib/custom_code/widgets/routine_mode_roleplay.dart # 기대값: 1
```

---

# 최종 검증

```bash
cd F:\flutter_project\stealth_vox
flutter analyze lib/custom_code/widgets/routine_mode_step_expand.dart lib/custom_code/widgets/routine_mode_free_talk.dart lib/custom_code/widgets/routine_mode_roleplay.dart
```
- 에러 0건이어야 함. unused 경고가 silence 관련으로 남으면 잔여 참조 재확인.

**실기기 테스트 체크리스트:**
1. [Step Expand] 세션 시작 후 7초 이상 침묵 → 아무 멘트 없이 계속 대기하는지
2. [Step Expand] 프리톡 기록이 있는 계정 → 첫 질문이 "전에 ~라고 했죠" 류 표현 없이, 의미있는 새 질문인지 (필러만 있는 기록이면 고정 안내로 폴백)
3. [Step Expand] 질문과 무관한 또렷한 말 → "방금 ~라고 말씀하신 건가요?" 음성만 나오고 화면에 버블 안 남는지 → 같은 말 반복 시 그대로 수용되는지
4. [Step Expand] 웅얼거림 → "잘 안 들렸어요. 다시 말씀해 주세요." 나오는지
5. [3개 모드 공통] "음 별로네" / "에이 그런 거 말고" → 직전 응답 삭제 후 재생성되는지
6. [Free Talk] Advanced 토글 → 답변 길이는 그대로, 어휘만 고급스러워지는지 (슬랭 없음)

# 롤백

```bash
git restore lib/custom_code/widgets/routine_mode_step_expand.dart lib/custom_code/widgets/routine_mode_free_talk.dart lib/custom_code/widgets/routine_mode_roleplay.dart
# 또는 커밋했다면
git revert <hash>
```