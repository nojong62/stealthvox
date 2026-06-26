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
- 완료후 관리자가 APK 라고 적으면, 날자와 시간이 이름에 들어간 APK만들어 줘. 

이 내용을 항상 기억하고 지시문에 포함해 줘.
=================================
지시문 

# StepExpand 정밀화 + CLARIFY 증발 지시서

> **PART A** — 선형확장 정밀화: 관계절을 일괄 금지하지 말고, **후행(trailing) 관계절은 허용**,
> **중간삽입(center-embedded) 관계절만 회피**하도록 프롬프트 문구 정밀화. (프롬프트 문자열만)
>
> **PART B** — CLARIFY 증발: 발음 오청취로 뜬 되묻기(CLARIFY) 질문이, 유저가 다시 말하면
> 화면·컨텍스트에서 **증발**하도록 수정. (마커 기반, 상태변수 없음)

- **대상 파일(하나)**: `lib/custom_code/widgets/routine_mode_step_expand.dart`
- **전제**: 이전 "선형확장 지시서"는 **이미 적용된 상태**(grep 확인 완료). 본 지시서는 그 위에 얹음.
- **편집 수**: PART A 2 + PART B 2 = 총 4
- **편집 순서**: 라인 드리프트 방지 위해 **아래에서 위로(높은 줄번호 먼저)**: 5405 → 5091 → 2384 → 2040
- **무관 영역(전부 무변경)**: 진짜 Box 7(TTS 인프라 3860줄~), P1, P2 카라오케, turnPractice, billing,
  CORRECTION/MISHEARD/RESTATE/GARBLED 경로, generateCleanOriginal

---

## 0. 세이브포인트 (필수)

```bash
cd F:\flutter_project\stealth_vox
git add -A
git commit -m "savepoint: before StepExpand 관계절 정밀화 + CLARIFY 증발"
```

---

## Phase 1 — grep 사전 검증 (각 앵커 유일성, 모두 1 기대)

```bash
cd F:\flutter_project\stealth_vox\lib\custom_code\widgets

grep -c "AVOID building the sentence on stacked relative clauses" routine_mode_step_expand.dart          # 기대: 1 (A-1)
grep -c "Do NOT stack relative clauses, front participial phrases, or chains of to-infinitives." routine_mode_step_expand.dart  # 기대: 1 (A-2)
grep -c "'target': clarifyText, 'original': ''" routine_mode_step_expand.dart                            # 기대: 1 (B-1)
grep -c "if (isGhost) {" routine_mode_step_expand.dart                                                   # 기대: 1 (B-2)
grep -c "'clarify': true" routine_mode_step_expand.dart                                                  # 기대: 0 (아직 없음)
```

---

## Phase 2 — str_replace 적용 (아래에서 위로)

### A-2 — 최종 합성 프롬프트: 관계절 금지 → 후행 허용/중간삽입만 회피 (라인 ~5405)

**old_str**
```
Do NOT stack relative clauses, front participial phrases, or chains of to-infinitives.
```

**new_str**
```
TRAILING relative clauses are fine and linear — a sentence-final, comma-led "who / which" (e.g. "...to call my friend Alex, who just moved to London") works just like "and he/it...", so keep using them. AVOID only CENTER-EMBEDDED relative clauses that split a subject from its verb, front participial phrases, and chains of to-infinitives.
```

---

### A-1 — 머징 규칙 AVOID: 관계절 일괄 회피 → 위치 기준 정밀화 (라인 ~5091–5092)

> 현재 문구는 2줄로 줄바꿈되어 있음. 두 줄을 한 블록으로 교체.

**old_str**
```
  AVOID building the sentence on stacked relative clauses, front participial
  phrases, or chains of to-infinitives. A touch is fine; never make them the spine.
```

**new_str**
```
  TRAILING relative clauses are FINE — a sentence-final, comma-led "who/which"
  (e.g. "...to call my friend Alex, who just moved to London") continues the chain
  just like "and he/it...". What to AVOID is CENTER-EMBEDDED clauses that split a
  subject from its verb, front participial phrases, and chains of to-infinitives.
  Never let nesting interrupt the left-to-right flow.
```

---

### B-1 — 되묻기(CLARIFY) SYSTEM 버블에 증발 표식 추가 (라인 ~2383–2384)

**old_str**
```
            _localMessages
                .add({'role': 'SYSTEM', 'target': clarifyText, 'original': ''});
```

**new_str**
```
            _localMessages.add({
              'role': 'SYSTEM',
              'target': clarifyText,
              'original': '',
              'clarify': true, // 💨 증발 표식: 유저가 다음 턴에 답하면 이 되묻기 버블 제거
            });
```

---

### B-2 — ghost 검열 직후 CLARIFY 증발 블록 삽입 (라인 ~2033–2040)

> `isGhost` 블록(노이즈 early-return) 바로 다음, FAST-LANE 체크 **이전**에 삽입.
> 여기 도달 = ghost 통과 = 실제 발화 → 직전 SYSTEM이 되묻기 표식이면 증발.
> 컨텍스트 빌드(STEP 2)보다 앞이므로, 증발 후의 다음 질문·번역은 깨끗한 맥락을 받음.

**old_str**
```
    if (isGhost) {
      if (mounted)
        setState(
            () => _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP'));
      if (_isConversationActive) _startDeepgramListening();
      return;
    }

    // 🔧 [FAST-LANE] 로컬 질문 불만 판정 — streamUserTranslation 호출 전 빠른 처리
```

**new_str**
```
    if (isGhost) {
      if (mounted)
        setState(
            () => _localMessages.removeWhere((m) => m['role'] == 'HOST_TEMP'));
      if (_isConversationActive) _startDeepgramListening();
      return;
    }

    // ❓→💨 [CLARIFY-EVAPORATE] 직전 SYSTEM 버블이 발음 오청취로 뜬 되묻기(CLARIFY)이고
    //   이번 발화가 그 답(재진술)이면, 군더더기 되묻기 버블을 증발시킨다.
    //   - ghost 노이즈는 위에서 이미 early-return → 여기 도달 = 실제 답일 때만 증발
    //   - 'clarify' 표식이 있는 SYSTEM만 제거 → 새 주제 시드 질문은 절대 안 지워짐
    //   - 컨텍스트 빌드 전이므로 다음 AI 질문/번역은 되묻기 흔적 없는 깨끗한 맥락을 받음
    if (mounted) {
      final lastSysIdx =
          _localMessages.lastIndexWhere((m) => m['role'] == 'SYSTEM');
      if (lastSysIdx != -1 && _localMessages[lastSysIdx]['clarify'] == true) {
        setState(() => _localMessages.removeAt(lastSysIdx));
      }
    }

    // 🔧 [FAST-LANE] 로컬 질문 불만 판정 — streamUserTranslation 호출 전 빠른 처리
```

---

## Phase 3 — grep 사후 검증

```bash
# OLD (모두 0 기대)
grep -c "AVOID building the sentence on stacked relative clauses" routine_mode_step_expand.dart                              # 기대: 0
grep -c "Do NOT stack relative clauses, front participial phrases, or chains of to-infinitives." routine_mode_step_expand.dart  # 기대: 0
grep -c "'target': clarifyText, 'original': ''});" routine_mode_step_expand.dart                                            # 기대: 0

# NEW (기대 수치)
grep -c "TRAILING relative clauses are fine and linear" routine_mode_step_expand.dart        # 기대: 1 (A-2)
grep -c "TRAILING relative clauses are FINE — a sentence-final" routine_mode_step_expand.dart # 기대: 1 (A-1)
grep -c "'clarify': true" routine_mode_step_expand.dart                                       # 기대: 2 (B-1 추가분 + B-2 비교문)
grep -c "CLARIFY-EVAPORATE" routine_mode_step_expand.dart                                     # 기대: 1 (B-2)
```

> 참고: `'clarify': true` 가 **2회** 나오는 게 정상 — B-1의 맵 키 추가 1회 + B-2의 비교
> 조건문(`['clarify'] == true`) 1회.

---

## Phase 4 — 분석 & 포맷 게이트

```bash
cd F:\flutter_project\stealth_vox
flutter analyze lib\custom_code\widgets\routine_mode_step_expand.dart
dart format lib\custom_code\widgets\routine_mode_step_expand.dart   # ★ 반드시 개별 파일만 (폴더 금지)
```

- PART A는 프롬프트 문자열만 → 구문 영향 없음.
- PART B는 맵 리터럴 키 추가 + null-safe 비교(`['clarify'] == true`, key 없으면 null → false)
  → 타입 안전, error 없어야 정상.
- error 발생 시 즉시 중단·롤백.

---

## 롤백

```bash
git reset --hard HEAD~1            # push 전
# 또는
git revert <commit-hash>          # push 후
```

---

## 검증 체크리스트 (적용 후)

**PART A (관계절 정밀화)**
1. 최종 합성·머징 프롬프트가 "trailing 허용 / center-embedded만 회피"로 바뀌었는가
2. 실측: `", who ..."` 같은 후행 관계절이 다시 등장하되, 주어-동사를 가르는 중간삽입은 안 나오는가

**PART B (CLARIFY 증발)**
3. 일부러 모호하게/오청취 유발 발화 → 되묻기 질문 버블이 뜨는가
4. 다시 정확히 말하면 → **방금 그 되묻기 버블이 사라지고**, 성장 문장이 되묻기 직전 상태에서
   자연스럽게 이어지는가
5. 다음 AI 질문이 "요미지간이 뭐예요?" 같은 죽은 맥락을 참조하지 않는가
6. **새 주제 시작** 시 첫 발화에서 시드 질문(SYSTEM)이 잘못 지워지지 않는가 (표식 없으므로 안전)
7. 되묻기 후 발화가 garbled면 → 특정 질문 대신 일반 "다시 말해 주세요"로 가는가 (허용된 엣지)

**무관 영역 무변경 확인**
8. 진짜 Box 7, P1, P2 카라오케, billing, CORRECTION/MISHEARD/RESTATE/GARBLED 경로 — 그대로