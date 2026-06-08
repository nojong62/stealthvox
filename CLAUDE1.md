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

# FREETALK_USER_FIRST_v1 — 유저 먼저(2초 grace) + 오프너 발화

## 목표
프리톡 불빛 ON 시 **유저가 먼저 말할 수 있게 마이크부터 켜고**, 2초 동안 침묵하면 AI가
**타겟 언어로 "자유롭게 대화하자"** 한마디를 발화한다. (StepExpand의 User-First 패턴 응용)

## 대상 파일 (반드시 이 경로만)
```
lib/custom_code/widgets/routine_mode_free_talk.dart
```
> `lib/custom_code/임시/` 는 FlutterFlow 프리뷰 전용 — 절대 수정 금지.

## 사전 작업 (세이브 포인트)
```
git add -A && git commit -m "save before FREETALK_USER_FIRST_v1"
```

---

## 편집 (반드시 아래→위 순서로, 줄밀림 방지)

### EDIT 1 — 오프너 프롬프트 교체 (약 3276~3283행)
삭제 시작: `          """You are a warm, friendly conversation partner starting a casual chat.`
삭제 끝:   `- Avoid a bare "Hello" or "Hi". Say something that invites a reply, for example: "Hey, how's your day going so far?" or "So, what have you been up to lately?"`

**BEFORE**
```dart
          """You are a warm, friendly conversation partner starting a casual chat.
Open with ONE short, natural line that invites the user to talk — like a friend would.

RULES:
- Speak ONLY in $targetLang. Do NOT use Korean or any other language.
- ONE sentence only. Under 12 words.
- Sound natural and friendly, never like an AI or a survey.
- Avoid a bare "Hello" or "Hi". Say something that invites a reply, for example: "Hey, how's your day going so far?" or "So, what have you been up to lately?"
```

**AFTER**
```dart
          """You are a warm, friendly conversation partner kicking off a casual, no-pressure chat.
Open with ONE short, natural line that invites the user to chat freely about anything.

RULES:
- Speak ONLY in $targetLang. Do NOT use Korean or any other language.
- ONE sentence only. Under 12 words.
- Relaxed and friendly, like a close friend — never like an AI or a survey.
- Convey the feeling of "let's just chat freely about whatever you like." For example: "Let's just chat freely — what's on your mind?" or "We can talk about anything you like, so what's up?"
```
> `- ${_freeTalkLevelInstruction(level)}` 와 `Output: ...""";` 줄은 그대로 둔다.

---

### EDIT 2 — 탭 핸들러 단순화 (약 1868~1876행)
삭제 시작: `                  if (_isConversationActive) {`
삭제 끝:   `                  }`  (else { _stopEverything(); } 닫는 중괄호)

**BEFORE**
```dart
                  if (_isConversationActive) {
                    if (_localMessages.isEmpty) {
                      _generateAndPlayAiOpener();
                    } else {
                      _startDeepgramListening();
                    }
                  } else {
                    _stopEverything();
                  }
```

**AFTER**
```dart
                  if (_isConversationActive) {
                    // 🆕 [유저 먼저] 항상 마이크부터 켠다. 첫 턴 2초 grace는
                    //     _startDeepgramListening 내부에서 처리.
                    _userHasSpoken = false;
                    _startDeepgramListening();
                  } else {
                    _stopEverything();
                  }
```

---

### EDIT 3 — connectAndStart 직후 nudge 가동 + 새 메서드 추가 (약 711~714행)
삭제 시작: `    _log('🎤 [LISTEN-04]', 'connectAndStart 호출 직전');`
삭제 끝:   `  }`  (`_startDeepgramListening` 닫는 중괄호, 714행)

**BEFORE**
```dart
    _log('🎤 [LISTEN-04]', 'connectAndStart 호출 직전');
    await _voiceManager!.connectAndStart();
    _log('🎤 [LISTEN-05]', 'connectAndStart 완료');
  }
```

**AFTER**
```dart
    _log('🎤 [LISTEN-04]', 'connectAndStart 호출 직전');
    await _voiceManager!.connectAndStart();
    _log('🎤 [LISTEN-05]', 'connectAndStart 완료');

    // 🆕 [유저 먼저] 첫 턴이고 유저가 아직 말 안 했으면 2초 grace 후 AI가 운을 뗌
    if (_localMessages.isEmpty && !_userHasSpoken) {
      _armOpenerNudge();
    }
  }

  // 🆕 [유저 먼저 → 2초 침묵 시 AI 오프너]
  // 마이크가 살아있는 상태에서 2초 grace. 그 안에 유저가 말하면
  // (onTranscriptUpdate에서 _userHasSpoken=true + 타이머 취소) 오프너는 안 나가고,
  // 침묵하면 마이크를 잠깐 내리고 AI가 "자유롭게 대화하자" 한마디.
  // (오프너 finally에서 _startDeepgramListening으로 청취 재개)
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

---

### EDIT 4 — onTranscriptUpdate에서 nudge 취소 (약 697~700행)
삭제 시작: `      onTranscriptUpdate: (transcript) {`
삭제 끝:   `      },`

**BEFORE**
```dart
      onTranscriptUpdate: (transcript) {
        _swDeepgram.reset();
        _swDeepgram.start();
      },
```

**AFTER**
```dart
      onTranscriptUpdate: (transcript) {
        // 🆕 [유저 먼저] 유저가 입을 떼는 순간 오프너 nudge 취소
        if (!_userHasSpoken) {
          _userHasSpoken = true;
          _openerNudgeTimer?.cancel();
        }
        _swDeepgram.reset();
        _swDeepgram.start();
      },
```

---

### EDIT 5 — 오프너 무음 방지 가드 (약 530~532행)
삭제 시작: `  Future<void> _generateAndPlayAiOpener() async {`
삭제 끝:   `    _isAiOpenerPlaying = true;`

**BEFORE**
```dart
  Future<void> _generateAndPlayAiOpener() async {
    if (_isAiOpenerPlaying) return;
    _isAiOpenerPlaying = true;
```

**AFTER**
```dart
  Future<void> _generateAndPlayAiOpener() async {
    if (_isAiOpenerPlaying) return;
    // 🆕 키 미로딩 상태에서 발화 시도 → 무음 방지
    if (_openAiKey.isEmpty) {
      _log('⚠️ [OPENER]', 'OpenAI key not ready — skip opener');
      return;
    }
    _isAiOpenerPlaying = true;
```

---

### EDIT 6 — _stopEverything에서 nudge 타이머 정리 (약 513~514행)
삭제 시작: `    _commitTimer?.cancel(); // 🔧 [v3.4] 대기 중 타이머 정리`
삭제 끝:   `    _commitTimer = null;`

**BEFORE**
```dart
    _commitTimer?.cancel(); // 🔧 [v3.4] 대기 중 타이머 정리
    _commitTimer = null;
```

**AFTER**
```dart
    _commitTimer?.cancel(); // 🔧 [v3.4] 대기 중 타이머 정리
    _commitTimer = null;
    _openerNudgeTimer?.cancel(); // 🆕 [유저 먼저] 오프너 nudge 정리
    _openerNudgeTimer = null;
```
> `dispose()`는 내부에서 `_stopEverything()`를 호출하므로 별도 수정 불필요.

---

### EDIT 7 — 상태 변수 추가 (66행 바로 아래)
삭제 시작: `  bool _isAiOpenerPlaying = false; // AI 첫 발화 재생 중 여부`
삭제 끝:   (동일 줄)

**BEFORE**
```dart
  bool _isAiOpenerPlaying = false; // AI 첫 발화 재생 중 여부
```

**AFTER**
```dart
  bool _isAiOpenerPlaying = false; // AI 첫 발화 재생 중 여부

  // 🆕 [유저 먼저] 2초 grace 동안 유저가 말 안 하면 AI가 오프너 발화
  Timer? _openerNudgeTimer;
  bool _userHasSpoken = false;
```

---

## 검증
```
grep -c "_openerNudgeTimer" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 6
grep -c "_userHasSpoken"     lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 6
grep -c "_armOpenerNudge"    lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 2
grep -c "_generateAndPlayAiOpener" lib/custom_code/widgets/routine_mode_free_talk.dart  # 기대값: 2
grep -c "chat freely"        lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 2
flutter analyze
```
- `flutter analyze`: 신규 에러 0건이어야 함.

## 롤백
```
git restore lib/custom_code/widgets/routine_mode_free_talk.dart
```

## 동작 체크리스트
1. 불빛 ON → 즉시 마이크 청취(노란 불빛), 소리 없음.
2. 2초 안에 말하면 → 오프너 안 나오고 바로 유저 턴 처리.
3. 2초 침묵하면 → AI가 타겟 언어로 "자유롭게 대화하자" 한마디 → 끝나면 다시 청취.
4. 키 로딩 전 빠르게 탭 시 → 무음으로 죽지 않고 오프너 스킵(로그만).