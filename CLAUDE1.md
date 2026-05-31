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

[작업] 오버플로 2건 수정. Box 7(TtsQueueManager/DeepgramV2VoiceManager) 및 다른 로직 수정 금지.
       각 변경은 적용 전 diff를 보여주고 내 승인 후 반영. 변경 전 각 파일 .bak 백업.
       수정 후 dart analyze 통과 확인.

========================================================
① 로그인 BOTTOM OVERFLOW 215px — intro_master.dart
========================================================
- 286행 부근의 Scaffold를 찾는다. 현재:

      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: isLoading

- backgroundColor 바로 다음 줄에 resizeToAvoidBottomInset: false, 한 줄을 추가해 아래처럼 만든다:

      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: isLoading

- 근거: body가 이미 SafeArea > SingleChildScrollView + padding(... + MediaQuery.viewInsets.bottom)로
  키보드를 처리 중. Scaffold가 inset을 또 빼면서 바깥 고정높이 Container와 충돌해 215px가 터짐.
  false로 두면 스크롤뷰가 단독으로 키보드를 처리.
- 검증: 디버그 실행 → 이메일/비번 탭하여 키보드 올림 → 노란 바 사라지고 "계정이 없으신가요?"까지
  스크롤로 닿는지 확인.

========================================================
② 롤플레이 인트로 상단바 RIGHT OVERFLOW 6.6px — routine_mode_roleplay.dart  _buildTopBar()
========================================================
구조: Padding(horizontal:16) > Row(spaceBetween, [뒤로가기버튼(width:72), 우측 Row[폰트/언어아이콘 + 타이머 pill]])
원인: 우측 Row의 타이머 pill('1589m' 등)이 넓어 상단 Row가 6.6px 넘침. 잔여시간 자릿수 커지면 재발.

수정 2곳 (둘 다 적용):

(2-A) 뒤로가기 버튼 폭 축소 — 현재:

          GestureDetector(
            onTap: _handleAutoSaveAndExit,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 72,
              height: 56,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 4),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70),
            ),
          ),

  → width: 72 를 width: 56 으로 변경 (나머지는 그대로).

(2-B) 타이머 pill 여백 축소 — 현재 (약 1886~1906행):

            const SizedBox(width: 8),
            // [v3.6] 잔여시간 표시 + 길게 누르면 로그 (개발자용)
            GestureDetector(
              onLongPress: _showDebugLogDialog,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  const Icon(Icons.timer_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${(FFAppState().remainingTime / 60).floor()}m',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
            ),

  → 아래로 교체 (SizedBox 8→4, pill padding horizontal 16→10, 텍스트를 FittedBox로 감싸 자릿수 증가 대비):

            const SizedBox(width: 4),
            // [v3.6] 잔여시간 표시 + 길게 누르면 로그 (개발자용)
            GestureDetector(
              onLongPress: _showDebugLogDialog,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${(FFAppState().remainingTime / 60).floor()}m',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
              ),
            ),

  → 합산 약 22px 여유 확보로 6.6px 해소 + 자릿수 증가에도 안전.
- 검증: 디버그 실행 → 롤플레이 인트로 화면에서 노란 바 사라지고 타이머 숫자 안 잘리는지 확인.

========================================================
공통 마무리
========================================================
- dart analyze 통과.
- 두 화면 모두 디버그에서 노란-검정 오버플로 바가 더 이상 안 뜨는지 육안 확인.
- STT/TTS/프롬프트 등 로직은 일절 안 건드렸는지 diff로 재확인.