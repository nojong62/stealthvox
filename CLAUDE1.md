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

# 인스트럭션: CORRECTION 신호 보강 + 가드 완화 (백업 패치)

## 목적
유저가 **말로** AI의 오해를 정정할 때 `[CORRECTION]` 판정을 더 잘 잡도록 분류 프롬프트를 보강한다.
- (a) 정정 신호 목록에 결정적 신호 추가: `"라고 했잖아" / "라고 말했어" / "I said" / "that's not what I said"` 등
- (b) "아니로 시작해도 새 정보면 제외" 가드가 **진짜 정정**까지 잡아먹는 문제 완화

> 로직 변경 0. **프롬프트 문자열만** 수정. Box 7 / billing / P1·P2·P3 / turnPractice 무관.

## 대상 파일 (2개)
- `routine_mode_roleplay.dart`  ← **CRLF 파일** (줄 끝 `\r\n`)
- `routine_mode_step_expand.dart` ← LF 파일

> ⚠️ str_replace 앵커는 모두 **단일 라인 내부 텍스트**만 사용한다. 줄 끝 `\r`/`\n`은 앵커에 포함하지 않으므로 CRLF/LF 차이의 영향을 받지 않는다.

---

## STEP 0 · Savepoint
```
git add -A && git commit -m "savepoint: before CORRECTION signal backup patch"
```

---

## PHASE 1 · 앵커 유일성 검증 (각 grep 결과가 정확히 1이어야 진행)
```bash
grep -c 'Starts with a correction signal:' routine_mode_roleplay.dart        # 기대: 1
grep -c 'happen to start with "아니" etc.'   routine_mode_roleplay.dart        # 기대: 1
grep -c 'Starts with correction signals:'  routine_mode_step_expand.dart      # 기대: 1
grep -c 'happen to start with "아니" etc.'   routine_mode_step_expand.dart      # 기대: 1
```
하나라도 1이 아니면 **중단하고 보고**.

---

## PHASE 2 · str_replace 편집 (파일별, bottom-to-top)

### 파일 1: routine_mode_roleplay.dart

#### ②-B 먼저 (아래 라인 3818 = 가드 완화)
- **old_str**
```
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.
```
- **new_str**
```
Do NOT output [CORRECTION] for genuinely NEW information that merely starts with "아니" etc. BUT if the AI's previous turn clearly captured the user's earlier utterance as DIFFERENT content (a wrong word or a wrong topic) and the user is now restating what they actually meant, output [CORRECTION] even when the restatement also reads like a fresh answer. Test: would the user naturally say "that's not what I said"? If yes -> output [CORRECTION].
```

#### ①-A 다음 (위 라인 3814 = 신호 목록 확장)
- **old_str**
```
- Starts with a correction signal: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
```
- **new_str**
```
- Starts with a correction signal: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "내가 말한 건" / "라고 했잖아" / "라고 말했어" / "I mean" / "I said" / "what I said was" / "that's not what I said" / "actually" / "no," / "wait,"
```

### 파일 2: routine_mode_step_expand.dart

#### ②-B 먼저 (라인 5054 = 가드 완화)
- **old_str**
```
Do NOT output [CORRECTION] when the user simply adds new details that happen to start with "아니" etc.
```
- **new_str**
```
Do NOT output [CORRECTION] for genuinely NEW information that merely starts with "아니" etc. BUT if the AI's previous turn clearly captured the user's earlier utterance as DIFFERENT content (a wrong word or a wrong topic) and the user is now restating what they actually meant, output [CORRECTION] even when the restatement also reads like a fresh answer. Test: would the user naturally say "that's not what I said"? If yes -> output [CORRECTION].
```

#### ①-A 다음 (라인 5050 = 신호 목록 확장)
- **old_str**
```
- Starts with correction signals: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "I mean" / "actually" / "no," / "wait,"
```
- **new_str**
```
- Starts with correction signals: "아니" / "아니요" / "아 그게 아니라" / "다시" / "내 말은" / "그러니까" / "내가 말한 건" / "라고 했잖아" / "라고 말했어" / "I mean" / "I said" / "what I said was" / "that's not what I said" / "actually" / "no," / "wait,"
```

---

## PHASE 3 · 검증 (grep count)
```bash
# 신규 신호가 각 파일에 정확히 1번씩 들어갔는지
grep -c '"that'"'"'s not what I said"' routine_mode_roleplay.dart      # 기대: 1
grep -c '"that'"'"'s not what I said"' routine_mode_step_expand.dart   # 기대: 1
# 구 가드 문구가 완전히 사라졌는지
grep -c 'simply adds new details' routine_mode_roleplay.dart          # 기대: 0
grep -c 'simply adds new details' routine_mode_step_expand.dart       # 기대: 0
```

---

## PHASE 4 · analyze + format (단일 파일만)
```bash
flutter analyze lib/custom_code/widgets/routine_mode_roleplay.dart
flutter analyze lib/custom_code/widgets/routine_mode_step_expand.dart
dart format lib/custom_code/widgets/routine_mode_roleplay.dart
dart format lib/custom_code/widgets/routine_mode_step_expand.dart
```
> ⚠️ **폴더 대상 format 금지** (한글 UTF-8 문자열 손상). 반드시 개별 파일만.
> (경로는 실제 프로젝트 구조에 맞춰 조정)

---

## ROLLBACK
문제 시:
```
git reset --hard HEAD~1
```

---

## 검증 체크리스트 (실장 확인용)
- [ ] PHASE 1 grep 4개 모두 1
- [ ] PHASE 3 신규 신호 카운트 각 1, 구 가드 0
- [ ] analyze 통과 (신규 경고 없음)
- [ ] format 후 한글 문자열 깨짐 없음 (git diff로 육안 확인)
- [ ] 실기기: AI가 오해 → "아니, 나 ~라고 했잖아" → 직전 교환 삭제 후 재처리 동작