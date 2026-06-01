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

[StealthVox · Clone 모드 주어 오인식 교정]
파일: routine_mode_clone.dart  (F:\flutter_project\stealthvox)
※ Box 7 (통신 엔진)은 절대 건드리지 말 것. 아래 2곳은 모두 Box 7-1 CloneBrain 내부 프롬프트 문자열만 교체.

────────────────────────────────────────
■ 작업 1 — Box 7-1-D `streamCloneResponse` 메서드 전체 교체
────────────────────────────────────────
[삭제 범위]
  - 시작 (약 3836줄): `static Stream<String> streamCloneResponse({`
  - 끝   (약 3913줄): 해당 메서드를 닫는 `}` (… finally { client.close(); } 직후의 메서드 닫는 중괄호)
  ※ 메서드 위 주석 블록(Box 7-1-D 헤더)은 그대로 둘 것.

[교체 코드 — 전체]
  static Stream<String> streamCloneResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String cloneContext,
    required String myTarget,
    String cloneSummary = '',
  }) async* {
    final client = http.Client();
    try {
      final safePersona = _truncatePersona(cloneContext);
      final summaryBlock = cloneSummary.isNotEmpty
          ? '\n\n[MEMORY] 당신은 다음 요약된 과거 내용을 기억하고 있습니다: $cloneSummary'
          : '';

      final sysPrompt =
          '''⚠️ ABSOLUTE OUTPUT RULES — these override the persona ⚠️
1. OUTPUT LANGUAGE: $myTarget ONLY. Zero Korean characters (한글) allowed in output.
2. If the persona contains Korean signature phrases, translate them to natural $myTarget equivalents. Never quote the Korean text.

$safePersona$summaryBlock

[SUBJECT & TARGET — read this BEFORE you answer]
- You are the clone character. The persona above states who the user is to you (e.g. your father, your friend). Apply that relationship FIRST.
- When the user names a third person (e.g. "Hojin", "your brother", "Mom"), THAT named person is the subject. Answer ABOUT that person.
- NEVER turn yourself or the user into the subject of a question that is about someone else. "What score will Hojin get?" is NOT "What score will I/you get?"
- If you cannot tell WHO or WHAT the question is about (the subject is missing or ambiguous), do NOT guess. Ask ONE short clarifying question in $myTarget, e.g. "You mean Hojin's score, right?" or "Sorry, who do you mean?"

[CONVERSATION RULES]
- Respond in $myTarget only.
- MAXIMUM 2 short sentences. Often 1 sentence is enough.
- Keep each sentence under 8 words when possible.
- Sound like a real person, not an AI. Stay in character.
- No greetings, no "I understand", no meta-comments, no prefixes. Just reply.
- Respond in natural, concise everyday conversational style.
- If the audio is garbled or impossible to make out (a speech recognition error), politely ask them to repeat in $myTarget.''';

      final request = http.Request(
        'POST',
        Uri.parse('https://api.openai.com/v1/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      });
      request.body = jsonEncode({
        'model': 'gpt-4o-mini',
        'stream': true,
        'temperature': 0.2,
        'max_tokens': 80, // 🔧 핵심: 2문장 모델 레벨 강제
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content':
                'Conversation history:\n$contextStr\n\nUser just said: "$userTargetText"\n\nYour brief reply:',
          },
        ],
      });

      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        yield '...';
        return;
      }

      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.startsWith('data: ') && chunk != 'data: [DONE]') {
          try {
            final delta = jsonDecode(chunk.substring(6))['choices'][0]['delta']
                ['content'];
            if (delta != null) yield delta.toString();
          } catch (_) {}
        }
      }
    } catch (_) {
      yield '...';
    } finally {
      client.close();
    }
  }

────────────────────────────────────────
■ 작업 2 — Box 7-1-B `streamUserTranslation` 의 [COMMON MISTAKES] 블록 교체
────────────────────────────────────────
[삭제 범위]
  - 시작 (약 3700줄): `[COMMON MISTAKES - avoid these]`
  - 끝   (약 3705줄): `The particle before the verb's doer (이/가) is ALWAYS the subject. Never swap subject and object.`
  ※ 위 [INTERNAL THINKING], 아래 [OUTPUT RULES] 블록은 그대로 둘 것. 이 6줄만 교체.

[교체 코드 — 전체]
[COMMON MISTAKES - avoid these]
Korean: "걔가 나한테 전화했어" → CORRECT: He called me. WRONG: I called him.
Korean: "엄마가 용돈 줬어" → CORRECT: Mom gave me allowance. WRONG: I gave mom allowance.
Korean: "선생님이 칭찬해주셨어" → CORRECT: The teacher praised me. WRONG: I praised the teacher.
Korean: "친구가 요즘 바빠서 못 만나" → CORRECT: My friend is busy lately, so I can't meet him. WRONG: I'm busy lately...
Korean: "호진이 시험 몇 점 받을 것 같아?" → CORRECT: What score do you think Hojin will get on the exam? WRONG: What score do you think you/I will get?
NAMED PEOPLE (proper nouns like 호진, 민수, 엄마, 선생님) must stay as that exact person. NEVER collapse a named subject into "I" or "you".
The particle before the verb's doer (이/가) is ALWAYS the subject. Never swap subject and object.

────────────────────────────────────────
■ 검증 (실행 후 단일 명령으로 확인)
────────────────────────────────────────
1) flutter analyze   → 에러 0 확인
2) grep -c "SUBJECT & TARGET" routine_mode_clone.dart ; grep -c "NAMED PEOPLE" routine_mode_clone.dart ; grep -c "Hojin will get on the exam" routine_mode_clone.dart
   → 각각 1, 1, 1 이면 정상 반영