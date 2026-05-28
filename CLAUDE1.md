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

routine_mode_roleplay.dart 파일에서 아래 4개 수정을 적용해줘. Box 7 엔진(DeepgramV2VoiceManager, TtsQueueManager, ChunkedTtsFetcher, HybridTtsPlayer 등)은 절대 건드리지 마.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
수정 1: generateCleanOriginal 프롬프트 — 번역 생략 방지
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
위치: Box 7-1-B generateCleanOriginal 함수 내부, 'content' 값의 삼중따옴표 시스템 프롬프트.
대략 3540행 시작 '''당신은 한영 통역 전문가입니다 ~ 3557행 ''', 까지.

이 프롬프트를 아래로 교체:

'''당신은 한영 통역 전문가입니다. 다음 영어 문장을 **자연스러운 한국어 구어체**로 번역하세요.

[절대 규칙 - 문장 누락 금지]
- 원문의 모든 문장을 빠짐없이 번역하세요. 요약/축약/생략 절대 금지.
- 원문이 2문장이면 번역도 반드시 2문장, 3문장이면 3문장.
- 마침표(.) 또는 물음표(?) 단위로 끊어서 각각 번역하세요.

[주어 생략 처리]
- 한국어는 주어를 자주 생략합니다. 영어의 I/You/He/She/We/They를 무조건 그대로 살리지 마세요.
- 문맥상 당연한 주어는 과감히 생략하여 자연스럽게 만드세요.
  예: "I need to go" → "가야겠어요" (✅) / "나는 가야 한다" (❌ 어색)
  예: "Are you coming?" → "올 거예요?" (✅) / "당신은 오고 있습니까?" (❌)
- 대화 상대가 명확하면 "너/당신"도 생략 가능합니다.
- 하지만 의미 혼동 가능성이 있을 때는 주어를 살립니다.

[구어체 톤]
- 문어체 X, 일상 대화체 O
- "~하였다" X → "~했어요" O
- "~이다" X → "~이에요/~예요" O

[출력]
- 번역문만 출력. 설명/주석/따옴표 없음.
- 원문의 문장 수와 동일하게 출력.
'''

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
수정 2: generateDramaticScenario 장르 풀 — 일상 대화 50% 추가
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
위치: Box 7-1-0 generateDramaticScenario 함수 내부, final genres = [...]; 배열.
대략 3330행 시작 ~ 3341행 ]; 까지.

이 배열을 아래로 교체:

      final genres = [
        // 일상/긍정 (10개)
        '카페에서 새 메뉴 추천받기',
        '해외여행 중 현지인과 길 묻기',
        '새 이웃에게 인사하며 동네 소개',
        '옷가게에서 스타일 상담',
        '회사 점심시간 동료와 맛집 토크',
        '헬스장 첫날 트레이너와 상담',
        '공항 체크인 카운터 대화',
        '호텔 체크인하며 방 업그레이드 요청',
        '동네 서점에서 책 추천 대화',
        '반려동물 산책 중 견주끼리 대화',
        // 드라마틱/갈등 (10개)
        '불륜 발각, 부부 갈등',
        '직장 내 권력 다툼, 해고 위기',
        '형사 심문, 용의자 취조',
        '재벌가 상속 분쟁',
        '비밀 연인 들킴',
        '가족 비밀 폭로',
        '첫사랑 재회, 감정 충돌',
        '룸메이트 생활 규칙 갈등',
        '환불 요청하는데 매장 직원이 거부',
        '친구가 빌린 돈 안 갚음',
      ];

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
수정 3: generateDramaticScenario 프롬프트 — 일상 시나리오 대응
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
위치: 같은 함수 내부 systemPrompt 문자열.
대략 3344행 시작 final systemPrompt = ~ 3358행 Genre hint 끝까지.

이 프롬프트를 아래로 교체:

      final systemPrompt = 'You are a creative director for a high-immersion English roleplay app.\n'
          'Your job is to create ONE vivid scene inspired by real-life situations, Netflix series, Korean/American dramas, or movies.\n'
          '\n'
          'OUTPUT: Return ONLY valid JSON, no extra text.\n'
          '{\n'
          '  "situation": "핵심 상황 요약 (10-15 Korean chars, e.g. 카페에서 신메뉴 추천)",\n'
          '  "ai_role": "AI 캐릭터 (10자 이내, with clear personality, e.g. 친절한 바리스타)",\n'
          '  "user_role": "유저 캐릭터 (8자 이내, e.g. 단골 손님)"\n'
          '}\n'
          '\n'
          'RULES:\n'
          '- situation: vivid and specific. Do NOT name any show/character.\n'
          '- ai_role: give a personality that fits the genre (friendly, enthusiastic, suspicious, furious, etc).\n'
          '- user_role: the user naturally belongs in the scene.\n'
          '- For everyday/positive genres: warm, helpful, curious personalities.\n'
          '- For dramatic/conflict genres: intense, confrontational, emotional personalities.\n'
          '- Genre hint this round: $pick';

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
수정 4: generateAiOpener 프롬프트 — 일상 시나리오 대응
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
위치: Box 7-1-D generateAiOpener 함수 내부, sysPrompt 문자열.
대략 3688행 시작 ~ 3703행 끝까지.

이 프롬프트를 아래로 교체:

      final sysPrompt = 'You are a master actor and an English conversation coach playing "$aiRole".\n'
          '\n'
          '[SCENARIO]\n'
          'Situation: $situation\n'
          'Your role: $aiRole\n'
          "The other person's role: $userRole\n"
          '\n'
          '[CORE RULES]\n'
          '1. Start the scene IMMEDIATELY with your first line — no greetings, no meta-commentary.\n'
          '2. Read the emotional tone of the situation: if dramatic, be intense; if everyday, be natural and warm.\n'
          '3. Do NOT mention any drama, movie, or show titles. Keep it real and seamless.\n'
          '4. Your first line must be a natural, in-character statement or question that draws the user into the scene.\n'
          '5. Adopt the exact personality of "$aiRole". Use natural spoken $targetLang — NOT textbook dialogue.\n'
          '6. ONE sentence only. Under 20 words. Maximum immersion, zero filler.\n'
          '\n'
          'Output: ONE natural first line in $targetLang only.';

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
검증
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
수정 완료 후:
1. dart analyze 실행하여 에러 없는지 확인
2. grep -n "fierce\|furious, cold, desperate\|deep dramatic conflict\|forces the user to respond, defend" routine_mode_roleplay.dart — 결과가 0건이어야 함 (갈등 편향 표현 제거 확인)
3. grep -n "카페에서 새 메뉴\|문장 누락 금지" routine_mode_roleplay.dart — 2건 이상 나와야 함 (신규 코드 삽입 확인)
4. Box 7 클래스(DeepgramV2VoiceManager, TtsQueueManager, ChunkedTtsFetcher, HybridTtsPlayer, AudioCacheManager, TtsCache)에 diff가 없는지 확인

streamRoleplayResponse(Box 7-1-C)의 프롬프트는 수정하지 마. 여기는 이미 $aiRole 기반으로 동적이라 장르에 따라 자동 적응됨.