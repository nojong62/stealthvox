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

# 수정 지시문 (재작성) — Step Expand 시드 질문: 프리톡 대화 + 롤플레이 대화 내용 혼합

## 목적
시드 질문 재료를 2축으로 확대한다.
- 축 1 (기존): 프리톡 히스토리의 유저 발화 2~3개
- 축 2 (신규): **롤플레이 히스토리의 유저 발화(HOST 메시지) 1~2개**

두 축의 실제 대화 내용을 섞어 매 세션 새로운 질문을 생성한다.
시나리오 설정값(scenario_situation 등)은 사용하지 않는다 — **메시지 서브컬렉션의 대화 내용만** 사용.

**핵심 가드:** 롤플레이 발화는 역할극 중의 대사(연기)라서 허구일 수 있다.
유저의 실제 사실/실제 사건으로 전제하는 질문이 나오면 안 된다.

## 작업 전 필수

### (0) 이전 버전 적용 여부 확인
직전 지시문(시나리오 필드 버전)을 이미 적용했다면 먼저 되돌린다:
```bash
cd F:\flutter_project\stealth_vox
grep -c "_fetchRoleplayTopic" lib/custom_code/widgets/routine_mode_step_expand.dart
# 결과가 0이 아니면 → 해당 변경 커밋을 git revert 하거나 git restore로 되돌린 후 진행
# 결과가 0이면 → 그대로 진행
```

### (1) 세이브 포인트
```bash
git add -A && git commit -m "save-point: before seed-question FT+RP conversation blend"
```

**대상 파일 (1개. lib/custom_code/임시/ 절대 금지):**
- `lib/custom_code/widgets/routine_mode_step_expand.dart`

**절대 규칙:**
- Box 7 클래스 내부 수정 금지 (이번 수정은 위젯 함수 + StepExpandBrain — Box 7 아님).
- 기존 `_fetchFreeTalkUserSnippets`는 **한 줄도 수정하지 않는다** (검증된 동작 보존). 롤플레이용 함수를 별도 신설한다.
- 온도 0.2, max_tokens 160, timeout 15s 등 기존 API 설정값 변경 금지.
- 아래 코드의 영어 프롬프트 문자열에는 어퍼스트로피가 없도록 이미 작성됨 — 그대로 사용할 것.
- 줄번호는 참고용. **반드시 anchor로 위치 확정 후, 아래→위 순서로 편집.**

---

## [E-1] Brain — streamFreeTalkSeedQuestion 시그니처 + roleplayBlock 추가 (약 5410~5418줄)

**찾기 (anchor):**
```dart
  static Stream<String> streamFreeTalkSeedQuestion({
    required String apiKey,
    required String myTarget,
    required List<String> snippets,
    String myNative = '',
  }) async* {
    final client = http.Client();
    try {
      final String snippetsBlock = snippets.map((s) => '- $s').join('\n');
```

**교체:**
```dart
  static Stream<String> streamFreeTalkSeedQuestion({
    required String apiKey,
    required String myTarget,
    required List<String> snippets,
    String myNative = '',
    List<String> roleplaySnippets = const [],
  }) async* {
    final client = http.Client();
    try {
      final String snippetsBlock = snippets.map((s) => '- $s').join('\n');
      // 🆕 롤플레이 대화 혼합 재료 (역할극 대사 = 허구 가능 — 실제 사실 전제 금지)
      final String roleplayBlock = roleplaySnippets.isEmpty
          ? ''
          : 'They also practiced a roleplay before. Here are a few things they said inside that roleplay (IN-CHARACTER PRACTICE LINES — possibly fictional, NOT real facts about the user):\n'
              '${roleplaySnippets.map((s) => '- $s').join('\n')}\n'
              '\n';
```

## [E-2] Brain — sysPrompt에 roleplayBlock 주입 (약 5424~5428줄)

**찾기 (anchor):**
```dart
          'The user has had earlier free-talk conversations. Here are a few things they said before:\n'
          '$snippetsBlock\n'
          '\n'
          'Use these snippets ONLY as quiet inspiration to sense what the user cares about. '
```

**교체:**
```dart
          'The user has had earlier free-talk conversations. Here are a few things they said before:\n'
          '$snippetsBlock\n'
          '\n'
          '$roleplayBlock'
          'Use these snippets ONLY as quiet inspiration to sense what the user cares about. '
```

## [E-3] Brain — RULES에 혼합 규칙 2줄 추가 (약 5435~5437줄)

**찾기 (anchor):**
```dart
          '- If NO snippet has real substance, ignore them all and ask a simple, warm everyday-life question instead. Never quote a content-free phrase back to the user.\n'
          '- The question must invite a short, simple statement — NOT yes/no, NOT a list.\n'
```

**교체:**
```dart
          '- If NO snippet has real substance, ignore them all and ask a simple, warm everyday-life question instead. Never quote a content-free phrase back to the user.\n'
          '- If roleplay lines are given: blend their THEME with a free-talk topic ONLY when the mix feels natural. If forcing them together would feel odd, pick ONE side as the main topic and let the other quietly shape the angle of the question.\n'
          '- Roleplay lines are acting practice. NEVER treat them as real events or real facts about the user, and never ask about them as if they actually happened. Use them only as a theme, mood, or angle.\n'
          '- The question must invite a short, simple statement — NOT yes/no, NOT a list.\n'
```

## [E-4] 위젯 — Brain 호출부에 roleplaySnippets 전달 (약 430~435줄)

**찾기 (anchor):**
```dart
    final aiStream = StepExpandBrain.streamFreeTalkSeedQuestion(
      apiKey: _openAiKey,
      myTarget: targetLangName,
      myNative: nativeLangName,
      snippets: snippets,
    );
```

**교체:**
```dart
    final aiStream = StepExpandBrain.streamFreeTalkSeedQuestion(
      apiKey: _openAiKey,
      myTarget: targetLangName,
      myNative: nativeLangName,
      snippets: snippets,
      roleplaySnippets: roleplaySnippets,
    );
```

## [E-5] 위젯 — _generateAndPlayFreeTalkSeedQuestion 시그니처 (약 414~415줄)

**찾기 (anchor):**
```dart
  Future<void> _generateAndPlayFreeTalkSeedQuestion(
      List<String> snippets) async {
```

**교체:**
```dart
  Future<void> _generateAndPlayFreeTalkSeedQuestion(
      List<String> snippets, List<String> roleplaySnippets) async {
```

## [E-6] 위젯 — _fetchRoleplayUserSnippets() 함수 신설 (약 411줄, _fetchFreeTalkUserSnippets 닫는 중괄호 직후)

기존 `_fetchFreeTalkUserSnippets`와 동일 패턴(필러 필터, 길이 정렬, 중복 회피)으로
**mode == 'roleplay'** 방의 HOST(유저) 발화를 1~2개 가져오는 별도 함수를 추가한다.

**찾기 (anchor — _fetchFreeTalkUserSnippets의 끝부분과 다음 함수의 주석 사이):**
```dart
    } catch (e) {
      _log('⚠️ [FT-SEED]', 'fetch 실패: $e');
      return [];
    }
  }

  // 🆕 프리톡 기반 첫 질문을 AI 버블로 렌더 + 타겟 TTS 재생 (그래머 질문과 동일 패턴)
```

**교체:**
```dart
    } catch (e) {
      _log('⚠️ [FT-SEED]', 'fetch 실패: $e');
      return [];
    }
  }

  // 🆕 롤플레이 기록에서 유저(HOST) 대화 발화 1~2개를 가져온다 (시드 질문 혼합 재료).
  //   - _fetchFreeTalkUserSnippets와 동일 패턴: 필러 제외, 내용 풍부한 발화 우선
  //   - 역할극 중 대사이므로 허구 가능 — 프롬프트에서 실제 사실 전제 금지 가드 적용됨
  //   - 최근에 안 쓴 방 우선 (SharedPreferences로 중복 회피, 전부 소진 시 초기화)
  //   - 기록 없으면 빈 리스트 → 프리톡 단독 모드로 동작
  Future<List<String>> _fetchRoleplayUserSnippets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    try {
      final roomsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chat_history')
          .orderBy('created_at', descending: true)
          .limit(30)
          .get();
      final rpRooms = roomsSnap.docs
          .where((d) => ((d.data()['mode'] ?? '').toString()) == 'roleplay')
          .take(5)
          .toList();
      if (rpRooms.isEmpty) return [];

      // 중복 회피: 최근에 안 쓴 방 우선
      final prefs = await SharedPreferences.getInstance();
      final usedKey = 'roleplay_seed_used_${user.uid}';
      final used = Set<String>.from(prefs.getStringList(usedKey) ?? []);
      var pool = rpRooms.where((d) => !used.contains(d.id)).toList();
      if (pool.isEmpty) {
        pool = List.of(rpRooms);
        await prefs.remove(usedKey); // 전부 소진 → 이력 초기화
      }
      pool.shuffle();
      final room = pool.first;
      final newUsed = Set<String>.from(prefs.getStringList(usedKey) ?? [])
        ..add(room.id);
      await prefs.setStringList(usedKey, newUsed.toList());

      // 해당 방의 HOST(유저) 발화 수집 (원문 우선, 없으면 번역문)
      final msgSnap = await room.reference.collection('messages').get();
      final hostTexts = msgSnap.docs
          .where((d) => ((d.data()['role'] ?? '').toString()) == 'HOST')
          .map((d) {
            final data = d.data();
            final orig = (data['original_text'] ?? '').toString().trim();
            final tgt = (data['translated_text'] ?? '').toString().trim();
            return orig.isNotEmpty ? orig : tgt;
          })
          .where((s) => s.isNotEmpty)
          .toList();
      if (hostTexts.isEmpty) return [];

      // 필러/연결용 발화 제외 → 구체적인 내용이 있는 발화만 후보로
      const fillerPatterns = [
        '네',
        '응',
        '어',
        '그래',
        '맞아',
        '맞아요',
        '좋아',
        '좋아요',
        '글쎄',
        'ok',
        'okay',
        '음',
        '아',
        '오',
        '그래요',
        '그러니까',
        '그렇구나',
        '알겠어',
        '알겠습니다',
        'yes',
        'yeah',
        'sure',
        'right',
        'thank you',
        'thanks',
      ];
      bool isFiller(String s) {
        final t = s.replaceAll(RegExp(r'[\s\.,!?~…]'), '').toLowerCase();
        if (t.length < 6) return true; // 너무 짧으면 내용 없음으로 간주
        return fillerPatterns.contains(t);
      }

      final contentTexts = hostTexts.where((s) => !isFiller(s)).toList();
      if (contentTexts.isEmpty) return [];

      contentTexts.sort((a, b) => b.length.compareTo(a.length));
      final seedPool = contentTexts.take(6).toList()..shuffle();
      return seedPool.take(2).toList(); // 1~2개 샘플
    } catch (e) {
      _log('⚠️ [RP-SEED]', 'fetch 실패: $e');
      return [];
    }
  }

  // 🆕 프리톡 기반 첫 질문을 AI 버블로 렌더 + 타겟 TTS 재생 (그래머 질문과 동일 패턴)
```

## [E-7] 위젯 — 세션 시작 호출부 (약 513~518줄)

**찾기 (anchor):**
```dart
    // 🆕 프리톡 기록 기반 첫 질문 (있으면) — 없으면 고정 안내
    final List<String> ftSnippets = await _fetchFreeTalkUserSnippets();

    if (ftSnippets.isNotEmpty && mounted && _isConversationActive) {
      // 프리톡 주제로 AI가 먼저 질문 → "기본 문장 말하세요" 안내 생략
      await _generateAndPlayFreeTalkSeedQuestion(ftSnippets);
    } else {
```

**교체:**
```dart
    // 🆕 프리톡 기록 기반 첫 질문 (있으면) — 없으면 고정 안내
    final List<String> ftSnippets = await _fetchFreeTalkUserSnippets();
    // 🆕 롤플레이 대화 발화 1~2개 혼합 (있으면) — 매 세션 질문 변주 확대
    final List<String> rpSnippets =
        ftSnippets.isNotEmpty ? await _fetchRoleplayUserSnippets() : [];

    if (ftSnippets.isNotEmpty && mounted && _isConversationActive) {
      // 프리톡(+롤플레이 대화) 주제로 AI가 먼저 질문 → "기본 문장 말하세요" 안내 생략
      await _generateAndPlayFreeTalkSeedQuestion(ftSnippets, rpSnippets);
    } else {
```

---

## 검증

```bash
cd F:\flutter_project\stealth_vox
grep -c "_fetchRoleplayUserSnippets" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 2 (정의 1 + 호출 1)
grep -c "roleplaySnippets" lib/custom_code/widgets/routine_mode_step_expand.dart            # 기대값: 8
grep -c "roleplay_seed_used_" lib/custom_code/widgets/routine_mode_step_expand.dart         # 기대값: 1
grep -c "IN-CHARACTER PRACTICE LINES" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 1
grep -c "_fetchRoleplayTopic" lib/custom_code/widgets/routine_mode_step_expand.dart         # 기대값: 0 (이전 버전 잔재 없어야 함)
grep -c "scenario_situation" lib/custom_code/widgets/routine_mode_step_expand.dart          # 기대값: 0 (시나리오 필드 미사용 확인)

flutter analyze lib/custom_code/widgets/routine_mode_step_expand.dart
```
- 에러 0건이어야 함. roleplaySnippets 기대값이 다르면 [E-1]~[E-5] 누락 여부 확인.

**실기기 테스트 체크리스트:**
1. 프리톡 + 롤플레이 기록이 모두 있는 계정 → 시드 질문에 두 대화의 주제가 자연스럽게 섞이는지 (어색하면 한쪽만 주재료로 쓰는지)
2. ⚠️ 롤플레이에서 연기로 한 말(예: "환불해 주세요", "사장님 사과 얼마예요")을 **실제 있었던 일처럼 묻지 않는지** — "지난번에 환불하셨을 때" 류가 나오면 실패
3. 프리톡 기록만 있는 계정 → 기존과 동일하게 프리톡 기반 질문 나오는지
4. 프리톡 기록 없는 계정 → 기존 고정 안내("기본 문장을 하나 제안해 주세요")로 폴백되는지
5. 세션을 3~4회 연속 시작 → 매번 다른 조합의 질문이 나오는지 (프리톡 방·롤플레이 방 각각 중복 회피 동작 확인)

## 롤백

```bash
git restore lib/custom_code/widgets/routine_mode_step_expand.dart
# 또는 커밋했다면
git revert <hash>
```