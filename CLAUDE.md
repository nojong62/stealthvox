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
롤플레이 통신 로직에서 첫 AI TTS 발사 기준만 6단어에서 5단어로 낮춘다.

중요 제한:
- 다른 파일 수정 금지
- commit wait 로직 수정 금지
- speechFinal 조건부 대기 로직 수정 금지
- AI 큐 개방 순서 수정 금지
- 빈 chunk 필터링 로직 수정 금지
- Duo / Lobby / Intro / Login / RevenueCat / AppsFlyer / Firebase 관련 수정 금지
- APK build 실행 금지
- 수정 후 flutter analyze만 실행

구체적 수정:
1. routine_mode_roleplay.dart 안의 HybridTtsPlayer 클래스에서
   첫 AI TTS 조각 발사 기준으로 쓰는 최소 단어 수 상수를 찾는다.

현재 값이 6단어 기준이라면:
- FIRST_CHUNK_MIN_WORDS = 6
또는
- firstChunkMinWords = 6
또는
- if (punctMatch == null && wordCount < 6) return -1;
형태일 것이다.

이 값을 5로만 변경해라.

즉:
- 6단어 → 5단어

2. 관련 로그 문구도 함께 맞춰라.
예:
"6단어"
→
"5단어"

3. 이외 로직은 절대 바꾸지 마라.
특히 아래는 건드리지 마라:
- COMMIT_WAIT_MS
- COMMIT_WAIT_SPEECH_FINAL_MS
- COMMIT_WAIT_UNCERTAIN_MS
- _getCommitWaitMs()
- _processRelayPipeline()의 흐름
- 250ms 안전 간격
- AI remainder queue 처리
- empty chunk continue 처리

4. 수정 후 flutter analyze만 실행해라.
APK build는 하지 마라.

보고 형식:
1. 수정한 파일
2. 바꾼 상수/조건
3. 수정 전 값
4. 수정 후 값
5. flutter analyze 결과