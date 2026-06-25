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

# VOICE_POLICY_FIX_v1 — 라이브 대화 되읽기 보이스 정책 정합화

## 목표 (정책)
- **내 발화 / 호스트 본인 = My Voice = `FFAppState().aiVoice`** (로비 선택값, fallback `'echo'`)
- **상대역(AI) / 듀오 상대방 = `'nova'` 고정**
- History · P1/P2/P3(에코잉 리드)는 **이미 정책과 일치** → 손대지 않음

## 수정 대상 3건 (전부 호출부 인자 1줄 단위, Box 7 무손상)
| # | 파일 | 위치 | 변경 |
|---|---|---|---|
| 1 | routine_mode_step_expand.dart | 유저턴 fetcher+hybrid | `'nova'` → `userVoice` |
| 2 | routine_mode_roleplay.dart | 유저턴 fetcher | `'nova'` → `userVoice` |
| 3 | routine_mode_duo.dart | 상대 말풍선 | `_myVoice()` → `'nova'` |

> ⚠️ Box 7 클래스(`TtsQueueManager`, `DeepgramV2VoiceManager`, `ChunkedTtsFetcher`, `HybridTtsPlayer`, `TtsCache`)는 **절대 수정 금지**. 본 작업은 전부 호출부 **인자값만** 바꾼다.

---

## PHASE 0 — 세이브포인트
```bash
git add -A && git commit -m "savepoint before VOICE_POLICY_FIX_v1"
```

---

## PHASE 1 — 파일 경로 + 앵커 발견 (편집 전 반드시 카운트 확인)

```bash
# (a) step_expand / roleplay 유저턴 앵커 — 각 파일에서 1건씩이어야 함
grep -rn "ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(" lib/custom_code/

# (b) duo 상대 말풍선 앵커 — duo 파일에서 1건이어야 함
grep -rn "if (bytes != null && _isConversationActive && !_isExiting) {" lib/custom_code/

# (c) duo _myVoice() 호출 현황 — 편집 전 '3건'( 정의 1 + 내말풍선 1 + 상대말풍선 1 )
grep -rn "_myVoice()" lib/custom_code/routine_mode_duo.dart
```

**진행 조건**: (a)가 step_expand·roleplay에서 각 1건, (b)가 duo에서 1건, (c)가 duo에서 3건이면 OK. 카운트가 다르면 **중단하고 보고**.

---

## PHASE 2 — 편집 (아래→위 순서로 적용)

### EDIT 3 — duo 상대 말풍선: `_myVoice()` → `'nova'`
파일: `lib/custom_code/routine_mode_duo.dart`

**old_str**
```dart
    // 내 타겟 소리로 재생 (직렬화)
    _rememberGenerated(tgt);
    _rememberGenerated(org);
    final Uint8List? bytes = await _fetchTTSBytes(tgt, _myVoice());
    if (bytes != null && _isConversationActive && !_isExiting) {
```

**new_str**
```dart
    // 🎙️ 상대 말풍선 소리 재생 (직렬화) — 상대방은 nova 고정
    //    (내 목소리=FFAppState().aiVoice 는 호스트 본인 발화에만 사용)
    _rememberGenerated(tgt);
    _rememberGenerated(org);
    final Uint8List? bytes = await _fetchTTSBytes(tgt, 'nova');
    if (bytes != null && _isConversationActive && !_isExiting) {
```

> 내 말풍선(상단의 `// 5. 내 타겟 소리 재생 (직렬화)` 블록, `_fetchTTSBytes(tgt, _myVoice())`)은 **그대로 둔다.** 위 앵커의 `!_isExiting` 한 줄 `if` 가 상대 말풍선 블록을 유일하게 식별한다.

---

### EDIT 2 — roleplay 유저턴: `'nova'` → `userVoice`
파일: `lib/custom_code/routine_mode_roleplay.dart`

**old_str**
```dart
      String userTargetText = "";
      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        "nova",
        onLog: _log,
      );
      _ttsQueueManager.setUserTurn(true);
```

**new_str**
```dart
      String userTargetText = "";
      // 🎙️ 유저 목소리 = 로비 선택값(FFAppState().aiVoice). AI는 nova 고정.
      final String userVoice =
          FFAppState().aiVoice.isNotEmpty ? FFAppState().aiVoice : 'echo';
      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        userVoice,
        onLog: _log,
      );
      _ttsQueueManager.setUserTurn(true);
```

> roleplay 유저턴에는 `HybridTtsPlayer` 가 없다(확인됨). fetcher 한 곳만 교체.

---

### EDIT 1 — step_expand 유저턴: `'nova'` → `userVoice` (fetcher + hybrid 동시)
파일: `lib/custom_code/routine_mode_step_expand.dart`

**old_str**
```dart
      String userTargetText = "";
      String userBuffer = "";
      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        "nova",
        onLog: _log,
      );
      final HybridTtsPlayer userHybridTts = HybridTtsPlayer(
        apiKey: _openAiKey,
        voice: 'nova',
        onLog: _log,
      );
```

**new_str**
```dart
      String userTargetText = "";
      String userBuffer = "";
      // 🎙️ 유저 목소리 = 로비 선택값(FFAppState().aiVoice). AI는 nova 고정.
      final String userVoice =
          FFAppState().aiVoice.isNotEmpty ? FFAppState().aiVoice : 'echo';
      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        userVoice,
        onLog: _log,
      );
      final HybridTtsPlayer userHybridTts = HybridTtsPlayer(
        apiKey: _openAiKey,
        voice: userVoice,
        onLog: _log,
      );
```

> `String userBuffer = "";` 가 직전에 오는 블록은 이 유저턴 1곳뿐이라 유일하게 식별된다. AI 응답부의 다른 `'nova'` 들은 건드리지 않는다.

---

## PHASE 3 — 검증 (기대 카운트)

```bash
# 1) step_expand: userVoice 토큰 3건(선언1 + fetcher1 + hybrid1)
grep -c "userVoice" lib/custom_code/routine_mode_step_expand.dart        # 기대: 3

# 2) roleplay: userVoice 토큰 2건(선언1 + fetcher1)
grep -c "userVoice" lib/custom_code/routine_mode_roleplay.dart           # 기대: 2

# 3) duo: 상대 말풍선이 nova가 됐는지 / _myVoice() 호출이 2건으로 줄었는지
grep -c "_fetchTTSBytes(tgt, 'nova')" lib/custom_code/routine_mode_duo.dart   # 기대: 1
grep -c "_myVoice()" lib/custom_code/routine_mode_duo.dart                    # 기대: 2 (정의1 + 내말풍선1)

# 4) 유저턴에 'nova' 잔존 없는지 (각 파일 유저턴 라인 주변 육안 확인)
grep -n "userTtsFetcher = ChunkedTtsFetcher(" -A4 lib/custom_code/routine_mode_step_expand.dart
grep -n "userTtsFetcher = ChunkedTtsFetcher(" -A4 lib/custom_code/routine_mode_roleplay.dart
```

이어서 분석 게이트 + 개별 파일 포맷(폴더 금지):
```bash
flutter analyze lib/custom_code/routine_mode_step_expand.dart
flutter analyze lib/custom_code/routine_mode_roleplay.dart
flutter analyze lib/custom_code/routine_mode_duo.dart

dart format lib/custom_code/routine_mode_step_expand.dart
dart format lib/custom_code/routine_mode_roleplay.dart
dart format lib/custom_code/routine_mode_duo.dart
```
> ⚠️ `dart format` 은 **반드시 개별 파일만**. 폴더 대상 금지(한글 문자열 UTF-8 손상 위험).

---

## 기대 동작 (적용 후)
- **대화방 Expand / Roleplay**: 내 발화 되읽기 = 로비에서 고른 My Voice(echo/onyx/fable), AI 질문/확장 = nova.
- **Duo**: 내 말풍선 = My Voice, 상대 말풍선 = nova (양쪽 화자 음성 구분됨).
- **History / P1·P2·P3**: 변화 없음(기존 정상).

---

## 롤백
```bash
# 아직 push 전:
git reset --hard HEAD~1
# 이미 push 했다면:
git revert <savepoint_커밋_해시>
```