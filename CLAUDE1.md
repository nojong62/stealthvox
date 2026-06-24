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

# 히스토리 리스트 삭제 모드 색상 → 차분한 회색 변경

## 목적
삭제 모드(선택삭제 버튼 + 선택 항목 테두리·체크박스)의 빨강/주황 색상이
StepExpand 주황색과 겹쳐 혼란스러움 → **차분한 회색 톤**으로 통일.

## 색상 기준 (회색 팔레트)
| 용도 | 변경 후 색상 |
|---|---|
| 선택삭제 버튼 배경 | `Color(0xFF4A4A4A)` (진회색) |
| 선택삭제 버튼 테두리/텍스트/아이콘 | `Color(0xFF9E9E9E)` (밝은 회색) |
| 선택 항목 테두리(체크됨) | `Color(0xFF9E9E9E)` |
| 체크박스 활성 색 | `Color(0xFF757575)` |

> StepExpand/Expand 버튼의 주황색(`Colors.orange` 계열)은 **그대로 유지**. 삭제 관련만 변경.

## 사전 준비
```bash
cd F:\flutter_project\stealth_vox
git add -A && git commit -m "savepoint: before delete-mode color change"
```

## 대상 파일
`lib/custom_code/chat_history_list_master.dart`

---

## Phase 1: 색상 위치 전수 조사 (먼저 실행, 수정 금지)

삭제 모드 UI가 어떤 색상 상수를 쓰는지 먼저 파악한다.

```bash
# 선택삭제 버튼 텍스트 주변 코드 확인
grep -n "선택삭제" lib/custom_code/chat_history_list_master.dart
```

```bash
# 빨강 계열 색상 사용처 (선택삭제 버튼 후보)
grep -n -E "Colors\.red|0xFF[Ee][0-9A-Fa-f]|0xFF[Dd][0-9A-Fa-f]|0xFF[Ff][0-5]" lib/custom_code/chat_history_list_master.dart
```

```bash
# 주황 계열 색상 사용처 (선택 항목 테두리/체크박스 후보)
grep -n -E "Colors\.orange|0xFF[Ff][Ff]?[6-9A]" lib/custom_code/chat_history_list_master.dart
```

```bash
# 체크박스 / 선택 상태 변수
grep -n -E "Checkbox|activeColor|isSelected|selected|Border\.all" lib/custom_code/chat_history_list_master.dart
```

**위 4개 grep 결과를 모두 출력한 뒤**, 아래에 해당하는 줄을 식별:
- (A) "선택삭제" 버튼의 **배경색**
- (B) "선택삭제" 버튼의 **테두리/텍스트/아이콘 색**
- (C) 선택된 카드의 **Border.all 색** (현재 주황)
- (D) 체크박스 **activeColor** (현재 주황)

> ⚠️ 식별된 줄번호·실제 색상 코드를 먼저 보고하고, 내가 확인하면 Phase 2 진행.
> (기존 색상 코드가 위 표의 예상과 다를 수 있으므로 실제 값 기준으로 str_replace 작성)

---

## Phase 2: 색상 치환 (Phase 1 식별 결과 기준, 4건)

각 위치에 대해 text-content 앵커로 str_replace. **아래는 패턴 예시이며, 실제 grep 결과의 정확한 문자열로 치환할 것.**

### (A) 선택삭제 버튼 배경 → 진회색
```
OLD: <식별된 빨강 배경색 코드, 예: Color(0xFFE53935) 또는 Colors.red.withValues(alpha: ...)>
NEW: Color(0xFF4A4A4A)
```

### (B) 선택삭제 버튼 테두리/텍스트/아이콘 → 밝은 회색
```
OLD: <식별된 빨강 강조색 코드>
NEW: Color(0xFF9E9E9E)
```

### (C) 선택 카드 Border.all 색 → 회색
```
OLD: Border.all(color: <식별된 주황 코드>, ...)
NEW: Border.all(color: Color(0xFF9E9E9E), ...)
```

### (D) 체크박스 activeColor → 회색
```
OLD: activeColor: <식별된 주황 코드>
NEW: activeColor: Color(0xFF757575)
```

> 동일 색상 코드가 삭제 UI 외(예: Expand 버튼)에도 쓰인다면 **str_replace가 유일하지 않아 실패**한다.
> 이 경우 해당 색상 줄을 포함한 **앞뒤 문맥(위젯 식별 가능한 범위)**을 OLD에 포함해 유일성 확보.
> Expand/StepExpand 주황은 절대 건드리지 말 것.

---

## Phase 3: 검증

```bash
# 삭제 버튼/선택 UI 영역에 빨강·주황이 남아있지 않은지 육안 확인
grep -n -E "선택삭제" lib/custom_code/chat_history_list_master.dart
# → 위 줄 주변 ±15줄 view로 회색 적용 확인
```

```bash
# 새 회색 코드가 의도한 횟수만큼 들어갔는지
grep -c "0xFF4A4A4A" lib/custom_code/chat_history_list_master.dart   # 기대: 1
grep -c "0xFF9E9E9E" lib/custom_code/chat_history_list_master.dart   # 기대: 2 (B, C)
grep -c "0xFF757575" lib/custom_code/chat_history_list_master.dart   # 기대: 1
```

```bash
# Expand 주황이 그대로인지 (실수로 안 바뀌었는지) 확인
grep -n -E "Colors\.orange|Expand" lib/custom_code/chat_history_list_master.dart
```

```bash
dart format lib/custom_code/chat_history_list_master.dart
flutter analyze lib/custom_code/chat_history_list_master.dart
```

---

## 빌드 후 눈으로 확인할 것
- 선택삭제 버튼: 진회색 배경 + 밝은 회색 글자
- 항목 체크 시: 회색 테두리 + 회색 체크박스
- Expand 버튼 / StepExpand 아이콘: **주황 그대로**

## 롤백
```bash
git checkout HEAD -- lib/custom_code/chat_history_list_master.dart
```