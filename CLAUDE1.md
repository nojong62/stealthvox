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

# FREETALK_VOICE_NOEXPAND_v1 — 유저 목소리 분리 + 확장 문장 제거

## 목표
1. **목소리 분리**: AI TTS는 `nova` 고정, **유저 TTS는 로비 선택값(`FFAppState().aiVoice`)** 사용.
2. **확장 문장 제거**: 종료 시 확장/다듬기 생성(`[EXPAND-EXIT]`)을 없애고, 히스토리엔 대화 기록만 저장.
   (대화 본문은 이미 턴마다 `chat_history/messages` 서브컬렉션에 저장되므로 영향 없음)

## 대상 파일 (이 경로만)
```
lib/custom_code/widgets/routine_mode_free_talk.dart
```

## 사전 작업
```
git add -A && git commit -m "save before FREETALK_VOICE_NOEXPAND_v1"
```

---

## 편집 (아래→위 순서)

### EDIT 1 — 확장 문장 제거: `_handleAutoSaveAndExit()` 전체 교체 (1481~1605행)
삭제 시작: `  Future<void> _handleAutoSaveAndExit() async {`  (1481행)
삭제 끝:   `  }`  (1605행, 이 메서드의 닫는 중괄호 — 바로 다음이 빈 줄/주석)

> 제거 대상: `overlayShown` 변수, `[EXPAND-EXIT]` 블록(다이얼로그 "확장 문장 만드는 중..." +
> `generateExpandedFromConversation` + `polishSentence` 호출), `update()`의
> `expanded_sentence`/`polished_sentence`/`has_practice`/`expand_*` 필드, finally의 오버레이 pop.

**교체 코드 (전체)**
```dart
  Future<void> _handleAutoSaveAndExit() async {
    try {
      if (_myHistoryRef != null) {
        final hasUserTurn = _localMessages.any((m) => m['role'] == 'HOST');
        if (!hasUserTurn) {
          await _myHistoryRef!.delete();
          _log('🗑️ [HIST-DEL]', '빈 방 삭제 완료');
        } else {
          String lastText = "대화 기록 저장";
          for (int i = _localMessages.length - 1; i >= 0; i--) {
            final t = (_localMessages[i]['target'] ?? '').toString().trim();
            if (t.isNotEmpty && t != '...') {
              lastText = t;
              break;
            }
          }

          // 🆕 프리톡은 확장 문장 생성 안 함 → 대화 기록만 저장
          await _myHistoryRef!.update({
            'last_message': lastText,
            'last_message_time': FieldValue.serverTimestamp(),
            'msg_count': _localMessages.length,
            'last_active': FieldValue.serverTimestamp(),
            'mode': 'free_talk',
            'user_label': 'the user',
            'partner_label': 'AI partner',
          });
          _log('💾 [HIST-UPD]', 'last_message 저장 (free_talk, no expand)');
        }
      }
    } catch (e) {
      _log('❌ [HIST-EXIT-ERR]', '$e');
    } finally {
      if (mounted) {
        if (StealthRoomMaster.exitCurrentMode != null) {
          StealthRoomMaster.exitCurrentMode!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          context.goNamed('Lobby');
        }
      }
    }
  }
```
> `FreeTalkBrain.generateExpandedFromConversation` / `polishSentence` 메서드 정의는
> **그대로 둬도 무방**(roleplay도 정의만 남기고 미사용). 호출만 사라지면 됨.
> 미사용 경고(info)는 에러 아님.

---

### EDIT 2 — 유저 목소리를 로비 선택값으로 (992~997행)
삭제 시작: `      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(`  (992행)
삭제 끝:   `      );`  (997행, 이 fetcher 닫힘)

**BEFORE**
```dart
      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        "nova",
        onLog: _log,
      );
```

**AFTER**
```dart
      // 🆕 유저 목소리 = 로비에서 고른 값(FFAppState().aiVoice). AI는 nova 고정.
      final String userVoice = FFAppState().aiVoice.isNotEmpty
          ? FFAppState().aiVoice
          : 'onyx';
      ChunkedTtsFetcher userTtsFetcher = ChunkedTtsFetcher(
        _openAiKey,
        _ttsQueueManager,
        userVoice,
        onLog: _log,
      );
```
> AI측 TTS(580/872/1135행의 `"nova"`)는 **건드리지 않음** — nova 고정 유지.
> 히스토리 캐시 재생(875행)도 이번 범위 밖(요청은 라이브 유저 목소리 분리).

---

## 검증
```
grep -c "FFAppState().aiVoice" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 2
grep -c "generateExpandedFromConversation" lib/custom_code/widgets/routine_mode_free_talk.dart  # 기대값: 1 (정의만)
grep -c "overlayShown"            lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 0
grep -c "확장 문장 만드는 중"      lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 0
grep -c "expanded_sentence\|has_practice\|expand_source" lib/custom_code/widgets/routine_mode_free_talk.dart  # 기대값: 0
dart analyze lib/custom_code/widgets/routine_mode_free_talk.dart   # error 0 (unused method info만 허용)
```

## 롤백
```
git restore lib/custom_code/widgets/routine_mode_free_talk.dart
```

---

## 적용 후 동작
1. AI 응답은 `nova`, **내(유저) 문장 읽어주는 목소리는 로비에서 고른 목소리**로 달라짐.
   (로비 미경유로 `aiVoice`가 비면 `onyx`로 폴백)
2. 대화 종료 시 "확장 문장 만드는 중..." 다이얼로그/지연 사라짐 → 즉시 나가기.
3. 히스토리엔 프리톡 대화 기록만 남고 확장/연습(`has_practice`) 데이터는 안 생김.