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


`chat_history_master.dart`, `routine_mode_roleplay.dart`, `routine_mode_free_talk.dart`, `routine_mode_duo.dart`를 확인해서 수정해 주세요.

목표는 **History Practice 화면 하단의 “Expanded Sentence / 확장문장 만들기” 버튼을 Roleplay, FreeTalk, Duo에서 완전히 제거**하는 것입니다.

현재 정책:

* Roleplay에서는 대화 전체를 바탕으로 새 확장문장을 만들 필요 없음.
* FreeTalk에서는 이미 확장문장 생성 기능을 제거한 상태임.
* Duo에서도 확장문장 생성 버튼은 반드시 숨겨야 함.
* 현재 프로젝트에는 Clone 파일이 없으므로 Clone 관련 수정이나 언급은 하지 말 것.
* Step Expand의 기존 확장문장 기능은 건드리지 말 것.

수정 지시:

1. `chat_history_master.dart`에서 History Practice / Tutor Practice 하단에 표시되는 `Expanded Sentence` 버튼을 찾아 제거하세요.

2. 버튼을 완전히 삭제하기 어렵다면 표시 조건을 명확히 제한하세요.
   다음 mode에서는 반드시 버튼이 보이면 안 됩니다.

   * `roleplay`
   * `free_talk`
   * `duo`
   * mode 값이 null, empty, unknown인 구버전 history 문서

3. 기존 코드에 `free_talk`만 숨기는 조건이 있다면 폐기하세요.
   이제는 `roleplay`, `free_talk`, `duo`, unknown mode 모두 숨김 처리해야 합니다.

4. `_buildExpandFromConversation()` 함수가 아직 남아 있다면 안전장치를 추가하세요.
   UI에서 버튼이 사라져도 혹시 다른 경로로 호출될 수 있으므로, 현재 history 문서의 mode가 아래 중 하나이면 즉시 return 하도록 하세요.

   * `roleplay`
   * `free_talk`
   * `duo`
   * null / empty / unknown

5. 위 mode에서는 `_buildExpandFromConversation()` 실행 시 다음 작업이 절대 일어나면 안 됩니다.

   * GPT 호출
   * 확장문장 생성
   * polished 문장 생성
   * Firestore 업데이트
   * `expanded_sentence` 저장
   * `polished_sentence` 저장
   * `has_practice` 변경
   * `expand_generated_at` 저장

6. `routine_mode_roleplay.dart`, `routine_mode_free_talk.dart`, `routine_mode_duo.dart`에서는 확장문장 생성 관련 호출이 남아 있는지만 확인하세요.
   호출이 없다면 불필요하게 수정하지 마세요.

7. `routine_mode_roleplay.dart` 안에 `generateExpandedFromConversation()` 또는 `polishSentence()` 같은 미사용 함수가 있어도 이번 작업의 필수 삭제 대상은 아닙니다.
   삭제하려면 전체 프로젝트 참조 검색 후 안전할 때만 삭제하세요.

8. Step Expand 관련 로직은 절대 건드리지 마세요.
   Step Expand는 원래 확장문장 기능이 핵심이므로 기존 Expanded Sentence / Polished Sentence 흐름은 유지해야 합니다.

검증 기준:

1. Roleplay History Practice 화면에 `Expanded Sentence` 버튼이 보이지 않아야 합니다.
2. FreeTalk History Practice 화면에 `Expanded Sentence` 버튼이 보이지 않아야 합니다.
3. Duo History Practice 화면에 `Expanded Sentence` 버튼이 보이지 않아야 합니다.
4. mode 값이 없거나 알 수 없는 기존 history 문서에서도 `Expanded Sentence` 버튼이 보이지 않아야 합니다.
5. Roleplay / FreeTalk / Duo에서 Practice 완료 후 하단에는 기본 제어 버튼만 남아야 합니다.
6. Roleplay / FreeTalk / Duo에서 새로 `expanded_sentence`, `polished_sentence`, `has_practice`, `expand_generated_at` 등이 생성되면 안 됩니다.
7. `flutter analyze`에서 이번 수정으로 인한 새 error가 없어야 합니다.

---

핵심 한 줄:

> `chat_history_master.dart`에서 History Practice 하단의 `Expanded Sentence` 버튼을 Roleplay, FreeTalk, Duo, unknown mode에서 전부 숨기고, `_buildExpandFromConversation()`도 이 모드들에서는 즉시 return 하도록 수정하세요. Clone 관련 내용은 현재 프로젝트에 없으므로 절대 포함하지 마세요.
