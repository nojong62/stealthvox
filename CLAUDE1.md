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

# Claude Code 지시문 — Clone 모드 페르소나 역할 뒤집힘 수정 (A + B②)

## 0. 목표
Clone 모드에서 클론(예: 호진=아들)이 대화 중간에 부모/코치 말투로 뒤집히는 문제 해결.
원인은 ① 대화 히스토리를 `User:`/`AI:` 라벨의 통짜 `user` 블롭으로 넣어 턴 신호가 사라진 것, ② 정체성 고정이 약한 것.

수정 전략:
- **A. 구조화 턴**: `streamCloneResponse`의 messages 배열을 역할별 교대 턴(user/assistant)으로 재구성. 히스토리 소스는 화면 메시지(`_localMessages`, 오프너 포함).
- **B②. 강한 정체성 앵커**: 시스템 프롬프트 최상단에 `[IDENTITY LOCK]` 블록 추가.

> **Box 7 / TTS / Deepgram 엔진은 절대 건드리지 않음.** 수정 범위는 `CloneBrain.streamCloneResponse`와 그 호출부 1곳뿐.

---

## 1. 대상 파일 (단 하나)
```
lib/custom_code/widgets/routine_mode_clone.dart
```
⚠️ `lib/custom_code/임시/` 의 프리뷰 복사본은 절대 수정하지 말 것. 빌드 타깃은 `widgets/` 뿐.

수정 지점은 총 **4곳**입니다. 각 지점은 `str_replace`로 처리하며, 줄 번호는 참고용(앵커 문자열로 위치 식별).

---

## 2. 수정 #1 — `streamCloneResponse` 시그니처에 `history` 파라미터 추가

**삭제 범위:** 약 4070줄 `static Stream<String> streamCloneResponse({` 부터 4077줄 `}) async* {` 까지.

**str_replace old_str:**
```dart
  static Stream<String> streamCloneResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String cloneContext,
    required String myTarget,
    String cloneSummary = '',
  }) async* {
```

**str_replace new_str (교체 전문):**
```dart
  static Stream<String> streamCloneResponse({
    required String apiKey,
    required String userTargetText,
    required String contextStr,
    required String cloneContext,
    required String myTarget,
    String cloneSummary = '',
    List<Map<String, dynamic>> history = const [], // 🧩 [A] 구조화 교대 턴(오프너 포함). 비면 contextStr 블롭으로 폴백
  }) async* {
```

---

## 3. 수정 #2 — 시스템 프롬프트 최상단에 IDENTITY LOCK 추가 (B②)

**삭제 범위:** 약 4088줄 `2. If the persona contains Korean signature phrases...` 부터 4090줄 `$safePersona$summaryBlock` 까지(중간 빈 줄 포함).

**str_replace old_str:**
```dart
2. If the persona contains Korean signature phrases, translate them to natural $myTarget equivalents. Never quote the Korean text.

$safePersona$summaryBlock
```

**str_replace new_str (교체 전문):**
```dart
2. If the persona contains Korean signature phrases, translate them to natural $myTarget equivalents. Never quote the Korean text.

[IDENTITY LOCK — highest priority, overrides everything below]
- You ARE the one clone character described in the persona below. You speak ONLY as that single person, on every single turn.
- The other speaker (their lines arrive in the "user" role) is a DIFFERENT person — exactly the relationship the persona states (e.g. your father, your friend).
- NEVER switch sides. Do NOT answer as the user, as a parent, as a coach, or as a neutral helper — unless that role IS literally your own character.
- Even when the user sounds stressed, worried, or asks for reassurance, stay 100% in your character's own voice and viewpoint. Do NOT slip into a soothing helper tone like "I understand, just do your best."

$safePersona$summaryBlock
```

> 이 블록이 실제 관찰된 실패 패턴("I understand, just do your best")을 직접 금지합니다.

---

## 4. 수정 #3 — messages 배열을 구조화 교대 턴으로 재구성 (A)

**삭제 범위:** 약 4115줄 `request.body = jsonEncode({` 부터 4128줄 `});` 까지(messages 블롭 포함 전체).

**str_replace old_str:**
```dart
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
```

**str_replace new_str (교체 전문):**
```dart
      // 🧩 [A] messages 구성: history(구조화 교대 턴)가 있으면 역할별로 펼치고,
      //   비어 있으면 기존 단일 블롭(contextStr) 방식으로 폴백(무회귀).
      final List<Map<String, String>> messages = [
        {'role': 'system', 'content': sysPrompt},
      ];
      if (history.isNotEmpty) {
        for (final m in history) {
          final r = (m['role'] ?? '').toString();
          final c = (m['content'] ?? '').toString().trim();
          if (c.isEmpty) continue;
          messages.add({
            'role': r == 'assistant' ? 'assistant' : 'user',
            'content': c,
          });
        }
        // 현재 유저 입력을 마지막 user 턴으로 추가 (어시스턴트 응답이 이어짐)
        messages.add({'role': 'user', 'content': userTargetText});
      } else {
        messages.add({
          'role': 'user',
          'content':
              'Conversation history:\n$contextStr\n\nUser just said: "$userTargetText"\n\nYour brief reply:',
        });
      }

      request.body = jsonEncode({
        'model': 'gpt-4o-mini',
        'stream': true,
        'temperature': 0.2,
        'max_tokens': 80, // 🔧 핵심: 2문장 모델 레벨 강제
        'messages': messages,
      });
```

---

## 5. 수정 #4 — 호출부에서 구조화 히스토리 빌드 후 전달

이 수정은 두 부분입니다: (4-a) `cloneHistory` 빌드 블록 삽입, (4-b) 호출부에 `history:` 인자 추가.

### 4-a. `cloneHistory` 빌드 블록 삽입

**위치:** contextStr 빌드가 끝나는 지점(약 1874줄 `}`) 과 약 1876줄 `String userTargetText = "";` 사이에 삽입.

**str_replace old_str:**
```dart
            .join("\n");
      }

      String userTargetText = "";
```

**str_replace new_str (교체 전문):**
```dart
            .join("\n");
      }

      // 🧩 [A] 클론 응답용 구조화 히스토리(오프너 포함, 역할별 교대 턴).
      //   소스는 화면 메시지(_localMessages): HOST→user, SYSTEM(클론 발화)→assistant.
      //   빈 target / '...' / HOST_TEMP 는 제외. 현재 입력(빈 HOST 버블)은 자동 제외되고,
      //   streamCloneResponse가 마지막 user 턴으로 따로 추가함.
      List<Map<String, dynamic>> cloneHistory = _localMessages
          .where((m) {
            final role = (m['role'] ?? '').toString();
            if (role != 'HOST' && role != 'SYSTEM') return false;
            final t = (m['target'] ?? '').toString().trim();
            return t.isNotEmpty && t != '...';
          })
          .map<Map<String, dynamic>>((m) => <String, dynamic>{
                'role': (m['role'] == 'HOST') ? 'user' : 'assistant',
                'content': (m['target'] ?? '').toString().trim(),
              })
          .toList();
      // 화면 메시지가 비어 있으면(예: 세션 복원 직후) 장기기억으로 폴백
      if (cloneHistory.isEmpty && _recentHistory.isNotEmpty) {
        cloneHistory = _recentHistory
            .map<Map<String, dynamic>>((m) => <String, dynamic>{
                  'role': (m['role'] == 'assistant') ? 'assistant' : 'user',
                  'content': (m['content'] ?? '').toString().trim(),
                })
            .where((m) => (m['content'] as String).isNotEmpty)
            .toList();
      }

      String userTargetText = "";
```

### 4-b. 호출부에 `history:` 인자 추가

**삭제 범위:** 약 2048줄 `final aiStream = CloneBrain.streamCloneResponse(` 부터 2055줄 `);` 까지.

**str_replace old_str:**
```dart
      final aiStream = CloneBrain.streamCloneResponse(
        apiKey: _openAiKey,
        userTargetText: userTargetText,
        contextStr: latestContextStr,
        cloneContext: _selectedCloneContext,
        myTarget: targetLangName,
        cloneSummary: _cloneSummary,
      );
```

**str_replace new_str (교체 전문):**
```dart
      final aiStream = CloneBrain.streamCloneResponse(
        apiKey: _openAiKey,
        userTargetText: userTargetText,
        contextStr: latestContextStr,
        cloneContext: _selectedCloneContext,
        myTarget: targetLangName,
        cloneSummary: _cloneSummary,
        history: cloneHistory, // 🧩 [A] 구조화 교대 턴 전달
      );
```

---

## 6. 검증 (반드시 실행)

### 6-1. grep 카운트
```powershell
# 작업 디렉토리: F:\flutter_project\stealth_vox
$f = "lib\custom_code\widgets\routine_mode_clone.dart"

Select-String -Path $f -Pattern "IDENTITY LOCK" | Measure-Object        # 기대값: 1
Select-String -Path $f -Pattern "List<Map<String, dynamic>> history"    # 기대값: 1 (시그니처)
Select-String -Path $f -Pattern "cloneHistory" | Measure-Object         # 기대값: 4
Select-String -Path $f -Pattern "history: cloneHistory"                 # 기대값: 1
Select-String -Path $f -Pattern "'messages': messages,"                 # 기대값: 1
Select-String -Path $f -Pattern "Your brief reply:" | Measure-Object    # 기대값: 1 (폴백 분기에만 잔존)
```

### 6-2. 정적 분석
```powershell
flutter analyze lib\custom_code\widgets\routine_mode_clone.dart
```
- 신규 에러/경고 0 이어야 함.
- 특히 타입: `cloneHistory`(`List<Map<String,dynamic>>`)와 파라미터 `history`(`List<Map<String,dynamic>>`) 타입 일치 확인.

### 6-3. 런타임 동작 확인 (스테일 빌드 먼저 배제)
1. `flutter clean` 후 재빌드 (UI/로직 변경 미반영은 스테일 빌드가 1순위 원인).
2. Clone(호진) 새 방 진입 → 오프너 수신 → 아빠 입장으로 응답 → **클론이 아들 말투를 유지하는지** 확인.
3. 로그에서 GPT 첫 청크(`🧠 [PIPE-03]`)가 코치 말투("I understand...")가 아닌 캐릭터 발화인지 점검.

---

## 7. 롤백 절차
4개 str_replace를 역순으로 되돌리면 됨(모두 new_str↔old_str 교체):
1. 4-b 호출부에서 `history: cloneHistory,` 줄 제거
2. 4-a `cloneHistory` 빌드 블록 제거
3. 수정 #3 messages 블록을 원래 단일 블롭으로 복원
4. 수정 #2 `[IDENTITY LOCK]` 블록 제거
5. 수정 #1 시그니처에서 `history` 파라미터 줄 제거

> Git: `git checkout -- lib/custom_code/widgets/routine_mode_clone.dart` 로 일괄 복원 가능.

---

## 8. 적용 후 기대 동작
- 모델이 OpenAI 네이티브 턴 신호로 "assistant = 나 = 호진" 을 인식 → 코치/부모 말투로 빠지지 않음.
- `[IDENTITY LOCK]` 이 "I understand, just do your best" 류 위로 톤을 명시적으로 차단.
- 오프너 문맥이 첫 유저 턴부터 살아있어, 화면 속 그 뒤집힘 턴이 재현되지 않음.