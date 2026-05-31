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

[작업 대상] lib/.../routine_mode_step_expand.dart
[원칙] Box 7(TtsQueueManager, DeepgramV2VoiceManager)은 절대 수정 금지. 아래는 모두 StepExpandBrain 내부 작업.
       URL은 순수 문자열만(마크다운 [text](url) 금지). 영어 프롬프트 문자열은 큰따옴표 또는 삼중따옴표 사용.
       각 변경은 적용 전 diff를 먼저 출력하고, 내 승인 후에만 파일에 반영할 것.

========================================================
작업 1) 68k.news 가벼운 헤드라인 페처 추가 (기존 KBS 패턴 그대로 미러링)
========================================================
- StepExpandBrain 안, 기존 [Box 7-1-E-0] KBS 블록 바로 아래에 새 블록 [Box 7-1-E-0b]를 추가한다.
- 먼저 raw HTML 구조를 확인할 것: `curl -sL "https://68k.news/index.php?section=technology&loc=US" | head -c 4000`
  (내가 본 건 마크다운 변환본이므로, 실제 <h3><a> 태그 구조를 직접 보고 정규식을 확정할 것.)
- 함수 시그니처:
    static Future<List<String>> _fetch68kNewsTopics() async
  요구사항:
    * SharedPreferences 일별 캐시. cacheKey = "news68k_" + 오늘날짜(yyyy-MM-dd). 캐시 있으면 즉시 반환.
    * 섹션은 가벼운 것만: ["technology", "entertainment", "science", "health"]
      각 섹션 URL: "https://68k.news/index.php?section=$section&loc=US"  (https 사용, http 금지)
    * http.get + .timeout(Duration(seconds: 8)) , utf8.decode(res.bodyBytes)
    * 헤드라인 추출: 각 스토리 클러스터의 대표 제목(<h3> 내부 <a> 텍스트)을 정규식으로 뽑는다.
      제목 끝의 " - 매체명" 접미사는 제거(마지막 " - " 기준 split 후 앞부분 사용).
    * 영어 heavy-topic 필터 정규식(대소문자 무시)으로 무거운 주제 제외. 최소 다음 키워드 포함:
      trump|biden|war|shooting|shoot|killed|dead|death|die|crash|attack|missile|strike|
      ICE|arrest|charged|lawsuit|court|judge|protest|crime|police|explosion|rocket|
      hostage|hunger strike|blockade|election|senate|congress|tariff|virus|outbreak
      (필요하면 보강 가능. 무거우면 버린다.)
    * 길이 필터: 너무 짧거나(예: 15자 미만) 너무 긴(120자 초과) 제목은 제외.
    * 결과가 1건 이상이면 캐시에 저장 후 반환. 0건이면 빈 리스트 반환.
- 중복 방지는 기존 _pickUnaskedTopic을 재사용하되 키 충돌을 피하기 위해,
  _pickUnaskedTopic을 일반화하거나, _pick68kUnaskedTopic(String userId)을 새로 만들어
  asked 키를 "asked_68k_$userId"로 쓰고 내부에서 _fetch68kNewsTopics()를 호출한다.
  (기존 KBS _pickUnaskedTopic 로직 그대로 복제 — 전부 소진 시 이력 초기화 포함.)

========================================================
작업 2) 오프닝 주제 소스를 68k.news 1순위로 교체 (폴백 유지)
========================================================
- streamGrammarQuestion의 isOpening 분기, [STEP 1] 구간(현재 GPT가 newsHeadline을 즉석 생성하는 약 4639~4693행)을 수정.
- 동작 변경:
    1. 먼저 newsHeadline = (await _pick68kUnaskedTopic(userId)) ?? ''  로 68k 실제 헤드라인을 시도.
       * userId가 이 함수에 없으면 파라미터로 추가하고, 호출부(약 336행, 1604행, 2196행)에서 현재 유저 uid를 넘기도록 함께 수정.
    2. 68k 결과가 비어 있을 때만(네트워크 실패/필터로 전멸 시) 기존 GPT 즉석 주제 생성 로직으로 폴백.
- [STEP 2] 오프닝 질문 생성부(openingSysPrompt)는 그대로 둔다. 이미 newsHeadline을 받아 쓰므로 변경 불필요.
- UX: 68k fetch는 캐시 덕분에 하루 첫 호출만 네트워크. 8초 timeout + 실패 시 즉시 폴백이라 블로킹 위험 낮음. 그대로 유지.

========================================================
작업 3) "새 주제(Start with a new topic)" 재시작도 68k로 라우팅
========================================================
- 약 2702행의 "Start with a new topic" 호출 경로를 확인하고,
  새 주제 시작 시에도 작업 2와 동일하게 _pick68kUnaskedTopic 기반 오프닝이 타도록 연결.
- 단, 대화 "중간" 꼬리질문(turn 1~N, isOpening=false)에는 절대 뉴스 주제를 주입하지 말 것(문장 확장 흐름 보호).

========================================================
작업 4) AI 질문의 문법 구조 로테이션 (soft 렌즈)
========================================================
- streamGrammarQuestion의 grammarHint(약 4762~4777행) 옆에, 턴마다 순환하는 structureSeed를 추가:
    turnNumber % 4 == 1 → 관계대명사(who / which / that)
    turnNumber % 4 == 2 → 관계부사(where / when / why)
    turnNumber % 4 == 3 → to부정사(to V)
    turnNumber % 4 == 0 → 분사구문(-ing / -ed)
- 이 seed를 follow-up용 sysPrompt에 "[STRUCTURE LENS — soft, never forced]" 섹션으로 주입:
    * 의도: 유저의 짧은 답이 이 구조로 자연스럽게 '확장 문장에 붙도록' 질문 각도를 설계.
    * 강제 금지: 자연스럽지 않으면 무시. 문법 용어를 유저에게 절대 노출하지 말 것(기존 BANNED 규칙 유지).
    * 5~8단어, 따뜻한 친구 톤, yes/no 금지 등 기존 규칙 전부 유지.
- isFinalTurn 합성 프롬프트의 "incorporate at least 2 structures" 목록에 관계부사(where/when/why)도 명시적으로 추가.

========================================================
자체 검증 (적용 후)
========================================================
- `dart analyze` 통과 확인.
- `grep -n "68k.news" lib/.../routine_mode_step_expand.dart` 로 http:// 없이 https://만 쓰였는지 확인.
- `grep -n "](http" lib/.../routine_mode_step_expand.dart` 결과 0건(마크다운 URL 없음) 확인.
- Box 7 클래스(TtsQueueManager / DeepgramV2VoiceManager)에 변경이 없는지 diff로 재확인.
- 롤백: 변경 전 원본을 routine_mode_step_expand.dart.bak로 백업해 둘 것.