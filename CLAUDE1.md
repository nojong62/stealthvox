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

A안 진행하겠습니다. 게이트(`streamUserTranslation`) 한 곳만 강화하는 거라, 핸들러(1899~1937줄)와 Box 7 통신엔진은 손대지 않습니다. 아래를 Claude Code에 그대로 넣으시면 됩니다.

---

**[Claude Code 지시문]**

**파일:** `routine_mode_step_expand.dart`
**위치:** `StepExpandBrain.streamUserTranslation` 내부 시스템 프롬프트 (대략 4374~4399줄)

**의도:** RESTATE 판정이 "동떨어짐 / 안 들림" 두 극단만 잡아서, *문법은 멀쩡한데 앞 질문에 대한 답이 아닌* 중간지대 발화가 통과해 AI가 헛소리하는 문제를 막는다. **관련성(relevance) 점검을 번역보다 먼저** 하게 하고, 세 번째 트리거(RELEVANCE MISMATCH)를 추가한다. 토큰 출력은 기존과 동일한 `[RESTATE]`라 핸들러 수정 불필요.

**삭제 범위:**
- 시작줄 (약 4374): `[RESTATE GUARD] — hold the center; never invent content`
- 끝줄 (약 4399): `Output: [RESTATE]` (마지막 CONTRAST EXAMPLE의 출력 줄. 그 아래 빈 줄과 `[RULES]`는 **건드리지 말 것**)

**교체할 코드 (위 삭제 범위 전체를 아래로 교체):**

```
[RELEVANCE CHECK — DO THIS FIRST, before any translation or attaching]
Look at the AI's LAST question in History. Ask: does the user's input actually function as an answer to, or a natural continuation of, THAT question?
- If yes (even loosely, even with small STT noise) -> proceed to translate / attach normally.
- If the input is grammatical and clear but does NOT respond to the last question, jumps to an unrelated subject, or contradicts a fact already established earlier in History -> this is a RELEVANCE MISMATCH. Do NOT force it onto the growing sentence and do NOT invent a connection. Output EXACTLY: [RESTATE]
Calibration: a natural, on-topic tangent that still belongs to the same story is FINE — translate it. Treat it as a mismatch only when the input genuinely does not belong as a response to the last question.

[RESTATE GUARD] — hold the center; never invent content
Stay anchored to the AI's LAST question and the growing sentence. If you cannot do that safely, ask the user to say it again instead of guessing.
Output EXACTLY: [RESTATE]  in these cases:
1. RELEVANCE MISMATCH: The input is clear but does not answer the AI's last question, switches to an unrelated subject, or contradicts established facts (see [RELEVANCE CHECK] above).
2. OFF-CONTEXT: The user clearly tried to answer, but the utterance does not connect to the AI's last question and cannot be attached to the growing sentence (and it is NOT a correction of a previous answer).
3. UNRELIABLE PRONUNCIATION: The text is garbled badly enough that the CORE meaning is genuinely uncertain, so translating it would require inventing what the user "probably" meant.
Do NOT output [RESTATE] when:
- A minor STT slip exists but the intended meaning is still clearly inferable from context  ->  translate normally (keep tolerating small errors).
- The input is on-topic for the last question, even if it adds a new natural detail  ->  translate normally.
- Only a single referent (who / what) is unclear but the rest is fine  ->  use [CLARIFY] instead.
- The user is explicitly correcting the AI  ->  use [CORRECTION] instead.

[RESTATE CONTRAST EXAMPLES]
History:
AI: What made you pick Busan this time?
Input: I ate kimchi stew yesterday.
Output: [RESTATE]

History:
AI: What made you pick Busan this time?
Input: My favorite movie is about robots.  (clear English, but does not answer the question at all)
Output: [RESTATE]

History:
AI: What made you pick Busan this time?
Input: i wanna see the the sea  (garbled but clearly means "I wanted to see the sea")
Output:
Because I wanted to see the ocean.

History:
AI: What made you pick Busan this time?
Input: uh the the it muh suh buh uh  (no recoverable meaning)
Output: [RESTATE]
```

**절대 건드리지 말 것:**
- RESTATE 핸들러 (약 1899~1937줄) — `[RESTATE]` 토큰만 보고 처리하므로 변경 불필요
- `streamUserTranslation`의 `temperature: 0.0` — 게이트 판정 일관성 유지, 그대로
- Box 7 통신엔진(`TtsQueueManager`, `DeepgramV2VoiceManager`)
- `[CASE 1]`/`[CASE 2]`/`[CLARIFICATION GUARD]`/`[RULES]` 등 다른 블록

**검증 체크리스트:**
1. `flutter analyze` → 에러 0
2. `grep -c "RELEVANCE MISMATCH" routine_mode_step_expand.dart` → **2** (CHECK 블록 + GUARD 1번)
3. `grep -c "\[RESTATE\]" routine_mode_step_expand.dart` → 기존보다 늘어났는지 (CONTRAST 예시 추가분 포함)
4. `grep -n "RELEVANCE CHECK — DO THIS FIRST" routine_mode_step_expand.dart` → 1건, `[CLARIFICATION GUARD]` 블록 **뒤**, `[RULES]` **앞**에 위치하는지 줄번호로 확인

---

실행 후 완료 표 주시면 grep + analyze 결과 같이 확인하겠습니다. 프로덕션에서 "이제는 안 막히는데 너무 자주 다시 말하라고 한다" 쪽으로 치우치면, 그때 calibration 줄만 미세조정하면 됩니다.