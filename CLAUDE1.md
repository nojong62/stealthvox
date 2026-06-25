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

# StepExpand 선형 확장 지시서 (구어체 전환)

> **목표**: 매 턴 관계절·분사구·to부정사로 *깊이 쌓는* 문어체 종속 확장을 →
> 원어민이 실제로 말하듯 *옆으로 잇는* 선형 확장(등위접속 + 가벼운 담화표지)으로 전환.
>
> **방향(확정)**: 산출물은 **여전히 ONE 문장 유지**. 종속을 선형 연결로 바꾸기만 함.
> 따라서 **P2 카라오케·P1·turnPractice·billing·진짜 Box 7(TTS 인프라)은 전혀 건드리지 않음.**

- **대상 파일(단 하나)**: `lib/custom_code/widgets/routine_mode_step_expand.dart`
- **수정 클래스**: `StepExpandBrain` (GPT 프롬프트 메서드 — TTS 인프라 Box 7과 무관)
- **수정 메서드 3개**: `streamUserTranslation`, `streamGrammarQuestion`, `polishSentence`
- **편집 수**: 필수 4 + 선택(코스메틱) 1 = 최대 5
- **편집 순서**: 라인 드리프트 방지 위해 **아래에서 위로(높은 줄번호 먼저)** 적용

---

## 0. 세이브포인트 (필수)

```bash
cd F:\flutter_project\stealth_vox
git add -A
git commit -m "savepoint: before StepExpand 선형 확장 전환"
```

---

## Phase 1 — grep 사전 검증 (적용 전, 각 앵커 유일성 확인)

각 명령의 기대 결과는 모두 **1** 이어야 함. 1이 아니면 중단하고 보고.

```bash
cd F:\flutter_project\stealth_vox\lib\custom_code\widgets

grep -c "Use varied grammatical structures to merge them smoothly:" routine_mode_step_expand.dart   # 기대: 1  (편집①)
grep -c "relative pronoun (who / which / that)" routine_mode_step_expand.dart                        # 기대: 1  (편집②)
grep -c "naturally incorporates at least 2 of these structures:" routine_mode_step_expand.dart       # 기대: 1  (편집③)
grep -c 'Grammar used: \[list\]' routine_mode_step_expand.dart                                       # 기대: 1  (편집③-b, 선택)
grep -c "Complex nested clauses that are hard to speak" routine_mode_step_expand.dart                # 기대: 1  (편집④)
```

---

## Phase 2 — str_replace 적용 (아래에서 위로)

### 편집 ④ — `polishSentence` [AVOID]: 선형 흐름을 다시 종속으로 되돌리지 못하게 (라인 ~5727)

폴리시는 이미 구어체 지향이지만, "한 문장으로 재정리"하면서 선형 흐름을 다시 임베딩으로
되돌릴 여지가 있음. AVOID에 한 줄만 추가해 막는다.

**old_str**
```
- Complex nested clauses that are hard to speak
- Adding information not in the original
```

**new_str**
```
- Complex nested clauses that are hard to speak
- Re-packing the linear, spoken flow back into nested/embedded clauses
- Adding information not in the original
```

---

### 편집 ③-b — (선택·코스메틱) 최종 합성 라벨 "Grammar used" → "Connectors used" (라인 ~5416)

> 다운스트림 파싱 없음(grep 1회뿐, 프롬프트 내부에만 존재). 테마 일관성 + AI가 다시
> 문법구조 사고로 회귀하는 것 방지용. **진짜 최소 diff를 원하면 이 편집은 건너뛰어도 됨.**

**old_str**
```
PART 1: "Expanded Sentence: " + your synthesized sentence (25–40 words) + newline + "Grammar used: [list]"
```

**new_str**
```
PART 1: "Expanded Sentence: " + your synthesized sentence (25–40 words) + newline + "Connectors used: [list]"
```

---

### 편집 ③ — `streamGrammarQuestion` 최종 합성 프롬프트: 종속 4종 리스트 → 선형 연결 (라인 ~5398)

5턴 끝의 최종 합성이 "Causal/Relative/Concessive/Conditional 중 2개 이상"으로 종속을
강제하고 있음. 이게 Alex 예시 같은 깊은 임베딩의 직접 원인. 선형 연결로 교체.
(25–40단어, breath group 5–7단어, "한 문장" 제약은 그대로 유지 → P2 안전)

**old_str**
```
Read the History carefully. Collect the user's fragmented answers and synthesize them into ONE fluent sentence that naturally incorporates at least 2 of these structures:
- Causal clause (because / since)
- Relative clause (who / which / where / when / why)
- Concessive clause (although / despite / even though)
- Conditional clause (if / when)
```

**new_str**
```
Read the History carefully. Collect the user's fragmented answers and synthesize them into ONE fluent, natural-SPOKEN sentence — the way an American would actually say it OUT LOUD, chained linearly (left to right), NOT packed with nested clauses. Build it mainly with these linear connectors (use at least 2, and vary them):
- Coordination: and / and then / so / but
- Result or reason: which is why / that's why / so that / because (kept short, never nested)
- Optionally ONE soft spoken marker if it fits: like / you know / I mean
Do NOT stack relative clauses, front participial phrases, or chains of to-infinitives.
```

---

### 편집 ② — `streamGrammarQuestion` structureSeed 로테이션: 임베딩 렌즈 → 선형 렌즈 (라인 ~5383)

질문이 4턴 주기로 유저 답변을 *관계절/분사구로 붙도록* 유도하는 소프트 렌즈.
이걸 등위·결과·담화표지로 붙도록 바꿈. **삼항 구조/들여쓰기는 그대로, 문자열만 교체** (Dart 안전).

**old_str**
```
      final String structureSeed = t4 == 1
          ? 'relative pronoun (who / which / that)'
          : t4 == 2
              ? 'relative adverb (where / when / why)'
              : t4 == 3
                  ? 'infinitive (to V)'
                  : 'participial phrase (-ing / -ed)';
```

**new_str**
```
      final String structureSeed = t4 == 1
          ? 'coordination (and / and then / so)'
          : t4 == 2
              ? 'contrast or result (but / so / which is why)'
              : t4 == 3
                  ? 'short reason link (because / since — never nested)'
                  : 'a light spoken add-on (like / you know — only if natural)';
```

---

### 편집 ① — `streamUserTranslation` CASE 2 PART 2 머징 규칙: 종속 5종 → 선형 연결 (라인 ~5085)

매 턴 유저 확장 문장을 만드는 핵심. 관계절/분사구/to부정사/전치사구/접속사로 머징하라는
지시를 선형 체이닝 + 담화표지로 교체. (한 문장·breath group 5–7단어 유지)

**old_str**
```
  Use varied grammatical structures to merge them smoothly:
    - Relative clauses (who/which/where/that)
    - Participial phrases (-ing / -ed)
    - To-infinitives (to V)
    - Prepositional phrases
    - Conjunctions (because/when/although)
```

**new_str**
```
  Grow it the way a native speaker actually TALKS — linearly, left to right,
  by chaining short clauses one after another. Do NOT nest clauses inside clauses.
  Preferred connectors (use these, and vary them turn to turn):
    - Coordination: and, but, so, and then
    - Result / reason links: which is why, that's why, so that, because (keep short)
    - At most ONE soft spoken marker if it fits naturally: like, you know, I mean
  AVOID building the sentence on stacked relative clauses, front participial
  phrases, or chains of to-infinitives. A touch is fine; never make them the spine.
  Keep it ONE sentence, speakable in short breath groups of 5–7 words.
```

---

## Phase 3 — grep 사후 검증

OLD 문구는 모두 **0**, NEW 문구는 모두 **1** 이어야 함.

```bash
# OLD (모두 0 기대)
grep -c "Use varied grammatical structures to merge them smoothly:" routine_mode_step_expand.dart   # 기대: 0
grep -c "relative pronoun (who / which / that)" routine_mode_step_expand.dart                        # 기대: 0
grep -c "naturally incorporates at least 2 of these structures:" routine_mode_step_expand.dart       # 기대: 0
grep -c "Complex nested clauses that are hard to speak" routine_mode_step_expand.dart                # 기대: 1  (이 줄은 유지됨, AVOID에 한 줄만 추가)

# NEW (모두 1 기대)
grep -c "the way a native speaker actually TALKS" routine_mode_step_expand.dart                      # 기대: 1  (편집①)
grep -c "coordination (and / and then / so)" routine_mode_step_expand.dart                           # 기대: 1  (편집②)
grep -c "natural-SPOKEN sentence" routine_mode_step_expand.dart                                      # 기대: 1  (편집③)
grep -c "Re-packing the linear, spoken flow" routine_mode_step_expand.dart                           # 기대: 1  (편집④)
# 편집③-b 적용 시:
grep -c 'Connectors used: \[list\]' routine_mode_step_expand.dart                                    # 기대: 1
grep -c 'Grammar used: \[list\]' routine_mode_step_expand.dart                                       # 기대: 0
```

---

## Phase 4 — 분석 & 포맷 게이트

```bash
cd F:\flutter_project\stealth_vox
flutter analyze lib\custom_code\widgets\routine_mode_step_expand.dart
dart format lib\custom_code\widgets\routine_mode_step_expand.dart   # ★ 반드시 개별 파일만. 폴더 금지(한글 깨짐)
```

- `flutter analyze` 0 error 기대 (프롬프트 문자열·삼항 리터럴만 수정 → 타입/구문 변화 없음).
- error 발생 시 **즉시 중단하고 보고** — 롤백.

---

## 롤백 절차

```bash
# 아직 push 전:
git reset --hard HEAD~1
# 이미 push 했다면:
git revert <commit-hash>
```

---

## 검증 체크리스트 (적용 후 육안 확인)

1. `streamUserTranslation` PART 2 머징 지시가 선형 연결/담화표지로 바뀌었는가
2. `structureSeed` 4개 문자열이 coordination/contrast/reason/spoken-marker로 바뀌었는가
3. 최종 합성 프롬프트가 natural-SPOKEN + 선형 연결 리스트로 바뀌었는가
4. `polishSentence` AVOID에 "Re-packing..." 한 줄이 추가됐는가
5. (선택) 라벨이 Connectors used로 바뀌었는가
6. **건드리지 않았는지 확인**: 진짜 Box 7(TTS 인프라, 3860줄~), P1, P2 카라오케, turnPractice,
   billing, splitIntoMeaningUnits, generateCleanOriginal — 전부 무변경
7. 25–40단어 / "한 문장" / breath group 5–7단어 제약은 유지됨 (P2 안전 보장)

---

## 적용 후 실측 테스트 시나리오 (1회 권장)

같은 Alex 흐름을 다시 돌려보고 산출 문장이 아래처럼 *선형*으로 나오는지 확인:

- **전(문어체)**: *"Checking my emails this morning, I suddenly remembered to call my old friend, Alex, who recently moved to London, to ask him about the restaurant where we had dinner last year."*
- **후(구어체 기대)**: *"This morning I was checking my emails, and it suddenly hit me that I needed to call my old friend Alex, who just moved to London, so I could ask him about that restaurant we went to last year."*

→ 후자가 등위(and/so) 중심으로 옆으로 이어지면 성공. 여전히 관계절이 스파인이면 프롬프트 강도
(temperature 0.0 → 0.2, 또는 NEW 문구에 "BANNED: relative-clause spine" 추가) 조정 검토.