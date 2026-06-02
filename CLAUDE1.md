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

결정 모두 반영하겠습니다 (①-C 하이브리드, ②-라벨 전부 삭제·아이콘 통일, ③-`mode` 기준 교체). 규모가 커서 **파일별 단계 분리**로 갑니다. 부분 적용 위험을 줄이고, 각 단계마다 `flutter analyze` + grep으로 검증하는 기존 워크플로우대로요.

먼저 **Phase 1 (chat_history_master.dart)** 지시문을 만들기 위해 라우터의 `mode` 읽는 위치와 헤더 아이콘 anchor 유일성만 확인하겠습니다.확인 끝났습니다. 라우터에 `data`는 있고 `mode`는 아직 안 읽으니 추가하면 됩니다. 헤더 양쪽 아바타 `padding: all(13)`이 2곳이라 각각 구분 컨텍스트가 필요합니다. 사람쪽 헤더 padding 줄만 보고 바로 Phase 1 지시문 작성하겠습니다.마지막으로 메시지 라벨 블록(삭제 대상)만 정확히 보고, Phase 1 지시문을 작성하겠습니다.Phase 1 설계 확정했습니다. 라우터가 `mode` 기준으로 바뀌므로, 이제 Clone/Roleplay 방에 `expanded_sentence`를 저장해도 안전하게 Tutor 모드로 갑니다 — 버튼이 "저장값 우선 → 없으면 전체 대화로 생성+캐시"로 동작합니다.

## Phase 1 — chat_history_master.dart 지시 프롬프트

> 전제: 지난 세션에서 추가한 `_isBuildingExpand`, `_buildExpandFromConversation`, `_combineIntoExpandedSentence`, `_polishExpandedSentence`, 하단 footer 버튼이 이미 파일에 있는 상태. 라인 번호는 어긋나 있을 수 있으니 **anchor(고유 코드) 기준**으로 찾을 것.

**절대 보존:** Box 7 일체, `_buildChunkPracticeScreen()`, `_buildChunks()`, `_goToChunkPractice()`, `_polishExpandedSentence()`(그대로 유지).

---

### 1) 라우터: `mode` 기준 판별로 교체

**찾기 (고유):**
```dart
      final polished = (data['polished_sentence'] as String?) ?? '';
      final expanded = (data['expanded_sentence'] as String?) ?? '';
```
**교체:**
```dart
      final polished = (data['polished_sentence'] as String?) ?? '';
      final expanded = (data['expanded_sentence'] as String?) ?? '';
      final roomMode = (data['mode'] as String?) ?? ''; // 🆕 [ROUTER-FIX]
```

**찾기 (고유):**
```dart
      if (polished.isNotEmpty || expanded.isNotEmpty) {
```
**교체:**
```dart
      // 🆕 [ROUTER-FIX] step_expand(또는 mode 없는 구버전+expanded 존재)만 Step Expand 분기.
      // clone/roleplay는 expanded_sentence가 있어도 아래 Tutor 모드로 진행.
      if (roomMode == 'step_expand' ||
          (roomMode.isEmpty && (polished.isNotEmpty || expanded.isNotEmpty))) {
```

---

### 2) 헤더 아바타 축소 (양쪽) + skip(`>|`) 삭제

**유저쪽 padding** — 찾기:
```dart
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _tutorUserRecording
```
→ `EdgeInsets.all(13)` 을 `EdgeInsets.all(9)` 로.

**유저쪽 아이콘 size** — 찾기:
```dart
                                Icons.person_rounded,
                                size: 24,
                                color: _tutorUserRecording
```
→ `size: 24,` 을 `size: 18,` 로.

**AI쪽 padding** — 찾기:
```dart
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _tutorAiSpeaking
```
→ `EdgeInsets.all(13)` 을 `EdgeInsets.all(9)` 로.

**AI쪽 아이콘 size** — 찾기:
```dart
                                Icons.smart_toy_rounded,
                                size: 24,
                                color: _tutorAiSpeaking
```
→ `size: 24,` 을 `size: 18,` 로.

**skip 버튼 삭제** — 찾기:
```dart
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded,
                        color: Colors.white54),
                    tooltip: "이번 차례 건너뛰기",
                    onPressed:
                        (isComplete || isAwaiting) ? null : _forceNextTurn,
                  ),
```
→ **블록 전체 삭제(빈 문자열)**. (`_forceNextTurn`이 미사용이 되면 analyze에 unused_element 경고만 뜸 — 에러 아님. 메서드는 남겨둘 것.)

---

### 3) 메시지 버블: AI 아바타 로봇으로 + "AI"/"You" 글자 전부 삭제

**아바타 아이콘** — 찾기:
```dart
                              child: Icon(
                                lineIsAi
                                    ? Icons.volume_up_rounded
                                    : Icons.person_rounded,
```
**교체:**
```dart
                              child: Icon(
                                lineIsAi
                                    ? Icons.smart_toy_rounded
                                    : Icons.person_rounded,
```

**라벨 텍스트 삭제** — 찾기:
```dart
                                children: [
                                  Text(
                                    lineIsAi ? "AI" : "You",
                                    style: TextStyle(
                                      color: isCurrent
                                          ? roleColor
                                          : Colors.white38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    line['text'] as String,
```
**교체:**
```dart
                                children: [
                                  Text(
                                    line['text'] as String,
```

---

### 4) 하단 버튼 라벨 변경 + 동작 교체(생성→이동/캐시)

**버튼 라벨** — 찾기:
```dart
                  label: Text(
                    _isBuildingExpand ? "만드는 중..." : "✨ 익스팬드 센텐스 만들기",
```
**교체:**
```dart
                  label: Text(
                    _isBuildingExpand ? "불러오는 중..." : "✨ Expanded Sentence",
```

**메서드 교체:** 지난 세션의 `_combineIntoExpandedSentence(...)` **메서드 전체를 아래 `_generateExpandedFromConversation(...)` 로 교체**, 그리고 `_buildExpandFromConversation(...)` **메서드 전체를 아래 새 버전으로 교체**. (`_polishExpandedSentence`는 그대로 둘 것.)

```dart
  // 🆕 [EXPAND-FROM-CHAT v2] 대화 전체(AI+유저) → 종합 확장 문장 1개 (의미단위 ~5개, 문법 연결)
  Future<String?> _generateExpandedFromConversation(String transcript) async {
    if (_apiKey.isEmpty || transcript.trim().isEmpty) return null;
    try {
      const sysPrompt = """You are an English speaking coach.
You are given a short conversation transcript between the user and an AI partner.
Your job: compose ONE long, natural English sentence that synthesizes the overall
content and gist of the WHOLE conversation.

[RULES]
- It must be ONE single sentence (do not split it into multiple sentences).
- Build it from about 5 meaning units joined with varied grammatical connectives
  (because, so, while, which, after, even though, and, etc.).
- Natural, speakable rhythm (commas for breath are fine).
- Capture the overall situation/idea of the conversation, not just one line.
- Common everyday vocabulary only. Do not add facts not in the transcript.
- Output exactly ONE sentence. No quotes, no prefixes, no explanation.""";
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'temperature': 0.2,
              'max_tokens': 250,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content':
                      "Conversation:\n$transcript\n\nOne synthesized sentence:"
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      String s =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim();
      if (s.startsWith('"') && s.endsWith('"')) {
        s = s.substring(1, s.length - 1);
      }
      return s.isEmpty ? null : s;
    } catch (e) {
      debugPrint("[generateExpandedFromConversation] $e");
      return null;
    }
  }

  // 🆕 [EXPAND-FROM-CHAT v2] 저장된 expanded/polished 우선 → 없으면 전체 대화로 생성+캐시 → P3 이동
  Future<void> _buildExpandFromConversation() async {
    if (_isBuildingExpand) return;
    if (mounted) setState(() => _isBuildingExpand = true);
    try {
      audioPlayer.stop();
      _stopAutoVADRecording();

      // 1순위: 방 문서에 이미 저장된 expanded/polished
      String expanded = "";
      String polished = "";
      try {
        final snap = await widget.historyDoc.get();
        final d = snap.data();
        expanded = (d?['expanded_sentence'] as String?)?.trim() ?? "";
        polished = (d?['polished_sentence'] as String?)?.trim() ?? "";
      } catch (e) {
        debugPrint("[buildExpand] doc fetch $e");
      }
      if (!mounted) return;

      // 2순위(fallback): 저장값 없으면 전체 대화로 즉석 생성 후 캐시
      if (expanded.isEmpty) {
        if (_apiKey.isEmpty) {
          setState(() => _isBuildingExpand = false);
          _showRoomEntryToast("API 키가 없어 생성할 수 없습니다");
          return;
        }
        final transcript = _tutorLines
            .map((l) {
              final t = (l['text'] as String? ?? '').trim();
              if (t.isEmpty) return null;
              final who = (l['role'] as String?) == 'HOST' ? 'AI' : 'User';
              return "$who: $t";
            })
            .whereType<String>()
            .join("\n");
        if (transcript.isEmpty) {
          setState(() => _isBuildingExpand = false);
          _showRoomEntryToast("연습할 대화가 없습니다");
          return;
        }
        final gen = await _generateExpandedFromConversation(transcript);
        if (!mounted) return;
        if (gen == null || gen.isEmpty) {
          setState(() => _isBuildingExpand = false);
          _showRoomEntryToast("확장문장 생성 실패");
          return;
        }
        expanded = gen;
        final pol = await _polishExpandedSentence(expanded);
        if (!mounted) return;
        polished = (pol != null && pol.trim().isNotEmpty) ? pol.trim() : "";

        // 캐시 저장 — mode가 clone/roleplay이므로 라우터가 Step Expand로 오인하지 않음
        try {
          await widget.historyDoc.update({
            'expanded_sentence': expanded,
            if (polished.isNotEmpty) 'polished_sentence': polished,
          });
        } catch (e) {
          debugPrint("[buildExpand] cache write $e");
        }
        if (!mounted) return;
      }

      // P3 진입 준비
      _isStepExpandRoom = false;
      _expandedSentence = expanded;
      _polishedSentence = polished;
      _practicingPolished = false;
      _polishedUnits = [];
      _polishedUnitIdx = -1;

      await _buildChunks(_expandedSentence);
      if (!mounted) return;

      setState(() => _isBuildingExpand = false);
      _goToChunkPractice();
    } catch (e) {
      debugPrint("[buildExpandFromConversation] $e");
      if (mounted) {
        setState(() => _isBuildingExpand = false);
        _showRoomEntryToast("오류: $e");
      }
    }
  }
```

---

### 적용 후 검증

```bash
flutter analyze
grep -c "roomMode == 'step_expand'" lib/**/chat_history_master.dart        # 1
grep -c "_generateExpandedFromConversation" lib/**/chat_history_master.dart # 2 (정의1+호출1)
grep -c "_combineIntoExpandedSentence" lib/**/chat_history_master.dart      # 0 (제거 확인)
grep -c "Icons.skip_next_rounded" lib/**/chat_history_master.dart           # 0 (삭제 확인)
grep -c "Icons.smart_toy_rounded" lib/**/chat_history_master.dart           # 2 이상 (헤더+버블)
grep -c 'lineIsAi ? "AI" : "You"' lib/**/chat_history_master.dart           # 0 (라벨 삭제 확인)
grep -c "EdgeInsets.all(9)" lib/**/chat_history_master.dart                 # 2 (헤더 양쪽)
```

**롤백:** 위 교체분을 역으로 되돌리면 원복. (라우터 조건은 원래 `if (polished.isNotEmpty || expanded.isNotEmpty)` 로)

---

이 Phase 1만 적용해도 **버튼은 완전히 동작**합니다 (저장값 없으면 전체 대화로 fallback 생성). 검증 결과 보고해 주시면, 이어서 **Phase 2(routine_mode_clone.dart) → Phase 3(routine_mode_roleplay.dart)** — 나가기 시점 로딩 오버레이로 미리 생성·저장하는 부분을 같은 형식으로 만들어 드리겠습니다.

