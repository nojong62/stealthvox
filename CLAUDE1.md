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

# StealthVox — Free Talk/Roleplay: 유저 TTS 통문장화 (조각 분할 제거)

## 목적
유저 영어 TTS가 2~3조각으로 분할되어 각각 별도 API 호출로 나가는 구조에서, **한 조각의 API stall(8~10초)이 유저 문장 중간 침묵**이 되고, stall이 게이트(15초)를 넘기면 **유저 소리가 마무리되지 않은 채 AI로 전환**된다.

유저 TTS를 **번역 스트림 종료 후 통문장 1회 발사**로 변경한다. Step Expand의 `HYB-01-LATE` 경로(실기기 검증 완료, 매끈함)와 동일 패턴이다.

- **AI TTS의 하이브리드(첫 청크 빠른 발사)는 변경하지 않는다** — AI는 첫 반응 속도가 중요.
- 텍스트 화면 표시는 기존대로 스트리밍 유지 (글자는 똑같이 흐름, 소리만 통문장).
- EVAPORATE/CORRECTION/CLARIFY 감지 로직은 그대로 유지.
- v3.7 유저 통문장 캐시(`_saveUserFullSentenceToCache`)와 키가 일치 → 반복 문장 캐시 HIT.
- 트레이드오프: 유저 첫 오디오 시작이 약 0.5~1.5초 늦어짐 (번역 스트림 완료 대기). 문장 중간 침묵 제거와 맞바꿈.

작업 전: `git commit -am "save point before USER_FULL_TTS"`

**`lib/custom_code/임시/` 아래 파일은 절대 건드리지 말 것.**
**각 파일 안에서는 반드시 아래(라인 큰 것)부터 위로 적용한다.**

---

# PART A — routine_mode_free_talk.dart

## A-1 — 잔여 발사를 통문장 1회 발사로 교체 (약 1201~1202번)

### old_str
```dart
      if (userBuffer.trim().isNotEmpty)
        userTtsFetcher.addText(userBuffer.trim());
```

### new_str
```dart
      // 🔧 [USER-FULL-TTS] 유저 통문장 1회 발사.
      // 조각 분할 시 한 조각의 API stall이 문장 중간 침묵/미완료 전환을
      // 유발하므로, Step Expand의 HYB-01-LATE 경로와 동일하게 통문장으로 보낸다.
      // v3.7 통문장 캐시와 키가 일치해 반복 문장은 캐시 HIT로 즉시 재생.
      final String fullUserTts = _cleanText(userTargetText.trim());
      if (fullUserTts.isNotEmpty) {
        userTtsFetcher.addText(fullUserTts);
      }
```

## A-2 — 루프 내 조각 발사 블록 제거 (약 1136~1159번)

### old_str
```dart
        // 구두점 도달 즉시 TTS 청크 발사
        final matches = splitPattern.allMatches(userBuffer).toList();
        if (matches.isNotEmpty) {
          int lastIdx = matches.last.end;
          String toSpeak = userBuffer.substring(0, lastIdx).trim();
          userBuffer = userBuffer.substring(lastIdx);
          if (toSpeak.isNotEmpty) {
            userTtsFetcher.addText(toSpeak);
            firstChunkSent = true;
          }
        }
        if (!firstChunkSent) {
          final wordCount = userBuffer
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
          if (wordCount >= 4) {
            userTtsFetcher.addText(_cleanText(userBuffer.trim()));
            userBuffer = "";
            firstChunkSent = true;
          }
        }
```

### new_str
```dart
        // 🔧 [USER-FULL-TTS] 유저 TTS 조각 발사 제거 — 스트림 종료 후 통문장 1회 발사.
        // (텍스트 화면 표시는 위 setState로 기존대로 스트리밍 유지)
```

## A-3 — 미사용 firstChunkSent 선언 제거 (약 1116번)

### old_str
```dart
      bool firstChunkSent = false;
```

### new_str
```dart
      // 🔧 [USER-FULL-TTS] firstChunkSent 제거 (조각 발사 폐지로 미사용)
```

> 참고: `splitPattern`(약 1100번)이 미사용이 되어 analyzer가 info/warning을 낼 수 있으나 error는 아니므로 그대로 둔다. 거슬리면 선언 줄만 추가로 삭제해도 된다(다른 곳에서 사용하지 않는 것 확인 후).

---

# PART B — routine_mode_roleplay.dart

## B-1 — 잔여 발사를 통문장 1회 발사로 교체 (약 1303~1310번)

### old_str
```dart
      if (userBuffer.trim().isNotEmpty) {
        final cleanedRem = _cleanText(userBuffer.trim());
        if (isMeaninglessTtsText(cleanedRem)) {
          _log('🔊 [TTS-SKIP] [USER]', '의미 없는 TTS 조각 skip: "$cleanedRem"');
        } else {
          userTtsFetcher.addText(cleanedRem);
        }
      }
```

### new_str
```dart
      // 🔧 [USER-FULL-TTS] 유저 통문장 1회 발사 (조각 stall로 인한
      // 문장 중간 침묵/미완료 전환 제거 — Step Expand HYB-01-LATE 패턴).
      final String fullUserTts = _cleanText(userTargetText.trim());
      if (fullUserTts.isNotEmpty) {
        if (isMeaninglessTtsText(fullUserTts)) {
          _log('🔊 [TTS-SKIP] [USER]', '의미 없는 TTS 조각 skip: "$fullUserTts"');
        } else {
          userTtsFetcher.addText(fullUserTts);
        }
      }
```

## B-2 — 루프 내 조각 발사 블록 제거 (약 1203~1235번)

### old_str
```dart
        // 구두점 도달 즉시 TTS 청크 발사
        final matches = splitPattern.allMatches(userBuffer).toList();
        if (matches.isNotEmpty) {
          int lastIdx = matches.last.end;
          String toSpeak = userBuffer.substring(0, lastIdx).trim();
          userBuffer = userBuffer.substring(lastIdx);
          if (toSpeak.isNotEmpty) {
            final cleanedChunk = _cleanText(toSpeak);
            if (isMeaninglessTtsText(cleanedChunk)) {
              _log('🔊 [TTS-SKIP] [USER]', '의미 없는 TTS 조각 skip: "$cleanedChunk"');
            } else {
              userTtsFetcher.addText(cleanedChunk);
              firstChunkSent = true;
            }
          }
        }
        if (!firstChunkSent) {
          final wordCount = userBuffer
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
          if (wordCount >= 4) {
            final cleanedBuf = _cleanText(userBuffer.trim());
            if (isMeaninglessTtsText(cleanedBuf)) {
              _log('🔊 [TTS-SKIP] [USER]', '의미 없는 TTS 조각 skip: "$cleanedBuf"');
            } else {
              userTtsFetcher.addText(cleanedBuf);
              firstChunkSent = true;
            }
            userBuffer = "";
          }
        }
```

### new_str
```dart
        // 🔧 [USER-FULL-TTS] 유저 TTS 조각 발사 제거 — 스트림 종료 후 통문장 1회 발사.
        // (텍스트 화면 표시는 위 setState로 기존대로 스트리밍 유지)
```

## B-3 — 미사용 firstChunkSent 선언 제거 (약 1176번)

### old_str
```dart
      bool firstChunkSent = false;
```

### new_str
```dart
      // 🔧 [USER-FULL-TTS] firstChunkSent 제거 (조각 발사 폐지로 미사용)
```

> 주의: roleplay에는 `firstChunkSentToTTS`(약 1363번, AI 쪽)라는 별개 변수가 있다. **절대 건드리지 말 것.** old_str의 `bool firstChunkSent = false;`는 정확히 이 문자열만 매칭된다.

---

## 절대 건드리지 말 것 (Do NOT touch)
- AI 쪽 하이브리드 발사(`HybridTtsPlayer`, `firstChunkSentToTTS`, HYB-01/02) — AI는 첫 청크 빠른 발사 유지.
- EVAPORATE / CORRECTION / CLARIFY 감지와 그 처리 블록 — 그대로 유지.
- 텍스트 화면 스트리밍 setState — 그대로 유지.
- PIPE-04 게이트(15초), 조각 TTS http timeout(8초)·재시도(3회) — 그대로.
- `_saveUserFullSentenceToCache`(v3.7) — 그대로 (이제 재생 캐시와도 정합).
- `DeepgramV2VoiceManager`, `TtsQueueManager`, `TtsCache`, opener 청킹(roleplay 759·784) — 그대로.

## 검증

### free_talk
```powershell
grep -c "USER-FULL-TTS" lib/custom_code/widgets/routine_mode_free_talk.dart          # 기대값: 3
grep -c "bool firstChunkSent = false" lib/custom_code/widgets/routine_mode_free_talk.dart  # 기대값: 0
flutter analyze lib/custom_code/widgets/routine_mode_free_talk.dart
```

### roleplay
```powershell
grep -c "USER-FULL-TTS" lib/custom_code/widgets/routine_mode_roleplay.dart           # 기대값: 3
grep -c "bool firstChunkSent = false" lib/custom_code/widgets/routine_mode_roleplay.dart   # 기대값: 0
grep -c "firstChunkSentToTTS" lib/custom_code/widgets/routine_mode_roleplay.dart     # 기대값: 변경 전과 동일 (AI 쪽 미변경 확인)
flutter analyze lib/custom_code/widgets/routine_mode_roleplay.dart
```
- 두 파일 모두 신규 error 0건 (미사용 변수 info/warning은 허용).

## 롤백
```powershell
git restore lib/custom_code/widgets/routine_mode_free_talk.dart lib/custom_code/widgets/routine_mode_roleplay.dart
```

## 실기기 확인
1. 유저 영어 음성이 **처음부터 끝까지 한 호흡으로** 재생되는지 (문장 중간 침묵 없음).
2. 유저 소리가 끝까지 나온 뒤에 AI 소리가 시작되는지 (미완료 전환 사라짐).
3. 로그에서 `[TTS-01] [USER] addText` 가 턴당 **1회만** 찍히는지 (`pending=1`).
4. 유저 첫 오디오 시작이 이전보다 0.5~1.5초 늦는 것이 체감상 허용 범위인지.
5. 같은 문장 반복 시 `[TTS-CACHE-HIT]`/즉시 재생되는지 (v3.7 캐시 정합 확인).