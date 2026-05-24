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

Claude Code 지시문 — 언어 표시 3단 토글 변경
📋 파일: chat_history_master.dart
목적
언어 전환 아이콘 버튼을 2-state(영어+한글 ↔ 영어만)에서 3-state 순환(영어+한글 → 영어만 → 한글만 → 영어+한글…)으로 변경한다.
모드 정의

0 = 영어 + 한글 (기본값, 앱 진입 시)
1 = 영어만 (한글 숨김)
2 = 한글만 (영어 숨김)


변경 ① — 상태 변수 선언 (줄 58)
삭제:
dart  bool _showOriginal = true;
교체:
dart  /// 언어 표시 모드: 0=영어+한글, 1=영어만, 2=한글만
  int _langDisplayMode = 0;

변경 ② — 아이콘 버튼 영역 (줄 2829~2838)
삭제: 줄 2829 IconButton( 부터 줄 2838 ), 까지 (닫는 괄호+쉼표 포함)
교체:
dart          IconButton(
            icon: CustomPaint(
              size: const Size(26, 26),
              painter: _LangIconPainter(mode: _langDisplayMode),
            ),
            tooltip: _langDisplayMode == 0
                ? '영어만 보기'
                : _langDisplayMode == 1
                    ? '한글만 보기'
                    : '영어+한글 보기',
            onPressed: () => setState(() {
              _langDisplayMode = (_langDisplayMode + 1) % 3;
            }),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),

변경 ③ — 메시지 말풍선 렌더링 (줄 3089~3107 부근)
삭제: 줄 3089 Text(translated, 부터 줄 3107 ], 까지 (children 내부의 translated Text + _showOriginal 조건부 블록 전체)
교체:
dart                            // 영어(타겟) 표시: mode 0,1 에서 보임
                            if (_langDisplayMode != 2) ...[
                              Text(translated,
                                  textAlign:
                                      isHost ? TextAlign.right : TextAlign.left,
                                  style: TextStyle(
                                      color: isHost
                                          ? Colors.white
                                          : const Color(0xFF93C5FD),
                                      fontSize: 16 * _fontScale,
                                      fontWeight: FontWeight.bold,
                                      height: 1.4)),
                            ],
                            // 한글(원어) 표시: mode 0,2 에서 보임
                            if (_langDisplayMode != 1 &&
                                original.isNotEmpty) ...[
                              if (_langDisplayMode == 0)
                                const SizedBox(height: 8),
                              Text(original,
                                  textAlign:
                                      isHost ? TextAlign.right : TextAlign.left,
                                  style: TextStyle(
                                      color: _langDisplayMode == 2
                                          ? (isHost
                                              ? Colors.white
                                              : const Color(0xFF93C5FD))
                                          : Colors.grey,
                                      fontSize: _langDisplayMode == 2
                                          ? 16 * _fontScale
                                          : 12 * _fontScale,
                                      fontWeight: _langDisplayMode == 2
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                            ],

설명: mode 2(한글만)에서는 한글 텍스트가 주인공이 되므로, 영어 표시 때와 동일한 색상·크기·굵기를 적용. mode 0(둘 다)에서는 기존처럼 회색·작은 폰트.


변경 ④ — _LangIconPainter 클래스 전체 교체 (줄 5814~5916)
삭제: 줄 5814 class _LangIconPainter extends CustomPainter { 부터 줄 5916 파일 끝 } 까지 전체
교체:
dartclass _LangIconPainter extends CustomPainter {
  /// 0=영어+한글, 1=영어만, 2=한글만
  final int mode;
  const _LangIconPainter({required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    canvas
        .clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));

    // ── 배경 ──
    // mode 0: 파란 투톤, mode 1: 하단 파란+상단 어둡게, mode 2: 상단 파란+하단 어둡게
    if (mode == 0) {
      // 밝은 파란 전체
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = const Color(0xFF1E7DB5));
      // 짙은 파란 삼각형 (하단 우측)
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.05, size.height)
          ..lineTo(size.width, size.height * 0.05)
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = const Color(0xFF0B4870),
      );
    } else if (mode == 1) {
      // 영어만: 상단(원어) 어둡게, 하단(타겟) 파란
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = const Color(0xFF2A2A2A));
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.05, size.height)
          ..lineTo(size.width, size.height * 0.05)
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = const Color(0xFF0B4870),
      );
    } else {
      // 한글만: 상단(원어) 파란, 하단(타겟) 어둡게
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = const Color(0xFF1E7DB5));
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.05, size.height)
          ..lineTo(size.width, size.height * 0.05)
          ..lineTo(size.width, size.height)
          ..close(),
        Paint()..color = const Color(0xFF2A2A2A),
      );
    }

    // ── 대각선 ──
    canvas.drawLine(
      Offset(size.width * 0.04, size.height * 0.96),
      Offset(size.width * 0.96, size.height * 0.04),
      Paint()
        ..color = const Color(0xFFD4AF37)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // ── 원형 테두리 ──
    canvas.drawCircle(
      center,
      r - 1.5,
      Paint()
        ..color = const Color(0xFFD4AF37)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ── 상단 좌측 "T" (원어/한글) ──
    final bool origActive = (mode == 0 || mode == 2);
    _drawText(canvas, 'T', Offset(size.width * 0.09, size.height * 0.06),
        size.width * 0.34, origActive ? Colors.white : const Color(0x44FFFFFF));

    // ── 상단 우측: 빨간 점(활성) 또는 X(비활성) ──
    if (origActive) {
      final dotC = Offset(size.width * 0.63, size.height * 0.23);
      final dotR = size.width * 0.105;
      canvas.drawCircle(dotC, dotR, Paint()..color = const Color(0xFFE03030));
      canvas.drawCircle(
          dotC, dotR * 0.45, Paint()..color = const Color(0xFFFF6060));
      canvas.drawCircle(
          dotC,
          dotR,
          Paint()
            ..color = const Color(0xBBFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
    } else {
      // 원어 숨김 X
      final xPaint = Paint()
        ..color = Colors.redAccent.withOpacity(0.65)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(size.width * 0.53, size.height * 0.11),
          Offset(size.width * 0.74, size.height * 0.32), xPaint);
      canvas.drawLine(Offset(size.width * 0.74, size.height * 0.11),
          Offset(size.width * 0.53, size.height * 0.32), xPaint);
    }

    // ── 하단 우측 "T" (타겟/영어) ──
    final bool targetActive = (mode == 0 || mode == 1);
    _drawText(canvas, 'T', Offset(size.width * 0.55, size.height * 0.58),
        size.width * 0.34, targetActive ? Colors.white : const Color(0x44FFFFFF));

    // ── 하단 좌측: 타겟 비활성일 때 X 표시 ──
    if (!targetActive) {
      final xPaint = Paint()
        ..color = Colors.redAccent.withOpacity(0.65)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(size.width * 0.27, size.height * 0.65),
          Offset(size.width * 0.48, size.height * 0.86), xPaint);
      canvas.drawLine(Offset(size.width * 0.48, size.height * 0.65),
          Offset(size.width * 0.27, size.height * 0.86), xPaint);
    }
  }

  void _drawText(
      Canvas canvas, String text, Offset offset, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              height: 1.0)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_LangIconPainter old) => old.mode != mode;
}

검증 체크리스트

mode 0 (영어+한글): 기존과 동일하게 영어 큰 글씨 + 한글 작은 회색 글씨
mode 1 (영어만): 한글 사라짐, 아이콘 상단 T 어둡게+X 표시
mode 2 (한글만): 영어 사라지고 한글이 큰 글씨+메인 색상으로 승격, 아이콘 하단 T 어둡게+X 표시
3번 클릭하면 원래(mode 0)로 복귀
_showOriginal 키워드가 파일 내 0개인지 확인 (전부 _langDisplayMode로 대체됨)