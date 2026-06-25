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

# P3_EchoIt_인트로_본문만가림_v2 — History Expand P3 시작 연출 (본문만 가림)

> ⚠️ **이전 `P3_EchoIt_인트로스플래시_지시서.md`(v1)는 폐기.** 그건 헤더·탭까지 화면 전체를 덮음.
> 본 v2는 **본문(청크 대사) 영역만** 가리고 헤더·P1/P2/P3 탭은 계속 보이게 함.

대상 파일: `lib/custom_code/chat_history_master.dart` (단일 파일)
영향 범위: **P3(`chunkPractice`) 인트로 연출만.** Box 7·P1·P2·빌링·청크 재생 로직 무손상.

## 목표
P3 진입 → **'Echo it!'만 2초** (본문 청크만 숨김, 헤더/탭은 유지) → 페이드인되며 **본 대화 내용 등장 + 첫 청크 시작**.

## 방식
오버레이(알약)는 그대로 두고, **본문 `Expanded` 만** `IgnorePointer + AnimatedOpacity`로 감싼다.
인트로 동안 본문 opacity 0(+탭 차단) → 사라지면 페이드인. 알약은 비워진 본문 위에 떠서 'Echo it!'만 보임.

## 변경 2건
1. 인트로 지속시간 **1600ms → 2000ms**
2. 본문 `Expanded` child를 `IgnorePointer(ignoring:_showEchoingOverlay) > AnimatedOpacity(opacity:…)`로 래핑 (여는 부분 + 닫는 괄호 2개)

---

## PHASE 0 — 세이브포인트
```bash
git add -A && git commit -m "savepoint before P3_EchoIt_인트로_본문만가림_v2"
```

## PHASE 1 — 앵커 발견 (각 1건 확인)
```bash
F=lib/custom_code/chat_history_master.dart
grep -n "_echoingOverlayTimer = Timer(const Duration(milliseconds: 1600)" $F   # 1건
grep -n "child: _practicingPolished$" $F                                       # 1건 (본문 Expanded 시작)
grep -n "// Do Echoing 팝업 오버레이" $F                                        # 1건 (본문 종료 직후)
```
세 앵커 모두 1건이면 진행. 다르면 **중단·보고**.

---

## PHASE 2 — 편집 (아래 → 위)

### EDIT 3 — 본문 종료부: 래퍼 닫는 괄호 2개 추가 (≈5815행)
**old_str**
```dart
                        })),
            ),
          ],
        ),
        // Do Echoing 팝업 오버레이
```
**new_str**
```dart
                        })),
                ), // [P3-INTRO] AnimatedOpacity close
              ), // [P3-INTRO] IgnorePointer close
            ),
          ],
        ),
        // Do Echoing 팝업 오버레이
```

### EDIT 2 — 본문 시작부: IgnorePointer + AnimatedOpacity로 래핑 (≈5582행)
**old_str**
```dart
            Expanded(
              child: _practicingPolished
```
**new_str**
```dart
            Expanded(
              // [P3-INTRO] 인트로 동안 본문(청크 대사)만 숨기고 탭 차단. 헤더/탭은 유지.
              child: IgnorePointer(
                ignoring: _showEchoingOverlay,
                child: AnimatedOpacity(
                  opacity: _showEchoingOverlay ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 500),
                  child: _practicingPolished
```
> 본문 ternary 내부는 들여쓰기를 그대로 둔다 → 마지막 `dart format`이 정렬 정리. 괄호 균형만 EDIT 3에서 +2로 맞춤.

### EDIT 1 — 인트로 지속시간 1600ms → 2000ms (≈1771행)
**old_str**
```dart
    _echoingOverlayTimer = Timer(const Duration(milliseconds: 1600), () {
```
**new_str**
```dart
    _echoingOverlayTimer = Timer(const Duration(milliseconds: 2000), () {
```

---

## PHASE 3 — 검증
```bash
F=lib/custom_code/chat_history_master.dart
grep -c "milliseconds: 1600" $F                          # 기대 0
grep -c "ignoring: _showEchoingOverlay$" $F              # 기대 1 (신규, '!' 없는 버전)
grep -c "opacity: _showEchoingOverlay ? 0.0 : 1.0" $F    # 기대 1 (본문 래퍼; 알약은 1.0:0.0이라 구분됨)
grep -c "\[P3-INTRO\] AnimatedOpacity close" $F          # 기대 1
grep -c "\[P3-INTRO\] IgnorePointer close" $F            # 기대 1
```
이어서 (괄호 균형·정렬은 여기서 검증·정리):
```bash
flutter analyze lib/custom_code/chat_history_master.dart   # 에러 0 이어야 함
dart format lib/custom_code/chat_history_master.dart       # ⚠️ 개별 파일만, 폴더 금지
```
> `flutter analyze`에서 괄호/구문 에러가 나면 EDIT 3의 닫는 괄호 개수(+2)가 안 맞은 것 → 롤백 후 재적용.

---

## 기대 동작 (적용 후)
1. P3 진입 → **헤더·P1/P2/P3 탭은 그대로**, 본문 청크 영역만 비워지고 가운데 **'Echo it!'** 표시.
2. 약 2초 후 'Echo it!' 사라지며 **본문 청크가 페이드인** → `_onChunkTapped(0)` 첫 청크 시작.
3. 인트로 중 본문 탭은 차단(IgnorePointer), 종료 후 정상 조작.

## 롤백
```bash
git reset --hard HEAD~1        # push 전
# 또는
git revert <savepoint_해시>    # push 후
```