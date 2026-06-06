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

요약본 주입은 그대로 두고(이미 있음), 하드코딩 예시 약화 + 온도 0.45, 딱 2곳만 수정합니다. 둘 다 routine_mode_clone.dart의 generateCloneOpener 함수(Box 7-1-E2) 안입니다.

수정 ① — sysPrompt 예시 bullet 약화
삭제 범위

시작: 4173번 줄       final sysPrompt = """$safePersona$memoryLine
끝: 4190번 줄 Output: ONE sentence in $targetLang only.""";

교체할 코드 (전체):
dart      final sysPrompt = """$safePersona$memoryLine

[YOUR TASK]
Based on the persona above, identify WHO you are to the user (parent, sibling, close friend, partner, coworker, etc.) and open the conversation with something real that reflects that relationship — NOT a generic greeting.

[RULES]
- Speak ONLY in $targetLang. Do NOT use Korean or any other language.
- ONE sentence only. Under 10 words.
- Match the persona's exact tone, energy, and vocabulary.
- NEVER open with a bare greeting such as "Hello", "Hi", "Hey", or "How have you been?".
- If [MEMORY] exists, build the opening line DIRECTLY on one concrete detail from it — pick up where the last conversation left off instead of starting fresh.
- If no memory exists, say something situational that only your specific relationship to the user would naturally produce (a short remark or question).

Output: ONE sentence in $targetLang only.""";

핵심: · Parent/elder: "Did you eat yet?"… 등 4줄짜리 구체 예시 묶음을 통째로 제거했습니다. 이게 반복의 실제 원인이었습니다. 대신 메모리가 있으면 그 디테일을 직접 이어받으라는 지시를 강화했습니다.


수정 ② — 온도 0.8 → 0.45
대상: 4203번 줄
dart        'temperature': 0.8,
교체할 코드:
dart        'temperature': 0.45,

검증 (PowerShell, F:\flutter_project\stealth_vox)
powershell# 예시 제거 확인 → 0 이 나와야 함
grep -c "Did you eat yet" lib/custom_code/widgets/routine_mode_clone.dart

# 온도 변경 확인 → 1 이 나와야 함
grep -c "'temperature': 0.45" lib/custom_code/widgets/routine_mode_clone.dart

flutter analyze