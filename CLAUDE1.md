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

# 지시문: 애니원 모드 "1초 침묵 안내음" 전환

## 사전 준비 (코드 수정 전에 실행)

### STEP 0. 안내음 mp3 파일 사전 생성 (1회성, 로컬에서 실행)

문구가 고정이므로 런타임 API 호출 없이 **로컬 정적 에셋**으로 번들합니다. 아래 Python 스크립트를 실장님 PC에서 1회만 실행해서 mp3를 만드세요.

```python
# generate_nudge_audio.py
import requests

OPENAI_API_KEY = "본인 OpenAI 키"  # Remote Config 콘솔에서 복사해서 임시로 넣고 실행 후 지울 것
TEXT = "여기, 그 사람이 있어요. 편하게 말 걸어보세요."

resp = requests.post(
    "https://api.openai.com/v1/audio/speech",
    headers={
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json",
    },
    json={
        "model": "tts-1",
        "input": TEXT,
        "voice": "fable",
        "speed": 1.0,
    },
)
resp.raise_for_status()
with open("anyone_nudge_fable.mp3", "wb") as f:
    f.write(resp.content)
print("saved:", len(resp.content), "bytes")
```

실행 후 생성된 `anyone_nudge_fable.mp3`를 다음 경로에 배치:
```
F:\flutter_project\stealth_vox\assets\audio\anyone_nudge_fable.mp3
```

### STEP 0-1. pubspec.yaml 에셋 등록 (별도 파일 — Codex가 직접 확인 후 처리)

`pubspec.yaml`에서 기존 `flutter: assets:` 섹션을 grep으로 찾아 아래 라인이 없으면 추가:
```yaml
    - assets/audio/anyone_nudge_fable.mp3
```
(만약 `assets/audio/` 폴더 전체를 이미 통째로 등록하는 방식이면 이 단계는 스킵 — Codex가 기존 패턴 확인 후 판단)

---

## 코드 수정 (`routine_mode_anyone.dart`) — 반드시 아래 순서(파일 하단→상단)로 진행

### 사전 조치
```
git add -A && git commit -m "savepoint: before anyone-mode nudge sound change"
```

### Edit 1 (파일 최하단부터) — GPT 기반 오프너 생성 함수 삭제

**grep 확인 (count=1 기대):**
```
grep -c "static Stream<String> generateFreeTalkOpener({" routine_mode_anyone.dart
```

**old_str** (라인 3661~3724, 위 구분선 주석부터 함수 끝까지 통째로):
```dart
  // ==================================================================
  static Stream<String> generateFreeTalkOpener({
    required String apiKey,
    required String targetLang,
    String level = "Intermediate",
  }) async* {
    final client = http.Client();
    try {
      final sysPrompt =
          """You are about to be spoken to by the user, as if you are a specific person they have in mind — but you do not know who yet.
Open with ONE short, warm line that simply lets them begin, as if you happen to be right there in front of them.

RULES:
- Speak ONLY in $targetLang. Do NOT use Korean or any other language.
- ONE sentence only. Under 12 words.
- Neutral and natural — do NOT assume any relationship, mood, or role yet. No names, no labels.
- Just open the door for them to speak first. For example: "Hey... I'm right here. What did you want to say?" or "I'm listening — go ahead."
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
}
```

**new_str**:
```dart
}
```
*(클래스 닫는 중괄호만 남기고 함수 전체 제거)*

---

### Edit 2 — `_generateAndPlayAiOpener` 함수 및 상단 주석 블록 삭제

**grep 확인 (count=1 기대):**
```
grep -c "Future<void> _generateAndPlayAiOpener() async {" routine_mode_anyone.dart
```

**old_str** (라인 441~554, 주석 블록 + 함수 전체):
```dart
  // ====================================================================
  // 📦 [AI 첫 발화 — AI가 먼저 대화 시작]
  // ====================================================================
  // 클론 대화 시작 원칙:
  //   1. AI가 항상 먼저 말한다 — 화면 진입 시 클론이 자동으로 먼저 발화.
  //   2. 타겟 언어로만 말한다 — 한국어 절대 혼용 금지.
  //   3. 클론 페르소나에 충실한 자연스러운 첫 마디 (AI 티 내지 않음).
  // ====================================================================
  Future<void> _generateAndPlayAiOpener() async {
```
*(이하 554라인 `}`까지 전체 — 파일이 길어 str_replace 시 449~554 전체 텍스트를 old_str로 그대로 사용)*

**new_str**:
```dart
  // ====================================================================
  // 📦 [1초 침묵 안내음] — GPT 오프너 대신 사전 생성된 고정 mp3 재생
  // ====================================================================
  Future<void> _playNudgeSound() async {
    if (_hasPlayedNudge) return;
    _hasPlayedNudge = true;
    try {
      await _nudgeAudioPlayer.play(AssetSource('audio/anyone_nudge_fable.mp3'));
    } catch (e) {
      _log('❌ [NUDGE-SOUND-ERR]', '$e');
    }
  }
```

> ⚠️ Codex 주의: old_str이 100줄 넘게 길어 grep 앵커만으로 정확히 잘라내기 까다로우면, `view routine_mode_anyone.dart` 449 554로 실제 라인을 재확인한 뒤 그 구간 전체를 old_str에 그대로 복사해서 사용할 것.

---

### Edit 3 — `_armOpenerNudge`: 2초→1초, AI 음성 대신 안내음 재생

**grep 확인 (count=1 기대):**
```
grep -c "void _armOpenerNudge() {" routine_mode_anyone.dart
```

**old_str**:
```dart
  void _armOpenerNudge() {
    _openerNudgeTimer?.cancel();
    _openerNudgeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_isConversationActive) return;
      if (_userHasSpoken || _localMessages.isNotEmpty) return;
      _log('💡 [NUDGE]', '2초 침묵 → AI 오프너 발화');
      _voiceManager?.dispose();
      _voiceManager = null;
      _generateAndPlayAiOpener();
    });
  }
```

**new_str**:
```dart
  void _armOpenerNudge() {
    _openerNudgeTimer?.cancel();
    _openerNudgeTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || !_isConversationActive) return;
      if (_userHasSpoken || _localMessages.isNotEmpty) return;
      _log('💡 [NUDGE]', '1초 침묵 → 안내음 재생 (마이크 유지)');
      _playNudgeSound();
    });
  }
```

*(마이크를 끊지 않으므로 `_voiceManager?.dispose()` 호출 제거)*

---

### Edit 4 — `_stopEverything`: 플래그명 교체

**grep 확인 (count=1 기대):**
```
grep -c "_isAiOpenerPlaying = false;" routine_mode_anyone.dart
```

**old_str**:
```dart
    _isConversationActive = false;
    _isAiOpenerPlaying = false;
    _isStartingListening = false;
```

**new_str**:
```dart
    _isConversationActive = false;
    _hasPlayedNudge = false;
    _isStartingListening = false;
```

---

### Edit 5 — `_startFreeTalkSession`: 안내음 가드 초기화 추가

**grep 확인 (count=1 기대, 문맥 포함):**
```
grep -c "if (_isConversationActive) return; // 중복 시작 방지" routine_mode_anyone.dart
```

**old_str**:
```dart
    if (_isConversationActive) return; // 중복 시작 방지
    _userHasSpoken = false;
    _startDeepgramListening();
```

**new_str**:
```dart
    if (_isConversationActive) return; // 중복 시작 방지
    _userHasSpoken = false;
    _hasPlayedNudge = false;
    _startDeepgramListening();
```

---

### Edit 6 — 상단 변수 선언부 교체 (플래그 + 오디오 플레이어)

**grep 확인 (count=1 기대):**
```
grep -c "bool _isAiOpenerPlaying = false; // AI 첫 발화 재생 중 여부" routine_mode_anyone.dart
```

**old_str**:
```dart
  bool _isAiOpenerPlaying = false; // AI 첫 발화 재생 중 여부
```

**new_str**:
```dart
  bool _hasPlayedNudge = false; // 🆕 [1초 침묵 안내음] 세션당 1회 재생 가드
  final AudioPlayer _nudgeAudioPlayer = AudioPlayer(); // 🆕 [1초 침묵 안내음] 전용 플레이어
```

---

### Edit 7 — dispose()에 안내음 플레이어 정리 추가

**grep 확인 (count=1 기대):**
```
grep -c "_audioRecorder.dispose();" routine_mode_anyone.dart
```

**old_str**:
```dart
    _audioRecorder.dispose();
```

**new_str**:
```dart
    _audioRecorder.dispose();
    _nudgeAudioPlayer.dispose();
```

---

## 마무리 절차

1. 모든 Edit 후 **post-grep 검증**: `_generateAndPlayAiOpener`, `generateFreeTalkOpener`, `_isAiOpenerPlaying` 세 문자열이 파일에 0건 남아있는지 확인
2. `dart format routine_mode_anyone.dart` (해당 파일 단독)
3. 빌드 검증 (`flutter analyze` → `flutter run` 실환경 1회 확인: 마이크 열고 1초 무음 시 안내음만 나오고 마이크 안 끊기는지, 두 번째 트리거 안 나가는지)
4. 문제 없으면 커밋: `git add -A && git commit -m "feat: anyone mode 1s-silence nudge sound (replaces GPT voice opener)"`
5. 문제 있으면 `git reset --hard HEAD~1` 로 즉시 롤백

---
