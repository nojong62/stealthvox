StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

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

파일: routine_mode_clone.dart

[목적]
"클론 특징" TextField의 hintText가 실기기(APK)에서 안 보이는 문제를 해결한다.
hintText를 제거하고, Stack으로 별도 placeholder Text 위젯을 올리는 방식으로 교체한다.

[전제 조건]
_kakaoTextController (line 199) 는 이미 선언되어 있으므로 건드리지 않는다.
setState 안에서 placeholder 표시/숨김을 제어하기 위해
_kakaoHasText 라는 bool 상태 변수를 추가한다.

[STEP 1] 상태 변수 추가
위치: line 199 바로 아래 (final TextEditingController _kakaoTextController 다음 줄)

추가할 코드:
  bool _kakaoHasText = false;

[STEP 2] initState 또는 변수 선언 직후에 리스너 등록
위치: _kakaoTextController 가 선언된 이후,
dispose()가 있는 블록(line ~256) 위쪽 initState 내부에 아래 코드를 추가한다.

추가할 코드:
    _kakaoTextController.addListener(() {
      final hasText = _kakaoTextController.text.isNotEmpty;
      if (hasText != _kakaoHasText) {
        setState(() => _kakaoHasText = hasText);
      }
    });

[STEP 3] UI 교체
삭제 범위: line 951 ~ line 968
  시작: `TextField(`  (line 951)
  끝:   `),`          (line 968, TextField 닫는 괄호)

교체할 코드 (전체):
Stack(
  children: [
    TextField(
      controller: _kakaoTextController,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      maxLines: 5,
      decoration: InputDecoration(
        hintText: null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    ),
    if (!_kakaoHasText)
      const IgnorePointer(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            "1. 이어서 나누고 싶은 카톡 대화를 PC에서 복사해 붙여 넣기 합니다. (대화 순서 그대로)\n\n2. AI가 대화 시나리오를 써 드립니다. 클론의 특성을 적어주세요.\n   예) 다정한 연인, 유머러스한 친구, 배려심 많은 선배 등",
            style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.5),
          ),
        ),
      ),
  ],
),

[STEP 4] 자가 검증
1. dart analyze 실행 → 에러 없음 확인
2. grep -n "_kakaoHasText" routine_mode_clone.dart → 3곳 이상 확인 (선언, 리스너, UI)
3. grep -n "hintText:" routine_mode_clone.dart → "hintText: null" 또는 hintText 관련 잔여 긴 문자열 없음 확인

[STEP 5] 롤백 기준
dart analyze 에러 발생 시, STEP 3 교체 부분만 원복하고 원본 TextField 블록 복원.