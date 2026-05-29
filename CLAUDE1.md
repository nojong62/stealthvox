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

routine_mode_step_expand.dart 파일의 Box 7-1-C streamGrammarQuestion 안,
isOpening 블록의 STEP 1 뉴스 소재 생성 프롬프트를 수정합니다.
목표: 매번 "조금 바뀐 비슷한 주제"가 아니라 "완전히 다른 영역"의 주제가 나오게 한다.

[절대 건드리지 말 것]
- STEP 2 질문 생성부 (temperature 0.7, max_tokens 30)
- grammarHint, LAYER 1, EMOTIONAL DEPTH RULE 등 턴 1~4 로직
- 5턴 구조, 최종 합성, Part1/Part2 포맷
- Box 7 엔진 클래스

[수정] STEP 1 소재 생성의 system content 교체

기존 (newsClient.post 안, temperature 0.9 요청의 system content):
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

이것을 아래로 교체합니다:
                      'content':
                          'Pick ONE light, everyday small-talk topic for an English conversation warm-up.\n'
                          'STEP A — Silently choose ONE category at random from this WIDE pool (do not always pick the first ones):\n'
                          '  food & cooking, weather & seasons, travel & places, hobbies & free time, movies & TV, music, books & reading, sports & exercise, technology & gadgets, pets & animals, fashion & style, health & sleep, work & study life, childhood memories, dreams & future plans, local festivals & events, coffee & cafes, shopping & trends, nature & outdoors, holidays & celebrations.\n'
                          'STEP B — Inside that ONE category, invent a fresh, specific everyday topic.\n'
                          'Each time you are called, pick a DIFFERENT category than an obvious default — vary widely across the whole pool.\n'
                          'FORBIDDEN: politics, war, AI ethics, crime, economics, illness, anything heavy or controversial.\n'
                          'Output format: ONLY a 4-to-8-word English noun phrase. No verb. No question. No punctuation.\n'
                          'Examples (note how different the categories are):\n'
                          'a cozy rainy-day movie marathon\n'
                          'learning to bake sourdough bread\n'
                          'a weekend hiking trip in autumn\n'
                          'an old song stuck in your head\n'
                          'rearranging furniture in your room\n'
                          'a childhood snack you suddenly miss',

[검증]
1. dart analyze 로 문법/이스케이프 에러 없는지 확인
2. grep -c "WIDE pool" routine_mode_step_expand.dart → 1 이어야 함
3. grep -c "from these categories ONLY: weather" → 0 이어야 함 (옛 프롬프트 제거 확인)
4. grep "temperature.*0.9" 로 STEP 1 온도가 그대로 0.9 유지되는지 확인
5. grep "temperature.*0.7" 로 STEP 2 온도가 그대로 0.7 유지되는지 확인