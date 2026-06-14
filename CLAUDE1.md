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

# 🔧 TTS 엣지케이스 3건 통합 수정

## 개요
| # | 문제 | 수정 위치 | 영향 |
|---|------|----------|------|
| 1 | `"!"` 단독 구두점 → TTS 타임아웃 | ChunkedTtsFetcher.addText | 모든 모드 |
| 2 | 긴 문장 TTS 3회 실패 → 유저 음성 스킵 | ChunkedTtsFetcher._fetch 타임아웃 사다리 | step_expand, roleplay |
| 3 | TtsCache 백그라운드 저장 타임아웃 | HybridTtsPlayer._cacheFullSentenceInBackground | 모든 모드 |

## 대상 파일 (Box 7 엔진은 모드별 독립)
- `lib/custom_code/widgets/routine_mode_free_talk.dart`
- `lib/custom_code/widgets/routine_mode_step_expand.dart`
- `lib/custom_code/widgets/routine_mode_roleplay.dart`

---

## 사전 준비

```bash
git add -A && git commit -m "save: before TTS edge case fixes"
```

---

# Fix 1: 단독 구두점 가드 (ChunkedTtsFetcher.addText)

> `"!"`, `","` 같은 단어 없는 순수 구두점 → TTS API가 불안정하므로 스킵

### 3개 파일 모두 동일 패턴 적용

**step_expand + roleplay** (동일 구조):

```
<<<<<<< OLD
  void addText(String text) {
    if (text.trim().isEmpty) return;
    _pendingCount++;
=======
  void addText(String text) {
    if (text.trim().isEmpty) return;
    // 🔧 단독 구두점 가드: 알파벳/숫자/한글 없이 구두점만 → TTS 스킵
    if (!RegExp(r'[a-zA-Z0-9가-힣]').hasMatch(text)) {
      onLog?.call('🔊 [TTS-SKIP]', 'punctuation-only skipped: "$text"');
      return;
    }
    _pendingCount++;
>>>>>>> NEW
```

**free_talk** (_cancelled 가드가 있는 버전):

```
<<<<<<< OLD
  void addText(String text) {
    if (text.trim().isEmpty) return;
    if (_cancelled) {
=======
  void addText(String text) {
    if (text.trim().isEmpty) return;
    // 🔧 단독 구두점 가드: 알파벳/숫자/한글 없이 구두점만 → TTS 스킵
    if (!RegExp(r'[a-zA-Z0-9가-힣]').hasMatch(text)) {
      onLog?.call('🔊 [TTS-SKIP]', 'punctuation-only skipped: "$text"');
      return;
    }
    if (_cancelled) {
>>>>>>> NEW
```

### 검증

```bash
grep -c "TTS-SKIP" lib/custom_code/widgets/routine_mode_free_talk.dart
# 예상: 1
grep -c "TTS-SKIP" lib/custom_code/widgets/routine_mode_step_expand.dart
# 예상: 1
grep -c "TTS-SKIP" lib/custom_code/widgets/routine_mode_roleplay.dart
# 예상: 1
```

---

# Fix 2: 타임아웃 사다리 확대 (ChunkedTtsFetcher._fetch)

> 긴 문장 TTS가 3초 안에 못 오면 3회 모두 실패 → `[3,5,8]` → `[5,8,12]`로 완화

### step_expand + roleplay (동일 구조)

```
<<<<<<< OLD
    const List<int> timeoutLadderSec = [3, 5, 8];
=======
    const List<int> timeoutLadderSec = [5, 8, 12];
>>>>>>> NEW
```

> **free_talk는 수정 불필요** — 별도 상수 `kFreeTalkChunkTtsTimeoutLadderSec`를 사용하며
> 이미 적절한 값으로 설정되어 있음.

### 검증

```bash
grep "timeoutLadderSec = \[5, 8, 12\]" lib/custom_code/widgets/routine_mode_step_expand.dart
# 예상: 1줄
grep "timeoutLadderSec = \[5, 8, 12\]" lib/custom_code/widgets/routine_mode_roleplay.dart
# 예상: 1줄
```

---

# Fix 3: TtsCache 백그라운드 저장 타임아웃 완화

> `_cacheFullSentenceInBackground`에서 15초 타임아웃 → 25초 + 1회 재시도

### step_expand + roleplay (동일 구조)

```
<<<<<<< OLD
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
=======
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
      // 🔧 25초 타임아웃 + 1회 재시도 (긴 문장 캐시 저장 실패 방지)
      Uint8List? bytes;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
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
              .timeout(const Duration(seconds: 25));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            bytes = res.bodyBytes;
            break;
          }
        } catch (e) {
          if (attempt == 0) {
            onLog?.call('[HYB-CACHE-RETRY]', '캐시 저장 재시도 (${e.runtimeType})');
          }
        }
      }
      if (bytes != null) {
        await TtsCache.put(fullSentence, voice, bytes);
        lastCacheSaveMs = sw.elapsedMilliseconds;
        onLog?.call('[HYB-04-SAVED]',
            '${lastCacheSaveMs}ms (${bytes.length}B)');
      } else {
        onLog?.call('[HYB-ERR]', 'TtsCache 저장 2회 실패 — 스킵');
      }
      sw.stop();
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');
    }
  }
>>>>>>> NEW
```

### free_talk (구조 약간 다름 — _voice, _apiKey 사용)

```
<<<<<<< OLD
  Future<void> _cacheFullSentenceInBackground(String sentence) async {
    try {
      final cached = await TtsCache.get(sentence, _voice);
      if (cached != null && cached.isNotEmpty) {
        onLog?.call('[HYB-03-HIT]', 'TtsCache HIT — 저장 생략');
        return;
      }
      final res = await http
          .post(
            Uri.parse('https://api.openai.com/v1/audio/speech'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'tts-1',
              'input': sentence,
              'voice': _voice,
              'speed': 1.0,
              'response_format': 'mp3',
            }),
          )
          .timeout(
              const Duration(seconds: kFreeTalkOpenAiTtsHttpTimeoutSeconds));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await TtsCache.put(sentence, _voice, res.bodyBytes);
        onLog?.call('[HYB-04-SAVED]', '${res.bodyBytes.length}B');
      } else {
        onLog?.call('[HYB-ERR]', 'API status=${res.statusCode}');
      }
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');
    }
  }
=======
  Future<void> _cacheFullSentenceInBackground(String sentence) async {
    try {
      final cached = await TtsCache.get(sentence, _voice);
      if (cached != null && cached.isNotEmpty) {
        onLog?.call('[HYB-03-HIT]', 'TtsCache HIT — 저장 생략');
        return;
      }
      // 🔧 25초 타임아웃 + 1회 재시도 (긴 문장 캐시 저장 실패 방지)
      Uint8List? bytes;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await http
              .post(
                Uri.parse('https://api.openai.com/v1/audio/speech'),
                headers: {
                  'Authorization': 'Bearer $_apiKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'model': 'tts-1',
                  'input': sentence,
                  'voice': _voice,
                  'speed': 1.0,
                  'response_format': 'mp3',
                }),
              )
              .timeout(const Duration(seconds: 25));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            bytes = res.bodyBytes;
            break;
          }
        } catch (e) {
          if (attempt == 0) {
            onLog?.call('[HYB-CACHE-RETRY]', '캐시 저장 재시도 (${e.runtimeType})');
          }
        }
      }
      if (bytes != null) {
        await TtsCache.put(sentence, _voice, bytes);
        onLog?.call('[HYB-04-SAVED]', '${bytes.length}B');
      } else {
        onLog?.call('[HYB-ERR]', 'TtsCache 저장 2회 실패 — 스킵');
      }
    } catch (e) {
      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');
    }
  }
>>>>>>> NEW
```

---

## 검증

```bash
flutter analyze lib/custom_code/widgets/routine_mode_free_talk.dart
flutter analyze lib/custom_code/widgets/routine_mode_step_expand.dart
flutter analyze lib/custom_code/widgets/routine_mode_roleplay.dart
# 각각 에러 0 확인
```

---

## Git 저장

```bash
git add -A && git commit -m "fix: TTS edge cases — punct guard + timeout ladder + cache retry"
```

---

## 효과 요약

| Before | After |
|--------|-------|
| `"!"` TTS 호출 → 타임아웃 재시도 | 구두점만 → 즉시 스킵 (API 호출 0) |
| 긴 문장 3/5/8초 사다리 → 3회 실패 | 5/8/12초 사다리 → 여유 확보 |
| 캐시 저장 15초 1회 시도 → 실패 | 25초 2회 시도 → 성공률 대폭 향상 |