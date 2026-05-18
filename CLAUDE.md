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

[StealthVox 롤플레이 상황 선택 200개 데이터 연결 오류 수정 지시문]

현재 파일:
- lib/custom_code/widgets/routine_mode_roleplay.dart
- assets/jsons/emergency_situations_200.json 또는 200개 상황설정 데이터 파일

문제:
롤플레이 화면에서 “상황 선택” 바텀시트를 열면 상단에 “0개 상황”으로 표시되고,
교통 / 숙소 / 쇼핑 / 공공 / 레저 탭을 눌러도 각 항목 리스트가 나오지 않는다.
첨부 캡처처럼 탭 UI는 뜨지만 실제 200개 상황 데이터가 연결되지 않은 상태다.

중요:
APK 빌드 명령은 실행하지 말고, 코드 수정과 flutter analyze/check 수준까지만 진행해라.

수정 목표:
1. `routine_mode_roleplay.dart`의 `_loadEmergencySituations()`가 실제 200개 상황 데이터를 정상 로드하도록 수정한다.
2. 상황 선택 바텀시트 상단에 반드시 `200개 상황`으로 표시되게 한다.
3. 각 탭별로 해당 카테고리 항목이 정상 표시되게 한다.
4. 각 항목을 누르면 선택한 situation이 `_selectedEmergencyKeyword`에 들어가고, `_generateScenario()`가 실행되어 메인 카드의 SITUATION / AI / YOU 내용이 새로 생성되게 한다.
5. 기존 음성 통신 로직, STT/TTS, 발화 확정 로직, 결제/타이머 로직은 절대 수정하지 않는다.

우선 점검할 것:
1. `assets/jsons/emergency_situations_200.json` 파일이 실제 프로젝트 안에 존재하는지 확인한다.
2. `pubspec.yaml`에 아래 asset 경로가 등록되어 있는지 확인한다.

예:
flutter:
  assets:
    - assets/jsons/emergency_situations_200.json

이미 assets 폴더 전체 등록 방식이면 중복 등록하지 말고 기존 방식에 맞춰라.

3. `_loadEmergencySituations()`의 경로가 실제 파일 위치와 정확히 일치하는지 확인한다.

현재 예상 코드:
final jsonStr = await rootBundle.loadString('assets/jsons/emergency_situations_200.json');

파일 위치가 다르면 실제 위치에 맞게 수정한다.

4. JSON 구조가 아래 구조인지 확인한다.

{
  "emergency_situations": [
    {
      "id": 1,
      "category": "공항_비행기_교통",
      "situation": "기내 의학 환자 발생"
    }
  ]
}

5. `_showSituationPicker()`의 category key와 JSON의 category 값이 정확히 일치하는지 확인한다.

필수 category key:
- 공항_비행기_교통
- 호텔_숙소_주거
- 식당_쇼핑_유흥
- 공공장소_병원_비즈니스
- 레저_관광_자연_기타

현재 탭:
- ✈️ 교통 → 공항_비행기_교통
- 🏨 숙소 → 호텔_숙소_주거
- 🛍️ 쇼핑 → 식당_쇼핑_유흥
- 🏥 공공 → 공공장소_병원_비즈니스
- 🏞️ 레저 → 레저_관광_자연_기타

이 매칭이 하나라도 다르면 리스트가 비어 보이므로 반드시 일치시켜라.

수정 방향:
1. `_loadEmergencySituations()`에 debugPrint를 추가해서 로딩 성공/실패와 로드된 개수를 확인 가능하게 해라.

예:
debugPrint('✅ Emergency situations loaded: ${list.length}');
debugPrint('❌ Emergency JSON Load Error: $e');

2. JSON 로드 실패 시 앱이 빈 화면이 되지 않도록, 최소한의 fallback 처리를 추가해라.
단, 가능하면 실제 200개 JSON asset을 정상 연결하는 방식이 우선이다.

3. `_SituationPickerSheet`에서 `widget.emergencySituations.length`가 0이면 사용자에게 빈 화면만 보여주지 말고,
“상황 데이터를 불러오지 못했습니다” 같은 안내 문구를 표시해라.
하지만 정상 상태에서는 반드시 200개 항목이 보여야 한다.

4. 항목 클릭 로직은 아래 흐름을 유지하되 정상 작동 여부를 확인해라.

onTap:
- Navigator.pop(ctx)
- `_selectedEmergencyKeyword = situationKeyword`
- `_generateScenario()`

현재 대화가 이미 시작된 상태에서는 상황 변경을 막는 기존 조건은 유지해도 된다.
단, 대화 시작 전에는 반드시 선택이 가능해야 한다.

5. 가능하면 `onSelected`에 keyword만 넘기지 말고 item 전체를 넘기는 구조로 바꿔도 된다.
하지만 최소 수정 원칙상 keyword만으로 충분하면 기존 구조를 유지해라.

검증 기준:
1. 앱 실행 후 롤플레이 화면 진입
2. “상황 선택” 버튼 클릭
3. 바텀시트 상단이 `200개 상황`으로 표시
4. 교통/숙소/쇼핑/공공/레저 각 탭에 항목 리스트 표시
5. 항목 하나 선택
6. 바텀시트 닫힘
7. 메인 카드의 상황/AI/YOU 내용이 선택한 키워드 기반으로 새로 생성
8. Start 버튼 실행 전까지 기존 대화 로직에는 영향 없어야 함

절대 수정하지 말 것:
- Deepgram 통신 로직
- OpenAI 스트리밍 응답 로직
- TTS 큐 로직
- COMMIT_WAIT / 발화 확정 로직
- BillingTicker / 결제 시간 차감 로직
- 화면 전체 디자인 구조
- APK 빌드 명령 실행

작업 후 보고:
- 어떤 파일을 수정했는지
- JSON 로드 경로가 무엇인지
- pubspec.yaml asset 등록 여부
- 실제 로드된 상황 개수
- flutter analyze 결과
를 간단히 보고해라.