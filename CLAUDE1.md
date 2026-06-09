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

# StealthVox — Free Talk AI 텍스트 실시간 표시 (5/2 개선 ②)

## 목적
유저 TTS 재생 중(`aiPaused=true`)에는 AI 영어 글자가 화면에 안 뜨다가 PIPE-07에서 한꺼번에 등장한다("와장창"). 이 때문에 침묵 동안 화면이 비어 보여 체감 흐름이 끊긴다.

`!aiPaused` 조건을 제거해 **AI 영어 텍스트가 유저 말하는 동안에도 실시간으로 흘러나오게** 한다. 소리/게이트/병렬 준비 시간(10초 게이트)은 일절 건드리지 않으므로 동작 타이밍은 동일하고, 체감 침묵만 짧아진다.

> 근거: 첨부 문서 `현_통신로직_및_개선.txt` 의 "② AI 텍스트 실시간 표시" 항목. 현재 코드에 미적용 상태(1181번 줄에 `!aiPaused` 조건 잔존).

## 대상 파일 (정확히 이 경로만)
```
lib/custom_code/widgets/routine_mode_free_talk.dart
```
**`lib/custom_code/임시/` 아래 파일은 절대 건드리지 말 것.**

## 작업 전 필수
- `git commit -am "save point before FREETALK_AI_TEXT_REALTIME_v1"` (세이브 포인트).

## 절대 건드리지 말 것 (Do NOT touch)
- `TtsQueueManager` (`setAiPaused` / `aiPaused` getter / 큐 로직) — 그대로 둔다.
- `DeepgramV2VoiceManager`, `HybridTtsPlayer`, `ChunkedTtsFetcher`, `TtsCache` — 직전 C+B 수정 포함, 추가 변경 없음.
- PIPE-04 유저 TTS 게이트 타임아웃(10초) — **유지**. 이 대기 동안 AI 번역·TTS가 병렬로 익으므로 줄이지 않는다.
- PIPE-07 일괄 표시 블록(약 1272~1275, `// [v3.6] PIPE-07 시점: 버퍼된 AI 텍스트 일괄 표시`) — **유지**. 최종 동기화 + AI 차례 스크롤 역할.
- 이 수정 블록(아래 1곳) 외 다른 곳.

---

## 수정 — aiGenerationTask 내 AI 텍스트 표시 조건 분리 (약 1181번 줄)

### 삭제 범위
- **시작**: `          if (mounted && !_ttsQueueManager.aiPaused) {` (약 1181번 줄)
- **끝**: 위 `if` 블록을 닫는 `          }` — 바로 위 줄이 `              _scrollToCurrent(aiIndex);` 와 `            }` (약 1191번 줄)

이 `if` 블록 **하나**를 아래로 교체한다.

### str_replace

**old_str** (현재 코드):
```dart
          if (mounted && !_ttsQueueManager.aiPaused) {
            setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
            // throttled ensureVisible — 스트리밍 중 현재 AI 버블 중앙 고정
            final _scrollNow = DateTime.now();
            if (_lastScrollThrottle == null ||
                _scrollNow.difference(_lastScrollThrottle!) >=
                    const Duration(milliseconds: 250)) {
              _lastScrollThrottle = _scrollNow;
              _scrollToCurrent(aiIndex);
            }
          }
```

**new_str** (교체 코드):
```dart
          // 🔧 [5/2 개선 ②] AI 영어 텍스트는 aiPaused와 무관하게 실시간 표시.
          // 유저 TTS 재생 중(aiPaused=true)에도 AI 글자가 화면에 흘러나와
          // 체감 침묵을 단축. 소리/게이트/병렬 준비 시간은 그대로 둔다.
          if (mounted) {
            setState(() => _localMessages[aiIndex]['target'] = aiTargetText);
            // 스크롤은 AI 차례(!aiPaused)에만 — 유저가 자기 버블을 보는 중
            // AI 버블로 화면이 튀는 것을 방지.
            if (!_ttsQueueManager.aiPaused) {
              final _scrollNow = DateTime.now();
              if (_lastScrollThrottle == null ||
                  _scrollNow.difference(_lastScrollThrottle!) >=
                      const Duration(milliseconds: 250)) {
                _lastScrollThrottle = _scrollNow;
                _scrollToCurrent(aiIndex);
              }
            }
          }
```

---

## 검증 (수정 후 순서대로)

### 1) grep 카운트
```powershell
# 새 주석 앵커 1개
grep -c "5/2 개선 ②" lib/custom_code/widgets/routine_mode_free_talk.dart            # 기대값: 1

# 위젯 코드 내 aiPaused getter 호출은 여전히 1곳(텍스트 조건 → 스크롤 조건으로 이동)
grep -c "_ttsQueueManager.aiPaused" lib/custom_code/widgets/routine_mode_free_talk.dart  # 기대값: 1
```

### 2) flutter analyze
```powershell
flutter analyze lib/custom_code/widgets/routine_mode_free_talk.dart
```
- 수정 전 대비 **신규 error 0건**.

---

## 롤백
- 로컬: `git restore lib/custom_code/widgets/routine_mode_free_talk.dart`
- push 후: `git revert <commit-hash>`

---

## 실기기 확인 포인트
1. 유저가 말하는 동안(또는 유저 TTS 재생 중) **AI 영어 글자가 화면에 똑똑똑 흘러나오는지**.
2. 그때 화면이 **유저 버블에서 AI 버블로 튀지 않는지** (스크롤은 AI 차례에만 움직여야 함).
3. **소리 타이밍은 이전과 동일한지** (AI 음성은 여전히 유저 TTS 끝난 뒤 시작 — 게이트 그대로).
4. 전체적으로 침묵 구간이 "비어 보이지" 않고 화면이 살아있게 느껴지는지.