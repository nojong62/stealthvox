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

## Claude Code 지시문

**파일:** `routine_mode_step_expand.dart`
**대상 함수:** `_processRelayPipeline`
**대상 줄범위:** 약 2212 ~ 2231줄 (STEP 5 "유저 TTS 재생 대기" 루프 ~ STEP 6 진입 직전 250ms 간격)

**Intent:**
스텝익스팬드에서 유저 확장문장(Part2)이 길 때 AI 소리가 유저 소리 종료 전에 겹쳐 나오는 문제를 수정한다. 원인은 ① 재생 대기 타임아웃이 10초로 짧고 ② `isBusy`가 긴 클립에서 실제 종료보다 일찍 false가 되기 때문이다. `isBusy` 단독 신뢰를 버리고 **단어수 기반 최소 재생시간 바닥값(floor)** 을 함께 강제하며, 타임아웃 ceiling을 60초로 올리고, 전환 간격을 250ms → 500ms로 늘린다. 겹침 0을 최우선으로 하되 floor 계산 시 게이트 이전에 이미 재생된 첫 청크(약 4단어)는 차감해 불필요한 공백을 줄인다.

**삭제할 코드 (시작/끝 기준):**
- 시작 (약 2212줄): `      waitTicks = 0;` 바로 다음 줄의 `while (_ttsQueueManager.isBusy) {`
- 끝 (약 2231줄): `      _log('🧠 [PIPE-GAP]', '유저-AI 전환 안전 간격 250ms 완료');`
- 즉, `waitTicks = 0;` 재할당부터 `isBusy` 루프 전체 + `[PIPE-06]` 로그 + STEP 6 주석 + 250ms `Future.delayed` + `[PIPE-GAP]` 로그까지 한 덩어리를 교체.

**BEFORE (현재 코드, 참조용):**
```dart
      waitTicks = 0;
      while (_ttsQueueManager.isBusy) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitTicks++;
        if (waitTicks > 200) {
          _log('⚠️ [PIPE-TIMEOUT]', '유저 TTS 재생 10초 초과, 강제 진행');
          break;
        }
      }
      _log('🧠 [PIPE-06]', '유저 TTS 재생 완료 → AI 큐 개방');

// ─────────────────────────────────────────────────────
      // STEP 6: AI 큐 개방
      // ─────────────────────────────────────────────────────
      // 🔧 [v3.3 안전 간격] 유저 TTS 재생 완료 직후 250ms 대기
      // 이유: isBusy=false가 되었어도 AudioPlayer 내부에서
      //       마지막 샘플이 디코딩/재생 꼬리가 남을 수 있어 소리 겹침 발생
      //       250ms = 체감상 자연스러운 "숨 고르기" + 겹침 방지
      await Future.delayed(const Duration(milliseconds: 250));
      _log('🧠 [PIPE-GAP]', '유저-AI 전환 안전 간격 250ms 완료');
```

**AFTER (교체할 전체 블록):**
```dart
      // 🌱 [OVERLAP-FIX] isBusy 단독 신뢰 금지.
      //   긴 Part2(30~50단어)에서 isBusy가 실제 재생보다 일찍 false가 되어
      //   AI 소리가 유저 소리 종료 전에 겹치는 문제 → 단어수 기반 floor 병행 강제.
      //   - tts-1 영어 낭독 속도 ≈ 2.2 wps
      //   - 게이트 진입 전 이미 재생된 첫 청크(약 4단어)는 차감
      //   - ceiling 60초 (마지막 5턴 경로와 동일 톤)
      const double _ttsWordsPerSec = 2.2;
      final int _userWordCount = _part2FullSentence.trim().isEmpty
          ? 0
          : _part2FullSentence
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
      final int _userPlayFloorMs =
          ((((_userWordCount - 4).clamp(0, 9999)) / _ttsWordsPerSec) * 1000)
              .round();
      final DateTime _userPlayWaitStart = DateTime.now();
      _log('🧠 [PIPE-FLOOR]',
          '유저 재생 floor=${_userPlayFloorMs}ms (words=$_userWordCount)');

      waitTicks = 0;
      while (_ttsQueueManager.isBusy ||
          DateTime.now().difference(_userPlayWaitStart).inMilliseconds 
              _userPlayFloorMs) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitTicks++;
        if (waitTicks > 1200) {
          // 60초 타임아웃 (좀비 방지용 ceiling)
          _log('⚠️ [PIPE-TIMEOUT]', '유저 TTS 재생 60초 초과, 강제 진행');
          break;
        }
      }
      _log('🧠 [PIPE-06]',
          '유저 TTS 재생 완료(floor 포함) → AI 큐 개방. busy=${_ttsQueueManager.isBusy}');

      // ─────────────────────────────────────────────────────
      // STEP 6: AI 큐 개방
      // ─────────────────────────────────────────────────────
      // 🔧 유저 소리 완전 종료 후 0.5초 숨 고르기 → 그 다음 글자+소리 동시 출력.
      //    유저 소리와 AI 소리는 절대 겹치지 않는다.
      await Future.delayed(const Duration(milliseconds: 500));
      _log('🧠 [PIPE-GAP]', '유저-AI 전환 안전 간격 500ms 완료');
```

**do-not-touch (절대 건드리지 말 것):**
- Box 7 전체 (`TtsQueueManager`, `ChunkedTtsFetcher`, `DeepgramV2VoiceManager`, `HybridTtsPlayer`). 특히 `estimatedDuration`, `isBusy` getter, `_processQueue`는 그대로 둔다.
- 2234~2244줄 턴 전환부 (`setUserTurn(false)` / `setAiPaused(false)` + AI 텍스트 setState)는 변경 금지. 글자+소리 동시 출력은 이미 이 구조가 보장한다.
- Loop A(유저 TTS fetch 대기, 약 2199~2208줄)는 변경하지 않는다.
- 마지막 5턴 경로(약 1984~2080줄)는 변경하지 않는다.

**검증 체크리스트:**
1. `flutter analyze` → 에러 0
2. `grep -n "_userPlayFloorMs" routine_mode_step_expand.dart` → 정의 1 + 사용 1
3. `grep -n "waitTicks > 1200" routine_mode_step_expand.dart` → STEP 5 재생 루프에서 매치 (10초 `> 200`이 사라졌는지 확인)
4. `grep -c "milliseconds: 250" routine_mode_step_expand.dart` → 이 구간의 250 간격이 500으로 바뀌었는지 (남은 250 매치가 의도된 다른 곳인지 확인)
5. `grep -n "PIPE-FLOOR" routine_mode_step_expand.dart` → 로그 1건
6. 실기기: 30단어 이상 확장문장 턴에서 유저 소리 끝난 뒤 약 0.5초 정적 → 글자+AI소리 동시 시작, 겹침 없음 확인

---
