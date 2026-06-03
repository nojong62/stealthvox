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

# StealthVox 정정(CORRECTION) 감지 통일 수정 지시문

## 목표
유저가 "아까 내 말 잘못 알아들었다, 그게 아니라 X다"라고 정정하면, AI의 직전 응답과
오해된 유저 발화를 지우고 정정 발화로 다시 응답한다.

이 기능은 이미 세 모드에 있으나 방식이 갈려 있다:
- **StepExpand**: GPT가 `[CASE CORRECTION]` 규칙으로 판단 → `[CORRECTION]` 토큰 (정교, 오탐 가드 있음). ← 정답
- **Clone / Roleplay**: 클라이언트 키워드 매칭(`_isCorrectionAttempt`). 오탐·미탐 발생. Brain엔 규칙 없음.

→ **Clone·Roleplay를 StepExpand 방식(GPT 판단 `[CORRECTION]`)으로 교체한다.** StepExpand는 손대지 않는다.

## 이 작업에서 같이 잡는 두 가지 (중요)
1. **Clone 장기기억 정리**: Clone은 contextStr을 `_recentHistory` 우선으로 만든다. `_removeLastExchange()`는
   `_localMessages`만 지우므로, 정정 후 재처리 시 `_recentHistory`에 남은 오해가 GPT로 재주입된다.
   → 정정 시 `_recentHistory`에서도 직전 2개(user+assistant)를 제거한다. (Roleplay는 해당 없음.)
2. **무한루프 방지**: 재처리 발화에도 "아니 내 말은…"이 남아 또 정정으로 잡힐 수 있다.
   → `_processRelayPipeline`에 `isCorrectionRetry` 플래그 추가, 재진입 시 `[CORRECTION]` 감지 생략.

---

## 절대 건드리지 말 것 (CRITICAL)
- **Box 7 통신 엔진**: `TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher` 내부 — 수정 금지.
  (단, 이미 쓰이는 public API `_ttsQueueManager.stop()` / `setUserTurn()` 호출은 허용.)
- **StepExpand 파일 전체** — 수정 금지(기준 구현이므로 그대로 둠).
- 프롬프트 문자열 규칙: URL 마크다운 금지, 따옴표 이스케이프 주의(삼중따옴표 내부이므로 안전).

---

# PART 1 — routine_mode_clone.dart

### 1-A. CloneBrain 유저 번역 프롬프트에 [CASE CORRECTION] 추가
**위치**: `streamUserTranslation`의 `sysPrompt`(3874줄 시작). pro-drop 설명 문단(3877줄) 바로 다음,
`[INTERNAL THINKING` 앞에 블록 삽입.

**기준 줄(3877) — 이 줄 바로 아래에 삽입:**
```
Korean is a heavy pro-drop language — subjects, objects, and pronouns are constantly omitted when clear from context. Your job is to resolve these omissions perfectly.
```

**삽입할 블록(앞뒤 빈 줄 포함):**
```

[CASE CORRECTION] — Check this FIRST, only when the conversation history contains at least one "User:" line.
The user is correcting the AI's misunderstanding or mishearing of their PREVIOUS utterance.
Signs:
- Starts with a correction signal: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST "User:" line in the history, NOT new information.
- The user is essentially saying "that's not what I said — what I said was X."
If this is a correction, output EXACTLY: [CORRECTION]  (and nothing else)
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.
```

---

### 1-B. `_processRelayPipeline` 시그니처에 재진입 플래그 추가
**위치**: 1839줄.

**Before:**
```dart
  Future<void> _processRelayPipeline(String finalTranscript) async {
```
**After:**
```dart
  Future<void> _processRelayPipeline(String finalTranscript,
      {bool isCorrectionRetry = false}) async {
```

---

### 1-C. 기존 키워드 정정 블록 삭제
**삭제 범위**: 1879줄(`    // ─────...` STEP 1.5 구분선) ~ 1892줄(`    }`).
즉 아래 블록 전체를 삭제한다(STEP 2의 `try {`는 남긴다):
```dart
    // ─────────────────────────────────────────────────────
    // STEP 1.5: 정정 감지 — AI 오해/오청취 시 직전 교환 삭제
    // ─────────────────────────────────────────────────────
    if (_isCorrectionAttempt(finalTranscript)) {
      _log('🔄 [CORRECT-01]', '정정 감지: "$finalTranscript" → 직전 교환 삭제');
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _removeLastExchange();
        });
        _scrollToBottom();
      }
      _log('🔄 [CORRECT-02]', '직전 교환 삭제 완료 → 재처리 진행');
    }
```

---

### 1-D. 스트림 루프에 `[CORRECTION]` 토큰 감지 추가
**위치**: `bool evaporated = false;`(1957줄) — 그 다음 줄에 `corrected` 선언 추가.

**Before:**
```dart
      bool evaporated = false;
      bool firstChunkSent = false;
```
**After:**
```dart
      bool evaporated = false;
      bool corrected = false; // 유저가 AI의 오해를 정정 → 직전 교환 삭제 후 재처리
      bool firstChunkSent = false;
```

**위치**: EVAPORATE 감지 블록(1964~1968줄) 바로 다음에 CORRECTION 감지 추가.

**Before:**
```dart
        if (userTargetText.contains("[EVAPORATE]")) {
          evaporated = true;
          _log('⚠️ [EVAPORATE]', '증발 감지 → 턴 취소');
          break;
        }
```
**After:**
```dart
        if (userTargetText.contains("[EVAPORATE]")) {
          evaporated = true;
          _log('⚠️ [EVAPORATE]', '증발 감지 → 턴 취소');
          break;
        }
        // 🔄 [CORRECTION] 정정 감지 (재진입 시 무시)
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 교환 삭제 후 재시작');
          break;
        }
```

---

### 1-E. post-loop CORRECTION 처리 추가
**위치**: `evaporated` 처리 블록(1997~2004줄)의 닫는 `}` 다음, `if (userBuffer.trim().isNotEmpty)`(2006줄) 앞.

**Before:**
```dart
      if (evaporated) {
        if (mounted)
          setState(
              () => _localMessages.removeWhere((m) => m['role'] == 'HOST'));
        if (_isConversationActive && _turnCounter == currentTurnId)
          _speakRetryAndListen();
        return;
      }

      if (userBuffer.trim().isNotEmpty)
```
**After:**
```dart
      if (evaporated) {
        if (mounted)
          setState(
              () => _localMessages.removeWhere((m) => m['role'] == 'HOST'));
        if (_isConversationActive && _turnCounter == currentTurnId)
          _speakRetryAndListen();
        return;
      }

      // 🔄 [CORRECTION] 유저가 AI의 오해/오청취를 정정 → 직전 교환 삭제 후 재처리
      if (corrected) {
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex); // 방금 만든 현재 HOST 버블 제거
            }
            _removeLastExchange(); // 직전 HOST(오해 발화)+SYSTEM(틀린 응답) 제거
          });
          _scrollToBottom();
        }
        // 🔑 장기기억에서도 직전 교환 제거 — 안 하면 재처리 시 오해가 contextStr로 재주입됨
        if (_recentHistory.length >= 2) {
          _recentHistory.removeRange(
              _recentHistory.length - 2, _recentHistory.length);
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        // 정정된 발화로 재처리 (재진입이므로 [CORRECTION] 재감지 안 함)
        _processRelayPipeline(finalTranscript, isCorrectionRetry: true);
        return;
      }

      if (userBuffer.trim().isNotEmpty)
```

---

# PART 2 — routine_mode_roleplay.dart
(Clone과 동일 패턴. 단 `_recentHistory` pop은 **없음** — Roleplay는 `_localMessages`만 사용.)

### 2-A. RoleplayBrain 유저 번역 프롬프트에 [CASE CORRECTION] 추가
**위치**: `streamUserTranslation`의 `sysPrompt`(3715줄 시작). pro-drop 설명 줄(3718줄) 바로 다음,
`[INTERNAL THINKING` 앞에 삽입.

**기준 줄(3718) — 이 줄 바로 아래에 삽입:**
```
Korean is a heavy pro-drop language - subjects, objects, and pronouns are constantly omitted when clear from context.
```
**삽입할 블록(PART 1-A와 동일 텍스트, 앞뒤 빈 줄 포함):**
```

[CASE CORRECTION] — Check this FIRST, only when the conversation history contains at least one "User:" line.
The user is correcting the AI's misunderstanding or mishearing of their PREVIOUS utterance.
Signs:
- Starts with a correction signal: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
- AND the content is clearly a re-statement or clarification of the LAST "User:" line in the history, NOT new information.
- The user is essentially saying "that's not what I said — what I said was X."
If this is a correction, output EXACTLY: [CORRECTION]  (and nothing else)
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.
```

---

### 2-B. `_processRelayPipeline` 시그니처에 재진입 플래그 추가
**위치**: 1126줄.

**Before:**
```dart
  Future<void> _processRelayPipeline(String finalTranscript) async {
```
**After:**
```dart
  Future<void> _processRelayPipeline(String finalTranscript,
      {bool isCorrectionRetry = false}) async {
```

---

### 2-C. 기존 키워드 정정 블록 삭제
**삭제 범위**: 1165줄(`    // ─────...` STEP 1.5 구분선) ~ 1179줄(`    }`).
아래 블록 전체 삭제(STEP 2의 `try {`는 남김):
```dart
    // ─────────────────────────────────────────────────────
    // STEP 1.5: 정정 감지 — AI 오해/오청취 시 직전 교환 삭제
    // ─────────────────────────────────────────────────────
    if (_isCorrectionAttempt(finalTranscript)) {
      _log('🔄 [CORRECT-01]', '정정 감지: "$finalTranscript" → 직전 교환 삭제');
      if (mounted) {
        setState(() {
          _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
          _removeLastExchange();
        });
        if (_localMessages.isNotEmpty)
          _scrollToBottom();
      }
      _log('🔄 [CORRECT-02]', '직전 교환 삭제 완료 → 재처리 진행');
    }
```

---

### 2-D. 스트림 루프에 `[CORRECTION]` 토큰 감지 추가
**위치**: `bool clarified = false;`(1238줄) 다음 줄에 `corrected` 선언 추가.

**Before:**
```dart
      bool evaporated = false;
      bool clarified = false; // 주어/목적어 모호 → AI 되묻기
      bool firstChunkSent = false;
```
**After:**
```dart
      bool evaporated = false;
      bool clarified = false; // 주어/목적어 모호 → AI 되묻기
      bool corrected = false; // 유저가 AI의 오해를 정정 → 직전 교환 삭제 후 재처리
      bool firstChunkSent = false;
```

**위치**: EVAPORATE 감지 블록(1245~1249줄) 바로 다음에 CORRECTION 감지 추가.

**Before:**
```dart
        if (userTargetText.contains("[EVAPORATE]")) {
          evaporated = true;
          _log('⚠️ [EVAPORATE]', '증발 감지 → 턴 취소');
          break;
        }
```
**After:**
```dart
        if (userTargetText.contains("[EVAPORATE]")) {
          evaporated = true;
          _log('⚠️ [EVAPORATE]', '증발 감지 → 턴 취소');
          break;
        }
        // 🔄 [CORRECTION] 정정 감지 (재진입 시 무시)
        if (!isCorrectionRetry && userTargetText.contains("[CORRECTION]")) {
          corrected = true;
          _log('🔄 [CORRECTION]', '정정 감지 → 직전 교환 삭제 후 재시작');
          break;
        }
```

---

### 2-E. post-loop CORRECTION 처리 추가
**위치**: `evaporated` 처리 블록(1295~1302줄)의 닫는 `}` 다음, `// ❓ [CLARIFY]`(1304줄) 앞.

**Before:**
```dart
      if (evaporated) {
        if (mounted)
          setState(
              () => _localMessages.removeWhere((m) => m['role'] == 'HOST'));
        if (_isConversationActive && _turnCounter == currentTurnId)
          _speakRetryAndListen();
        return;
      }

      // ❓ [CLARIFY] 유저 발화 주어/목적어 모호 → In-Character 되묻기 + STT 재시작
```
**After:**
```dart
      if (evaporated) {
        if (mounted)
          setState(
              () => _localMessages.removeWhere((m) => m['role'] == 'HOST'));
        if (_isConversationActive && _turnCounter == currentTurnId)
          _speakRetryAndListen();
        return;
      }

      // 🔄 [CORRECTION] 유저가 AI의 오해/오청취를 정정 → 직전 교환 삭제 후 재처리
      if (corrected) {
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length &&
                _localMessages[hostIndex]['role'] == 'HOST') {
              _localMessages.removeAt(hostIndex); // 방금 만든 현재 HOST 버블 제거
            }
            _removeLastExchange(); // 직전 HOST(오해 발화)+SYSTEM(틀린 응답) 제거
          });
          if (_localMessages.isNotEmpty) _scrollToBottom();
        }
        _ttsQueueManager.stop();
        _ttsQueueManager.setUserTurn(false);
        // 정정된 발화로 재처리 (재진입이므로 [CORRECTION] 재감지 안 함)
        _processRelayPipeline(finalTranscript, isCorrectionRetry: true);
        return;
      }

      // ❓ [CLARIFY] 유저 발화 주어/목적어 모호 → In-Character 되묻기 + STT 재시작
```

---

## 선택적 정리 (Optional cleanup)
1-C / 2-C로 호출이 사라지면 다음 헬퍼가 미사용이 된다. flutter analyze info 경고만 나므로
급하지 않으면 둬도 되고, 깔끔히 하려면 제거:
- Clone: `_isCorrectionAttempt`(1617), `_wordOverlap`(1601), `_hasLastExchange`(1591), `_lastRawTranscript` 대입(1898)
- Roleplay: `_isCorrectionAttempt`(868), `_hasLastExchange`(842), `_lastRawTranscript` 대입(1185)
- **주의**: `_removeLastExchange`는 신규 정정 처리에서 계속 사용하므로 **삭제 금지**.

---

## 검증 체크리스트
1. `flutter analyze` → 신규 에러 0개.
2. 프롬프트 규칙 삽입:
   ```
   grep -c "\[CASE CORRECTION\]" routine_mode_clone.dart      # 1
   grep -c "\[CASE CORRECTION\]" routine_mode_roleplay.dart   # 1
   ```
3. 토큰 파싱 + 재진입 플래그:
   ```
   grep -c "isCorrectionRetry" routine_mode_clone.dart        # 2 이상 (시그니처+루프)
   grep -c "isCorrectionRetry" routine_mode_roleplay.dart     # 2 이상
   grep -c 'contains("\[CORRECTION\]")' routine_mode_clone.dart     # 1
   grep -c 'contains("\[CORRECTION\]")' routine_mode_roleplay.dart  # 1
   ```
4. 키워드 호출 제거:
   ```
   grep -c "_isCorrectionAttempt(finalTranscript)" routine_mode_clone.dart    # 0
   grep -c "_isCorrectionAttempt(finalTranscript)" routine_mode_roleplay.dart # 0
   ```
5. Clone 장기기억 정리 존재 / Roleplay엔 없음:
   ```
   grep -c "_recentHistory.removeRange" routine_mode_clone.dart     # 1
   grep -c "_recentHistory.removeRange" routine_mode_roleplay.dart  # 0
   ```
6. Box 7 무수정 / StepExpand 무수정:
   ```
   grep -c "TtsQueueManager\|DeepgramV2VoiceManager" routine_mode_clone.dart   # 수정 전후 동일
   git diff --stat routine_mode_step_expand.dart   # 변경 없음
   ```

---

## 테스트 시나리오 (실기기)
1. **Clone 정정**: 발화 → AI가 오해한 응답 → "아니, 내 말은 ○○" → 직전 AI응답+유저발화 사라지고
   ○○ 기준 새 응답. **그 다음 턴**의 AI 응답이 오해 없이 ○○ 기반이면 성공(=장기기억도 정리됨).
2. **Roleplay 정정**: 동일.
3. **오탐 방지(중요)**: "아니야, 그리고 어제 거기서…"처럼 **새 정보**를 "아니"로 시작 →
   직전 교환이 지워지면 실패(GPT가 `[CORRECTION]`을 내지 말아야 함).
4. **StepExpand 회귀**: 안 건드렸으니 기존 정정 동작 그대로인지 한 번 확인.

---

## 롤백
각 파일에서 (A)삽입한 [CASE CORRECTION] 블록, (D)`corrected` 선언+토큰 감지, (E)post-loop 처리 블록을
제거하고, (B)시그니처를 `(String finalTranscript)`로 원복, (C)삭제했던 STEP 1.5 키워드 블록을 복원한다.
선택적 정리를 했다면 헬퍼들도 복원.