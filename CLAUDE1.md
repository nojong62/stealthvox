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

=== StealthVox 과금 정책 정비 + 오토포즈 보강 (일괄 작업) ===

[전제 / 절대 금지]
- Box 7(TtsQueueManager, DeepgramV2VoiceManager) 일체 수정 금지
- 라인 번호는 근사치 → 반드시 현재 파일을 직접 읽고 위치 확정 후 작업
- 작업 후 flutter analyze 에러 0 확인

────────────────────────────────────────
파일 1: chat_history_master.dart
────────────────────────────────────────

[작업 1] 확장문장/Polished 연습 진입 시 full(100%) 전환
- 위치 A: _enterShadowing(...) 함수 (약 920행).
  setState로 _phase = ShadowingPhase.chunkPractice 를 지정하는 블록(약 960행) 직전에 추가:
      BillingTicker.instance.setRate(BillingRate.full);
- 위치 B: _enterShadowingFromRoom() 의 Step Expand 분기
  (roomMode == 'step_expand' || (roomMode.isEmpty && (polished/expanded 존재)) 블록, 약 447~484행).
  _phase = ShadowingPhase.variantSelect 를 지정하는 setState 직전에 추가:
      BillingTicker.instance.setRate(BillingRate.full);
- 주의: 같은 함수의 "Tutor 모드 분기"(turnPractice, 약 514행)에는 추가 금지.
  이 경로는 quarter 유지(원문 대화 섀도잉 = 25%).

[작업 2] 연습 이탈 시 quarter(25%) 복귀
- 위치: _exitShadowing() 함수 (약 1127행) 시작부, _deleteUserRecordings(); 호출 직후에 추가:
      BillingTicker.instance.setRate(BillingRate.quarter);

[작업 3] 오토포즈 busy 감지 보강
- 위치: bool get _isSystemBusy 게터 (약 193~200행).
- 최종 형태:
      bool get _isSystemBusy {
        return _isTutorPlaying ||
            isPlaying ||
            _appIsRecording ||
            _appIsShadowRecording ||
            _isPlayingAppAudio ||
            _isAutoRecording ||
            _tutorUserRecording ||
            _tutorAiSpeaking ||
            _aiChunkPlaying ||
            _aiChunkLoading ||
            _isPlayingFullAI ||
            _isPlayingFullUser ||
            _polishedUnitAIPlaying;
      }
- initState의 base quarter, dispose의 pause(), _idleElapsedSec >= 60 임계값은 그대로 유지.

────────────────────────────────────────
파일 2: intro_master.dart
────────────────────────────────────────

[작업 4-A] 오토포즈 안내 문구 30초 → 60초 (약 264행)
- 변경 전:
    "• ⏸️ Auto Pause: 30초 이상 반응이 없으면 자동으로 일시정지되어 과금이 멈춥니다. 다시 말을 시작하면 자동으로 재개됩니다.",
- 변경 후:
    "• ⏸️ Auto Pause: 60초 이상 반응이 없으면 자동으로 일시정지되어 과금이 멈춥니다. 다시 말을 시작하면 자동으로 재개됩니다.",

────────────────────────────────────────
파일 3: chat_history_list_master.dart
────────────────────────────────────────

[작업 4-B] 안내 문구 30초 → 60초 (약 1850행)
- 해당 라인의 "30초 이상 반응이 없으면" → "60초 이상 반응이 없으면" 으로만 교체.
  앞뒤 문장은 그대로 유지.

────────────────────────────────────────
파일 4~6: (선택) 코드 주석 정정 — 사용자 영향 없음
────────────────────────────────────────

[작업 4-C] routine_mode_clone.dart:69, routine_mode_roleplay.dart:300, routine_mode_step_expand.dart:69
  주석 "연속 30초 지속되면 pause" → "연속 60초 지속되면 pause"
- 주의: 같은 파일들의 3090/2797/3722행 "30초 타임아웃"은 스트림(네트워크) 타임아웃이라
  오토포즈와 무관 → 절대 건드리지 말 것.

────────────────────────────────────────
[최종 검증 체크리스트]
────────────────────────────────────────
1. flutter analyze → 에러 0
2. grep -n "setRate(BillingRate.full)" chat_history_master.dart
   → 3개 (기존 튜터링 1 + _enterShadowing 1 + step_expand 분기 1)
3. grep -n "setRate(BillingRate.quarter)" chat_history_master.dart
   → initState 1 + 튜터링 종료 1 + _exitShadowing 1 (총 3개)
4. _isSystemBusy 게터 내부에 _polishedUnitAIPlaying 등 신규 8개 플래그 포함 확인
5. grep -rn "30초 이상 반응" *.dart → 0건
6. grep -rn "60초 이상 반응" *.dart → 2건 (intro + history_list)