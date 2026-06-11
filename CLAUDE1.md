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

# 수정 지시문 — Step Expand 로그 분석 후속 4건 (우선순위 순)

## 수정 목록 (이 순서대로 진행)
1. **[심각]** TtsCache 저장이 파이프라인을 최대 15초 블로킹 → 백그라운드 분리 (프리톡 [C 수정] 포팅)
2. **[기능]** 불만 재생성이 동일 질문을 또 냄 → 거절된 질문 텍스트를 금지 항목으로 프롬프트에 전달
3. **[품질]** 시드 풀에 과거 불만/메타 발화 혼입 → 시드 필터에 불만 패턴 추가
4. **[경미]** (a) FAST 레인 패턴 보강 (b) 재질문 경로 스톱워치 미리셋으로 디버그 ms 왜곡

## 작업 전 필수
```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "save-point: before log-analysis 4-fix (cache-block/dup-question/seed-filter/fast-lane)"
```

**대상 파일 (1개. lib/custom_code/임시/ 절대 금지):**
- `lib/custom_code/widgets/routine_mode_step_expand.dart`

**절대 규칙:**
- 수정 ①은 이 파일의 `HybridTtsPlayer`(Box 7 사본)를 건드리는 **유일한** 항목이며,
  프리톡 `routine_mode_free_talk.dart`에서 이미 검증 완료된 [C 수정]의 그대로 포팅이다.
  포팅 내용 외에 `HybridTtsPlayer`의 다른 로직(onChunk, remainder 발사 등)은 한 글자도 변경 금지.
- `TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`는 일절 수정 금지.
- 줄번호는 참고용 근사치. **반드시 anchor 문자열로 위치 확정 후, 아래(줄번호 큰 곳)→위 순서로 편집.**
- `dart:async`는 이미 import되어 있으므로(23줄) `unawaited` 사용 가능 — import 추가 불필요.

---

## [L-1] 수정② Brain — isDifferent 프롬프트에 금지 질문 텍스트 주입 (약 5407~5415줄)

**찾기 (anchor):**
```dart
${isDifferent ? """- [DISSATISFIED — REPLACEMENT QUESTION REQUIRED]
  The user rejected the last AI question. That question is now permanently BANNED.
  Rules:
  • Rejected question must NEVER be rephrased, simplified, or reused in any form.
  • Do NOT ask about the same object, action, time, reason, or topic as the banned question.
  • Choose a completely different emotional or situational angle.
  • If the context is thin (early turns), ask about a different aspect of what the user mentioned.
  Every other rule above still applies.""" : (isRetry ? "- [RETRY] The previous question confused the user. Ask a simpler, more direct 5–8-word question." : "")}
```

**교체:**
```dart
${isDifferent ? """- [DISSATISFIED — REPLACEMENT QUESTION REQUIRED]
  The user rejected the last AI question. That question is now permanently BANNED.
${rejectedQuestion.trim().isNotEmpty ? '  BANNED QUESTION (verbatim): "${rejectedQuestion.trim()}"' : ''}
  Rules:
  • The banned question must NEVER be repeated, rephrased, simplified, or reused in any form.
  • Do NOT ask about the same object, action, time, reason, or topic as the banned question.
  • Choose a completely different emotional or situational angle.
  • If the context is thin (early turns), ask about a different aspect of what the user mentioned.
  Every other rule above still applies.""" : (isRetry ? "- [RETRY] The previous question confused the user. Ask a simpler, more direct 5–8-word question." : "")}
```

## [L-2] 수정② Brain — streamGrammarQuestion 시그니처 (약 5166~5175줄)

**찾기 (anchor):**
```dart
  static Stream<String> streamGrammarQuestion({
    required String apiKey,
    required String contextStr,
    required int turnNumber,
    required int maxTurns,
    required String myTarget,
    String userId = '',
    bool isRetry = false,
    bool isDifferent = false,
  }) async* {
```

**교체:**
```dart
  static Stream<String> streamGrammarQuestion({
    required String apiKey,
    required String contextStr,
    required int turnNumber,
    required int maxTurns,
    required String myTarget,
    String userId = '',
    bool isRetry = false,
    bool isDifferent = false,
    String rejectedQuestion = '',
  }) async* {
```

## [L-3] 수정① HybridTtsPlayer — 캐시 저장 백그라운드 분리 (약 3888~3929줄)

**삭제 범위:** 약 3888줄 `    // 2. TtsCache 저장 (재생 없음)` 부터 약 3929줄 클래스 닫는 `}` 까지를 아래로 교체.

**찾기 (anchor — onStreamEnd 후반부 + 클래스 끝, 정확히 일치):**
```dart
    // 2. TtsCache 저장 (재생 없음)
    if (fullSentence.trim().isEmpty) return;
    try {
      final cached = await TtsCache.get(fullSentence, voice);
      if (cached != null && cached.isNotEmpty) {
        lastCacheHit = true;
        lastCacheSaveMs = 0;
        onLog?.call('[HYB-03-HIT]', 'TtsCache HIT — 저장 생략');
        return;
      }
      lastCacheHit = false;
      final sw = Stopwatch()..start();
      final res = await http
          .post(
            Uri.parse('https://api.openai.com/v1/audio/speech'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'tts-1',
              'input': fullSentence,
              'voice': voice,
              'speed': 1.0,
              'response_format': 'mp3',
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await TtsCache.put(fullSentence, voice, res.bodyBytes);
        lastCacheSaveMs = sw.elapsedMilliseconds;
        onLog?.call('[HYB-04-SAVED]',
            '${lastCacheSaveMs}ms (${res.bodyBytes.length}B)');
      } else {
        onLog?.call('[HYB-ERR]', 'API status=${res.statusCode}');
      }
      sw.stop();
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');
    }
  }
}
```

**교체:**
```dart
    // 2. TtsCache 저장 — 🔧 [C 수정 포팅] 백그라운드 fire-and-forget으로 분리.
    //    기존: 캐시 저장 HTTP(최대 15초)를 await → PIPE-02가 그만큼 블로킹됨 (로그로 확인).
    //    프리톡에서 검증 완료된 동일 수정의 포팅. remainder 발사 로직은 그대로 유지.
    final sentence = fullSentence.trim();
    if (sentence.isEmpty) return;
    unawaited(_cacheFullSentenceInBackground(sentence));
  }

  // 🔧 [C 수정 포팅] 통문장 캐시 저장은 await하지 않는 백그라운드 작업.
  Future<void> _cacheFullSentenceInBackground(String fullSentence) async {
    try {
      final cached = await TtsCache.get(fullSentence, voice);
      if (cached != null && cached.isNotEmpty) {
        lastCacheHit = true;
        lastCacheSaveMs = 0;
        onLog?.call('[HYB-03-HIT]', 'TtsCache HIT — 저장 생략');
        return;
      }
      lastCacheHit = false;
      final sw = Stopwatch()..start();
      final res = await http
          .post(
            Uri.parse('https://api.openai.com/v1/audio/speech'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'tts-1',
              'input': fullSentence,
              'voice': voice,
              'speed': 1.0,
              'response_format': 'mp3',
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await TtsCache.put(fullSentence, voice, res.bodyBytes);
        lastCacheSaveMs = sw.elapsedMilliseconds;
        onLog?.call('[HYB-04-SAVED]',
            '${lastCacheSaveMs}ms (${res.bodyBytes.length}B)');
      } else {
        onLog?.call('[HYB-ERR]', 'API status=${res.statusCode}');
      }
      sw.stop();
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');
    }
  }
}
```

## [L-4] 수정② GPT 레인 — 거절 질문 텍스트 전달 (약 2199~2200줄)

**찾기 (anchor):**
```dart
        await _handleRetryQuestion(dissCleanCtx, targetLangName,
            isDifferent: true, silentReplace: true);
```

**교체:**
```dart
        await _handleRetryQuestion(dissCleanCtx, targetLangName,
            isDifferent: true, silentReplace: true,
            rejectedQuestion: dissRejected);
```

## [L-5] 수정② GPT 레인 — 거절 질문 텍스트 캡처 (약 2168~2169줄)

**찾기 (anchor):**
```dart
        final dissLastSysIdx = dissCleanMsgs.lastIndexWhere((m) => m['role'] == 'SYSTEM');
        if (dissLastSysIdx != -1) dissCleanMsgs.removeAt(dissLastSysIdx);
```

**교체:**
```dart
        final dissLastSysIdx = dissCleanMsgs.lastIndexWhere((m) => m['role'] == 'SYSTEM');
        // 🔧 거절된 질문 텍스트 보존 → 재생성 프롬프트에 금지 질문으로 전달 (동일 질문 재생성 방지)
        final String dissRejected = dissLastSysIdx != -1
            ? (dissCleanMsgs[dissLastSysIdx]['target'] ?? '').toString().trim()
            : '';
        if (dissLastSysIdx != -1) dissCleanMsgs.removeAt(dissLastSysIdx);
```

## [L-6] 수정② FAST 레인 — 거절 질문 텍스트 전달 (약 1906줄)

**찾기 (anchor):**
```dart
      await _handleRetryQuestion(_fclCtx, _fclLang, isDifferent: true, silentReplace: true);
```

**교체:**
```dart
      await _handleRetryQuestion(_fclCtx, _fclLang,
          isDifferent: true, silentReplace: true, rejectedQuestion: _fclRejected);
```

## [L-7] 수정② FAST 레인 — 거절 질문 텍스트 캡처 (약 1886~1887줄)

**찾기 (anchor):**
```dart
      final _fclSysIdx = _fastCleanMsgs.lastIndexWhere((m) => m['role'] == 'SYSTEM');
      if (_fclSysIdx != -1) _fastCleanMsgs.removeAt(_fclSysIdx);
```

**교체:**
```dart
      final _fclSysIdx = _fastCleanMsgs.lastIndexWhere((m) => m['role'] == 'SYSTEM');
      // 🔧 거절된 질문 텍스트 보존 → 재생성 프롬프트에 금지 질문으로 전달 (동일 질문 재생성 방지)
      final String _fclRejected = _fclSysIdx != -1
          ? (_fastCleanMsgs[_fclSysIdx]['target'] ?? '').toString().trim()
          : '';
      if (_fclSysIdx != -1) _fastCleanMsgs.removeAt(_fclSysIdx);
```

## [L-8] 수정④b — 재질문 경로 스톱워치 리셋 (약 1764~1769줄, _handleRetryQuestion 내부)

**찾기 (anchor):**
```dart
    String aiText = "";
    String aiOriginalRetry = "";
    String aiBuffer = "";
    bool aiRetryHasDoubleNewline = false;

    await for (final chunk in aiStream) {
```

**교체:**
```dart
    String aiText = "";
    String aiOriginalRetry = "";
    String aiBuffer = "";
    bool aiRetryHasDoubleNewline = false;

    _swTTS..reset()..start(); // 🔧 재질문 경로 스톱워치 리셋 — 디버그 발사 ms 왜곡(9274ms 등) 방지

    await for (final chunk in aiStream) {
```

## [L-9] 수정② — _handleRetryQuestion 시그니처 + Brain 전달 (약 1700~1701줄, 1740~1749줄)

**(a) 찾기 (anchor):**
```dart
  Future<void> _handleRetryQuestion(String contextStr, String targetLangName,
      {bool isDifferent = false, bool isMisheard = false, bool silentReplace = false}) async {
```

**교체:**
```dart
  Future<void> _handleRetryQuestion(String contextStr, String targetLangName,
      {bool isDifferent = false,
      bool isMisheard = false,
      bool silentReplace = false,
      String rejectedQuestion = ''}) async {
```

**(b) 찾기 (anchor):**
```dart
      isRetry: !isDifferent && !isMisheard,
      isDifferent: isDifferent,
    );
```

**교체:**
```dart
      isRetry: !isDifferent && !isMisheard,
      isDifferent: isDifferent,
      rejectedQuestion: rejectedQuestion,
    );
```

## [L-10] 수정③ — 롤플레이 시드 필터에 불만/메타 패턴 추가 (약 476~487줄)

※ 비교 대상 `t`는 공백이 모두 제거된 문자열이므로 패턴도 공백 없이 작성한다.
※ 과잉 필터링은 안전하다 — 후보가 비면 기존 고정 안내로 폴백된다.

**찾기 (anchor):**
```dart
      const fillerPatterns = [
        '네', '응', '음', '그래', '맞아', '맞아요', '좋아', '좋아요',
        '글쎄', 'ok', 'okay', '오케이', '아', '어', '그래요', '그럴까',
        '그렇구나', '고마워', '고맙습니다', 'yes', 'yeah', 'sure',
        'right', 'thank you', 'thanks',
      ];
      bool isFiller(String s) {
        final t = s.replaceAll(RegExp(r'[\s\.,!?~…]'), '').toLowerCase();
        if (t.length < 6) return true;
        return fillerPatterns.contains(t);
      }
```

**교체:**
```dart
      const fillerPatterns = [
        '네', '응', '음', '그래', '맞아', '맞아요', '좋아', '좋아요',
        '글쎄', 'ok', 'okay', '오케이', '아', '어', '그래요', '그럴까',
        '그렇구나', '고마워', '고맙습니다', 'yes', 'yeah', 'sure',
        'right', 'thank you', 'thanks',
      ];
      // 🧹 과거 불만/메타 발화 제외 — 시드 주제로 부적합 (t는 공백 제거됨 → 패턴도 공백 없음)
      const complaintPatterns = [
        '질문', '물어봐', '물어본', '다시말', '이상한', '이상해', '이상하',
        '별로', '뭐야', '바꿔', '그런거말고', '딴거', '다른거', '다른걸',
        '마음에안', '맘에안', 'question', 'askme', 'weird',
      ];
      bool isFiller(String s) {
        final t = s.replaceAll(RegExp(r'[\s\.,!?~…]'), '').toLowerCase();
        if (t.length < 6) return true;
        if (fillerPatterns.contains(t)) return true;
        for (final p in complaintPatterns) {
          if (t.contains(p)) return true;
        }
        return false;
      }
```

## [L-11] 수정③ — 프리톡 시드 필터에 불만/메타 패턴 추가 (약 385~395줄)

**찾기 (anchor):**
```dart
      const fillerPatterns = [
        '네', '응', '어', '그래', '맞아', '맞아요', '좋아', '좋아요',
        '글쎄', 'ok', 'okay', '음', '아', '오', '그래요', '그러니까',
        '그렇구나', '알겠어', '알겠습니다', 'yes', 'yeah', 'sure',
        'right', 'thank you', 'thanks',
      ];
      bool isFiller(String s) {
        final t = s.replaceAll(RegExp(r'[\s\.,!?~…]'), '').toLowerCase();
        if (t.length < 6) return true;
        return fillerPatterns.contains(t);
      }
```

**교체:**
```dart
      const fillerPatterns = [
        '네', '응', '어', '그래', '맞아', '맞아요', '좋아', '좋아요',
        '글쎄', 'ok', 'okay', '음', '아', '오', '그래요', '그러니까',
        '그렇구나', '알겠어', '알겠습니다', 'yes', 'yeah', 'sure',
        'right', 'thank you', 'thanks',
      ];
      // 🧹 과거 불만/메타 발화 제외 — 시드 주제로 부적합 (t는 공백 제거됨 → 패턴도 공백 없음)
      const complaintPatterns = [
        '질문', '물어봐', '물어본', '다시말', '이상한', '이상해', '이상하',
        '별로', '뭐야', '바꿔', '그런거말고', '딴거', '다른거', '다른걸',
        '마음에안', '맘에안', 'question', 'askme', 'weird',
      ];
      bool isFiller(String s) {
        final t = s.replaceAll(RegExp(r'[\s\.,!?~…]'), '').toLowerCase();
        if (t.length < 6) return true;
        if (fillerPatterns.contains(t)) return true;
        for (final p in complaintPatterns) {
          if (t.contains(p)) return true;
        }
        return false;
      }
```

## [L-12] 수정④a — FAST 레인 패턴 보강 (약 136~145줄)

**찾기 (anchor):**
```dart
      '그건 좀 아닌', '그건 별로', '그건 싫어', '그런 거 말고',
      '질문 바꿔', '바꿔줘', '다른 걸로',
```

**교체:**
```dart
      '그건 좀 아닌', '그건 별로', '그건 싫어', '그런 거 말고',
      '질문 바꿔', '바꿔줘', '다른 걸로',
      '마음에 안 드', '맘에 안 드', '같은 질문',
```

---

## 검증

```bash
cd F:\flutter_project\stealth_vox
F=lib/custom_code/widgets/routine_mode_step_expand.dart
grep -c "unawaited(_cacheFullSentenceInBackground" $F   # 기대값: 1
grep -c "_cacheFullSentenceInBackground" $F             # 기대값: 3 (호출1 + 주석1 + 정의1)
grep -c "rejectedQuestion" $F                           # 기대값: 6
grep -c "_fclRejected" $F                               # 기대값: 2
grep -c "dissRejected" $F                               # 기대값: 2
grep -c "BANNED QUESTION" $F                            # 기대값: 1
grep -c "complaintPatterns" $F                          # 기대값: 4 (정의2 + 루프2)
grep -c "같은 질문" $F                                   # 기대값: 1
grep -c "_swTTS..reset()..start();" $F                  # 기대값: 1

flutter analyze lib/custom_code/widgets/routine_mode_step_expand.dart
```
- 에러 0건이어야 함. 기대값 불일치 시 해당 편집 누락/중복을 sed -n 으로 직접 확인.

**실기기 테스트 체크리스트 (우선순위 순):**
1. [수정①] 첫 턴 발화 후 유저 TTS → AI 응답까지 무음 구간이 짧아졌는지. 로그에서 `[HYB-ERR] TtsCache 저장 실패`가 떠도 **PIPE-02가 그보다 먼저** 찍히는지 확인 (기존: HYB-ERR 이후에 PIPE-02)
2. [수정②] AI 질문에 "질문이 뭐 이래"라고 항의 → 교체 질문이 **다른 주제/각도**인지. 로그에 `[HYB-03-HIT]`(동일 질문 캐시 적중)가 교체 직후 뜨면 실패
3. [수정②] 같은 턴에서 2회 연속 항의 → 두 번 모두 서로 다른 질문이 나오는지
4. [수정③] 과거 항의 발화가 많은 계정으로 세션 시작 → `[SEED-FT] picked=...` 로그에 "질문/이상한/다시 물어봐" 류 발화가 안 뽑히는지
5. [수정④a] "질문이 마음에 안 드는데" → `[FAST-DISSATISFIED]` 로그로 즉시 반응하는지 (기존: GPT 레인 ~5초)
6. [수정④b] 불만 교체 시 `[HYB-01] 발사` ms가 정상 범위(수백 ms 이내)로 찍히는지
7. [회귀] 정상 5턴 완주 → 확장문장 → polish 저장까지 기존과 동일하게 동작하는지. 히스토리 재방문 시 TTS 캐시 HIT도 확인 (백그라운드 저장이 여전히 완료되는지)

## 롤백

```bash
git restore lib/custom_code/widgets/routine_mode_step_expand.dart
# 또는 커밋했다면
git revert <hash>
```