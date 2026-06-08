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

# FREETALK_AUTOSTART_v1 — 진입 시 자동 시작 + 점은 표시등(버튼 아님)

## 원인
- 점(불빛)은 **작동 표시등**이지 버튼이 아님. 그런데 free_talk는 시작 로직이 **점 탭**에 묶여 있어
  진입해도 자동 시작이 안 됨 → `_startDeepgramListening` 미실행 → 소리/입력/글자/로그 전부 0.
- StepExpand는 **키 로드 완료 → `addPostFrameCallback` → 세션 자동 시작**(마이크 버튼 없음, 하단은 표시등만).

## 이 패치가 하는 일 (StepExpand 패턴 정렬)
1. `_fetchKeys`가 키를 받은 직후 `_startFreeTalkSession()`을 자동 호출 → 진입하면 스스로 시작.
   (키 로드 후 시작하므로 race 자체가 사라짐)
2. `_startFreeTalkSession()`은 `_startDeepgramListening()`을 호출 → `_isConversationActive=true`로
   **점이 자동 점등**, 마이크 청취 시작, 첫 턴 2초 grace 무장(기존 v1 로직 그대로 활용).
3. 점에서 `GestureDetector(onTap)` 제거 → **순수 표시등**으로 전환.

> v1에서 만든 `_userHasSpoken` / `_openerNudgeTimer` / `_armOpenerNudge` / 오프너 프롬프트는 **그대로 유지**.
> 이 패치는 "시작 방식"만 점 탭 → 자동으로 교정함. (정지는 기존대로 뒤로가기 → AutoSave)

## 대상 파일 (이 경로만)
```
lib/custom_code/widgets/routine_mode_free_talk.dart
```

## 사전 작업
```
git add -A && git commit -m "save before FREETALK_AUTOSTART_v1"
```

---

## 편집 (아래→위 순서)

### EDIT 1 — 점을 패시브 표시등으로 (1900~1936행)
삭제 시작: `              GestureDetector(`  (1900행)
삭제 끝:   `              ),`  (1936행, 해당 GestureDetector 닫힘 — 바로 다음 줄이 `            ],`)

**BEFORE**
```dart
              GestureDetector(
                onTap: () {
                  if (_deepgramKey.isEmpty) return;
                  _resetIdleTimer();
                  setState(
                      () => _isConversationActive = !_isConversationActive);
                  if (_isConversationActive) {
                    // 🆕 [유저 먼저] 항상 마이크부터 켠다. 첫 턴 2초 grace는
                    //     _startDeepgramListening 내부에서 처리.
                    _userHasSpoken = false;
                    _startDeepgramListening();
                  } else {
                    _stopEverything();
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isConversationActive
                          ? const Color(0xFFFBBF24)
                          : Colors.transparent,
                      border: Border.all(
                        color: _isConversationActive
                            ? const Color(0xFFFBBF24)
                            : Colors.white24,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
```

**AFTER**
```dart
              // 🆕 작동 표시등(패시브). 버튼 아님 — 세션 활성 시 자동 점등.
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConversationActive
                        ? const Color(0xFFFBBF24)
                        : Colors.transparent,
                    border: Border.all(
                      color: _isConversationActive
                          ? const Color(0xFFFBBF24)
                          : Colors.white24,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
```

---

### EDIT 2 — `_fetchKeys` 뒤에 자동 시작 체인 + 새 메서드 (273~286행)
삭제 시작: `  Future<void> _fetchKeys() async {`  (273행)
삭제 끝:   `  }`  (286행, `_fetchKeys` 닫는 중괄호 — 바로 다음 줄이 빈 줄, 그 다음이 `// ====`)

**BEFORE**
```dart
  Future<void> _fetchKeys() async {
    try {
      await FirebaseRemoteConfig.instance.fetchAndActivate();
      if (mounted) {
        setState(() {
          _deepgramKey =
              FirebaseRemoteConfig.instance.getString('DeepgramAPIKey');
          _openAiKey = FirebaseRemoteConfig.instance.getString('OpenAIAPIKey');
        });
      }
    } catch (e) {
      print('❌ Key Load Error: $e');
    }
  }
```

**AFTER**
```dart
  Future<void> _fetchKeys() async {
    try {
      await FirebaseRemoteConfig.instance.fetchAndActivate();
      if (mounted) {
        setState(() {
          _deepgramKey =
              FirebaseRemoteConfig.instance.getString('DeepgramAPIKey');
          _openAiKey = FirebaseRemoteConfig.instance.getString('OpenAIAPIKey');
        });
        // 🆕 키 로드 완료 → 세션 자동 시작 (StepExpand 패턴). race 제거.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startFreeTalkSession();
        });
      }
    } catch (e) {
      print('❌ Key Load Error: $e');
    }
  }

  /// 🆕 세션 자동 시작: 표시등 ON + 마이크 먼저(유저 먼저 말하게).
  /// 마이크 청취가 시작되면 _isConversationActive=true → 점 자동 점등.
  /// 첫 턴 2초 침묵 시 _armOpenerNudge가 AI 오프너를 발화(v1 로직).
  Future<void> _startFreeTalkSession() async {
    if (_deepgramKey.isEmpty || !mounted) return;
    if (_isConversationActive) return; // 중복 시작 방지
    _userHasSpoken = false;
    _startDeepgramListening();
  }
```

---

## 검증
```
grep -c "_startFreeTalkSession" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 2
grep -c "_isConversationActive = !_isConversationActive" lib/custom_code/widgets/routine_mode_free_talk.dart  # 기대값: 0
grep -c "onTap: () {" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 1 (레벨 토글만 남음)
flutter analyze
```
- `flutter analyze`: 신규 에러 0건.

## 롤백
```
git restore lib/custom_code/widgets/routine_mode_free_talk.dart
```

---

## 적용 후 동작
1. Free Talk 진입 → 키 로드 끝나면 **자동으로 점이 노랗게 점등** + 마이크 청취 시작.
2. 2초 안에 말하면 → 그 발화로 진행(글자/AI 응답/소리).
3. 2초 침묵 → AI가 타겟 언어로 "자유롭게 대화하자" 한마디 → 다시 청취.
4. 정지는 뒤로가기(AutoSave). 점은 손대지 않는 표시등.
5. 로그 팝업엔 이제 `[LISTEN-01]`부터 정상적으로 쌓임.