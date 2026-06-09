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

# StealthVox — Free Talk Deepgram 400 무한 재연결 수정

## 증상
앱 실행 시 Deepgram WebSocket이 계속 끊기며 무한 재연결("DG-WS-ERR / DG-RETRY" 반복). STT가 전혀 동작하지 않음.

로그:
```
❌ [DG-WS-ERR] ... Connection to '...utterance_end_ms=900...' was not upgraded to websocket, HTTP status code: 400
```

## 원인 (확정)
**Deepgram `utterance_end_ms` 파라미터는 최소 1000ms 이상이어야 한다.** 현재 값이 `900`이라 Deepgram이 연결 요청을 `400 Bad Request`로 거부하고, 400은 재연결해도 동일하게 거부되므로 무한 루프에 빠진다.

원본(정상 동작)에서는 이 값이 `1200`이었고, Codex 수정 과정에서 `900`으로 낮아지면서 깨졌다. URL의 나머지 파라미터·괄호·상수는 모두 정상이다.

## 대상 파일 (정확히 이 경로만)
```
lib/custom_code/widgets/routine_mode_free_talk.dart
```
**`lib/custom_code/임시/` 아래 파일은 절대 건드리지 말 것.**

## 작업 전
- `git commit -am "save point before FREETALK_DEEPGRAM_400_FIX"`

## 수정 — 상수 한 줄 (약 44번 줄)

### str_replace

**old_str**:
```dart
const int kFreeTalkDeepgramUtteranceEndMs = 900;
```

**new_str**:
```dart
const int kFreeTalkDeepgramUtteranceEndMs = 1000; // 🔧 Deepgram 최소 허용값 1000ms (900은 400 거부 → 무한 재연결)
```

> 참고: `endpointing=700`(2104번 줄)은 1000ms 제한이 없는 별개 파라미터이고 정상이므로 건드리지 않는다. 반응속도는 주로 `endpointing`이 좌우하므로 `utterance_end_ms`를 1000으로 올려도 체감 반응속도 손해는 거의 없다. 더 빠르게 하고 싶으면 추후 `endpointing` 값을 조정한다.

## 절대 건드리지 말 것 (Do NOT touch)
- Deepgram URL의 다른 파라미터(`model`, `language`, `endpointing`, `encoding`, `sample_rate`, `channels`, `filler_words`) — 전부 정상.
- 재연결 로직(`_handleDisconnect`, `DG-RETRY`) — utterance_end_ms를 고치면 400이 사라져 루프도 멈춘다. 이번엔 손대지 않는다.
- 그 외 모든 로직.

## 검증

### 1) grep
```powershell
grep -c "kFreeTalkDeepgramUtteranceEndMs = 1000" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 1
grep -c "kFreeTalkDeepgramUtteranceEndMs = 900"  lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 0
```

### 2) flutter analyze
```powershell
flutter analyze lib/custom_code/widgets/routine_mode_free_talk.dart
```
- 신규 error 0건.

## 롤백
- `git restore lib/custom_code/widgets/routine_mode_free_talk.dart`

## 실기기 확인
1. 앱 실행 시 `❌ [DG-WS-ERR] ... HTTP status code: 400` 이 **더 이상 안 뜨는지**.
2. `📡 [DG-02] Metadata 수신 → onConnected` 가 정상적으로 뜨고 STT(음성 인식)가 동작하는지.
3. 무한 `DG-RETRY` 루프가 사라졌는지.