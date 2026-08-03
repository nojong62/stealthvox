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
import 'dart:async';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '/custom_code/actions/billing_ticker.dart';
import '/custom_code/services/deepgram_prewarm_session.dart';
import '/custom_code/services/openai_connection_pool.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'trial/trial_flow_state.dart';
import 'circle_talk_guide.dart';

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

class _StealthRoomMasterState extends State<StealthRoomMaster>
    with WidgetsBindingObserver {
  // ============================================================================
  // 📦 [1. 상태 변수 및 모드 제어 (STATE & MODE CONTROL)]
  // 현재 선택된 모드(Duo, Clone, Roleplay, Expand)를 기억하고 전환하는 역할
  // ============================================================================
  // 0: 메뉴 화면, 1: Duo, 2: Circle Talk, 3: Roleplay, 4: Expand
  int? _currentMode;
  bool _circleSetupOpen = false;
  bool _isRecommendingCircle = false;
  String? _selectedCircleDescription;
  final TextEditingController _circleController = TextEditingController();
  final AudioRecorder _anyoneAudioRecorder = AudioRecorder();
  late Future<void> _anyoneAudioReady;
  DateTime? _anyoneMicInputAt;
  // 🎤 [ENTRY-GATE] Circle Talk은 서클 선택 후 입장하고, 준비가 끝나는 즉시
  //   Deepgram 청취와 Realtime verse 응답을 시작한다.
  // 초대 링크에서 소비한 roomId (1회용 — build에서 Duo 생성자에 전달)
  String? _pendingDuoRoomId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StealthRoomMaster.exitCurrentMode = () {
      setState(() {
        _currentMode = null;
        _circleSetupOpen = false;
        _selectedCircleDescription = null;
      });
      unawaited(_refreshAnyonePrewarmAfterExit());
    };
    AppsFlyerManager.duoInviteSignal.addListener(_onDuoInviteSignal);
    _anyoneAudioReady = _prepareAnyoneAudioInput();
    unawaited(_prepareFirstUserResponse());

    // Duo 초대 링크 자동 진입 처리
    // FFAppState 초대 상태는 여기서 지우지 않음 — _joinAsGuest 성공 후에만 삭제
    if (FFAppState().isGuestSession && FFAppState().duoRoomId.isNotEmpty) {
      final String consumedRoomId = FFAppState().duoRoomId;
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

    // 트라이얼 Anyone 자동 진입 — 메뉴 화면을 건너뛰고 바로 Anyone 모드로
    TrialFlowState.instance.restoreFromAppState();
    if (TrialFlowState.instance.isTrialAnyone) {
      _anyoneMicInputAt = DateTime.now();
      _currentMode = 2;
    }
  }

  Future<void> _refreshAnyonePrewarmAfterExit() async {
    // 이전 Anyone의 recorder/소켓 정리가 끝난 뒤 다음 입장을 다시 준비한다.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || _currentMode != null) return;
    _anyoneAudioReady = _prepareAnyoneAudioInput();
    unawaited(_prepareFirstUserResponse());
  }

  /// StealthRoom 메뉴를 보는 동안 첫 유저 번역/TTS용 OpenAI 연결을 준비한다.
  /// UI나 모드 진입을 막지 않으며, 준비 실패 시 각 모드의 기존 요청이 동작한다.
  Future<void> _prepareFirstUserResponse() async {
    final remoteConfig = FirebaseRemoteConfig.instance;
    String openAiKey = remoteConfig.getString('OpenAIAPIKey');
    String deepgramKey = remoteConfig.getString('DeepgramAPIKey');

    if (openAiKey.isEmpty || deepgramKey.isEmpty) {
      try {
        await remoteConfig
            .fetchAndActivate()
            .timeout(const Duration(seconds: 6));
        openAiKey = remoteConfig.getString('OpenAIAPIKey');
        deepgramKey = remoteConfig.getString('DeepgramAPIKey');
      } catch (error) {
        debugPrint('[ROOM-PREWARM] key unavailable: ${error.runtimeType}');
      }
    }

    if (deepgramKey.isNotEmpty) {
      final nativeLanguage = FFAppState().nativeLang.isNotEmpty
          ? FFAppState().nativeLang
          : 'Korean';
      unawaited(DeepgramPrewarmSession.instance.prepare(
        apiKey: deepgramKey,
        languageCode: deepgramLanguageCode(nativeLanguage),
        onLog: debugPrint,
      ));
    }
    if (openAiKey.isNotEmpty) {
      await OpenAiConnectionPool.instance.warmUp(
        openAiKey,
        onLog: debugPrint,
      );
    }
  }

  /// 메뉴 진입 시 권한 요청과 record 플러그인 채널 초기화를 끝낸다.
  Future<void> _prepareAnyoneAudioInput() async {
    final stopwatch = Stopwatch()..start();
    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        debugPrint('[ANY-INPUT-PREWARM] permission_denied');
        return;
      }
      await _anyoneAudioRecorder.hasPermission();
      await _anyoneAudioRecorder.isRecording();
      debugPrint(
          '[ANY-INPUT-PREWARM] ready elapsedMs=${stopwatch.elapsedMilliseconds}');
    } catch (error) {
      debugPrint(
          '[ANY-INPUT-PREWARM] failed reason=${error.runtimeType} elapsedMs=${stopwatch.elapsedMilliseconds}');
    } finally {
      stopwatch.stop();
    }
  }

  /// 딥링크 신호 수신 후 StealthRoom 메뉴에서 Duo로 진입한다.
  void _onDuoInviteSignal() {
    if (!mounted) return;
    if (FFAppState().isGuestSession &&
        FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[StealthRoom] duoInviteSignal - entering Duo mode');
      setState(() {
        _pendingDuoRoomId = FFAppState().duoRoomId;
        _currentMode = 1;
      });
    }
  }

  @override
  void dispose() {
    AppsFlyerManager.duoInviteSignal.removeListener(_onDuoInviteSignal);
    WidgetsBinding.instance.removeObserver(this);
    StealthRoomMaster.exitCurrentMode = null;
    _circleController.dispose();
    unawaited(DeepgramPrewarmSession.instance.discard(reason: 'room_dispose'));
    unawaited(_anyoneAudioRecorder.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      BillingTicker.instance.flushNow();
    }
  }

  void _switchMode(int newMode) {
    if (newMode == 2) {
      setState(() => _circleSetupOpen = true);
      return;
    }
    if (_currentMode == newMode) return;
    setState(() {
      _currentMode = newMode;
    });
  }

  void _enterCircleTalk(String description) {
    final clean = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('참여할 서클을 입력해 주세요.')),
      );
      return;
    }
    _anyoneMicInputAt = DateTime.now();
    debugPrint(
        '[FIRST-SPEECH] event=MIC_INPUT at=${_anyoneMicInputAt!.toIso8601String()} deltaMs=0');
    setState(() {
      _selectedCircleDescription =
          clean.length > 200 ? clean.substring(0, 200) : clean;
      _circleSetupOpen = false;
      _currentMode = 2;
    });
  }

  Future<void> _recommendCircle() async {
    if (_isRecommendingCircle) return;
    setState(() => _isRecommendingCircle = true);
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      String apiKey = remoteConfig.getString('OpenAIAPIKey').trim();
      if (apiKey.isEmpty) {
        await remoteConfig
            .fetchAndActivate()
            .timeout(const Duration(seconds: 8));
        apiKey = remoteConfig.getString('OpenAIAPIKey').trim();
      }
      if (apiKey.isEmpty) throw StateError('OpenAI key unavailable');

      final response = await OpenAiConnectionPool.instance.client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': 'gpt-4o-mini',
              'temperature': 1.2,
              'response_format': <String, String>{'type': 'json_object'},
              'max_tokens': 180,
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content':
                      '''Create one unpredictable Korean circle name for member-to-member conversation.
A circle is a company, workplace, professional team, project group, club, hobby group, association, or community.
Return ONLY valid JSON: {"name":"..."}.
- Vary widely across work, industry, business, hobbies, lifestyle, and local communities.
- Make the name concrete enough to imply its members, vocabulary, atmosphere, and common concerns.
- name: one natural Korean circle name, 30 characters or fewer.
- Do not create a classroom, AI chat, language-learning group, or generic casual-chat group.''',
                },
                <String, String>{
                  'role': 'user',
                  'content': '지금 참여해 볼 무작위 서클 하나를 추천해 줘.',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw http.ClientException('status=${response.statusCode}');
      }
      final envelope = jsonDecode(utf8.decode(response.bodyBytes));
      final content = envelope['choices'][0]['message']['content'].toString();
      final recommendation = jsonDecode(content) as Map<String, dynamic>;
      final name = (recommendation['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        throw const FormatException('empty recommendation');
      }

      if (!mounted) return;
      _circleController.value = TextEditingValue(
        text: name,
        selection: TextSelection.collapsed(offset: name.length),
      );
    } catch (error) {
      debugPrint('[CIRCLE-RECOMMEND] failed reason=${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서클을 추천하지 못했습니다. 다시 눌러 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRecommendingCircle = false);
    }
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
                          _buildManualItem('Circle Talk', '커뮤니티 대화',
                              'AI 추천을 받거나 원하는 커뮤니티를 직접 입력하세요. AI가 그 서클의 구성원이 되어 분야의 말투, 관심사와 분위기에 맞춰 자연스럽게 대화합니다.'),
                          const Divider(color: Colors.white12, height: 24),
                          _buildManualItem('AI Roleplay', '상황극 대화',
                              '창의적이고 구체적인 역할과 상황을 무한히 추천받고, 현실감 넘치는 실전 비즈니스 및 일상 회화를 연습합니다.'),
                          const Divider(color: Colors.white12, height: 24),
                          _buildManualItem('Step Expand', '점진적 문장 확장',
                              '짧은 기초 문장부터 시작해, AI의 날카로운 질문에 대답하며 점점 길고 세련된 문장 구조를 만들어가는 집중 훈련입니다.'),
                          const Divider(color: Colors.white12, height: 32),
                          _buildBillingLegend(),
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

  Widget _buildBillingLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '과금 인디케이터',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        _buildBillingDotRow(
          2,
          'AI 대화 중 1초 차감, 복습·히스토리 체류 시 4초당 1초 차감',
        ),
        const SizedBox(height: 10),
        _buildBillingDotRow(
          0,
          '과금 정지 — 마이크 대기(오토포즈) 시 자동 정지',
        ),
      ],
    );
  }

  Widget _buildBillingDotRow(int state, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(
                painter: BillingDotPainter(state),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // 📦 [3. 메인 화면 라우터 (MAIN BUILDER / ROUTER)]
  // 선택된 모드(_currentMode)에 따라 각 훈련 위젯을 화면에 띄워주는 역할
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    if (_currentMode == 2) {
      return RoutineModeAnyone(
        key: const ValueKey('RoutineModeAnyone'),
        width: widget.width,
        height: widget.height,
        preparedAudioRecorder: _anyoneAudioRecorder,
        audioPreparation: _anyoneAudioReady,
        micInputAt: _anyoneMicInputAt,
        circleDescription: _selectedCircleDescription ?? '편안한 일상 대화 커뮤니티',
      );
    }
    if (_currentMode == 4) {
      // 준비 화면을 거치지 않는다 — 곧바로 페이지로 들어가고, 안내 문구는
      // 스텝 페이지가 직접 띄운다. onListeningReady를 넘기지 않는 것이 그
      // 스위치다(routine_mode_step_expand.dart `_startSessionWaitingForUserSeed`).
      return RoutineModeStepExpand(
        key: const ValueKey('RoutineModeStepExpand'),
        width: widget.width,
        height: widget.height,
      );
    }
    if (_currentMode == 1) {
      return RoutineModeDuo(
          key: const ValueKey('RoutineModeDuo'),
          width: widget.width,
          height: widget.height,
          roomId: _pendingDuoRoomId);
    } else if (_currentMode == 3) {
      return RoutineModeRoleplay(
          key: const ValueKey('RoutineModeRoleplay'),
          width: widget.width,
          height: widget.height);
    }

    if (_circleSetupOpen) return _buildCircleSetup();

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
                    tooltip: '이전 단계',
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    constraints:
                        const BoxConstraints(minWidth: 64, minHeight: 56),
                    onPressed: () => context.pop()),
              ]),
              GestureDetector(
                  onTap: () => context.pushNamed('ChatHistory'),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF3B82F6)
                                .withValues(alpha: 0.5))),
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
            _buildMenuCard(2, "Circle Talk", "서클 구성원 대화",
                Icons.groups_rounded, const Color(0xFF9333EA)),
            _buildMenuCard(3, "AI Roleplay", "상황극 대화", Icons.smart_toy,
                const Color(0xFF16A34A)),
            _buildMenuCard(4, "Step Expand", "점진적 문장 확장", Icons.trending_up,
                const Color(0xFFEA580C)),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleSetup() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF121212),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => setState(() => _circleSetupOpen = false),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 22),
                    tooltip: '대화 모드 선택으로 돌아가기',
                  ),
                  IconButton(
                    onPressed: () => showCircleTalkGuide(context),
                    icon: const Icon(Icons.menu_book_rounded,
                        color: Color(0xFFB46CFF), size: 25),
                    tooltip: 'Circle Talk 사용설명서',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Circle Talk',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '서클을 추천받거나 직접 입력하세요.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'AI는 정보를 설명하는 사람이 아니라, 선택한 서클의 한 구성원이 되어 그 분야의 분위기와 말투로 대화합니다.',
                style:
                    TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Icon(Icons.groups_rounded,
                    color: Color(0xFFB46CFF), size: 64),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 56,
                    child: OutlinedButton(
                      onPressed:
                          _isRecommendingCircle ? null : _recommendCircle,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        side: const BorderSide(color: Color(0xFF9333EA)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isRecommendingCircle
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFB46CFF),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.auto_awesome_rounded, size: 17),
                                SizedBox(width: 6),
                                Text('서클 추천',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _circleController,
                      maxLength: 200,
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white),
                      textInputAction: TextInputAction.done,
                      onSubmitted: _enterCircleTalk,
                      decoration: InputDecoration(
                        hintText: '직접 서클 입력',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 17),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: Color(0xFF9333EA), width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _enterCircleTalk(_circleController.text),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9333EA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.forum_rounded),
                label: const Text('이 서클에서 대화 시작',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
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
