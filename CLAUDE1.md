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

# StealthVox — Free Talk 통신로직 수정 지시문 (C+B)

## 목적
유저 TTS가 첫 3~5단어 재생 후 긴 침묵이 생기고, 일부 턴에서 "유저 앞부분 → AI → 못한 유저 뒷부분" 순서로 꼬이는 문제 해결.

근본 원인 두 가지를 제거한다.
- **원인 C**: `HybridTtsPlayer.onStreamEnd`가 통문장 TtsCache 저장(http.post, 최대 15초)을 `await`로 동기 차단 → 파이프라인(PIPE-08~09, 다음 턴 마이크 재시작)이 멈춤.
- **원인 B**: `ChunkedTtsFetcher._fetch` 첫 줄 `await TtsCache.get`이 락·타임아웃 없는 디스크 I/O에서 hang하면 `_pendingCount`가 감소하지 않음 → PIPE-04 게이트가 10초 타임아웃까지 막혔다가 강제 진행 → 늦게 도착한 유저 조각이 큐에 섞임.

## 대상 파일 (정확히 이 경로만)
```
lib/custom_code/widgets/routine_mode_free_talk.dart
```
**`lib/custom_code/임시/` 아래 파일은 절대 건드리지 말 것.**

## 작업 전 필수
1. 작업 시작 전 `git commit -am "save point before FREETALK_TTS_CB_FIX_v1"` (세이브 포인트).
2. 아래 수정은 **반드시 아래(라인 큰 것)부터 위로** 적용한다 (라인 드리프트 방지).

## 절대 건드리지 말 것 (Do NOT touch)
- `DeepgramV2VoiceManager` 전체 — 마이크/웹소켓/턴종료(utterance_end_ms 등) 로직.
- `TtsQueueManager` 전체 — 재생 큐/우선순위/`setAiPaused` 로직.
- `_processRelayPipeline`의 PIPE 게이트 흐름(PIPE-04~09) — 이번 작업 대상 아님.
- `FreeTalkBrain` / `streamUserTranslation` / `generateCleanOriginal` 등 프롬프트·번역 로직.
- 아래 3개 외 다른 메서드/클래스.

---

## 수정 ① — HybridTtsPlayer.onStreamEnd (통문장 저장 백그라운드 분리)

### 삭제 범위
- **시작**: `Future<void> onStreamEnd({String fullSentence = ''}) async {` (약 2830번 줄)
- **끝**: 이 메서드를 닫는 `}` — 바로 위 줄이 `      onLog?.call('[HYB-ERR]', 'TtsCache 저장 실패: $e');` 이고 그 아래 `    }` 와 메서드 닫는 `  }` (약 2884번 줄)

즉 `onStreamEnd` 메서드 **전체**를 아래 블록으로 교체한다. (메서드 하나가 둘로 늘어남: `onStreamEnd` + 신규 `_cacheFullSentenceInBackground`)

### str_replace

**old_str** (현재 코드 — `onStreamEnd` 전체):
```dart
  Future<void> onStreamEnd({String fullSentence = ''}) async {
    final remainder = _chunkBuffer.toString().trim();
    if (!_firstChunkFired && remainder.isNotEmpty) {
      // 구두점/4단어 없이 스트림 종료 — 전체 발사
      _fetcher.addText(remainder);
      _firstChunkFired = true;
      onLog?.call(
          '[HYB-01-LATE]', 'no punct/4words — full text fired at stream end');
    } else if (_firstChunkFired && remainder.isNotEmpty) {
      int lastIdx = 0;
      for (final match in kTtsDelimiterPattern.allMatches(remainder)) {
        final seg = remainder.substring(lastIdx, match.end).trim();
        if (seg.isNotEmpty) _fetcher.addText(seg);
        lastIdx = match.end;
      }
      final tail = remainder.substring(lastIdx).trim();
      if (tail.isNotEmpty) _fetcher.addText(tail);
      onLog?.call('[HYB-02]', 'remainder fired (${remainder.length}c)');
    }

    // TtsCache 통문장 백그라운드 저장 (재생 없음)
    final sentence = fullSentence.trim();
    if (sentence.isEmpty) return;
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
          .timeout(const Duration(seconds: 15));
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
```

**new_str** (교체 코드):
```dart
  Future<void> onStreamEnd({String fullSentence = ''}) async {
    final remainder = _chunkBuffer.toString().trim();
    if (!_firstChunkFired && remainder.isNotEmpty) {
      // 구두점/4단어 없이 스트림 종료 — 전체 발사
      _fetcher.addText(remainder);
      _firstChunkFired = true;
      onLog?.call(
          '[HYB-01-LATE]', 'no punct/4words — full text fired at stream end');
    } else if (_firstChunkFired && remainder.isNotEmpty) {
      int lastIdx = 0;
      for (final match in kTtsDelimiterPattern.allMatches(remainder)) {
        final seg = remainder.substring(lastIdx, match.end).trim();
        if (seg.isNotEmpty) _fetcher.addText(seg);
        lastIdx = match.end;
      }
      final tail = remainder.substring(lastIdx).trim();
      if (tail.isNotEmpty) _fetcher.addText(tail);
      onLog?.call('[HYB-02]', 'remainder fired (${remainder.length}c)');
    }

    // 🔧 [C 수정] 통문장 TtsCache 저장을 백그라운드로 분리 — 파이프라인을 막지 않음.
    // 이전 통신 로직의 "캐시 저장은 fire-and-forget" 원칙으로 회귀.
    final sentence = fullSentence.trim();
    if (sentence.isNotEmpty) {
      unawaited(_cacheFullSentenceInBackground(sentence));
    }
  }

  // 🔧 [C 수정] 통문장 캐시 저장 — onStreamEnd에서 await 분리 (fire-and-forget).
  // 여기서 http.post가 최대 15초 걸려도 호출 측 파이프라인은 영향받지 않음.
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
          .timeout(const Duration(seconds: 15));
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
```

> **참고**: 호출부 `await _hybridTtsPlayer!.onStreamEnd(...)` (약 1281번 줄)는 **수정하지 않는다.** onStreamEnd가 이제 remainder 발사 직후 즉시 리턴하므로 그대로 두면 된다.

---

## 수정 ② — ChunkedTtsFetcher._fetch (try/finally로 pending 감소 보장)

### 삭제 범위
- **시작**: `  Future<void> _fetch(int id, String text) async {` (약 2556번 줄)
- **끝**: 이 메서드를 닫는 `  }` — 바로 위 줄이 `    if (_pendingCount == 0) onAllComplete?.call();` (약 2610번 줄)

`_fetch` 메서드 **전체**를 교체한다.

### str_replace

**old_str** (현재 코드 — `_fetch` 전체):
```dart
  Future<void> _fetch(int id, String text) async {
    // [1단계] 로컬 캐시 확인 (히트 시 즉시 반환)
    final cached = await TtsCache.get(text, voice);
    if (cached != null && cached.isNotEmpty) {
      _buffer[id] = cached;
      _pendingCount--;
      _pushReady();
      if (_pendingCount == 0) onAllComplete?.call();
      return;
    }

    // [2단계] API 호출 (재시도 1회)
    Uint8List result = Uint8List(0);
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
                'input': text,
                'voice': voice,
                'speed': 1.0,
                'response_format': 'mp3',
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          result = res.bodyBytes;
          final turnTag = isUser ? 'USER' : 'AI';
          onLog?.call('🔊 [TTS-02]',
              '[$turnTag] API OK (${result.length}B) for "$text"');
          // [3단계] 캐시 저장 (백그라운드)
          TtsCache.put(text, voice, result);
          break;
        } else {
          onLog?.call('❌ [TTS-API-ERR]', 'statusCode=${res.statusCode}');
        }
      } catch (_) {
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }

    _buffer[id] = result;
    _pendingCount--;
    _pushReady();
    if (_pendingCount == 0) onAllComplete?.call();
  }
```

**new_str** (교체 코드):
```dart
  Future<void> _fetch(int id, String text) async {
    // 🔧 [B 수정] 모든 경로(캐시 히트 / API 성공·실패 / 예외)에서
    // _pendingCount가 정확히 1회 감소하도록 try/finally로 보장.
    // → TtsCache.get/put이 hang해도 PIPE-04 게이트가 영구히 막히지 않음.
    Uint8List result = Uint8List(0);
    try {
      // [1단계] 로컬 캐시 확인 (히트 시 result에 담고 finally에서 큐 적재)
      final cached = await TtsCache.get(text, voice);
      if (cached != null && cached.isNotEmpty) {
        result = cached;
        return; // finally에서 _buffer 적재 + pending 감소
      }

      // [2단계] API 호출 (재시도 1회)
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
                  'input': text,
                  'voice': voice,
                  'speed': 1.0,
                  'response_format': 'mp3',
                }),
              )
              .timeout(const Duration(seconds: 10));

          if (res.statusCode == 200) {
            result = res.bodyBytes;
            final turnTag = isUser ? 'USER' : 'AI';
            onLog?.call('🔊 [TTS-02]',
                '[$turnTag] API OK (${result.length}B) for "$text"');
            // [3단계] 캐시 저장 (백그라운드 — await 안 함)
            unawaited(TtsCache.put(text, voice, result));
            break;
          } else {
            onLog?.call('❌ [TTS-API-ERR]', 'statusCode=${res.statusCode}');
          }
        } catch (_) {
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
    } catch (_) {
      // 예외가 나도 finally에서 pending 정리 — 게이트 영구 막힘 방지
    } finally {
      _buffer[id] = result;
      _pendingCount--;
      _pushReady();
      if (_pendingCount == 0) onAllComplete?.call();
    }
  }
```

---

## 수정 ③ — TtsCache.get / put (디스크 I/O 2초 타임아웃)

### 삭제 범위
- **시작**: `  static Future<Uint8List?> get(String text, String voice) async {` (약 2353번 줄)
- **끝**: `put` 메서드를 닫는 `  }` — 바로 위 줄이 `      await File(path).writeAsBytes(data);` 와 `    } catch (_) {}` (약 2369번 줄)

`get`과 `put` **두 메서드를 함께** 아래 블록으로 교체한다 (내부 메서드 2개 추가됨).

### str_replace

**old_str** (현재 코드 — `get` + `put`):
```dart
  static Future<Uint8List?> get(String text, String voice) async {
    try {
      final path = '${await _getDir()}/${_key(text, voice)}.mp3';
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  static Future<void> put(String text, String voice, Uint8List data) async {
    try {
      final path = '${await _getDir()}/${_key(text, voice)}.mp3';
      await File(path).writeAsBytes(data);
    } catch (_) {}
  }
```

**new_str** (교체 코드):
```dart
  // 🔧 [B 수정] 디스크 I/O 경합으로 hang하는 것을 막기 위해 2초 타임아웃.
  // 타임아웃/예외 시 캐시 미스로 처리(null) — 호출 측은 API 경로로 진행.
  static Future<Uint8List?> get(String text, String voice) async {
    try {
      return await _getInternal(text, voice)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _getInternal(String text, String voice) async {
    final path = '${await _getDir()}/${_key(text, voice)}.mp3';
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  // 🔧 [B 수정] 저장도 2초 타임아웃 — 실패해도 조용히 무시(캐시는 best-effort).
  static Future<void> put(String text, String voice, Uint8List data) async {
    try {
      await _putInternal(text, voice, data)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  static Future<void> _putInternal(
      String text, String voice, Uint8List data) async {
    final path = '${await _getDir()}/${_key(text, voice)}.mp3';
    await File(path).writeAsBytes(data);
  }
```

---

## 검증 (수정 후 순서대로 실행)

### 1) grep 카운트 확인
```powershell
# 신규 백그라운드 캐시 메서드: 정의 1 + 호출 1 = 2
grep -c "_cacheFullSentenceInBackground" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 2

# _fetch 안 캐시 저장이 unawaited로 바뀜 = 1
grep -c "unawaited(TtsCache.put" lib/custom_code/widgets/routine_mode_free_talk.dart            # 기대값: 1

# TtsCache 내부 메서드: 각 정의 1 + 호출 1 = 2
grep -c "_getInternal" lib/custom_code/widgets/routine_mode_free_talk.dart                      # 기대값: 2
grep -c "_putInternal" lib/custom_code/widgets/routine_mode_free_talk.dart                      # 기대값: 2

# _fetch가 finally로 pending 정리 (주석 앵커)
grep -c "게이트 영구 막힘 방지" lib/custom_code/widgets/routine_mode_free_talk.dart             # 기대값: 1

# onStreamEnd가 더 이상 통문장을 직접 await로 저장하지 않음 (HYB-04-SAVED는 백그라운드 메서드로 1회만 이동)
grep -c "HYB-04-SAVED" lib/custom_code/widgets/routine_mode_free_talk.dart                      # 기대값: 1
```

### 2) flutter analyze
```powershell
flutter analyze lib/custom_code/widgets/routine_mode_free_talk.dart
```
- **수정 전 대비 신규 error 0건**이어야 한다.
- `unawaited` 미정의 에러가 나면 `import 'dart:async';` 존재 여부 확인(이미 있어야 함, 약 23번 줄).

---

## 롤백 절차
- 로컬 결과가 마음에 안 들면: `git restore lib/custom_code/widgets/routine_mode_free_talk.dart`
- 이미 push했다면: `git revert <commit-hash>`

---

## 실기기 확인 포인트 (수정 후)
1. 유저 발화 후 첫 조각 → 다음 조각 사이 침묵이 줄었는지.
2. `⚠️ [PIPE-TIMEOUT] 유저 TTS fetch 10초 초과` 로그가 사라졌는지 (정상이면 안 찍혀야 함).
3. "유저 앞부분 → AI → 못한 유저 뒷부분" 순서 꼬임이 사라졌는지.
4. `[HYB-ERR] TtsCache 저장 실패: TimeoutException` 이 떠도 대화 흐름(다음 턴 마이크 재시작)은 막히지 않는지.