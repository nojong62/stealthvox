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

# StepExpand 오프닝 질문 — 오늘 뉴스 기반 짧은 질문 + 번역 품질 수정

## 현재 문제 (스크린샷 확인)
1. 첫 질문이 너무 길고 무거움
   - 뉴스 소재 선정이 "최근 관심 주제" 기반이라 AI 윤리 등 심층 토론 주제 등장
   - 질문 프롬프트에 "1 to 2 sentences"가 허용되어 두 문장짜리 질문 생성
2. 한국어 번역이 질문 번역이 아니라 AI가 직접 답변을 서술하는 강의 수준
   - generateCleanOriginal 프롬프트에 길이/역할 제약이 없어 hallucination 발생

## 수정 대상 파일
routine_mode_step_expand.dart (이 파일만 수정)

## 수정 2곳 — 다른 로직 절대 건드리지 말 것

---

### 수정 1: isOpening 분기 — 뉴스 선정 + 질문 생성 프롬프트 교체
위치: `streamGrammarQuestion` 내 `if (isOpening)` 블록 전체
라인: 4545~4660 부근 (if (isOpening) { ... return; } 전체)

현재 코드:
```dart
      if (isOpening) {
        // ── [STEP 1] 당일 뉴스 헤드라인 가져오기 (non-streaming, 10초 timeout) ──
        String newsHeadline = '';
        final newsClient = http.Client();
        try {
          final newsRes = await newsClient
              .post(
                Uri.parse('https://api.openai.com/v1/chat/completions'),
                headers: {
                  'Authorization': 'Bearer $apiKey',
                  'Content-Type': 'application/json; charset=utf-8',
                },
                body: jsonEncode({
                  'model': 'gpt-4o-mini',
                  'max_tokens': 40,
                  'temperature': 0.9,
                  'messages': [
                    {
                      'role': 'system',
                      'content':
                          'Output ONLY one short, interesting news topic (max 10 words) that $myNative-speaking people are curious about recently. No explanation. No extra text.',
                    },
                    {
                      'role': 'user',
                      'content':
                          'Give me one current news topic people in $myNative-speaking countries find interesting.',
                    },
                  ],
                }),
              )
              .timeout(const Duration(seconds: 10));
          if (newsRes.statusCode == 200) {
            final newsJson = jsonDecode(newsRes.body);
            final choices = newsJson['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              newsHeadline =
                  (choices[0]['message']?['content'] ?? '').toString().trim();
            }
          }
        } catch (_) {
          newsHeadline = '';
        } finally {
          newsClient.close();
        }

        // ── [STEP 2] 뉴스 소재 기반 or 폴백 오프닝 질문 생성 (streaming) ──
        final String openingSysPrompt = newsHeadline.isNotEmpty
            ? """You are a warm, friendly conversation coach.
Today's news topic: "$newsHeadline"

Use this as a casual conversation opener. Ask ONE natural open-ended question in $myTarget that gently invites the user to share their opinion or personal experience related to this topic.

[RULES]
- Sound like a friend casually bringing it up — not a news anchor.
- Open-ended: never yes/no.
- Warm and light — 1 to 2 sentences max.
- No grammar terms. No leading phrases.

[OUTPUT]
Output ONLY the question in $myTarget. Nothing else."""
            : """You are a warm conversation coach starting a new session.

Ask ONE open-ended question in $myTarget that invites the user to share something from their everyday life — naturally and without pressure.

[RULES]
- 5 to 8 words only.
- Open-ended: never yes/no.
- Warm and casual — like a curious friend, not an interviewer.
- Everyday topics are perfect: recent events, something they noticed, something on their mind.
- No grammar terms. No leading phrases.

[OUTPUT]
Output ONLY the question in $myTarget. Nothing else.""";

        final openReq = http.Request(
          'POST',
          Uri.parse('https://api.openai.com/v1/chat/completions'),
        );
        openReq.headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json; charset=utf-8',
        });
        openReq.body = jsonEncode({
          'model': 'gpt-4o-mini',
          'stream': true,
          'temperature': 0.7,
          'max_tokens': 80,
          'messages': [
            {'role': 'system', 'content': openingSysPrompt},
            {'role': 'user', 'content': 'Start the session.'},
          ],
        });
        final openResp =
            await openReq.send().timeout(const Duration(seconds: 15));
        if (openResp.statusCode != 200) {
          return;
```

교체할 코드:
```dart
      if (isOpening) {
        // ── [STEP 1] 오늘 뉴스 헤드라인 1건 선정 ────────────────────────
        // 가볍고 일상적인 뉴스 (생활/날씨/음식/문화/스포츠)만 선정
        // 정치·사회·AI윤리 등 무거운 주제 제외
        String newsHeadline = '';
        final newsClient = http.Client();
        try {
          final newsRes = await newsClient
              .post(
                Uri.parse('https://api.openai.com/v1/chat/completions'),
                headers: {
                  'Authorization': 'Bearer $apiKey',
                  'Content-Type': 'application/json; charset=utf-8',
                },
                body: jsonEncode({
                  'model': 'gpt-4o-mini',
                  'max_tokens': 20,
                  'temperature': 0.9,
                  'messages': [
                    {
                      'role': 'system',
                      'content':
                          'Pick ONE real-feeling everyday news topic from $myNative-speaking countries that would appear in today\'s news feed.\n'
                          'Topic must be light and relatable — from these categories ONLY: weather, food prices, sports, popular culture, seasonal events, local life.\n'
                          'FORBIDDEN topics: politics, war, AI ethics, crime, economics, anything heavy or controversial.\n'
                          'Output format: ONLY a 4-to-8-word English noun phrase. No verb. No question. No punctuation.\n'
                          'Examples:\n'
                          'summer heat wave hitting this week\n'
                          'coffee prices rising at local cafes\n'
                          'popular drama ending this weekend\n'
                          'school lunch menu changes next month\n'
                          'heavy rain forecast for the weekend',
                    },
                    {
                      'role': 'user',
                      'content': 'Today\'s topic.',
                    },
                  ],
                }),
              )
              .timeout(const Duration(seconds: 10));
          if (newsRes.statusCode == 200) {
            final newsJson = jsonDecode(utf8.decode(newsRes.bodyBytes));
            final choices = newsJson['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              newsHeadline =
                  (choices[0]['message']?['content'] ?? '').toString().trim();
            }
          }
        } catch (_) {
          newsHeadline = '';
        } finally {
          newsClient.close();
        }

        // ── [STEP 2] 뉴스 소재 기반 짧은 오프닝 질문 생성 (streaming) ──
        final String openingSysPrompt = newsHeadline.isNotEmpty
            ? 'You are starting a casual English conversation.\n'
              'News topic: "$newsHeadline"\n\n'
              'Write ONE short open-ended question in $myTarget about this topic.\n'
              'Rules:\n'
              '- ONE sentence only. 8 words or fewer.\n'
              '- Sound like a friend, not a reporter.\n'
              '- Never yes/no.\n'
              'Output ONLY the question. Nothing else.'
            : 'You are starting a casual English conversation.\n'
              'Write ONE short open-ended question in $myTarget about something from everyday life.\n'
              'Rules:\n'
              '- ONE sentence only. 8 words or fewer.\n'
              '- Sound like a friend, not an interviewer.\n'
              '- Never yes/no.\n'
              'Output ONLY the question. Nothing else.';

        final openReq = http.Request(
          'POST',
          Uri.parse('https://api.openai.com/v1/chat/completions'),
        );
        openReq.headers.addAll({
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json; charset=utf-8',
        });
        openReq.body = jsonEncode({
          'model': 'gpt-4o-mini',
          'stream': true,
          'temperature': 0.2,
          'max_tokens': 30,
          'messages': [
            {'role': 'system', 'content': openingSysPrompt},
            {'role': 'user', 'content': 'Go.'},
          ],
        });
        final openResp =
            await openReq.send().timeout(const Duration(seconds: 15));
        if (openResp.statusCode != 200) {
          return;
```

---

### 수정 2: generateCleanOriginal — 오프닝 질문 번역 시 짧고 정확하게
위치: `generateCleanOriginal` 메서드 내 system 프롬프트
라인: 4414~4431 부근

현재 코드:
```dart
                    'content':
                        '''당신은 한영 통역 전문가입니다. 다음 영어 문장을 **자연스러운 한국어 구어체**로 번역하세요.

[중요 규칙 - 주어 생략 처리]
- 한국어는 주어를 자주 생략합니다. 영어의 I/You/He/She/We/They를 무조건 그대로 살리지 마세요.
- 문맥상 당연한 주어는 과감히 생략하여 자연스럽게 만드세요.
- 하지만 의미 혼동 가능성이 있을 때는 주어를 살립니다.

[구어체 톤]
- 문어체 X, 일상 대화체 O

[포맷 유지]
- 원문에 빈 줄(\\n\\n)이 있으면 한국어에도 반드시 그대로 유지하세요.

[출력]
- 번역문만 출력. 설명/주석/따옴표 없음.
''',
```

교체할 코드:
```dart
                    'content':
                        '''당신은 영한 번역가입니다. 주어진 영어를 한국어 구어체로 번역하세요.

[규칙]
- 원문 내용만 번역. 설명·부연·의견 추가 절대 금지.
- 짧은 문장은 짧게, 긴 문장은 길게 — 원문 길이에 비례하게.
- 한국어 주어 생략: 문맥상 명확한 I/You/We/They는 생략.
- 구어체 (문어체 X).
- 원문에 빈 줄(\\n\\n)이 있으면 한국어에도 그대로 유지.
- 번역문만 출력. 설명/주석/따옴표 없음.
''',
```

그리고 같은 메서드에서 `temperature`와 `max_tokens`도 수정:

현재 코드:
```dart
                'model': 'gpt-4o-mini',
                'temperature': 0.0,
                'max_tokens': 200,
```

교체할 코드:
```dart
                'model': 'gpt-4o-mini',
                'temperature': 0.2,
                'max_tokens': 120,
```

---

## 수정 요약

| 항목 | 변경 전 | 변경 후 | 이유 |
|---|---|---|---|
| 뉴스 선정 프롬프트 | "recently curious" — 트렌드 주제 | 오늘 생활/날씨/음식/문화만, 무거운 주제 금지 | AI윤리 등 무거운 주제 차단 |
| 뉴스 선정 max_tokens | 40 | 20 | 4~8단어 명사구만 필요 |
| 질문 생성 temperature | 0.7 | 0.2 | 짧고 예측 가능하게 |
| 질문 생성 max_tokens | 80 | 30 | 8단어 이하 강제 |
| 역번역 프롬프트 | "자연스러운 구어체" — 길이 제약 없음 | 원문 길이 비례, 부연 금지 | 강의 수준 번역 차단 |
| 역번역 temperature | 0.0 | 0.2 | 약간의 자연스러움 허용 |
| 역번역 max_tokens | 200 | 120 | 과도한 출력 차단 |

## 절대 금지 사항
1. Box 7 (TtsQueueManager, DeepgramV2VoiceManager, ChunkedTtsFetcher) 코드 수정 금지
2. isOpening 이외 `streamGrammarQuestion` 분기 수정 금지
3. `_startSessionWithAiQuestion` TTS/STT 흐름 변경 금지
4. Firestore 저장 로직 변경 금지
5. `streamUserTranslation`, `streamGrammarQuestion` 일반 턴 프롬프트 수정 금지

## 검증
1. `dart analyze` — 에러 0건
2. `grep -n "max_tokens.*80" routine_mode_step_expand.dart` → 0건 (구 질문 max_tokens 제거 확인)
3. `grep -n "max_tokens.*30" routine_mode_step_expand.dart` → isOpening STEP 2에서 발견
4. `grep -n "max_tokens.*120" routine_mode_step_expand.dart` → generateCleanOriginal에서 발견
5. `grep -n "temperature.*0.2" routine_mode_step_expand.dart` → 질문 생성 + 역번역 양쪽에서 발견