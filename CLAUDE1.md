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

[작업 대상] lib/custom_code/widgets/ 아래 4개 모드 파일.
[목적] 저장 시점에 native==target(단일언어)이면 original_text를 빈 문자열로 저장.
       → 히스토리 화면(무수정)의 기존 "비어있으면 안 그림" 로직이 알아서 타겟만 표시.
[성격] 앞으로 저장되는 데이터에만 적용(소급 없음). 과거 문서는 건드리지 않음.
[금지] 히스토리 화면 파일, TTS/Box 7/Brain, 그 외 라인 변경 금지.
       각 파일에서 저장 choke point의 'original_text' 쓰기 한 줄만 교체.
       적용 전 grep -n 으로 앵커 확인, 적용 후 flutter analyze.

────────────────────────────────────────────────────────
■ 1) routine_mode_duo.dart  (_saveHistoryMessage 내부)
────────────────────────────────────────────────────────
[찾기] grep -n "'original_text': original," lib/custom_code/widgets/routine_mode_duo.dart
[삭제] 약 862번 줄, 아래 한 줄 (앞 공백 8칸)

        'original_text': original,

[교체 블록 전체]

        'original_text': (FFAppState().nativeLang.isNotEmpty &&
                FFAppState().nativeLang == FFAppState().targetLang)
            ? ''
            : original,

────────────────────────────────────────────────────────
■ 2) routine_mode_clone.dart  (_saveHistoryMessages 내부)
────────────────────────────────────────────────────────
[찾기] grep -n "'original_text': (line\['original_text'\]" lib/custom_code/widgets/routine_mode_clone.dart
[삭제] 약 2345번 줄, 아래 한 줄 (앞 공백 10칸)

          'original_text': (line['original_text'] ?? '').toString(),

[교체 블록 전체]

          'original_text': (FFAppState().nativeLang.isNotEmpty &&
                  FFAppState().nativeLang == FFAppState().targetLang)
              ? ''
              : (line['original_text'] ?? '').toString(),

────────────────────────────────────────────────────────
■ 3) routine_mode_roleplay.dart  (_saveHistoryMessages 내부)
────────────────────────────────────────────────────────
[찾기] grep -n "'original_text': (line\['original_text'\]" lib/custom_code/widgets/routine_mode_roleplay.dart
[삭제] 약 1732번 줄, 아래 한 줄 (앞 공백 10칸)

          'original_text': (line['original_text'] ?? '').toString(),

[교체 블록 전체]

          'original_text': (FFAppState().nativeLang.isNotEmpty &&
                  FFAppState().nativeLang == FFAppState().targetLang)
              ? ''
              : (line['original_text'] ?? '').toString(),

────────────────────────────────────────────────────────
■ 4) routine_mode_step_expand.dart  (_saveHistoryMessages 내부)
────────────────────────────────────────────────────────
[찾기] grep -n "'original_text': (line\['original_text'\]" lib/custom_code/widgets/routine_mode_step_expand.dart
[삭제] 약 2474번 줄, 아래 한 줄 (앞 공백 10칸)
      (주의: 바로 아래 'expanded_sentence' 줄은 건드리지 말 것)

          'original_text': (line['original_text'] ?? '').toString(),

[교체 블록 전체]

          'original_text': (FFAppState().nativeLang.isNotEmpty &&
                  FFAppState().nativeLang == FFAppState().targetLang)
              ? ''
              : (line['original_text'] ?? '').toString(),

────────────────────────────────────────────────────────
■ 검증
────────────────────────────────────────────────────────
grep -c "original_text': (FFAppState" lib/custom_code/widgets/routine_mode_duo.dart         # 1
grep -c "original_text': (FFAppState" lib/custom_code/widgets/routine_mode_clone.dart       # 1
grep -c "original_text': (FFAppState" lib/custom_code/widgets/routine_mode_roleplay.dart    # 1
grep -c "original_text': (FFAppState" lib/custom_code/widgets/routine_mode_step_expand.dart # 1
flutter analyze   # 0 error