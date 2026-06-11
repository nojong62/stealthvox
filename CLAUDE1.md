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

# 리팩토링 지시문 1차-A1 — Step Expand KBS 뉴스 폴백 데드코드 삭제 (276줄)

## 배경
침묵 폴백 기능을 삭제하면서, 진입점이었던 `streamOpeningFallbackQuestion`이
아무 데서도 호출되지 않는 고아 함수가 됐다.
이 함수가 내부적으로만 호출하는 `_pickUnaskedTopic`, `_fetchKbsNewsTopics`, `_heavyTopicRe`까지
포함한 닫힌 체인 전체(276줄)를 삭제한다.

## 작업 전 필수
```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "save-point: before A1 dead-code removal (KBS news fallback)"
```

**대상 파일 (1개):**
- `lib/custom_code/widgets/routine_mode_step_expand.dart`

---

## STEP 0: 호출처 0건 재검증 — 하나라도 어긋나면 중단

```bash
F=lib/custom_code/widgets/routine_mode_step_expand.dart

echo "=== streamOpeningFallbackQuestion ==="
grep -n "streamOpeningFallbackQuestion" $F
# 기대: 정의(static Stream...) 1줄 + 주석 헤더 1줄 = 총 2줄만
# "await StepExpandBrain.streamOpening..." 같은 호출이 있으면 중단

echo "=== _pickUnaskedTopic ==="
grep -n "_pickUnaskedTopic" $F
# 기대: 정의 1 + streamOpeningFallback 내부 호출 1 = 총 2줄만

echo "=== _fetchKbsNewsTopics ==="
grep -n "_fetchKbsNewsTopics" $F
# 기대: 정의 1 + _pickUnaskedTopic 내부 호출 2 = 총 3줄만

echo "=== _heavyTopicRe ==="
grep -n "_heavyTopicRe" $F
# 기대: 정의 1 + _fetchKbsNewsTopics 내부 사용 1 = 총 2줄만
```

**위 4개 결과가 모두 "정의 + 자기 체인 내부"로만 구성되어야 한다.**
외부 호출이 하나라도 있으면 **삭제하지 말고 중단** → 보고할 것.

---

## STEP 1: 삭제 범위 확정

```bash
F=lib/custom_code/widgets/routine_mode_step_expand.dart

# 삭제 시작줄 찾기: "[Box 7-1-E-0] KBS" 헤더 바로 위 구분선
START=$(grep -n "📦 \[Box 7-1-E-0\] KBS" $F | head -1 | cut -d: -f1)
START=$((START - 1))
echo "삭제 시작줄: $START"
# 기대값: 5743 부근 (// ====...==== 구분선)

# 삭제 끝줄 찾기: "class _LangIconPainter" 바로 위 클래스 닫는 } 의 직전 줄
PAINTER=$(grep -n "class _LangIconPainter" $F | head -1 | cut -d: -f1)
END=$((PAINTER - 3))
echo "삭제 끝줄: $END"
# 기대값: 6018 부근 (streamOpeningFallbackQuestion의 닫는 })
# PAINTER-1 = 빈 줄, PAINTER-2 = StepExpandBrain 클래스 닫는 }, PAINTER-3 = 함수 닫는 }

# 확인: 시작줄과 끝줄 내용 출력
echo "=== 시작줄 ==="
sed -n "${START}p" $F
# 기대: "  // ====..."

echo "=== 끝줄 ==="
sed -n "${END}p" $F
# 기대: "  }"

echo "=== 끝줄+1 (StepExpandBrain 클래스 닫는 } — 보존 대상) ==="
sed -n "$((END+1))p" $F
# 기대: "}"

echo "=== 삭제 대상 줄수 ==="
echo "$((END - START + 1))줄"
# 기대: 약 276줄
```

**시작줄이 `// ====`이 아니거나, 끝줄+1이 `}`가 아니면 줄번호가 어긋난 것 → 수동 확인 후 조정.**

---

## STEP 2: 삭제 실행

```bash
F=lib/custom_code/widgets/routine_mode_step_expand.dart

# 위에서 확정한 START, END 값을 그대로 사용
sed -i "${START},${END}d" $F

echo "삭제 완료. 남은 줄수:"
wc -l $F
# 기대: 약 5833줄 (원본 6109 - 약 276)
```

---

## STEP 3: 검증

```bash
F=lib/custom_code/widgets/routine_mode_step_expand.dart

grep -c "streamOpeningFallbackQuestion" $F  # 기대값: 0
grep -c "_pickUnaskedTopic" $F              # 기대값: 0
grep -c "_fetchKbsNewsTopics" $F            # 기대값: 0
grep -c "_heavyTopicRe" $F                  # 기대값: 0
grep -c "KBS" $F                            # 기대값: 0
grep -c "class StepExpandBrain" $F          # 기대값: 1 (클래스 보존)
grep -c "class _LangIconPainter" $F         # 기대값: 1 (후속 클래스 보존)
grep -c "polishSentence" $F                 # 기대값: 변동 없음 (보통 2 이상)

# 삭제 경계 확인: polishSentence 끝 → 클래스 끝 → _LangIconPainter 순서
grep -n "return originalSentence" $F
# 그 아래 줄이 "  }" → "}" → 빈 줄 → "class _LangIconPainter" 순이어야 한다

flutter analyze $F
```
- 에러 0건이어야 한다.
- `unused_import` 경고가 새로 뜨지 않아야 한다
  (http, dart:convert 등은 다른 곳에서 다수 사용 중이라 유지됨).

---

## STEP 4: 실기기 스모크 테스트

1. Step Expand 세션 시작 → 시드 질문 정상 생성/재생되는지
2. 세션 시작 후 10초 이상 침묵 → 멘트 없이 그대로 대기하는지
3. 5턴 정상 완주 → 확장문장 → polish 저장까지 동작하는지
4. 불만 발화 → 질문 교체 정상 동작하는지

## 롤백
```bash
git restore lib/custom_code/widgets/routine_mode_step_expand.dart
# 또는 커밋했다면
git revert <hash>
```