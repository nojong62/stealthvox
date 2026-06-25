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

# 실전 튜터링 교정 — "정답 1개 강제 → 허위 오류" 문제 해결 (정답 일치 분기 추가)

## 목적
유저가 **문법적으로 완벽히 맞는 다른 표현**을 말해도, 시스템이 미리 만든 정답(`_appAnswerEn`) 1개와
다르다는 이유로 `어순이 틀렸다` 같은 **허위 교정**을 내보내는 문제 해결.

- 근본 원인: Box 18-C 교정 프롬프트가 `[TARGET_EN_FIXED]`를 "absolute correct answer"로 박고,
  RULE 4에서 *"USER_SPEECH를 TARGET 쪽으로 무조건 교정"* 하라고 명령 → 정답이 1개로 고정됨.
- 영작은 정답이 여러 개인데, "정답과 다름 = 틀림"으로 처리되어 모델이 가짜 사유를 지어냄.

→ 프롬프트에 **"정답 일치(self-correct) 분기"** 추가:
USER_SPEECH가 그 자체로 맞고 자연스러우면 → **유저 문장 그대로 인정 + 칭찬**, TARGET은 참고 예시로만.
진짜 오류일 때만 교정.

## 적용 파일 (단 1개)
`chat_history_master.dart` — Box 18-C `_stopAppRecordAndProcess` 내 `corrPrompt` 문자열

## 건드리지 않는 것 (불변)
- Whisper STT 호출, GPT 호출 파라미터(model/temperature/max_tokens/response_format)
- JSON 키(`corrected_en`, `reason_ko`) 및 파싱 로직, `_appCorrection` 조립, TTS/쉐도잉/캐시
- Box 7, 빌링, P1/P2/P3, Box 18(응용문장 생성) — 전부 무관
- **변경 대상은 오직 `corrPrompt` 문자열 1개**

---

## 0. SAVEPOINT (필수)
```bash
git add -A
git commit -m "savepoint: 튜터링 교정 정답일치 분기 추가 직전"
```

---

## Phase 1 — grep 발견 (기대 카운트)
```bash
grep -c "final corrPrompt" chat_history_master.dart                # → 1
grep -c "TARGET_EN_FIXED" chat_history_master.dart                 # → 7 (전부 corrPrompt 내부)
grep -c "the absolute correct answer" chat_history_master.dart     # → 1
grep -c "corrected_en" chat_history_master.dart                    # → 다수(파싱부 포함, 참고용)
```
`TARGET_EN_FIXED`가 7이 아니면(=다른 곳에도 존재) **중단·보고**.

---

## Phase 2 — str_replace (단일 편집)

### ▶ `corrPrompt` 문자열 전체 교체
**old_str**
```dart
      final corrPrompt = '''You are an English pronunciation and grammar coach.

[TARGET_EN_FIXED]: "$targetEn"
[USER_SPEECH]: "$transcript"

RULES — follow exactly:
1. [TARGET_EN_FIXED] is the absolute correct answer. You must NEVER rephrase, reword, or replace it with any other sentence.
2. Compare [USER_SPEECH] against [TARGET_EN_FIXED] only. No other reference exists.
3. If [USER_SPEECH] matches [TARGET_EN_FIXED] closely (minor STT noise allowed):
   - Set "corrected_en" to the exact text of [TARGET_EN_FIXED].
   - Set "reason_ko" to a single short praise sentence in Korean.
4. If [USER_SPEECH] differs from [TARGET_EN_FIXED]:
   - Set "corrected_en" to the minimally corrected version that moves [USER_SPEECH] toward [TARGET_EN_FIXED] (fix only what is wrong: pronunciation spelling, grammar, word order, or tense).
   - Set "reason_ko" to 1-3 Korean sentences explaining what was wrong (specify which of: 발음, 문법, 어순, 시제). Do NOT write sentences that redefine [TARGET_EN_FIXED] as a different sentence.
5. Output ONLY valid JSON with exactly these two keys: {"corrected_en": "...", "reason_ko": "..."}''';
```

**new_str**
```dart
      final corrPrompt = '''You are an English pronunciation and grammar coach.

[TARGET_EN]: "$targetEn"
[USER_SPEECH]: "$transcript"

IMPORTANT: English allows MANY correct ways to express the same meaning. [TARGET_EN] is only ONE valid example answer, NOT the single correct answer. Never treat a sentence as wrong just because it differs from [TARGET_EN].

RULES — follow exactly:
1. First decide: is [USER_SPEECH], on its own, grammatically correct, natural, and does it convey the same meaning as [TARGET_EN]? Ignore minor STT noise such as missing punctuation or capitalization.
2. If YES — the user's sentence is correct on its own:
   - Set "corrected_en" to the user's OWN sentence, cleaned of STT noise only. Do NOT replace it with [TARGET_EN].
   - Set "reason_ko" to one short Korean praise sentence. You MAY optionally append "다른 표현: [TARGET_EN]" as an alternative, but you MUST NOT call the user's sentence wrong.
3. If NO — there is a genuine error (grammar, tense, word order, word choice, or a real pronunciation/spelling error):
   - Set "corrected_en" to the minimally corrected version of [USER_SPEECH]. Fix ONLY the actual error and keep every part that is already correct.
   - Set "reason_ko" to 1-3 Korean sentences naming the REAL problem (specify which of: 발음, 문법, 어순, 시제, 단어선택). Never invent an error that is not actually present.
4. Output ONLY valid JSON with exactly these two keys: {"corrected_en": "...", "reason_ko": "..."}''';
```

> 핵심 변경점
> - `[TARGET_EN_FIXED]` → `[TARGET_EN]` (라벨에서 "절대 정답" 프레이밍 제거)
> - IMPORTANT 한 줄: "정답은 여러 개, TARGET은 예시 1개"
> - RULE 2(YES 분기): 맞으면 **유저 문장 그대로 유지** + 칭찬, TARGET은 선택적 "다른 표현"으로만
> - RULE 3(NO 분기): **실제 오류만** 최소 교정, 없는 오류 지어내기 금지 + `단어선택` 사유 추가
> - JSON 키(`corrected_en`/`reason_ko`)·출력 형식 **그대로** → 파싱부 수정 불필요

---

## Phase 3 — grep 검증 (기대 카운트)
```bash
grep -c "TARGET_EN_FIXED" chat_history_master.dart                 # → 0  (구 라벨 전멸)
grep -c "the absolute correct answer" chat_history_master.dart     # → 0  (구 문구 제거)
grep -c "moves \[USER_SPEECH\] toward" chat_history_master.dart     # → 0  (강제 교정 문구 제거)
grep -c "MANY correct ways" chat_history_master.dart               # → 1  (신 IMPORTANT)
grep -c "the user's OWN sentence" chat_history_master.dart         # → 1  (신 YES 분기)
grep -c "단어선택" chat_history_master.dart                         # → 1  (신 사유 토큰)
grep -c "final corrPrompt" chat_history_master.dart                # → 1
```
하나라도 어긋나면 **롤백** 후 보고.

---

## Phase 4 — 정적 분석 / 포맷 (개별 파일만)
```bash
flutter analyze chat_history_master.dart
dart format chat_history_master.dart
```
> ⚠️ `dart format`은 반드시 **이 파일 하나만**. 폴더 단위 금지(한글 문자열 깨짐).

문자열만 바꿨으므로 신규 error/warning 0 이어야 함.

---

## 실측 검증 (꼭 1회 수동 테스트)
스샷의 막혔던 케이스로 재현 확인:
1. 한국어: "방금 지나가는 자동차가 나의 자전거를 부딪혔어."
2. 유저 발화(영어): **"The car passing by hit my bicycle."**
3. 기대 결과: **틀렸다고 안 함.**
   - `corrected_en` ≈ 유저 문장 그대로
   - `reason_ko` = 칭찬(+선택적으로 "다른 표현: ...")
4. 반대로 진짜 틀린 발화(예: "Car hit my bicycle yesterday passing")는 여전히 교정 + 정확한 사유.
5. 교정 TTS("Shadow This!") 정상 생성·재생 확인.

---

## 롤백
```bash
git reset --hard HEAD~1          # push 전
git revert <savepoint_hash>      # push 후
```

---

## 참고 — 더 큰 개선 여지 (이번 범위 아님)
지금은 정답이 1개라 "다른 표현" 안내가 제한적. 향후 Box 18에서 정답을
`en` 단일 → `en_examples`(2~3개 배열)로 받으면 모델 판단 근거가 더 풍부해짐.
단 Box 18 생성 프롬프트 + 호출부 변경 필요(변경 폭 큼) → 별도 결정 사안으로 보류.