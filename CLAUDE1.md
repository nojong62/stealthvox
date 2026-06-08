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

# FREETALK_LEVEL_UI_v1 — 레벨 토글: 영어만 + 선택 시 테두리만 색

## 목표
- Beginner / Intermediate / Advanced **영어 라벨만** 표시 (초급/중급/고급 한글 자막 제거)
- 선택된 칸은 **보라색 테두리만** 표시 (배경 채움·그림자 글로우 제거)
- 라벨이 두 줄로 깨지던(`Intermedia te`) 문제 해결 (FittedBox로 1줄 고정)

## 대상 파일 (이 경로만)
```
lib/custom_code/widgets/routine_mode_free_talk.dart
```

## 사전 작업
```
git add -A && git commit -m "save before FREETALK_LEVEL_UI_v1"
```

---

## EDIT — `_buildTopControls()` 전체 교체 (1706~1780행)
삭제 시작: `  Widget _buildTopControls() {`  (1706행)
삭제 끝:   `  }`  (1780행, `_buildTopControls` 닫는 중괄호 — 바로 다음 줄이 `Widget _buildChatList() {`)

**AFTER (이 블록 전체로 교체)**
```dart
  Widget _buildTopControls() {
    const levels = ["Beginner", "Intermediate", "Advanced"];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: List.generate(levels.length, (i) {
            final bool selected = _freeTalkLevel == levels[i];
            return Expanded(
              child: GestureDetector(
                onTap: () => _setFreeTalkLevel(levels[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    // 🆕 배경 채움 없음 — 선택 시 테두리만 색
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF9333EA)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        levels[i], // 🆕 영어 라벨만 (한글 자막 제거)
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white38,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
```

---

## 검증
```
grep -c "초급\|중급\|고급" lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 0
grep -c "subtitles"        lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 0
grep -c "0xFF9333EA"       lib/custom_code/widgets/routine_mode_free_talk.dart   # 기대값: 2 (토글 테두리 1 + 기타 1)
flutter analyze
```
- `flutter analyze`: 신규 에러 0건.

## 롤백
```
git restore lib/custom_code/widgets/routine_mode_free_talk.dart
```

## 결과
- 라벨 영어 1줄 (Beginner / Intermediate / Advanced), 줄바꿈 깨짐 없음.
- 선택 칸: 보라 테두리만, 배경/그림자 없음.