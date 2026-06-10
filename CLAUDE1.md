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

# StealthVox — Step Expand: 질문 불만 시 확인 후 재질문

## 기능
유저가 AI 질문 내용에 불만을 표시하면:
1. AI: "좀전에 질문을 취소하고 다른 질문을 드릴까요?"
2. 유저가 동의 → 이전 질문 삭제(화면에서도 제거) + 새 질문 생성
3. 유저가 거부 → "알겠어요, 다시 대답해 주세요" + 기존 질문 유지, 재청취

기존 `[RETRY]`(유저가 질문을 못 알아들었을 때 → 즉시 재질문)와 구분되는 별도 흐름.
기존 `_handleRetryQuestion`을 동의 시 재활용한다.

## 대상 파일
```
lib/custom_code/widgets/routine_mode_step_expand.dart
```
**`lib/custom_code/임시/` 아래 파일은 절대 건드리지 말 것.**

작업 전: `git commit -am "save point before STEP_EXPAND_DISSATISFIED"`

**반드시 아래(라인 큰 것)부터 위로 적용한다.**

---

## 수정 ⑥ — Brain 프롬프트에 [DISSATISFIED] 태그 추가 (약 4635번)

### str_replace

**old_str**:
```dart
- Output [RETRY] ONLY when the user's answer shows they did not understand the AI's question itself, so re-asking the same thing would not help.""";
```

**new_str**:
```dart
- Output [RETRY] ONLY when the user's answer shows they did not understand the AI's question itself, so re-asking the same thing would not help.
- Output [DISSATISFIED] when the user expresses dissatisfaction, complaint, or rejection about the AI's QUESTION itself (not about the topic). Signs: "다른 질문 해줘" / "그 질문 싫어" / "질문 바꿔" / "별로야" / "그건 좀" / "다른 거 물어봐" / "change the question" / "ask something else" / "I don't like that question". Do NOT output [DISSATISFIED] when the user is simply answering negatively (e.g., "아니, 안 갔어" = a valid negative answer).""";
```

---

## 수정 ⑤ — 새 함수 _handleDissatisfiedConfirmation (기존 _handleRetryQuestion 바로 위, 약 1609번)

### str_replace

**old_str**:
```dart
// 📦 [Box 5-RETRY: 재질문 처리]
```

**new_str**:
```dart
// 📦 [Box 5-DISSATISFIED: 질문 불만 확인 후 재질문]
// ====================================================================
  Future<void> _handleDissatisfiedConfirmation() async {
    _log('😤 [DISSATISFIED]', '질문 불만 감지 → 확인 단계 진입');
    _ttsQueueManager.setUserTurn(false);
    _ttsQueueManager.setAiPaused(false);

    // 확인 멘트 TTS
    final confirmTts = ChunkedTtsFetcher(
      _openAiKey,
      _ttsQueueManager,
      'nova',
      isUser: false,
      onLog: _log,
    );
    confirmTts.addText('좀전에 질문을 취소하고 다른 질문을 드릴까요?');
    int ticks = 0;
    while ((confirmTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
        mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (++ticks > 200) break;
    }

    // 유저 응답 대기 (마이크 ON)
    if (mounted && _isConversationActive && !_isSessionComplete) {
      _awaitingDissatisfiedConfirm = true;
      _startDeepgramListening();
    }
  }

  // 🔧 [DISSATISFIED] 유저 응답이 동의인지 판단 (한국어/영어 패턴)
  bool _isDissatisfiedAgreement(String raw) {
    final lower = raw.toLowerCase().trim();
    final agreePatterns = [
      '응', '예', '어', '그래', '맞아', '좋아', '해줘', '부탁', '바꿔',
      '다른', '네', '그렇게', 'yes', 'yeah', 'sure', 'okay', 'ok',
      'please', 'change',
    ];
    for (final p in agreePatterns) {
      if (lower.contains(p)) return true;
    }
    return false;
  }

// 📦 [Box 5-RETRY: 재질문 처리]
```

---

## 수정 ④ — _commitAndProcess에 확인 응답 분기 추가 (약 1539번)

`_commitAndProcess` 함수 안, `_log('🔀 [COMMIT-01]', ...)` 줄 바로 **뒤**에 분기를 추가한다.

### str_replace

**old_str**:
```dart
    _log('🔀 [COMMIT-01]', '확정: "$committed" → 파이프라인 시작');

    // 마이크/VoiceManager 정리
    await _voiceManager?.dispose();
    _voiceManager = null;
    _log('🔀 [COMMIT-02]', 'VoiceManager dispose 완료');

    _log('🔀 [COMMIT-03]', '_processRelayPipeline 호출');
    _processRelayPipeline(committed);
```

**new_str**:
```dart
    _log('🔀 [COMMIT-01]', '확정: "$committed" → 파이프라인 시작');

    // 🔧 [DISSATISFIED] 확인 응답 대기 중이면 동의/거부 분기
    if (_awaitingDissatisfiedConfirm) {
      _awaitingDissatisfiedConfirm = false;
      await _voiceManager?.dispose();
      _voiceManager = null;

      if (_isDissatisfiedAgreement(committed)) {
        _log('😤 [DISSATISFIED-YES]', '동의 → 이전 질문 삭제 + 새 질문 생성');
        _turnCounter--; // 불만 턴 카운트 취소
        // 직전 AI 질문(SYSTEM) 삭제 — _handleRetryQuestion이 다시 지움+생성
        await _handleRetryQuestion(
            _dissatisfiedContextStr, _dissatisfiedTargetLangName);
      } else {
        _log('😤 [DISSATISFIED-NO]', '거부 → 기존 질문 유지, 재청취');
        _ttsQueueManager.setUserTurn(false);
        _ttsQueueManager.setAiPaused(false);
        final noTts = ChunkedTtsFetcher(
          _openAiKey, _ttsQueueManager, 'nova',
          isUser: false, onLog: _log);
        noTts.addText('알겠어요, 다시 대답해 주세요.');
        int t = 0;
        while ((noTts.pendingRequests > 0 || _ttsQueueManager.isBusy) &&
            mounted) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (++t > 200) break;
        }
        if (mounted && _isConversationActive) _startDeepgramListening();
      }
      return;
    }

    // 마이크/VoiceManager 정리
    await _voiceManager?.dispose();
    _voiceManager = null;
    _log('🔀 [COMMIT-02]', 'VoiceManager dispose 완료');

    _log('🔀 [COMMIT-03]', '_processRelayPipeline 호출');
    _processRelayPipeline(committed);
```

---

## 수정 ③ — 파이프라인 처리 분기 추가 (retried 처리 블록 뒤, 약 1977번)

기존 `if (retried) {...}` 블록 바로 뒤에 dissatisfied 분기를 추가한다.

### str_replace

**old_str**:
```dart
      if (retried) {
        _turnCounter--; // 실패한 턴은 카운트 취소
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
        }
        await _handleRetryQuestion(contextStr, targetLangName);
        return;
      }

      // 🔄 [CORRECTION] 유저가 AI의 오해를 정정
```

**new_str**:
```dart
      if (retried) {
        _turnCounter--; // 실패한 턴은 카운트 취소
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
        }
        await _handleRetryQuestion(contextStr, targetLangName);
        return;
      }

      // 😤 [DISSATISFIED] 유저가 질문 내용에 불만 → 확인 단계
      if (dissatisfied) {
        if (mounted) {
          setState(() {
            _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP');
            // 불만 발화(HOST) 화면에서 제거 — AI 질문(SYSTEM)은 아직 유지
            if (hostIndex < _localMessages.length) {
              _localMessages.removeAt(hostIndex);
            }
          });
        }
        // 확인 단계에서 쓸 context 저장
        _dissatisfiedContextStr = contextStr;
        _dissatisfiedTargetLangName = targetLangName;
        await _handleDissatisfiedConfirmation();
        return;
      }

      // 🔄 [CORRECTION] 유저가 AI의 오해를 정정
```

---

## 수정 ② — 파이프라인 감지 플래그 + 태그 체크 추가

### 수정 ②-a — 플래그 선언 (약 1854번)

#### str_replace

**old_str**:
```dart
      bool restated = false; // 맥락 어긋남/발음 불확실 → 같은 AI 질문 유지하고 다시 말하기 요청
```

**new_str**:
```dart
      bool restated = false; // 맥락 어긋남/발음 불확실 → 같은 AI 질문 유지하고 다시 말하기 요청
      bool dissatisfied = false; // 🔧 [DISSATISFIED] 유저가 AI 질문에 불만 → 확인 후 재질문
```

### 수정 ②-b — 태그 감지 (RETRY 감지 뒤, 약 1876번)

#### str_replace

**old_str**:
```dart
        if (userTargetText.contains("[RETRY]")) {
          retried = true;
          _log('⚠️ [RETRY]', '재질문 감지 → 다른 질문 생성');
          break;
        }

        // 정정 감지: 유저가 AI의 오해를 바로잡는 경우
```

**new_str**:
```dart
        if (userTargetText.contains("[RETRY]")) {
          retried = true;
          _log('⚠️ [RETRY]', '재질문 감지 → 다른 질문 생성');
          break;
        }

        // 🔧 [DISSATISFIED] 유저가 AI 질문에 불만 표시
        if (userTargetText.contains("[DISSATISFIED]")) {
          dissatisfied = true;
          _log('😤 [DISSATISFIED]', '질문 불만 감지 → 확인 단계로');
          break;
        }

        // 정정 감지: 유저가 AI의 오해를 바로잡는 경우
```

---

## 수정 ① — 멤버 변수 추가 (약 208번)

### str_replace

**old_str**:
```dart
  int _consecutiveRestateCount = 0; // 같은 턴 연속 RESTATE 횟수 (2 이상이면 더 쉬운 문장 유도)
```

**new_str**:
```dart
  int _consecutiveRestateCount = 0; // 같은 턴 연속 RESTATE 횟수 (2 이상이면 더 쉬운 문장 유도)
  bool _awaitingDissatisfiedConfirm = false; // 🔧 [DISSATISFIED] 확인 응답 대기 중
  String _dissatisfiedContextStr = ''; // 🔧 [DISSATISFIED] 재질문에 쓸 context
  String _dissatisfiedTargetLangName = ''; // 🔧 [DISSATISFIED] 재질문에 쓸 targetLang
```

---

## 절대 건드리지 말 것
- `_handleRetryQuestion` — 그대로 재활용 (동의 시 호출).
- `_stopMicAndProcess` — 변경 없음 (기존 흐름 유지).
- Brain 프롬프트의 기존 태그(`[RETRY]`, `[RESTATE]`, `[CORRECTION]`, `[CLARIFY]`, `[EVAPORATE]`) 정의 — 추가만.
- `DeepgramV2VoiceManager`, `TtsQueueManager`, `HybridTtsPlayer`, `ChunkedTtsFetcher` — Box 7 불변.
- `_startDeepgramListening`, `_processRelayPipeline`의 기존 분기 — 위치만 뒤에 끼워넣기.

## 검증

```powershell
# 멤버 변수 3개
grep -c "_awaitingDissatisfiedConfirm" lib/custom_code/widgets/routine_mode_step_expand.dart   # 기대값: 4 (선언1+set true 1+set false 1+check 1)
grep -c "_dissatisfiedContextStr" lib/custom_code/widgets/routine_mode_step_expand.dart         # 기대값: 3 (선언1+저장1+사용1)

# 새 함수
grep -c "_handleDissatisfiedConfirmation" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 2 (정의1+호출1)
grep -c "_isDissatisfiedAgreement" lib/custom_code/widgets/routine_mode_step_expand.dart        # 기대값: 2 (정의1+호출1)

# Brain 프롬프트 태그
grep -c "DISSATISFIED" lib/custom_code/widgets/routine_mode_step_expand.dart                    # 기대값: 8 이상 (프롬프트+감지+처리+로그)

# 기존 RETRY 미변경
grep -c "_handleRetryQuestion" lib/custom_code/widgets/routine_mode_step_expand.dart            # 기대값: 변경 전 + 1 (DISSATISFIED-YES에서 호출)

flutter analyze lib/custom_code/widgets/routine_mode_step_expand.dart
```
- 신규 error 0건.

## 롤백
```powershell
git restore lib/custom_code/widgets/routine_mode_step_expand.dart
```

## 실기기 확인
1. AI 질문 후 "다른 질문 해줘" → AI: "좀전에 질문을 취소하고 다른 질문을 드릴까요?" → "응" → **이전 질문 삭제 + 새 질문 등장**
2. AI 질문 후 "그 질문 별로야" → 확인 → "아니 됐어" → **기존 질문 유지 + "알겠어요, 다시 대답해 주세요"**
3. AI 질문 후 정상 답변("아니, 안 갔어" 같은 부정 대답) → `[DISSATISFIED]`가 뜨지 **않고** 정상 번역 진행
4. 기존 `[RETRY]`·`[RESTATE]`·`[CORRECTION]`·`[CLARIFY]` 동작 그대로인지