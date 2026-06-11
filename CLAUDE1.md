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

# [지시문] Free Talk 3종 개선 + TTS 타임아웃 사다리 (4개 모드)

## 0. 배경 및 목적

이전 패치(5초 타임아웃 + 3회 시도)는 정상 작동 확인됨 — 로그에서 `[TTS-RETRY]` 4건 모두
재시도 1회 만에 1.3~1.7초로 성공. 남은 공백의 정체는 "5초 타임아웃 대기" 그 자체이므로
타임아웃 사다리(3→5→8초)로 1차 재시도를 앞당긴다. 추가로 Free Talk 전용 개선 2건.

| Fix | 내용 | 대상 파일 |
|-----|------|----------|
| 1 | TTS 타임아웃 사다리 [3,5,8]초 + 타임아웃 시 즉시 재시도 | 4개 모드 전부 |
| 2 | [DISSATISFIED] 감지 신호에 질문-반복 요청 패턴 추가 (프롬프트만) | free_talk |
| 3 | 레벨 지침 구체화 (CEFR + 문장 길이/문법/숙어 수치 제약) | free_talk |

**절대 건드리지 말 것:**
- `_pushReady()` 순서 보장, `_pendingCount` 증감, `_buffer[id] = result;` 이하 라인
- DISSATISFIED **처리 로직**(약 1236줄~) — 이미 정상, 감지 프롬프트만 수정
- `kFreeTalkOpenAiTtsHttpTimeoutSeconds = 18` (HYB 캐시 저장용 — 별개, 유지)
- Deepgram utterance_end_ms (1000ms 미만 금지), PIPE 게이트류
- Brain 내부의 다른 `attempt` 루프 (GPT 호출용 — 수정 금지)
- 프롬프트 내 URL은 순수 텍스트 유지. PowerShell 파일 쓰기 시 `[IO.File]::WriteAllText` + UTF-8 명시.

⚠️ 모든 편집은 `lib/custom_code/widgets/` 대상. `lib/custom_code/임시/` 금지.
⚠️ 줄번호는 참고용, 실제 편집은 str_replace 앵커 텍스트 기준.

---

## 1. 사전 작업: git 세이브 포인트

```bash
cd F:\flutter_project\stealth_vox
git add -A
git commit -m "save point: before TTS ladder + freetalk dissatisfied/level fix"
```

---

## 2. 사전 검증 (하나라도 불일치 시 중단·보고)

```bash
# (a) free_talk — 상수형 블록인지 확인. 기대값 2 (정의+사용처)
grep -c "kFreeTalkChunkTtsHttpTimeoutSeconds" lib/custom_code/widgets/routine_mode_free_talk.dart

# (b) free_talk — DISSATISFIED Signs 줄. 기대값 1
grep -c "무슨 대답이 그래" lib/custom_code/widgets/routine_mode_free_talk.dart

# (c) free_talk — 레벨 함수. 기대값 1
grep -c "Use very simple, common words" lib/custom_code/widgets/routine_mode_free_talk.dart

# (d) step_expand / roleplay / clone — 기존 패치 블록. 각각 기대값 1
grep -c "5초 타임아웃, 최대 3회 시도" lib/custom_code/widgets/routine_mode_step_expand.dart
grep -c "5초 타임아웃, 최대 3회 시도" lib/custom_code/widgets/routine_mode_roleplay.dart
grep -c "5초 타임아웃, 최대 3회 시도" lib/custom_code/widgets/routine_mode_clone.dart
```

⚠️ clone이 free_talk처럼 상수형으로 다르게 패치돼 있으면(기대값 0) 중단하고 실제 블록을 보고할 것.

---

## 3. 파일 1: routine_mode_free_talk.dart (편집 4곳, 아래→위 순서)

### [편집 1-1] 레벨 지침 구체화 — 약 3518~3528줄

삭제 시작: `  static String _freeTalkLevelInstruction(String level) {`
삭제 끝: 함수 닫는 `  }` (약 3528줄, `default:` return 직후)

**old_str:**
```dart
  static String _freeTalkLevelInstruction(String level) {
    switch (level) {
      case "Beginner":
        return "Use very simple, common words and short sentences. Avoid idioms and difficult grammar.";
      case "Advanced":
        return "Use rich, natural vocabulary including idioms and nuanced expressions, as with a fluent speaker.";
      case "Intermediate":
      default:
        return "Use everyday vocabulary with some variety. Common phrasal verbs and natural expressions are fine.";
    }
  }
```

**new_str:**
```dart
  static String _freeTalkLevelInstruction(String level) {
    switch (level) {
      case "Beginner":
        return "BEGINNER (CEFR A1-A2). Use only the most common everyday words. "
            "Keep every sentence to 8 words or fewer. "
            "Use only simple present and simple past tense. "
            "No idioms, no phrasal verbs, no slang. "
            "Speak as if talking to a young child learning the language.";
      case "Advanced":
        return "ADVANCED (CEFR C1-C2). Speak exactly like an educated native adult. "
            "Freely use idioms, phrasal verbs, colloquial slang, and witty or nuanced expressions. "
            "Use varied grammar such as conditionals, relative clauses, and perfect tenses. "
            "Do not simplify anything.";
      case "Intermediate":
      default:
        return "INTERMEDIATE (CEFR B1-B2). Use everyday vocabulary with some variety. "
            "Keep sentences to about 14 words or fewer. "
            "Common phrasal verbs and natural expressions are fine, "
            "but avoid rare idioms and slang.";
    }
  }
```

### [편집 1-2] DISSATISFIED 감지 신호 확장 — 약 3363~3366줄

**old_str:**
```dart
[CASE DISSATISFIED] — Check this THIRD, only when the history contains at least one "AI:" line.
The user is complaining about the AI's LAST reply itself and wants a different one.
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해줘" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)''';
```

**new_str:**
```dart
[CASE DISSATISFIED] — Check this THIRD, only when the history contains at least one "AI:" line.
The user is complaining about the AI's LAST reply itself and wants a different one,
OR the user did not catch / did not like the AI's last QUESTION and asks for it to be repeated, rephrased, or replaced.
Signs: "무슨 대답이 그래" / "무슨 질문이 그래" / "대답이 이상해" / "다른 말 해줘" / "다시 대답해 봐" / "그 대답 별로야" / "say something else" / "that's a weird reply" / "answer again"
More signs (question complaints): "뭐라고 물었어" / "뭐라고 물은 거야" / "다시 물어봐" / "제대로 다시 물어봐" / "질문 다시 해줘" / "다른 질문 해줘" / "what did you ask" / "ask me again" / "ask a different question"
If so, output EXACTLY: [DISSATISFIED]  (and nothing else)''';
```

### [편집 1-3] 재시도 딜레이 조건 — 약 2866~2872줄 (catch 블록)

타임아웃 예외는 이미 3초를 기다린 상태이므로 0.3초 추가 대기 없이 즉시 재발사.

**old_str:**
```dart
        } catch (e) {
          onLog?.call('⚠️ [TTS-RETRY]',
              'attempt=${attempt + 1}/3 실패 (${e.runtimeType}) for "$text"');
          if (attempt < 2) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
```

**new_str:**
```dart
        } catch (e) {
          onLog?.call('⚠️ [TTS-RETRY]',
              'attempt=${attempt + 1}/3 실패 (${e.runtimeType}) for "$text"');
          if (attempt < 2 && e is! TimeoutException) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
```

### [편집 1-4] 타임아웃 상수 사용처 — 약 2851~2852줄

**old_str:**
```dart
              .timeout(
                  const Duration(seconds: kFreeTalkChunkTtsHttpTimeoutSeconds));
```

**new_str:**
```dart
              .timeout(Duration(
                  seconds: kFreeTalkChunkTtsTimeoutLadderSec[attempt]));
```

### [편집 1-5] 타임아웃 상수 정의 — 약 51줄 (파일 상단, 마지막에 편집)

**old_str:**
```dart
const int kFreeTalkChunkTtsHttpTimeoutSeconds = 5; // Chunk TTS retry timeout.
```

**new_str:**
```dart
const List<int> kFreeTalkChunkTtsTimeoutLadderSec = [
  3,
  5,
  8
]; // Chunk TTS per-attempt timeout ladder.
```

### 파일 1 검증

```bash
grep -c "kFreeTalkChunkTtsTimeoutLadderSec" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값 2
grep -c "kFreeTalkChunkTtsHttpTimeoutSeconds" lib/custom_code/widgets/routine_mode_free_talk.dart  # 기대값 0
grep -c "e is! TimeoutException" lib/custom_code/widgets/routine_mode_free_talk.dart               # 기대값 1
grep -c "CEFR" lib/custom_code/widgets/routine_mode_free_talk.dart                                 # 기대값 3
grep -c "뭐라고 물은 거야" lib/custom_code/widgets/routine_mode_free_talk.dart                      # 기대값 1
```

---

## 4. 파일 2~4: step_expand / roleplay / clone (파일당 편집 1곳)

세 파일 모두 동일한 블록 교체. 적용 순서: step_expand → roleplay → clone.
(step_expand 약 4370~4410줄 / roleplay 약 3157~3197줄 / clone은 grep으로 위치 확인)

### 삭제할 코드 (old_str)

시작: `    // [2단계] API 호출 (5초 타임아웃, 최대 3회 시도) — TTS 지연 스파이크 대응`
끝: for 루프 닫는 `    }` (catch 닫힘 직후, `if (result.isEmpty)` 직전)

```dart
    // [2단계] API 호출 (5초 타임아웃, 최대 3회 시도) — TTS 지연 스파이크 대응
    Uint8List result = Uint8List(0);
    for (int attempt = 0; attempt < 3; attempt++) {
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
            .timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          result = res.bodyBytes;
          final turnTag = isUser ? 'USER' : 'AI';
          onLog?.call('🔊 [TTS-02]',
              '[$turnTag] API OK (${result.length}B) for "$text"');
          // [3단계] 캐시 저장 (백그라운드)
          TtsCache.put(text, voice, result);
          break;
        } else {
          onLog?.call('❌ [TTS-API-ERR]',
              'statusCode=${res.statusCode} (attempt=${attempt + 1}/3)');
        }
      } catch (e) {
        onLog?.call('⚠️ [TTS-RETRY]',
            'attempt=${attempt + 1}/3 실패 (${e.runtimeType}) for "$text"');
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
```

### 교체할 코드 (new_str)

```dart
    // [2단계] API 호출 (타임아웃 사다리 3/5/8초, 최대 3회 시도) — TTS 지연 스파이크 대응
    Uint8List result = Uint8List(0);
    const List<int> timeoutLadderSec = [3, 5, 8];
    for (int attempt = 0; attempt < 3; attempt++) {
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
            .timeout(Duration(seconds: timeoutLadderSec[attempt]));

        if (res.statusCode == 200) {
          result = res.bodyBytes;
          final turnTag = isUser ? 'USER' : 'AI';
          onLog?.call('🔊 [TTS-02]',
              '[$turnTag] API OK (${result.length}B) for "$text"');
          // [3단계] 캐시 저장 (백그라운드)
          TtsCache.put(text, voice, result);
          break;
        } else {
          onLog?.call('❌ [TTS-API-ERR]',
              'statusCode=${res.statusCode} (attempt=${attempt + 1}/3)');
        }
      } catch (e) {
        onLog?.call('⚠️ [TTS-RETRY]',
            'attempt=${attempt + 1}/3 실패 (${e.runtimeType}) for "$text"');
        if (attempt < 2 && e is! TimeoutException) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
```

**주의:** old_str/new_str 직후의 `if (result.isEmpty)` 블록과 `_buffer[id] = result;` 이하는 편집 범위에 포함하지 말 것.
`TimeoutException`은 `dart:async` 소속 — 3개 파일 모두 23줄에 이미 import 확인됨, 추가 import 불필요.

### 파일별 검증 (파일명 바꿔 3회)

```bash
grep -c "timeoutLadderSec" lib/custom_code/widgets/routine_mode_step_expand.dart        # 기대값 2
grep -c "5초 타임아웃, 최대 3회 시도" lib/custom_code/widgets/routine_mode_step_expand.dart  # 기대값 0
grep -c "e is! TimeoutException" lib/custom_code/widgets/routine_mode_step_expand.dart   # 기대값 1
```

---

## 5. 전체 검증

```bash
flutter analyze
```

에러 0건이어야 함. 에러 발생 시 즉시 중단·전문 보고.

---

## 6. 실기기 테스트 포인트

**Fix 1 (공백 단축):**
1. `[TTS-RETRY]` 발생 시 addText → API OK 간격이 5초 이내인지 (기존 6.5초+ → 약 4.5초 목표).
2. 1차 타임아웃이 3초로 짧아져 `[TTS-RETRY]` 빈도 자체는 다소 늘 수 있음 — 정상. 중요한 건 공백 길이.
3. `[TTS-FAIL]`(3회 전멸)이 나오지 않는지.

**Fix 2 (재질문):**
4. 대화 중 "뭐라고 물은 거야? 다시 물어봐"라고 말하기 → 직전 AI 버블 삭제 + "그럼 다시 답해 볼게요" + 새 응답이 나오는지 (`🟣 [DISSATISFIED]` 로그 확인).
5. 정상 대화("아니 근데 어제는...")가 오탐으로 DISSATISFIED 처리되지 않는지 2~3턴 확인.

**Fix 3 (레벨):**
6. Beginner로 3턴 → AI 문장이 8단어 이하, 단순 시제인지.
7. Advanced로 3턴 → 숙어/구동사가 실제로 섞이는지. Intermediate와 귀로 구분되는지.

---

## 7. 롤백 절차

```bash
# 커밋 전:
git restore lib/custom_code/widgets/routine_mode_free_talk.dart
git restore lib/custom_code/widgets/routine_mode_step_expand.dart
git restore lib/custom_code/widgets/routine_mode_roleplay.dart
git restore lib/custom_code/widgets/routine_mode_clone.dart

# 커밋 후:
git revert <패치 커밋 해시>
```