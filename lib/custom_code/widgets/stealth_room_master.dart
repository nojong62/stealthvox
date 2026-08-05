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
import 'dart:math'; // 서클 분야 순서 셔플
import 'package:shared_preferences/shared_preferences.dart'; // 분야 순회 커서
import 'package:firebase_auth/firebase_auth.dart'; // 회원별 커서 분리
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

  // 🎬 Scenario Talk 설정 — 써클톡과 같은 앞 페이지 구조.
  //   예전에는 방 안에 초록 박스로 상황을 띄웠는데, 들어가기 전에 정하고
  //   확인하는 편이 자연스러워 앞 페이지로 뺐다.
  bool _scenarioSetupOpen = false;
  bool _isRecommendingScenario = false;
  final TextEditingController _situationController = TextEditingController();
  final TextEditingController _aiRoleController = TextEditingController();
  final TextEditingController _userRoleController = TextEditingController();
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
        _scenarioSetupOpen = false;
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
    _situationController.dispose();
    _aiRoleController.dispose();
    _userRoleController.dispose();
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
    if (newMode == 3) {
      setState(() => _scenarioSetupOpen = true);
      // 비어 있으면 첫 제안을 미리 받아 둔다.
      if (_situationController.text.trim().isEmpty) _recommendScenario();
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

  /// 🎯 서클 분야 120개.
  ///   모델에게 "평범한 서클 하나 만들어"라고만 하면 카페·회사 같은 확률 높은
  ///   답 몇 개로 수렴한다. 온도를 올리면 이번엔 기괴한 게 나온다. 그래서
  ///   분야를 여기서 정해 던지고, 모델은 그 안에서만 이름을 짓게 한다.
  ///   다양성은 이 목록이, 색깔은 분야의 구체성이 만든다.
  static const List<String> _circleDomains = [
    // ── 직장·업종 (60) ──
    '무역회사', '물류센터', '택배 대리점', '제조 공장', '자동차 정비소', '건설 현장',
    '인테리어 시공팀', '부동산 중개사무소', '회계사무소', '세무사사무소', '법무사사무소',
    '보험 설계사', '은행 지점', '증권사 영업점', '광고 대행사', '디자인 스튜디오',
    '인쇄소', '출판사', '방송 제작팀', '신문사 편집국', 'IT 스타트업', '소프트웨어 개발팀',
    '고객센터 상담팀', '병원 간호팀', '약국', '치과', '한의원', '동물병원',
    '물리치료실', '요양원', '어린이집', '유치원', '초등학교 교무실', '학원 강사실',
    '대학 연구실', '도서관', '박물관', '미술관', '호텔 프런트', '여행사',
    '항공사 지상직', '렌터카 영업소', '카페', '베이커리', '정육점', '반찬가게',
    '청과상', '수산시장', '편의점', '대형마트', '백화점 매장', '옷가게',
    '신발가게', '안경점', '꽃집', '문구점', '서점', '미용실', '네일숍', '세탁소',
    // ── 동호회·취미 (35) ──
    '축구 동호회', '풋살팀', '배드민턴 동호회', '탁구 동호회', '테니스 동호회',
    '볼링 동호회', '야구 동호회', '농구 동호회', '등산 모임', '자전거 동호회',
    '러닝 크루', '마라톤 모임', '수영 동호회', '골프 모임', '낚시 동호회',
    '캠핑 동호회', '백패킹 모임', '클라이밍 동호회', '요가 모임', '필라테스 수강생',
    '헬스장 회원', '복싱 체육관', '검도 도장', '태권도장', '독서 모임',
    '사진 동호회', '영화 감상 모임', '보드게임 모임', '합창단', '직장인 밴드',
    '통기타 모임', '댄스 동아리', '서예 교실', '도예 공방', '베이킹 클래스',
    // ── 지역·생활 (25) ──
    '아파트 입주민 모임', '아파트 부녀회', '반상회', '학부모회', '어린이집 학부모 모임',
    '통학 도우미 모임', '반려견 산책 모임', '고양이 집사 모임', '텃밭 가꾸기 모임',
    '봉사 동아리', '헌혈 동호회', '재활용 캠페인 모임', '동네 청소 모임', '육아 품앗이',
    '신혼부부 모임', '자취생 모임', '기숙사 룸메이트들', '향우회', '동창회',
    '사내 동호회', '등산 계모임', '계모임', '종교 소모임', '어르신 복지관', '청년 창업 모임',
  ];

  static const String _circleDomainCursorKey = 'circle_domain_cursor_';

  Future<void> _recommendScenario() async {
    if (_isRecommendingScenario) return;
    setState(() => _isRecommendingScenario = true);
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

      final result = await RoleplayBrain.generateDramaticScenario(apiKey);
      if (result == null) throw const FormatException('empty scenario');
      if (!mounted) return;
      setState(() {
        _situationController.text = result['situation'] ?? '';
        _aiRoleController.text = result['ai_role'] ?? '';
        _userRoleController.text = result['user_role'] ?? '';
      });
    } catch (error) {
      debugPrint('[SCENARIO-RECOMMEND] failed reason=${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('상황을 추천하지 못했습니다. 다시 눌러 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRecommendingScenario = false);
    }
  }

  void _enterScenarioTalk() {
    final situation = _situationController.text.trim();
    final aiRole = _aiRoleController.text.trim();
    final userRole = _userRoleController.text.trim();
    if (situation.isEmpty || aiRole.isEmpty || userRole.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상황과 두 역할을 모두 채워 주세요.')),
      );
      return;
    }
    // 방은 이 홀더를 읽어 시나리오를 세팅한다(재진입 보존과 같은 경로).
    RoleplayScenarioStore.situation = situation;
    RoleplayScenarioStore.aiRole = aiRole;
    RoleplayScenarioStore.userRole = userRole;
    setState(() {
      _scenarioSetupOpen = false;
      _currentMode = 3;
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

      // 🔁 회원별 순차 배분. 무작위로 뽑으면 120개를 다 보기 전에 같은 분야가
      //   계속 겹친다. 커서를 하나씩 밀어 한 바퀴 안에는 분야가 안 겹치게 하고,
      //   두 바퀴째부터는 순서를 새로 섞는다.
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final prefs = await SharedPreferences.getInstance();
      final cursorKey = '$_circleDomainCursorKey$uid';
      final cursor = prefs.getInt(cursorKey) ?? 0;
      final round = cursor ~/ _circleDomains.length;
      final order = List<int>.generate(_circleDomains.length, (i) => i)
        ..shuffle(Random(uid.hashCode ^ (round * 0x9E3779B9)));
      final domain = _circleDomains[order[cursor % _circleDomains.length]];
      await prefs.setInt(cursorKey, cursor + 1);
      debugPrint('[CIRCLE-RECOMMEND] domain=$domain round=$round');

      final response = await OpenAiConnectionPool.instance.client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': 'gpt-4o-mini',
              // 분야가 이미 고정돼 있어 이 온도는 "그 분야 안에서 어떤
              // 서클이냐"만 흔든다. 분야 자체가 튀는 일은 없다.
              'temperature': 1.0,
              'response_format': <String, String>{'type': 'json_object'},
              'max_tokens': 180,
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content':
                      '''Name ONE real Korean circle that exists inside this field: "$domain".
A circle is a workplace team, a shop and its regulars, a club, or a local community.
Return ONLY valid JSON: {"name":"..."}.
- Stay inside "$domain". Do not drift to another field.
- Give it the flavour of that field: who these people are and what they deal with.
  "무역회사" → 무역회사 영업팀 / 수출 통관 담당자들 / 무역회사 신입사원들
  "배드민턴 동호회" → 동네 배드민턴 동호회 / 배드민턴 동호회 초보반
  "병원 간호팀" → 소아과 간호사들 / 응급실 야간 간호팀
- It must be a group that really exists and that ordinary people join or visit.
  Concrete is good. Weird is not.
  Bad: 우주덕후 무역회사, 심해어 연구 간호팀, 세계정복 배드민턴부
- One natural Korean name, 20 characters or fewer. No quotes, no explanation.
- Do not create a classroom, AI chat, language-learning group, or generic casual-chat group.''',
                },
                <String, String>{
                  'role': 'user',
                  'content': '"$domain" 분야의 서클 하나를 추천해 줘.',
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
                          _buildManualItem('Scenario Talk', '실전 상황 대화',
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
          '과금 진행중',
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
    if (_scenarioSetupOpen) return _buildScenarioSetup();

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
            _buildMenuCard(2, "Circle Talk", "서클 구성원 대화", Icons.groups_rounded,
                const Color(0xFF9333EA)),
            _buildMenuCard(3, "Scenario Talk", "실전 상황 대화", Icons.smart_toy,
                const Color(0xFF16A34A)),
            _buildMenuCard(4, "Step Expand", "점진적 문장 확장", Icons.trending_up,
                const Color(0xFFEA580C)),
          ],
        ),
      ),
    );
  }

  /// 설정 페이지 두 곳이 함께 쓰는 자판 대응 높이.
  ///   키보드가 올라온 만큼 높이를 줄인다. 그래야 스크롤 뷰포트가 자판 위쪽으로
  ///   한정돼, 입력란을 탭했을 때 Flutter가 그 칸을 위로 밀어 올린다.
  ///   widget.height가 비어 있어도 화면 높이를 기준으로 삼아야 한다. 기준이
  ///   없으면 스크롤 뷰가 콘텐츠 높이를 그대로 요구해서, 자판이 차지한 만큼
  ///   부모를 넘겨 노란 줄무늬가 떴다.
  double _setupVisibleHeight(double keyboardInset) {
    final base = widget.height ?? MediaQuery.of(context).size.height;
    return (base - keyboardInset).clamp(0.0, base);
  }

  /// Scenario Talk 설정 페이지 — 써클톡과 같은 구조/여백/자판 처리.
  Widget _buildScenarioSetup() {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final visibleHeight = _setupVisibleHeight(keyboardInset);
    const accent = Color(0xFF16A34A);
    return Container(
      width: widget.width,
      height: visibleHeight,
      color: const Color(0xFF121212),
      // 자판이 떠 있으면 하단 안전영역은 자판에 가려 보이지도 않는다.
      // 그 패딩을 그대로 두면 좁아진 화면을 더 밀어낸다.
      child: SafeArea(
        bottom: keyboardInset == 0,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 12, 24, keyboardInset > 0 ? 16 : 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => setState(() => _scenarioSetupOpen = false),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 22),
                    tooltip: '대화 모드 선택으로 돌아가기',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Scenario Talk Settings',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '추천을 받거나 원하는 상황과 역할을 직접 입력해도 됩니다.',
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed:
                      _isRecommendingScenario ? null : _recommendScenario,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: accent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isRecommendingScenario
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      : const Text('상황 추천',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              _scenarioField(_situationController, '상황', '예: 카페에서 음료 고르기'),
              const SizedBox(height: 10),
              _scenarioField(_aiRoleController, 'AI 역할', '예: 바리스타'),
              const SizedBox(height: 10),
              _scenarioField(_userRoleController, '내 역할', '예: 단골 손님'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _enterScenarioTalk,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.smart_toy_rounded),
                label: const Text('상황 대화 시작',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scenarioField(
      TextEditingController controller, String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          maxLength: 60,
          maxLines: 1,
          style: const TextStyle(color: Colors.white),
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white30),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            counterText: '',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFF16A34A), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCircleSetup() {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final visibleHeight = _setupVisibleHeight(keyboardInset);
    return Container(
      width: widget.width,
      height: visibleHeight,
      color: const Color(0xFF121212),
      child: SafeArea(
        child: SingleChildScrollView(
          // 자판이 떠 있을 때는 하단 여백을 조금 더 줘서 마지막 버튼까지
          // 가려지지 않게 한다.
          padding: EdgeInsets.fromLTRB(24, 12, 24, keyboardInset > 0 ? 16 : 32),
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
                'Circle Talk Settings',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '원하는 서클을 직접 입력해도 됩니다.',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _isRecommendingCircle ? null : _recommendCircle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
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
                      : const Text('서클 추천',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _circleController,
                maxLength: 200,
                maxLines: 1,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.done,
                onSubmitted: _enterCircleTalk,
                decoration: InputDecoration(
                  hintText: '서클 이름을 입력하세요',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF1E1E1E),
                  counterText: '',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: Color(0xFF9333EA), width: 1.5),
                  ),
                ),
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
                label: const Text('서클 대화 시작',
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
