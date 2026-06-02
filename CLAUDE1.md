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

## Claude Code 지시 프롬프트 (최종 통합본)

**대상 파일:** `lib/.../chat_history_master.dart` (단일 파일, 외부 import 추가 없음, 순수 추가형 변경)

---

### 절대 보존 / 주의 (변경 금지)

- Box 7 (`TtsQueueManager`, `DeepgramV2VoiceManager`) 일체.
- `_buildChunkPracticeScreen()`, `_switchToPolishedPractice()`, `_splitPolishedIntoUnits()`, `_buildChunks()`, `_goToChunkPractice()` — **읽기만** 하고 수정하지 말 것.
- 기존 `_buildTurnPracticeScreen()`의 기존 children·로직(완료 화면·역할 선택·오버레이)은 전부 유지. **맨 아래 footer에 한 블록만 추가.**
- 🚫 이 기능은 Clone/Roleplay 히스토리에서 **"임시"** 확장문장을 만들어 Practice3로 연결만 한다. 생성된 expanded/polished 문장을 historyDoc(방 문서)의 `expanded_sentence` / `polished_sentence` 필드에 **절대 저장하지 말 것.** 저장하면 재입장 시 `_enterShadowingFromRoom()` 라우터가 이 방을 Step Expand 방으로 오인한다. (런타임 상태로만 P3에 전달)
- `_isStepExpandRoom`은 **false로 유지**한다 (P1/P2/P3 탭바가 뜨면 안 됨).
- 유저 발화 추출은 **raw `role != 'HOST'`만** 사용한다. `_isAiTurn()`은 `_swapRoles`를 반영하므로 추출에 쓰지 말 것 (스왑 상태에서 AI 대사가 섞일 수 있음).

---

### 수정 1 — 상태 변수 추가 (약 136행 근처)

`bool _practicingPolished = false; // false = expanded, true = polished` 줄 **바로 다음 줄**에 추가:

```dart
  bool _isBuildingExpand = false; // 🆕 [EXPAND-FROM-CHAT] 확장문장 생성 중 플래그
```

---

### 수정 2 — 신규 메서드 3개 추가

`void _goToChunkPractice() {` 줄 **바로 위**에 아래 3개 메서드 전체를 삽입:

```dart
  // 🆕 [EXPAND-FROM-CHAT] 유저 발화 여러 개 → 자연스러운 긴 영어 한 문장으로 결합
  Future<String?> _combineIntoExpandedSentence(List<String> userLines) async {
    if (_apiKey.isEmpty || userLines.isEmpty) return null;
    try {
      final joined = userLines
          .asMap()
          .entries
          .map((e) => "${e.key + 1}. ${e.value}")
          .join("\n");
      const sysPrompt = """You are an English speaking coach.
The user said several short English lines during a conversation.
Your job: weave them into ONE natural, flowing spoken English sentence.

[RULES]
- Combine the ideas in the given order into a single coherent sentence.
- Keep it natural and speakable (commas for breath are fine).
- Do not add new facts that are not implied by the lines.
- Common everyday vocabulary only.
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
              'max_tokens': 200,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content': "Lines:\n$joined\n\nCombined sentence:"
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
      debugPrint("[combineIntoExpandedSentence] $e");
      return null;
    }
  }

  // 🆕 [EXPAND-FROM-CHAT] 확장문장 → 쉽고 세련된 한 문장 (StepExpandBrain.polishSentence 동일 로직 복제)
  Future<String?> _polishExpandedSentence(String originalSentence) async {
    if (_apiKey.isEmpty || originalSentence.trim().isEmpty) return null;
    try {
      const sysPrompt = """You are an English speaking coach.
The user has built a long English sentence through step-by-step expansion.
Your job: Rewrite it as ONE "easy but elegant" spoken English sentence.

[GOALS]
- Natural spoken rhythm (not written/academic)
- Common vocabulary (no SAT words, no bookish phrases)
- Smooth flow (pause-friendly, commas for breath)
- Same meaning as the original (do not add new facts)
- Slightly more elegant/polished than the original
- Easier to pronounce and say out loud

[AVOID]
- Big academic words
- Formal written phrases
- Complex nested clauses that are hard to speak
- Adding information not in the original

[OUTPUT]
- Exactly ONE sentence.
- No explanation, no quotes, no prefixes.
- Just the polished sentence.""";
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
              'max_tokens': 150,
              'messages': [
                {'role': 'system', 'content': sysPrompt},
                {
                  'role': 'user',
                  'content':
                      'Original sentence:\n$originalSentence\n\nPolished version:'
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return originalSentence;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      String polished =
          ((body['choices'] as List).first['message']['content'] as String)
              .trim();
      if (polished.startsWith('"') && polished.endsWith('"')) {
        polished = polished.substring(1, polished.length - 1);
      }
      return polished.isEmpty ? originalSentence : polished;
    } catch (e) {
      debugPrint("[polishExpandedSentence] $e");
      return originalSentence;
    }
  }

  // 🆕 [EXPAND-FROM-CHAT] 유저 발화 최대 5개 → 확장문장+폴리시문장 생성 → P3 진입
  // 주의: 생성 결과는 런타임 상태로만 P3에 전달. Firestore(historyDoc)에 저장 금지.
  Future<void> _buildExpandFromConversation() async {
    if (_isBuildingExpand) return;
    if (_apiKey.isEmpty) {
      _showRoomEntryToast("API 키가 없어 생성할 수 없습니다");
      return;
    }
    // 유저 발화 추출: raw role != 'HOST'만 (스왑 무관, AI 대사 절대 불포함)
    // 시간순 전체 중 5개 초과 시 "최근 5개" 사용 + 5개 내부 원래 순서 유지
    final allUserLines = _tutorLines
        .where((l) => (l['role'] as String?) != 'HOST')
        .map((l) => (l['text'] as String? ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (allUserLines.isEmpty) {
      _showRoomEntryToast("연습할 유저 문장이 없습니다");
      return;
    }
    final userLines = allUserLines.length > 5
        ? allUserLines.sublist(allUserLines.length - 5)
        : allUserLines;

    if (mounted) setState(() => _isBuildingExpand = true);
    try {
      audioPlayer.stop();
      _stopAutoVADRecording();

      final expanded = await _combineIntoExpandedSentence(userLines);
      if (!mounted) return;
      if (expanded == null || expanded.isEmpty) {
        setState(() => _isBuildingExpand = false);
        _showRoomEntryToast("확장문장 생성 실패");
        return;
      }

      final polished = await _polishExpandedSentence(expanded);
      if (!mounted) return;

      _isStepExpandRoom = false; // 🆕 임시 문장이므로 Step Expand 방 아님 (탭바 방지)
      _expandedSentence = expanded;
      _polishedSentence =
          (polished != null && polished.trim().isNotEmpty) ? polished.trim() : "";
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
        _showRoomEntryToast("생성 중 오류: $e");
      }
    }
  }

```

---

### 수정 3 — turnPractice 하단 고정 footer 버튼 추가

`_buildTurnPracticeScreen()` 안에서 버튼을 **스크롤 리스트(`Expanded`) 내부가 아니라 Column의 footer 영역(마지막 child)**에 둔다. 대화 리스트는 `Expanded`로 유지하고, 완료 화면·역할 선택·오버레이 구조는 변경하지 않는다.

`if (isComplete)` Padding 블록이 끝난 직후이자 Column children을 닫는 `],` **바로 앞**에 삽입.

**찾을 컨텍스트 (약 4487~4490행):**
```dart
              ),
          ],
        ),
        // 역할 선택 말풍선 오버레이
```

**변경 후 (`],` 앞에 footer 추가):**
```dart
              ),

            // 🆕 [EXPAND-FROM-CHAT] 항상 고정 하단 footer 버튼
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                6,
                20,
                (isComplete ? 6 : 12) +
                    MediaQuery.of(context).viewPadding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _isBuildingExpand
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.amber),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    _isBuildingExpand ? "만드는 중..." : "✨ 익스팬드 센텐스 만들기",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.withOpacity(0.12),
                    foregroundColor: Colors.amber,
                    side: const BorderSide(color: Colors.amber),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed:
                      _isBuildingExpand ? null : _buildExpandFromConversation,
                ),
              ),
            ),
          ],
        ),
        // 역할 선택 말풍선 오버레이
```

---

### 적용 후 검증 (필수)

```bash
flutter analyze
grep -c "_buildExpandFromConversation" lib/**/chat_history_master.dart   # 2 (정의 1 + onPressed 1)
grep -c "_combineIntoExpandedSentence" lib/**/chat_history_master.dart   # 2
grep -c "_polishExpandedSentence"      lib/**/chat_history_master.dart   # 2
grep -c "_isBuildingExpand"            lib/**/chat_history_master.dart   # 6 이상
# Firestore 저장이 잘못 들어가지 않았는지 확인 (0이어야 정상)
grep -c "historyDoc.*expanded_sentence\|update.*expanded_sentence" lib/**/chat_history_master.dart   # 0
```

**롤백:** 수정 1~3에서 추가한 블록만 제거하면 원복 (기존 코드 삭제분 없음).

---

