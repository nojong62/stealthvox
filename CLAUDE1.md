StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

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

# StepExpand 유저 2턴+ 한국어(original) 표시 기획 변경

## 새 기획 (반드시 이 구조를 따를 것)

유저 1턴:
  영어 ← 표시
  한글 ← 표시

AI:
  영어 ← 표시
  한글 ← 표시

유저 2턴+:
  짧은 대답 영어 ← 표시
  짧은 대답 한글 ← 표시
  ----한줄띄기----
  확장문장 영어 ← 표시
  (확장문장 한글 ← 자체 없음)

AI:
  영어 ← 표시
  한글 ← 표시

## 현재 상태 (이전 수정으로 적용된 것)
- 2턴+에서 Part1\n\nPart2 영어를 통째로 generateCleanOriginal에 보내서 "Part1한국어\n\nPart2한국어" 역번역 생성
- _buildTextBlock에서 Part2 한국어만 표시하고 Part1 한국어는 숨김

## 변경 이유
- 확장문장(Part2)에는 한국어가 아예 필요 없음
- 짧은 대답(Part1)의 한국어는 대화방에서도 보여야 함

## 수정 대상 파일
routine_mode_step_expand.dart (이 파일만 수정)

## 수정 2곳 — 다른 로직 절대 건드리지 말 것

### 수정 1: 2턴+ 역번역을 Part1(짧은 대답)만 대상으로 변경
위치: `_processRelayPipeline` 내부, 라인 1932~1942 부근의 `else if (hasDoubleNewline)` 분기

현재 코드:
```dart
      } else if (hasDoubleNewline) {
        // 2턴+: Part1\n\nPart2 형태의 영어를 통째로 역번역
        // generateCleanOriginal 프롬프트가 \n\n 구조를 유지하므로 한국어도 Part1한국어\n\nPart2한국어로 나옴
        userOrigFuture = StepExpandBrain.generateCleanOriginal(
            apiKey: _openAiKey, englishText: userTargetText);
        userOrigFuture.then((cleanKorean) {
          if (mounted && _localMessages.length > hostIndex) {
            setState(() => _localMessages[hostIndex]['original'] = cleanKorean);
          }
        });
      }
```

교체할 코드:
```dart
      } else if (hasDoubleNewline) {
        // 2턴+: Part1(짧은 대답)만 역번역 → 확장문장(Part2)은 한국어 불필요
        final part1English = userTargetText.substring(0, userTargetText.indexOf('\n\n')).trim();
        if (part1English.isNotEmpty) {
          userOrigFuture = StepExpandBrain.generateCleanOriginal(
              apiKey: _openAiKey, englishText: part1English);
          userOrigFuture.then((cleanKorean) {
            if (mounted && _localMessages.length > hostIndex) {
              setState(() => _localMessages[hostIndex]['original'] = cleanKorean);
            }
          });
        }
      }
```

### 수정 2: _buildTextBlock에서 유저 2턴+ original 표시를 단순화
위치: `_buildTextBlock` 메서드 내부, 라인 2849~2861 부근

현재 코드:
```dart
    // 🌱 유저 2턴+ original은 "Part1한국어\n\nPart2한국어" 구조
    // 대화방에서는 Part1 한국어를 숨기고 Part2 한국어만 표시
    // (공부방/Firestore에는 전체가 저장되어 열람 가능)
    final String effectiveOriginal;
    if (role == 'HOST_TEMP') {
      effectiveOriginal = '';
    } else if (role == 'HOST' && originalRaw.contains('\n\n')) {
      // Part2(확장문장) 한국어만 표시
      final origParts = originalRaw.split(RegExp(r'\n\s*\n'));
      effectiveOriginal = origParts.sublist(1).join('\n\n').trim();
    } else {
      effectiveOriginal = originalRaw;
    }
```

교체할 코드:
```dart
    // 🌱 유저 2턴+: original = Part1(짧은 대답) 한국어만 저장됨 (확장문장 한국어 없음)
    // → 그대로 표시하면 됨
    final String effectiveOriginal = (role == 'HOST_TEMP') ? '' : originalRaw;
```

## 절대 금지 사항
1. Box 7 (TtsQueueManager, DeepgramV2VoiceManager, ChunkedTtsFetcher, HybridTtsPlayer) 코드 수정 금지
2. StepExpandBrain의 프롬프트(streamUserTranslation, streamGrammarQuestion, generateCleanOriginal) 수정 금지
3. 대화 순서/흐름/파이프라인 로직 변경 금지
4. TTS 발사 로직 변경 금지
5. Firestore 저장 구조(필드명, 컬렉션 구조) 변경 금지
6. 수정 1의 if (currentTurnId == 1) 분기는 그대로 유지 — 건드리지 말 것
7. effectiveTarget 로직 변경 금지 — target(영어) 표시는 현재 그대로 정상

## 검증
1. `dart analyze` — 에러 0건
2. `grep -n "통째로 역번역" routine_mode_step_expand.dart` → 결과 0건 (이전 주석 제거 확인)
3. `grep -n "part1English" routine_mode_step_expand.dart` → 수정 1에서 발견
4. `grep -n "effectiveOriginal" routine_mode_step_expand.dart` → 수정 2 포함 확인, \n\n 분기 로직 없어야 함