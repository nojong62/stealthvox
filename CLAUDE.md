StealthVox 프로젝트 가이드 (FlutterFlow)

 📂 파일 위치 및 위젯 리스트
 모든 화면(Pages): `lib/` 폴더 내 각 이름별 폴더
 커스텀 액션: `lib/custom_code/actions/`
 전역 상태: `lib/app_state.dart`

 🛠️ 커스텀 위젯 (`lib/custom_code/widgets/`)
현재 구현된 위젯 파일들 (새 작업 시 참고):

 ⚙️ AI 작업 규칙
1. 복사붙여넣기: FlutterFlow 웹 에디터에 바로 적용할 수 있게 `import`와 클래스 구조 전체를 제공한다.
2. 디자인: `lib/flutter_flow/flutter_flow_theme.dart`의 테마 변수를 최우선으로 사용한다.
3. 작업 시작 전에 반드시 다음 순서로 진행해 주세요.
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

수정 대상:
lib/custom_code/widgets/routine_mode_roleplay.dart 만 수정해라.

목표:
USER/AI TTS 큐에 ".", ",", "\"\"" 같은 의미 없는 punctuation 조각이나 빈 문자열이 들어가지 않도록 필터링한다.

중요 제한:
- 다른 파일 수정 금지
- commit wait 로직 수정 금지
- speechFinal 조건부 대기 로직 수정 금지
- HybridTtsPlayer chunk 로직 수정 금지
- Deepgram reconnect 구조 수정 금지
- AI queue unlock 로직 수정 금지
- Duo / Lobby / Intro / RevenueCat / AppsFlyer / Firebase 관련 수정 금지
- APK build 실행 금지
- flutter analyze만 실행

문제:
현재 로그에 아래와 같은 의미 없는 TTS 조각이 들어간다.

[USER] addText: "."
[USER] addText: "\"\""

이런 조각은:
- 학습 효과가 없음
- TTS pending count만 증가시킴
- 큐 상태를 복잡하게 만듦
- timing/debugging을 더럽힘

목표는 실제 의미 있는 텍스트만 TTS 큐에 넣는 것이다.

수정 지시:

1. routine_mode_roleplay.dart 안에서 TTS enqueue 전에 사용할 helper 함수를 추가해라.

예:

bool isMeaninglessTtsText(String text) {
  final t = text.trim();

  if (t.isEmpty) return true;

  if (RegExp(r'^[\\s\\.,!?;:"“”‘’()\\[\\]{}\\-]+$').hasMatch(t)) {
    return true;
  }

  return false;
}

정규식 의미:
- 공백만 있는 문자열
- ".", ",", "!", "?", "\"", "-", 괄호 등 punctuation만 있는 문자열
을 모두 skip한다.

2. USER TTS addText 직전에 필터 적용

현재:
userTtsFetcher.addText(...)

또는:
_log('🔊 [TTS-01] [USER] addText: ...')

직전에:

if (isMeaninglessTtsText(text)) {
  _log('🔊 [TTS-SKIP] [USER]', '의미 없는 TTS 조각 skip: "$text"');
  return;
}

형태로 적용해라.

3. AI TTS addText 직전에도 동일 필터 적용

현재:
aiTtsFetcher.addText(...)

또는 AI chunk enqueue 직전에:

if (isMeaninglessTtsText(text)) {
  _log('🔊 [TTS-SKIP] [AI]', '의미 없는 TTS 조각 skip: "$text"');
  return;
}

적용.

4. 중요한 조건:
- 실제 단어가 하나라도 포함된 경우는 절대 skip하면 안 된다.
예:
"okay."
"yes!"
"no?"
이런 것은 정상 enqueue 되어야 한다.

즉:
punctuation ONLY 문자열만 skip한다.

5. 기대 결과:

기존:
[USER] addText: "."
pending=2

수정 후:
[TTS-SKIP] [USER] 의미 없는 TTS 조각 skip: "."
pending 증가 없음

6. 수정 후 flutter analyze만 실행해라.
APK build는 하지 마라.

보고 형식:
1. 수정한 함수
2. 추가한 helper 함수
3. USER 필터 적용 위치
4. AI 필터 적용 위치
5. skip 로그 예시
6. flutter analyze 결과