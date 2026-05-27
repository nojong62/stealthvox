// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'index.dart'; // Imports other custom widgets

import '/custom_code/actions/index.dart';
// Imports custom actions

import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

class StealthRoomMaster extends StatefulWidget {
  const StealthRoomMaster({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);
  final double? width;
  final double? height;

  static void Function()? exitCurrentMode;

  @override
  _StealthRoomMasterState createState() => _StealthRoomMasterState();
}

class _StealthRoomMasterState extends State<StealthRoomMaster> {
  // ============================================================================
  // 📦 [1. 상태 변수 및 모드 제어 (STATE & MODE CONTROL)]
  // 현재 선택된 모드(Duo, Clone, Roleplay, Expand)를 기억하고 전환하는 역할
  // ============================================================================
  // 0: 메뉴 화면, 1: Duo, 2: Clone, 3: Roleplay, 4: Expand
  int? _currentMode;

  // 초대 링크에서 소비한 roomId (1회용 — build에서 Duo 생성자에 전달)
  String? _pendingDuoRoomId;

  @override
  void initState() {
    super.initState();
    StealthRoomMaster.exitCurrentMode =
        () => setState(() => _currentMode = null);

    // Duo 초대 링크 자동 진입 처리
    // roomId를 로컬 변수에 옮기고 FFAppState는 즉시 clear → 뒤로가기 루프 방지
    if (FFAppState().isGuestSession &&
        FFAppState().duoRoomId.isNotEmpty) {
      final String consumedRoomId = FFAppState().duoRoomId;
      FFAppState().isGuestSession = false;
      FFAppState().duoRoomId = '';
      debugPrint('[AppState] duo invite state cleared');
      debugPrint('[StealthRoom] Duo invite detected — roomId: $consumedRoomId');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _pendingDuoRoomId = consumedRoomId;
            _currentMode = 1;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    StealthRoomMaster.exitCurrentMode = null;
    super.dispose();
  }

  void _switchMode(int newMode) {
    setState(() {
      _currentMode = newMode;
    });
  }

// ============================================================================
  // 📦 [2. 도움말 및 팝업 (MANUAL & DIALOGS)]
  // 스텔스 훈련소 가이드 팝업창 및 설명 텍스트 렌더링
  // ============================================================================
  void _showManualDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Dialog(
            backgroundColor: const Color(0xFF1C1C1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.help_outline_rounded,
                          color: Colors.amberAccent, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "대화 모드 설명서",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildManualItem('Duo Connect', '초청인 대화',
                              '초청 링크를 통해 파트너와 함께 모국어로 대화하면, 실시간으로 통역해주는 글로벌 만능 통역 모드입니다.'),
                          const Divider(color: Colors.white12, height: 24),
                          _buildManualItem('Clone AI', '클론 AI와 대화',
                              '지인의 카카오톡 대화를 분석하여 완벽하게 복제된 클론 AI 파트너와 실감나는 롤플레잉 훈련을 진행합니다.'),
                          const Divider(color: Colors.white12, height: 24),
                          _buildManualItem('AI Roleplay', '상황극 대화',
                              '창의적이고 구체적인 역할과 상황을 무한히 추천받고, 현실감 넘치는 실전 비즈니스 및 일상 회화를 연습합니다.'),
                          const Divider(color: Colors.white12, height: 24),
                          _buildManualItem('Step Expand', '점진적 문장 확장',
                              '짧은 기초 문장부터 시작해, AI의 날카로운 질문에 대답하며 점점 길고 세련된 문장 구조를 만들어가는 집중 훈련입니다.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("확인",
                          style: TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildManualItem(String title, String label, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 💡 [수술 핵심] 좁은 화면에서 배지가 잘리지 않게 Row 대신 Wrap으로 변경
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8, // 가로 간격
          runSpacing: 4, // 줄바꿈 시 세로 간격
          children: [
            Text(title,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4)),
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(desc,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.4)),
      ],
    );
  }

  // ============================================================================
  // 📦 [3. 메인 화면 라우터 (MAIN BUILDER / ROUTER)]
  // 선택된 모드(_currentMode)에 따라 각 훈련 위젯을 화면에 띄워주는 역할
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    if (_currentMode == 1) {
      return RoutineModeDuo(
          key: const ValueKey('RoutineModeDuo'),
          width: widget.width,
          height: widget.height,
          roomId: _pendingDuoRoomId);
    } else if (_currentMode == 2) {
      return RoutineModeClone(
          key: const ValueKey('RoutineModeClone'),
          width: widget.width,
          height: widget.height);
    } else if (_currentMode == 3) {
      return RoutineModeRoleplay(
          key: const ValueKey('RoutineModeRoleplay'),
          width: widget.width,
          height: widget.height);
    } else if (_currentMode == 4) {
      return RoutineModeStepExpand(
          key: const ValueKey('RoutineModeStepExpand'),
          width: widget.width,
          height: widget.height);
    }

    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF121212),
      child: _buildMenu(),
    );
  }

  // ============================================================================
  // 📦 [4. 메뉴 UI 빌더 (MENU UI BUILDERS)]
  // 초기 메뉴 화면과 4가지 모드 선택 카드 렌더링
  // ============================================================================
  Widget _buildMenu() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                IconButton(
                    icon: const Icon(Icons.home_rounded,
                        color: Colors.white70, size: 26),
                    onPressed: () => context.pushNamed('Lobby')),
                IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 22),
                    onPressed: () => context.pop()),
              ]),
              GestureDetector(
                  onTap: () => context.pushNamed('ChatHistory'),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF3B82F6).withOpacity(0.5))),
                    child: const Text("Study Room",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ))
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("대화 모드 선택",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.3)),
              // 💡 도움말 아이콘 (클릭 시 _showManualDialog 실행)
              IconButton(
                onPressed: _showManualDialog,
                icon: const Icon(Icons.help_outline,
                    color: Colors.amberAccent, size: 30),
              )
            ]),
            const SizedBox(height: 30),
            _buildMenuCard(1, "Duo Connect", "초청인 대화\n만능 통역", Icons.people,
                const Color(0xFF2563EB)),
            _buildMenuCard(2, "Clone AI", "클론 AI와 대화", Icons.face,
                const Color(0xFF9333EA)),
            _buildMenuCard(3, "AI Roleplay", "상황극 대화", Icons.smart_toy,
                const Color(0xFF16A34A)),
            _buildMenuCard(4, "Step Expand", "점진적 문장 확장", Icons.trending_up,
                const Color(0xFFEA580C)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
      int mode, String title, String desc, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.5)),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28)),
        const SizedBox(width: 16),
        Expanded(
            child: GestureDetector(
                onTap: () => _switchMode(mode),
                child: Container(
                    color: Colors.transparent,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(desc,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12))
                        ])))),
        GestureDetector(
            onTap: () => _switchMode(mode),
            child: const Icon(Icons.arrow_forward_ios,
                color: Colors.white30, size: 16))
      ]),
    );
  }
}
