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

[Duo 모드 버그 수정] DuoBrain 프롬프트를 "대화 상대"에서 "통역기"로 교체

파일: lib/custom_code/widgets/routine_mode_duo.dart

## 배경
Duo 모드는 호스트와 게스트 사이의 양방향 실시간 통역기인데,
현재 DuoBrain 프롬프트가 AI를 "conversation partner"로 규정하여
유저 발화에 대해 번역이 아닌 자기 생각으로 응답/되묻기를 하고 있음.
예: 유저가 "Share this video with your friends"라고 하면
AI가 "What video are you referring to?"라고 대답함 (번역 아님).

## 수정 범위: DuoBrain 클래스의 processTranslation 메서드 내부

### 수정 A: 프롬프트 교체
약 1106줄부터 1136줄까지의 String prompt = ... 전체를 아래로 교체:

```dart
      String prompt = "You are a real-time interpreter/translator.\n"
          "Your ONLY job is to translate the user's speech.\n"
          "NEVER respond to the user. NEVER answer questions. NEVER add comments.\n"
          "NEVER ask clarification questions. Just translate exactly what was said.\n\n"
          "Source language: $originalLang\n"
          "Target language: $targetLang\n\n"
          "=== RECENT CONVERSATION (for context only) ===\n"
          "$historyContext\n\n"
          "=== RULES ===\n"
          "1. Translate the user's speech from $originalLang to $targetLang faithfully.\n"
          "2. Preserve the speaker's tone, intent, and nuance.\n"
          "3. If the speech is already in $targetLang, still output it cleaned up.\n"
          "4. Use the conversation history ONLY to resolve pronouns or context — never to generate your own response.\n\n"
          "=== OUTPUT (strict JSON, nothing else) ===\n"
          "{\n"
          "  \"translated_text\": \"<the translation in $targetLang>\",\n"
          "  \"original_input\": \"<the original speech cleaned up in $originalLang>\"\n"
          "}\n\n"
          "User said: \"$text\"";
```

### 수정 B: temperature 낮추기
같은 메서드 내 약 1146줄:
'temperature': 0.3 → 'temperature': 0.2 로 변경
(통역은 창의성이 아니라 정확성이 중요하므로)

### 수정 C: return map에서 needs_clarification 제거
약 1160~1165줄의 return 블록을 아래로 교체:

```dart
        return {
          'translated_text': parsed['translated_text']?.toString() ?? "",
          'original_input': parsed['original_input']?.toString() ?? "",
        };
```

## 수정하면 안 되는 것
- Box 7 (TtsQueueManager, DeepgramV2VoiceManager 등 통신 엔진)
- _processRelayPipeline 함수의 구조
- _cleanJsonString 헬퍼 메서드
- initState, dispose, UI build 관련 코드

## 검증
1. dart analyze lib/custom_code/widgets/routine_mode_duo.dart — 에러 0
2. grep -n "conversation partner" lib/custom_code/widgets/routine_mode_duo.dart — 결과 0줄
3. grep -n "needs_clarification" lib/custom_code/widgets/routine_mode_duo.dart — 결과 0줄
4. grep -n "AMBIGUITY GUARD" lib/custom_code/widgets/routine_mode_duo.dart — 결과 0줄
5. grep -c "real-time interpreter" lib/custom_code/widgets/routine_mode_duo.dart — 결과 1줄