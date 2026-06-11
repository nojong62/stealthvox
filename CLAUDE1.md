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

# 수정 지시문 — 고스트 필터 부분일치 버그 (3개 모드 공통)

## 배경
파이프라인 STEP 1 증발 검열의 `ghostWords.any((gw) => lowerClean.contains(gw))`가
한 글자 고스트 단어('네', '응')를 **부분 문자열**로 검사하여,
"별로네" / "이상하네" / "응 별로야" / "갔다 왔네" 같은 정상 발화·불만 발화를
GPT 도달 전에 증발시키는 버그. **전체 일치**로 변경한다.

## 작업 전 필수
```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "save-point: before ghost-filter exact-match fix (3 modes)"
```

**대상 파일 (lib/custom_code/widgets/ 폴더만. lib/custom_code/임시/ 절대 금지):**
1. `lib/custom_code/widgets/routine_mode_free_talk.dart` (약 1009~1011줄)
2. `lib/custom_code/widgets/routine_mode_roleplay.dart` (약 1100~1102줄)
3. `lib/custom_code/widgets/routine_mode_step_expand.dart` (약 1760~1762줄)

**절대 규칙:**
- Box 7 클래스 내부 수정 금지 (이번 수정은 `_processRelayPipeline` 내부 — Box 7 아님).
- 줄번호는 참고용. **반드시 anchor로 위치 확정 후 편집.**
- 세 파일 모두 동일한 코드 블록이며, 각 파일에 **정확히 1곳**씩 존재한다.
  편집 전 각 파일에서 아래 grep으로 1곳임을 먼저 확인할 것:
```bash
grep -c "ghostWords.any((gw) => lowerClean.contains(gw))" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 1
grep -c "ghostWords.any((gw) => lowerClean.contains(gw))" lib/custom_code/widgets/routine_mode_roleplay.dart    # 기대값: 1
grep -c "ghostWords.any((gw) => lowerClean.contains(gw))" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 1
```

---

## 수정 내용 — 세 파일 동일 (각 1건)

**삭제 범위:** `bool isGhost = ...` 로 시작하는 3줄
(시작줄: `    bool isGhost = finalTranscript.length <= 2 ||`
 끝줄: `            finalTranscript.length < 20);`)

**찾기 (anchor — 세 파일 공통, 정확히 일치):**
```dart
    bool isGhost = finalTranscript.length <= 2 ||
        (ghostWords.any((gw) => lowerClean.contains(gw)) &&
            finalTranscript.length < 20);
```

**교체 (전체):**
```dart
    // 🛡️ [GHOST-EXACT] 부분일치(contains) → 전체일치로 변경.
    //   기존: '네'/'응'이 음절로 포함된 정상 발화("별로네", "갔다 왔네")까지 증발시킴.
    //   변경: 발화 전체가 고스트 단어 그 자체일 때만 증발.
    //   복합 필러("네 감사합니다")는 통과하되, 프롬프트의 [EVAPORATE] 규칙이 2차로 처리.
    bool isGhost = finalTranscript.length <= 2 ||
        ghostWords.contains(lowerClean.trim());
```

세 파일에 동일하게 적용한다. `ghostWords` 리스트 자체는 수정하지 않는다.

---

## 검증

```bash
cd F:\flutter_project\stealth_vox
grep -c "lowerClean.contains(gw)" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 0
grep -c "lowerClean.contains(gw)" lib/custom_code/widgets/routine_mode_roleplay.dart    # 기대값: 0
grep -c "lowerClean.contains(gw)" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 0
grep -c "GHOST-EXACT" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 1
grep -c "GHOST-EXACT" lib/custom_code/widgets/routine_mode_roleplay.dart    # 기대값: 1
grep -c "GHOST-EXACT" lib/custom_code/widgets/routine_mode_step_expand.dart # 기대값: 1

flutter analyze lib/custom_code/widgets/routine_mode_free_talk.dart lib/custom_code/widgets/routine_mode_roleplay.dart lib/custom_code/widgets/routine_mode_step_expand.dart
```
- 에러 0건이어야 함.

**실기기 테스트 체크리스트:**
1. [3모드 공통] AI 응답 후 "별로네" → 직전 응답 삭제 + 재생성되는지 (기존: 무반응)
2. [3모드 공통] "이상하네" / "응 별로야" → 동일하게 재생성되는지
3. [3모드 공통] "갔다 왔네" 같은 정상 발화 → 정상 번역·진행되는지 (기존: 증발)
4. [회귀 확인] "네" / "응" / "감사합니다" 단독 발화 → 여전히 조용히 증발하고 재청취되는지
5. [회귀 확인] 2글자 이하 웅얼거림 → 여전히 재청취 요청 나오는지

## 롤백

```bash
git restore lib/custom_code/widgets/routine_mode_free_talk.dart lib/custom_code/widgets/routine_mode_roleplay.dart lib/custom_code/widgets/routine_mode_step_expand.dart
# 또는 커밋했다면
git revert <hash>
```