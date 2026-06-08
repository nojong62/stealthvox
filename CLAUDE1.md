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

# Free Talk 모드 전환 작업 지시서 (v1)

> 클론(`routine_mode_clone.dart`)을 복사해 **Free Talk 모드**(`routine_mode_free_talk.dart`)로 만든다.
> 클론 원본은 **건드리지 않고 그대로 보존**(롤백 안전). 라우팅만 Free Talk로 돌린다.
> Free Talk = AI와의 자유 대화. 초청/페르소나/클론 선택 없음. 통신 골격은 클론과 동일.

---

## 0. 절대 원칙 (CRITICAL)

1. **Box 7(통신 엔진), Box 5 / Box 5-A(파이프라인), 번역/원문 생성 메서드는 손대지 않는다.**
2. **STEP 4의 새 파일 내부 편집은 반드시 "아래(큰 줄번호) → 위(작은 줄번호)" 순서로 적용**한다. (위부터 지우면 아래 줄번호가 밀려 앵커가 어긋남.)
3. 줄번호는 **갓 복사한 새 파일 = 클론 원본과 동일**한 상태 기준이다. 각 편집에 첫 줄/끝 줄 내용 앵커를 함께 표기했다.
4. 작업 파일은 `lib/custom_code/widgets/` 에만 둔다. `lib/custom_code/임시/` 는 빌드 대상 아님.
5. 모든 영어 프롬프트 문자열은 큰따옴표 / 삼중 큰따옴표(`"""`) 기반 — 작은따옴표 이스케이프 사고 방지. URL 마크다운 변환 금지(해당 없음).

---

## STEP 0 — 파일 복사 + 전역 식별자 리네임

PowerShell (`F:\flutter_project\stealth_vox`):

```powershell
Copy-Item lib\custom_code\widgets\routine_mode_clone.dart lib\custom_code\widgets\routine_mode_free_talk.dart

# 새 파일 내부에서만 위젯/브레인 클래스명 변경 (클론 원본은 그대로 둠)
$p = 'lib\custom_code\widgets\routine_mode_free_talk.dart'
(Get-Content $p -Raw) `
  -replace 'RoutineModeClone','RoutineModeFreeTalk' `
  -replace 'CloneBrain','FreeTalkBrain' `
  | Set-Content $p -NoNewline
```

- `RoutineModeClone` → `RoutineModeFreeTalk` 는 `_RoutineModeCloneState` → `_RoutineModeFreeTalkState` 도 함께 처리됨(부분 문자열 포함).
- Box 7 클래스명(`TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`, `TtsCache`, `HybridTtsPlayer`, `ConversationHistory`, `UnifiedBrain`)은 **변경하지 않는다.** 다른 모드 파일과 동일 이름이 중복돼도, 서로 다른 라이브러리이고 동시에 참조되지 않으므로 충돌 없음(기존 4개 모드가 이미 같은 패턴).
- 새 파일을 Android Studio에서 커스텀 위젯으로 인식시킨다(`widgets/` 폴더 자동 포함).

검증:
```powershell
Select-String -Path lib\custom_code\widgets\routine_mode_free_talk.dart -Pattern 'class RoutineModeFreeTalk|class _RoutineModeFreeTalkState|class FreeTalkBrain' | Measure-Object  # 3
Select-String -Path lib\custom_code\widgets\routine_mode_free_talk.dart -Pattern 'RoutineModeClone|CloneBrain' | Measure-Object  # 0
```

---

## STEP 1 — `stealth_room_master.dart` (라우팅)

**1-1. import 추가** (파일 상단 import 블록):
```dart
import 'routine_mode_free_talk.dart';
```

**1-2. mode 2 분기 교체** — 현재 209~213줄:
```dart
    } else if (_currentMode == 2) {
      return RoutineModeClone(
          key: const ValueKey('RoutineModeClone'),
          width: widget.width,
          height: widget.height);
```
↓ 교체:
```dart
    } else if (_currentMode == 2) {
      return RoutineModeFreeTalk(
          key: const ValueKey('RoutineModeFreeTalk'),
          width: widget.width,
          height: widget.height);
```

**1-3. 메뉴 카드 라벨** — 291줄:
```dart
            _buildMenuCard(2, "Clone AI", "클론 AI와 대화", Icons.face,
```
↓ 교체:
```dart
            _buildMenuCard(2, "Free Talk", "AI와 자유 대화", Icons.forum,
```

**1-4. 수동 안내 항목** — 131줄:
```dart
                          _buildManualItem('Clone AI', '클론 AI와 대화',
```
↓ 교체:
```dart
                          _buildManualItem('Free Talk', 'AI와 자유 대화',
```

---

## STEP 2 — `store_master.dart` (사용 내역 라벨)

`_modeDisplayName` switch — 333~334줄 `case 'clone'` 바로 위에 `free_talk` 케이스 추가:
```dart
      case 'free_talk':
        return '💬 Free Talk';
      case 'clone':
        return '🤖 AI Clone';
```
(클론 케이스는 과거 데이터 표시용으로 남겨둠.)

---

## STEP 3 — `chat_history_list_master.dart` (필터칩)

660줄:
```dart
                  _buildFilterChip('Clone', 'Clone', Icons.face),
```
↓ 교체:
```dart
                  _buildFilterChip('Free Talk', 'Free Talk', Icons.forum),
```
(아이콘/색상은 이미 `room_name`에 "Free Talk" 포함 기준으로 들어가 있어 자동 적용됨 — 299·310줄.)

---

## STEP 4 — 새 파일 `routine_mode_free_talk.dart` 내부 (반드시 아래→위 순서)

> STEP 0 직후 줄번호 기준. **4A → 4O 순서대로(=파일 하단부터) 적용.**

---

### 4A. (삭제) FreeTalkBrain의 클론 전용 메서드 3개

`confirmCloneIdentity` ~ `generateRecommendedScenarios` 통째 삭제.

- **시작**: 4232줄 — `  // 📦 [Box 7-1-E1] confirmCloneIdentity — 이름 확정 (temperature 0.2)`
- **끝**: 4437줄 — `10. 듣고 있는 음악 추천하기''';` 의 닫힘 `  }` (generateRecommendedScenarios 의 닫는 중괄호, 4437줄)

즉 **4232~4437줄 전체 삭제**. 바로 아래 4438줄 `}`(= FreeTalkBrain 클래스 닫힘)는 **남긴다.**

검증: `Select-String 'generatePersonaFromChat|confirmCloneIdentity|generateRecommendedScenarios'` → **0건**.

---

### 4B. (교체) `generateCloneOpener` → `generateFreeTalkOpener`

4155줄 `static Stream<String> generateCloneOpener({` 부터 4231줄(메서드 닫는 `}`)까지 — **메서드 전체** 교체:

```dart
  static Stream<String> generateFreeTalkOpener({
    required String apiKey,
    required String targetLang,
    String level = "Intermediate",
  }) async* {
    final client = http.Client();
    try {
      final sysPrompt =
          """You are a warm, friendly conversation partner starting a casual chat.
Open with ONE short, natural line that invites the user to talk — like a friend would.

RULES:
- Speak ONLY in $targetLang. Do NOT use Korean or any other language.
- ONE sentence only. Under 12 words.
- Sound natural and friendly, never like an AI or a survey.
- Avoid a bare "Hello" or "Hi". Say something that invites a reply, for example: "Hey, how's your day going so far?" or "So, what have you been up to lately?"
- ${_freeTalkLevelInstruction(level)}

Output: ONE sentence in $targetLang only.""";

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
        'temperature': 0.8,
        'max_tokens': 40,
        'messages': [
          {'role': 'system', 'content': sysPrompt},
          {
            'role': 'user',
            'content':
                'Start the conversation — say your friendly opening line in $targetLang.',
          },
        ],
      });

      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ') && line != 'data: [DONE]') {
          try {
            final delta =
                jsonDecode(line.substring(6))['choices'][0]['delta']['content'];
            if (delta != null) yield delta.toString();
          } catch (_) {}
        }
      }
    } catch (_) {
    } finally {
      client.close();
    }
  }
```

---

### 4C. (교체) `streamCloneResponse` → `streamFreeTalkResponse` + 레벨 헬퍼

4064줄 `static Stream<String> streamCloneResponse({` 부터 4150줄(메서드 닫는 `}`)까지 — **메서드 전체** 교체. 레벨 분기 헬퍼도 함께 추가:

```dart
  // 📦 Free Talk 언어 수준별 어휘 지침
  static String _freeTalkLevelInstruction(String level) {
    switch (level) {
      case "Beginner":
        return "Use very simple, common words and short sentences. Avoid idioms and difficult grammar.";
      case "Advanced":
        return "Use rich, natural vocabulary including idioms and nuanced expressions, as with a fluent speaker.";
      case "Intermediate":
      default:
        return "Use everyday vocabulary with some variety. Common phrasal verbs and natural expressions are fine.";
    }
  }

  // 📦 [Box 7-1-D] streamFreeTalkResponse — Free Talk AI 응답 스트림
  static Stream<String> streamFreeTalkResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String myTarget,
    String level = "Intermediate",
  }) async* {
    final client = http.Client();
    try {
      final sysPrompt =
          """You are a warm, friendly $myTarget conversation partner.
Keep every reply to 2 short sentences maximum.
Talk like a real friend — sound natural, show interest, and keep the chat flowing.
Match your vocabulary and grammar to the learner's level below.
Never say that you are an AI or a language model.

OUTPUT LANGUAGE: $myTarget ONLY. Zero Korean characters in output.

[RULES]
- Respond in $myTarget only. MAXIMUM 2 short sentences. Often 1 sentence is enough.
- No greetings, no "I understand", no meta-comments, no prefixes. Just reply.
- If the audio is garbled or impossible to make out (a speech recognition error), politely ask them to repeat in $myTarget.

Learner level: ${_freeTalkLevelInstruction(level)}""";

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
        'temperature': 0.5,
        'max_tokens': 90,
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
```

---

### 4D. (삭제) `_truncatePersona` (이제 미사용)

3872줄 `  // 📦 [Box 7-1-A] _truncatePersona — 페르소나 토큰 과부하 방지` 부터,
`_truncatePersona` 메서드 닫힘 `  }`(3892줄 부근, `streamUserTranslation` 시작 3893줄 바로 위)까지 삭제.

검증: `Select-String '_truncatePersona'` → **0건**.

> ⚠️ `streamUserTranslation`(3893~), `generateCleanOriginal`(3994~), `generateExpandedFromConversation`, `polishSentence`는 **유지**(범용 번역/원문/확장 — 손대지 않음).

---

### 4E. (교체) 대화 영역 라벨 "Clone" → "Free Talk"

2718줄:
```dart
              Text("Clone",
```
↓
```dart
              Text("Free Talk",
```

---

### 4F. (삭제) 채팅 리스트 클론 선택 게이트

`_buildChatList` 진입부 — 2639~2645줄:
```dart
  Widget _buildChatList() {
    if (_selectedCloneId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [],
        ),
      );
    }
```
↓ 교체 (게이트 제거, 시그니처만 유지):
```dart
  Widget _buildChatList() {
```

---

### 4G. (교체) `_buildTopControls` → 언어수준 선택기

"Manage Clones" 버튼(2610~2636줄, `Widget _buildTopControls() {` 부터 닫힘 `}`까지) **전체** 교체:

```dart
  Widget _buildTopControls() {
    const levels = ["Beginner", "Intermediate", "Advanced"];
    const labels = ["초급", "중급", "고급"];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: List.generate(levels.length, (i) {
            final bool selected = _freeTalkLevel == levels[i];
            return Expanded(
              child: GestureDetector(
                onTap: () => _setFreeTalkLevel(levels[i]),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        selected ? const Color(0xFF9333EA) : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    "${labels[i]} ${levels[i]}",
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white54,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
```
> 대화 중 레벨 변경 시 다음 AI 응답부터 즉시 반영됨(`streamFreeTalkResponse`가 `_freeTalkLevel`을 매 호출 읽음).

---

### 4H. (교체) 세션/히스토리 저장 3곳 — `mode`/`room_name`/`clone_*` 정리

**4H-③ (가장 아래 먼저)** — `_myHistoryRef!.update` 블록, 2455~2459줄:
```dart
            'mode': 'clone',
            'clone_id': _selectedCloneId,
            'clone_name': _selectedCloneName,
            'user_label': userLabel,
            'partner_label': partnerLabel,
```
↓
```dart
            'mode': 'free_talk',
            'user_label': userLabel,
            'partner_label': partnerLabel,
```

**4H-②** — `userLabel`/`partnerLabel` 지역변수 정의, 2390~2391줄:
```dart
          final userLabel = _cloneUserLabel;
          final partnerLabel = _clonePartnerLabel;
```
↓
```dart
          final userLabel = 'the user';
          final partnerLabel = 'AI partner';
```

**4H-①b** — `_myHistoryRef!.set` 블록, 2317~2322줄:
```dart
        'room_name': "Clone Mode",
        'mode': 'clone',
        'clone_id': _selectedCloneId,
        'clone_name': _selectedCloneName,
        'user_label': _cloneUserLabel,
        'partner_label': _clonePartnerLabel,
```
↓
```dart
        'room_name': "Free Talk",
        'mode': 'free_talk',
        'user_label': 'the user',
        'partner_label': 'AI partner',
```

**4H-①a** — `sessions.add` 블록, 2265~2269줄:
```dart
          'mode': 'clone',
          'clone_id': _selectedCloneId,
          'clone_name': _selectedCloneName,
          'user_label': _cloneUserLabel,
          'partner_label': _clonePartnerLabel,
```
↓
```dart
          'mode': 'free_talk',
          'user_label': 'the user',
          'partner_label': 'AI partner',
```

---

### 4I. (교체) AI 응답 호출부

2048~2055줄:
```dart
      final aiStream = FreeTalkBrain.streamCloneResponse(
        apiKey: _openAiKey,
        userTargetText: userTargetText,
        contextStr: latestContextStr,
        cloneContext: _selectedCloneContext,
        myTarget: targetLangName,
        cloneSummary: _cloneSummary,
      );
```
> (STEP 0 리네임으로 이미 `FreeTalkBrain.`로 바뀐 상태)
↓ 교체:
```dart
      final aiStream = FreeTalkBrain.streamFreeTalkResponse(
        apiKey: _openAiKey,
        userTargetText: userTargetText,
        contextStr: latestContextStr,
        myTarget: targetLangName,
        level: _freeTalkLevel,
      );
```

---

### 4J. (교체) AI 오프너 호출부 + 가드

**4J-b** — 오프너 스트림 호출, 1532~1537줄:
```dart
      await for (final chunk in FreeTalkBrain.generateCloneOpener(
        apiKey: _openAiKey,
        cloneContext: _selectedCloneContext,
        targetLang: targetLangName,
        cloneSummary: _cloneSummary,
      )) {
```
↓
```dart
      await for (final chunk in FreeTalkBrain.generateFreeTalkOpener(
        apiKey: _openAiKey,
        targetLang: targetLangName,
        level: _freeTalkLevel,
      )) {
```

**4J-a** — 오프너 가드, 1494줄:
```dart
    if (_isAiOpenerPlaying || _selectedCloneContext.isEmpty) return;
```
↓
```dart
    if (_isAiOpenerPlaying) return;
```

---

### 4K. (삭제) Box 4 — 대시보드 + 편집 다이얼로그

- **시작**: 704줄 — `  void _showCloneDashboard() {`
- **끝**: 1406줄 — `_showEditCloneDialog` 메서드 닫힘 `  }` (바로 아래 1408줄 `// 📦 [Box 5: Deepgram + Relay Pipeline]` 주석 위)

**704~1406줄 전체 삭제.**

> ⚠️ 그 위 `_showDebugLogDialog`(580~702줄)는 **삭제 금지** — 잔여시간 롱프레스(2581줄 `onLongPress: _showDebugLogDialog`)에서 쓰는 공통 기능.

---

### 4L. (삭제) Box 4 — 클론 Firestore CRUD / 메모리 메서드

- **시작**: 314줄 — `  // 📦 [Box 4: Clone 관리] — Firestore 기반`
- **끝**: 578줄 — 클론 summary 갱신 메서드의 닫힘 `  }` (바로 아래 580줄 `// 🔬 [v3.1 진단] 로그 뷰어 다이얼로그` 주석 위)

**314~578줄 전체 삭제.** (`_clonesRef`, `_loadClones`, `_loadClonesFromPrefs`, `_createCloneInFirestore`, `_updateCloneInFirestore`, `_deleteCloneInFirestore`, `_loadCloneContext`, 클론 summary 동기화까지.)

---

### 4M. (삭제) dispose 컨트롤러 정리

288~290줄:
```dart
    _cloneNameController.dispose();
    _kakaoTextController.dispose();
    _editPersonaController.dispose();
```
**3줄 삭제.**

---

### 4N. (수정) initState — 리스너/로드/빌링

**4N-c** — kakao 리스너 블록, 261~266줄:
```dart
    _kakaoTextController.addListener(() {
      final hasText = _kakaoTextController.text.isNotEmpty;
      if (hasText != _kakaoHasText) {
        setState(() => _kakaoHasText = hasText);
      }
    });
```
**삭제.**

**4N-b** — 269줄 `    _loadClones();` → 교체:
```dart
    _loadFreeTalkLevel();
```

**4N-a** — 273줄(initState 내, 들여쓰기 4칸):
```dart
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('clone');
```
↓
```dart
    BillingTicker.instance.setRate(BillingRate.full);
    BillingTicker.instance.resume();
    BillingTicker.instance.logMode('free_talk');
```

**4N-a2** — 88~89줄(`_resetIdleTimer` 내, 들여쓰기 6칸):
```dart
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('clone');
```
↓
```dart
      BillingTicker.instance.resume();
      BillingTicker.instance.logMode('free_talk');
```

---

### 4O. (교체) 상태변수 블록 — 클론 변수 제거, 레벨 변수 추가

190~228줄 전체:
```dart
  // 클론 데이터 관리
  String _selectedCloneId = "";
  String _selectedCloneContext = "";
  List<Map<String, dynamic>> _clones = [];

  String get _selectedCloneName {
    if (_selectedCloneId.isNotEmpty) {
      for (final clone in _clones) {
        if ((clone['id'] ?? '').toString() == _selectedCloneId) {
          final name = (clone['name'] ?? '').toString().trim();
          if (name.isNotEmpty) return name;
        }
      }
    }
    return '';
  }

  String get _cloneUserLabel => 'the user';
  String get _clonePartnerLabel {
    final name = _selectedCloneName;
    return name.isNotEmpty ? name : 'the clone';
  }

  String get _cloneUiLabel {
    final name = _selectedCloneName;
    return name.isNotEmpty ? name : 'Clone';
  }

  // 🧠 [장기 기억] 클론별 메모리 (SharedPreferences 동기화)
  String _cloneSummary = '';
  List<Map<String, String>> _recentHistory = [];
  int _memoryTurnCount = 0;

  final TextEditingController _cloneNameController = TextEditingController();
  final TextEditingController _kakaoTextController = TextEditingController();
  bool _kakaoHasText = false;
  final TextEditingController _editPersonaController = TextEditingController();
  bool _isCreatingClone = false;
  bool _isEditingClone = false;
```
↓ 교체 (`_recentHistory`는 파이프라인에서 쓰므로 **유지**, 나머지 제거):
```dart
  // Free Talk 언어 수준 (대화 중 토글 가능: Beginner / Intermediate / Advanced)
  String _freeTalkLevel = "Intermediate";

  // 대화 컨텍스트용 슬라이딩 히스토리 (파이프라인 1857·1972줄에서 사용 — 유지)
  List<Map<String, String>> _recentHistory = [];

  // 언어 수준 로드/저장 (SharedPreferences, 커스텀 코드)
  Future<void> _loadFreeTalkLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('free_talk_level');
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _freeTalkLevel = saved);
    }
  }

  Future<void> _setFreeTalkLevel(String level) async {
    if (mounted) setState(() => _freeTalkLevel = level);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('free_talk_level', level);
  }
```

---

## 5. 최종 검증 (새 파일 기준)

```powershell
cd F:\flutter_project\stealth_vox
$f = 'lib\custom_code\widgets\routine_mode_free_talk.dart'

# 클론 잔재 0건이어야 함
Select-String -Path $f -Pattern '_selectedClone|_showCloneDashboard|_showEditCloneDialog|_loadClones|generatePersonaFromChat|generateCloneOpener|streamCloneResponse|_truncatePersona|_cloneSummary|_cloneNameController|_kakaoTextController|_editPersonaController|CloneBrain' | Measure-Object   # → 0

# 신규 심볼 존재 확인
Select-String -Path $f -Pattern "logMode\('free_talk'\)" | Measure-Object        # → 2
Select-String -Path $f -Pattern 'streamFreeTalkResponse|generateFreeTalkOpener|_freeTalkLevel|_freeTalkLevelInstruction' | Measure-Object  # → 다수(>5)
Select-String -Path $f -Pattern "'mode': 'free_talk'" | Measure-Object           # → 3

# _recentHistory 는 유지되어야 함
Select-String -Path $f -Pattern '_recentHistory' | Measure-Object               # → 3 이상

flutter analyze
```

`flutter analyze` 무경고/무에러 목표. (`_recentHistory`가 read-only로만 남아 "could be final" 류 info가 뜨면 무시 가능.)

빌드 후 확인 사항:
- StealthRoom 메뉴 → "Free Talk" 카드 진입.
- 상단: 글자크기 / 언어(원문) / 잔여시간(기존) + **언어수준 3분할 토글**(신규).
- 시작 점 탭 → AI가 친근한 한 마디로 먼저 발화 → 자유 대화.
- 레벨 변경 시 다음 AI 응답부터 어휘 난이도 변화.
- 뒤로가기 시 대화 있으면 "Free Talk" room_name으로 히스토리 저장, 빈 방이면 삭제.
- 히스토리 리스트에서 "Free Talk" 필터/아이콘 정상.

---

## 6. 롤백

```powershell
# 새 파일 제거
Remove-Item lib\custom_code\widgets\routine_mode_free_talk.dart
```
- `stealth_room_master.dart` STEP 1 변경 4곳 되돌림(`RoutineModeClone` 복귀, import 제거, 라벨 복귀).
- `store_master.dart` `free_talk` 케이스 제거.
- `chat_history_list_master.dart` 필터칩 'Clone' 복귀.
- 클론 원본(`routine_mode_clone.dart`)은 처음부터 미변경이므로 그대로 사용 가능.
- `billing_ticker.dart` / Cloud Functions / RevenueCat: **변경 없음** → 롤백 불필요.

---

## 부록 — 빌링/Firebase 영향 요약

- `billing_ticker.dart`: **변경 없음.** 모드→요율 화이트리스트가 없고, 요율은 `setRate(BillingRate.full)`로 결정됨(복사 시 자동 승계 → Free Talk도 100%). `logMode('free_talk')`는 `usage_logs` 라벨일 뿐.
- Cloud Functions(`deductRemainingTime`, `revenueCatWebhook`): 모드 무관 → **변경 없음.**
- RevenueCat: 시간 크레딧 상품/적립만 관여 → **변경 없음.**
- Firestore: schemaless → 마이그레이션/인덱스 불필요. 쓰는 필드 값만 바뀜(`mode`,`room_name`, `clone_*` 제거).
- `users/{uid}/clones` 서브컬렉션: 미사용 상태로 남음(무해, 추후 정리 가능).