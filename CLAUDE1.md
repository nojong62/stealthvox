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

routine_mode_step_expand.dart 의 첫 질문 STEP2 프롬프트(openingSysPrompt)를 수정합니다.
목표: 첫 질문을 "유저 자신을 캐묻는 회상/설명형"이 아니라,
가벼운 일상 소재에 대해 "누구나 자기 관점으로 가볍게 판단·추측해서 답할 수 있는" 짧은 질문으로 바꾼다.

[의도]
- 자기 자신에 대한 질문(X) → 세상일·일반 상황에 대한 의견·추측 질문(O)
- 예: "주말에 비 오면 사람들은 보통 뭘 할까?" / "고양이와 강아지 중 어느 쪽이 키우기 쉬울까?"
- 자기 얘기가 아니라 부담 없이 한마디 보탤 수 있고, 그 판단 안에 성향이 담겨 다음 턴 개인화로 연결됨.
- 질문은 반드시 짧고 간단. 복잡하거나 길면 안 됨.

[절대 건드리지 말 것]
- STEP1 소재 생성 로직 (20개 카테고리 WIDE pool, 온도 0.9) — 소재는 가벼운 일상에서 그대로 가져옴
- STEP2의 http 요청 구조, 온도 0.7, max_tokens, 스트리밍 파싱
- LAYER 1 FEELING FIRST / GO DEEPER / EMOTIONAL DEPTH (유저 답변 이후 점진 개인화)
- 5턴 구조, 최종 합성, Part1/Part2, Box 7 엔진

──────────────────────────────────────────────
[수정] openingSysPrompt 두 분기 모두 교체
──────────────────────────────────────────────

기존:
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

교체:
        final String openingSysPrompt = newsHeadline.isNotEmpty
            ? 'You are starting a casual English conversation as a warm-up.\n'
              'Everyday topic: "$newsHeadline"\n\n'
              'Write ONE short, simple question in $myTarget that asks the user for a LIGHT OPINION or GUESS about this topic in general — NOT about the user personally.\n'
              'Think: "what do people usually...", "why might...", "which would be...", "what do you think happens when...".\n'
              'Rules:\n'
              '- ONE sentence only. 8 words or fewer. Simple and easy.\n'
              '- Ask for a general judgment or guess anyone can answer in 1-3 words.\n'
              '- Do NOT ask about the user\'s own life, memories, or feelings yet.\n'
              '- Do NOT demand explanation or a long answer.\n'
              '- Avoid yes/no and avoid plain "A or B" either/or questions.\n'
              '- Sound like a curious friend, not a reporter.\n'
              'Output ONLY the question. Nothing else.'
            : 'You are starting a casual English conversation as a warm-up.\n'
              'Write ONE short, simple question in $myTarget that asks the user for a LIGHT OPINION or GUESS about everyday life in general — NOT about the user personally.\n'
              'Think: "what do people usually...", "why might...", "which would be...", "what do you think happens when...".\n'
              'Rules:\n'
              '- ONE sentence only. 8 words or fewer. Simple and easy.\n'
              '- Ask for a general judgment or guess anyone can answer in 1-3 words.\n'
              '- Do NOT ask about the user\'s own life, memories, or feelings yet.\n'
              '- Do NOT demand explanation or a long answer.\n'
              '- Avoid yes/no and avoid plain "A or B" either/or questions.\n'
              '- Sound like a curious friend, not an interviewer.\n'
              'Output ONLY the question. Nothing else.';

⚠️ 따옴표 주의: 위 문자열은 작은따옴표 문자열이므로 user\'s 의 이스케이프(\')를 정확히 유지할 것.
   URL 마크다운 변환 금지 규칙도 그대로 적용(이 프롬프트엔 URL 없음).

[검증]
1. dart analyze → 에러 0 (특히 작은따옴표 이스케이프 \' 정상)
2. grep -c "LIGHT OPINION or GUESS" routine_mode_step_expand.dart → 2 (두 분기 각 1회)
3. grep -c "Do NOT ask about the user" → 2 (자기 얘기 금지 확인)
4. grep -c "short open-ended question" → 0 (옛 프롬프트 제거 확인)
5. grep -c "WIDE pool" → 1 (STEP1 소재 로직 보존)
6. grep -c "FEELING FIRST" → 1 (점진 개인화 보존)
7. grep "temperature.*0.9" → STEP1 온도 유지 / grep "temperature.*0.7" → STEP2 온도 유지
8. 런타임 테스트:
   (a) 첫 질문: "사람들은 보통 ~할까?" "왜 ~할까?" 류의 가볍게 판단·추측하는 짧은 질문
   (b) 첫 질문이 유저 자신을 직접 캐묻지 않음 (자기 얘기 강요 X)
   (c) 매번 다른 일상 소재 (STEP1 풀 유지)
   (d) 유저 답변 후: 점차 개인적인 질문으로 전개 (FEELING FIRST 동작)
9. Box 7 클래스 diff 변경 0