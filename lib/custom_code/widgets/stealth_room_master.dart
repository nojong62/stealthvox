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
import '/custom_code/services/openai_streaming_transcribe_prewarm.dart';
import '/custom_code/services/openai_streaming_transcribe_session.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'trial/trial_flow_state.dart';
import 'circle_talk_guide.dart';
import 'scenario_talk_guide.dart';

class StealthRoomMaster extends StatefulWidget {
  const StealthRoomMaster({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);
  final double? width;
  final double? height;

  static void Function()? exitCurrentMode;

  /// 지금 열려 있는 모드의 저장·정리 경로(`_handleAutoSaveAndExit`).
  ///
  /// [exitCurrentMode]는 화면만 메뉴로 되돌린다 — 그것만 부르면 방을 강제로
  /// 닫을 때 히스토리 저장과 빈 방 삭제가 통째로 빠진다. 잔여시간 소진처럼
  /// 바깥에서 방을 닫아야 할 때는 각 모드가 스스로 등록해 둔 이 경로를 쓴다.
  static Future<void> Function()? saveAndExitCurrentMode;

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
  //   유저 음성 청취와 AI 첫 마디를 시작한다.
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
    BillingTicker.instance.balanceExhausted.addListener(_onBalanceExhausted);
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

    // 트라이얼 Duo 직접 통화 진입 — 모드 메뉴와 방식 선택을 건너뛴다.
    // 실제 10분은 이 화면 진입이 아니라 초대한 게스트가 방에 들어온 순간부터
    // RoutineModeDuo에서 시작한다.
    TrialFlowState.instance.restoreFromAppState();
    if (TrialFlowState.instance.isTrialDuo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _currentMode = 1);
      });
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

    // 🔥 [STT-PREWARM] 켜진 엔진 **하나만** 예열한다. 둘 다 열면 소켓도 비용도
    //   이중이 된다 (Circle Talk의 전사 경로는 한 턴에 하나뿐이다).
    final nativeLanguage =
        FFAppState().nativeLang.isNotEmpty ? FFAppState().nativeLang : 'Korean';
    if (kFreeTalkUseStreamingStt) {
      if (openAiKey.isNotEmpty) {
        unawaited(OpenAiStreamingTranscribePrewarm.instance.prepare(
          apiKey: openAiKey,
          // 🌐 [ORIGIN-RESOLVE] 언어를 박지 않고 예열한다(빈 값 = 자동 감지).
          //   첫 발화는 유저가 실제로 쓴 언어 그대로 받아야, 로비 ORIGIN이
          //   기본값 그대로인 유저를 가려낼 수 있다. 언어가 확정되면 방이
          //   `switchLanguage`로 갈아 끼운다 — 소켓은 그대로 산다.
          //   모드 쪽 `take()`도 같은 빈 값으로 물어보므로 채택이 어긋나지 않는다.
          languageCode: '',
          onLog: (tag, msg) => debugPrint('$tag $msg'),
        ));
      }
    } else if (deepgramKey.isNotEmpty) {
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

  /// 저장이 몇 초 걸리는 사이에 신호가 또 와서 두 번 나가는 것을 막는다.
  bool _handlingExhaustion = false;

  /// 방 안에서 잔여시간이 0이 됐을 때 — 네 모드 전부 여기서 닫는다.
  ///
  /// 모드마다 따로 붙이지 않는 이유는 나가는 순서 때문이다. 모드가 스스로
  /// 스토어로 이동하면 방이 그 아래 살아남아 마이크와 소켓이 물려 있고, 반대로
  /// 여기서 화면만 메뉴로 되돌리면 히스토리 저장이 빠진다. 모드가 등록해 둔
  /// 저장 경로를 **먼저 끝내고** 그 다음에 스토어로 보낸다.
  Future<void> _onBalanceExhausted() async {
    if (!BillingTicker.instance.balanceExhausted.value) return;
    // 메뉴·설정 화면은 과금하지 않으니 내보낼 이유가 없다.
    if (_currentMode == null) return;
    if (_handlingExhaustion) return;
    _handlingExhaustion = true;
    debugPrint('[StealthRoom] balance exhausted — closing mode $_currentMode');
    try {
      final saveAndExit = StealthRoomMaster.saveAndExitCurrentMode;
      if (saveAndExit != null) {
        await saveAndExit();
      } else {
        // 등록이 없는 모드는 없지만, 남아 있으면 무료로 계속 도는 쪽이 더
        // 나쁘다. 저장은 포기하더라도 방은 닫는다.
        BillingTicker.instance.pause();
        StealthRoomMaster.exitCurrentMode?.call();
      }
      if (!mounted) return;
      dismissRoutesAbove(context);
      showBillingBlockedNotice(
        context,
        message: '잔여 시간이 모두 소진되어 대화를 저장하고 종료했습니다.',
        offerStore: false,
      );
      context.pushNamed('Store');
    } finally {
      _handlingExhaustion = false;
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
    BillingTicker.instance.balanceExhausted.removeListener(_onBalanceExhausted);
    WidgetsBinding.instance.removeObserver(this);
    StealthRoomMaster.exitCurrentMode = null;
    _circleController.dispose();
    _situationController.dispose();
    _aiRoleController.dispose();
    _userRoleController.dispose();
    unawaited(DeepgramPrewarmSession.instance.discard(reason: 'room_dispose'));
    unawaited(OpenAiStreamingTranscribePrewarm.instance
        .discard(reason: 'room_dispose'));
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
    // 모드 진입 = 과금 시작이다. 카드를 누르는 지점에서 막아, 서클·시나리오를
    // 다 채워 넣은 뒤에 되돌려보내는 일이 없게 한다.
    if (!guardBillingEntry(context)) return;
    if (newMode == 2) {
      setState(() => _circleSetupOpen = true);
      // 비어 있으면 첫 제안을 미리 받아 둔다. (Scenario Talk과 같은 규칙)
      if (_circleController.text.trim().isEmpty) _recommendCircle();
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
    // 설정 화면을 열어 둔 사이에 시간이 바닥날 수 있다(다른 기기에서 소진 등).
    // 실제로 과금이 시작되는 이 문에서 한 번 더 본다.
    if (!guardBillingEntry(context)) return;
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

  /// 🎯 서클 분야 200개. 20~50대가 실제로 속해 있을 법한 곳만 담는다.
  ///   모델에게 "평범한 서클 하나 만들어"라고만 하면 카페·회사 같은 확률 높은
  ///   답 몇 개로 수렴한다. 온도를 올리면 이번엔 기괴한 게 나온다. 그래서
  ///   분야를 여기서 정해 던지고, 모델은 그 안에서만 이름을 짓게 한다.
  ///   다양성은 이 목록이, 색깔은 분야의 구체성이 만든다.
  static const List<String> _circleDomains = [
    // ── 직장·업종 (100) ──
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
    '반도체 공장', '조선소', '화학 플랜트', '발전소 정비팀', '철도 정비창',
    '시내버스 회사', '택시 회사', '화물 운송 기사들', '항만 하역팀', '식품 가공 공장',
    '양조장', '커피 로스터리', '프랜차이즈 본사', '치킨집', '국밥집', '삼겹살집',
    '횟집', '중국집', '분식집', '이자카야', '와인바', '배달 라이더들',
    '이사 업체', '청소 용역팀', '아파트 관리사무소', '소방서', '파출소', '우체국',
    '주민센터', '시청 민원실', '농협 지점', '축산 농가', '딸기 농장', '어촌계',
    '목공소', '철물점', '자전거 수리점', '사진 스튜디오', '웨딩 플래너 사무실',
    '인력 파견 사무소',
    // ── 동호회·취미 (55) ──
    '축구 동호회', '풋살팀', '배드민턴 동호회', '탁구 동호회', '테니스 동호회',
    '볼링 동호회', '야구 동호회', '농구 동호회', '등산 모임', '자전거 동호회',
    '러닝 크루', '마라톤 모임', '수영 동호회', '골프 모임', '낚시 동호회',
    '캠핑 동호회', '백패킹 모임', '클라이밍 동호회', '요가 모임', '필라테스 수강생',
    '헬스장 회원', '복싱 체육관', '검도 도장', '태권도장', '독서 모임',
    '사진 동호회', '영화 감상 모임', '보드게임 모임', '합창단', '직장인 밴드',
    '통기타 모임', '댄스 동아리', '서예 교실', '도예 공방', '베이킹 클래스',
    '스쿠버다이빙 동호회', '서핑 모임', '스키 동호회', '스노보드 모임', '배구 동호회',
    '족구 모임', '당구 동호회', '다트 동호회', '바둑 모임', '장기 동호회',
    '캘리그라피 교실', '수채화 교실', '뜨개질 모임', '가죽공예 공방', '향수 공방',
    '와인 동호회', '위스키 모임', '요리 교실', '국궁 활터', '승마 클럽',
    // ── 지역·생활 (45) ──
    '아파트 입주민 모임', '아파트 부녀회', '반상회', '학부모회', '어린이집 학부모 모임',
    '통학 도우미 모임', '반려견 산책 모임', '고양이 집사 모임', '텃밭 가꾸기 모임',
    '봉사 동아리', '헌혈 동호회', '재활용 캠페인 모임', '동네 청소 모임', '육아 품앗이',
    '신혼부부 모임', '자취생 모임', '기숙사 룸메이트들', '향우회', '동창회',
    '사내 동호회', '동네 맘카페 모임', '계모임', '종교 소모임', '복지관 사회복지사들',
    '청년 창업 모임',
    '귀농 귀촌 모임', '전원주택 이웃들', '원룸 이웃들', '재건축 조합', '상가 번영회',
    '전통시장 상인회', '소상공인 모임', '프리랜서 모임', '대학원생 모임', '워킹맘 모임',
    '아빠 육아 모임', '다둥이 부모 모임', '유기견 봉사팀', '지역 축제 준비위',
    '마을 방범대', '이직 준비 모임', '재테크 스터디', '자격증 준비 모임',
    '집수리 품앗이 모임', '캠핑카 오너 모임',
  ];

  /// 🎨 분야에 얹는 변형 축 14개.
  ///   분야 200개를 다 돌아도 모델이 짓는 이름은 "OO 동호회 초보반",
  ///   "동네 OO 단골들" 같은 몇 가지 틀로 수렴한다. 분야가 한 바퀴 돌 때마다
  ///   이 결을 바꿔 던지면 같은 분야가 다시 와도 다른 서클이 나온다.
  ///   200 × 14 = 2,800가지. 첫 칸이 빈 문자열인 건 1회차는 분야 그대로
  ///   보여주기 위해서다.
  static const List<String> _circleFlavors = [
    '',
    '새로 만들어진 지 얼마 안 된',
    '오래돼서 사람들이 서로 다 아는',
    '신입과 막내가 많은',
    '10년 넘은 베테랑이 많은',
    '20대가 주축인',
    '30대가 주축인',
    '40~50대가 주축인',
    '주말에만 모이는',
    '퇴근 후 저녁에 모이는',
    '지방 소도시에 있는',
    '사람이 몇 명 안 되는 작은',
    '사람이 아주 많은 큰',
    '평소엔 온라인으로 만나는',
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
    if (!guardBillingEntry(context)) return;
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

      // 🔁 회원별 순차 배분. 무작위로 뽑으면 200개를 다 보기 전에 같은 분야가
      //   계속 겹친다. 커서를 하나씩 밀어 한 바퀴 안에는 분야가 안 겹치게 하고,
      //   두 바퀴째부터는 순서를 새로 섞는다. 바퀴마다 결(flavor)도 한 칸씩
      //   밀어, 같은 분야가 다시 와도 다른 서클이 된다.
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final prefs = await SharedPreferences.getInstance();
      final cursorKey = '$_circleDomainCursorKey$uid';
      // 🎲 [시작점 무작위] 시나리오톡과 같은 이유. 커서가 없으면 0이 아니라
      //   아무 자리에서 시작한다. 순서는 uid로 고정이라 커서만 0으로 돌아가면
      //   재설치 때마다 같은 분야가 또 첫 추천으로 나온다.
      var cursor = prefs.getInt(cursorKey);
      if (cursor == null) {
        cursor = Random().nextInt(_circleDomains.length);
        await prefs.setInt(cursorKey, cursor);
      }
      final round = cursor ~/ _circleDomains.length;
      final order = List<int>.generate(_circleDomains.length, (i) => i)
        ..shuffle(Random(uid.hashCode ^ (round * 0x9E3779B9)));
      final domain = _circleDomains[order[cursor % _circleDomains.length]];
      final flavor = _circleFlavors[round % _circleFlavors.length];
      // 모델에게는 결까지 붙인 한 덩어리로 던진다. 1회차는 flavor가 비어
      // 있어 예전과 똑같이 분야만 간다.
      final seed = flavor.isEmpty ? domain : '$flavor $domain';
      await prefs.setInt(cursorKey, cursor + 1);
      debugPrint('[CIRCLE-RECOMMEND] seed=$seed round=$round');

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
                      '''Name ONE real Korean circle that matches this seed: "$seed".
A circle is a workplace team, a shop and its regulars, a club, or a local community.
Its members are ordinary Korean adults between their 20s and their 50s.
Return ONLY valid JSON: {"name":"..."}.
- Stay inside "$domain". Do not drift to another field.
- Reflect the whole seed, not just the field. If the seed describes who they are
  or when they meet, let the name carry that.
- Give it the flavour of that field: who these people are and what they deal with.
  "무역회사" → 무역회사 영업팀 / 수출 통관 담당자들 / 무역회사 신입사원들
  "배드민턴 동호회" → 동네 배드민턴 동호회 / 배드민턴 동호회 초보반
  "병원 간호팀" → 소아과 간호사들 / 응급실 야간 간호팀
- Vary the shape of the name. Do NOT fall back on the same few templates every
  time — "OO 동호회 초보반", "동네 OO 단골들", "OO 모임 회원들" are worn out.
  Name the people, the place, the shift, or the thing they gather around.
- It must be a group that really exists and that ordinary people join or visit.
  Concrete is good. Weird is not.
  Bad: 우주덕후 무역회사, 심해어 연구 간호팀, 세계정복 배드민턴부
- One natural Korean name, 20 characters or fewer. No quotes, no explanation.
- Do not create a classroom, AI chat, language-learning group, or generic casual-chat group.''',
                },
                <String, String>{
                  'role': 'user',
                  'content': '"$seed" 서클 하나를 추천해 줘.',
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
                          // Duo는 초대할 때 호스트가 두 방식 중 하나를 고른다.
                          // 설명서에도 그 갈림길이 그대로 보이게 둘을 나눠 쓴다.
                          _buildManualItem('Duo Connect', '초청 직접 대화',
                              '초청 링크로 부른 상대와 서로의 실제 목소리로 자연스럽게 통화하면서, 그 통화에서 어학 공부 자료를 수집하는 기능입니다. 통화가 끝나면 오간 말 중 연습할 가치가 있는 문장만 정리되어 공부방으로 이어지고, 방금 나눈 진짜 대화로 복습합니다.'),
                          const Divider(color: Colors.white12, height: 24),
                          _buildManualItem('Duo Connect', '초청 만능 통역',
                              '초청 링크를 통해 파트너와 함께 모국어로 대화하면, 실시간으로 통역해주는 글로벌 만능 통역 모드입니다.'),
                          const Divider(color: Colors.white12, height: 24),
                          _buildManualItem('Circle Talk', '커뮤니티 대화',
                              'AI 추천을 받거나 원하는 커뮤니티를 직접 입력하세요. AI가 그 서클의 구성원이 되어 분야의 말투, 관심사와 분위기에 맞춰 자연스럽게 대화합니다.'),
                          const Divider(color: Colors.white12, height: 24),
                          _buildManualItem('Scenario Talk', '실전 상황 대화',
                              '창의적이고 구체적인 역할과 상황을 무한히 추천받고, 현실감 넘치는 실전 비즈니스 및 일상 회화를 연습합니다.'),
                          const Divider(color: Colors.white12, height: 24),
                          _buildManualItem('Step Expand', '점진적 문장 확장',
                              'AI가 오늘의 뉴스나 가벼운 이야기로 먼저 말을 겁니다. 편하게 주고받다 보면 AI가 그중에서 씨앗문장이 될 만한 당신의 한마디를 찾아냅니다. 그 순간부터 그 문장이 화면에 적히고, 이어지는 질문에 답할 때마다 문장이 한 조각씩 자라 다섯 번 만에 길고 세련된 한 문장으로 완성됩니다. 씨앗을 찾기 전 잡담은 화면에 적히지 않습니다.'),
                          const Divider(color: Colors.white12, height: 32),
                          _buildSessionLegend(),
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

  /// 30분 세션 안내. "끊긴다"가 아니라 "저장된다"로 읽히게 쓴다 — 실제로도
  /// 방에서 나가지 않고 같은 화면에서 대화가 이어진다.
  Widget _buildSessionLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '대화 세션 (30분)',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '대화방은 30분 단위 세션으로 운영됩니다. 30분이 지나도 대화가 끊기거나 '
          '방에서 나가지 않습니다 — 지금까지의 대화가 기록에 저장되고, 같은 '
          '화면에서 이어서 계속 대화할 수 있습니다.',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '말하는 도중에 30분이 되어도 하던 말과 AI의 답변이 끝난 뒤에 저장되므로, '
          '한 번의 대화가 둘로 잘리지 않습니다.',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '30',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '세션이 끝나기 30초 전부터 잔여시간 자리에 남은 초가 표시되고, '
                '마지막 10초에는 과금 표시등이 주황색으로 깜박입니다. 저장이 '
                '끝나면 잔여시간 표시로 돌아옵니다.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '이 30초 동안에도 잔여시간은 평소와 똑같이 차감됩니다.',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            height: 1.5,
          ),
        ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 상단 줄은 좌우 여백 바깥에 둔다 — 아래 구분선이 화면 끝까지
          // 이어져야 본문과 갈라져 보인다.
          _buildMenuTopBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("대화 모드 선택",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          height: 1.3)),
                  const SizedBox(height: 22),
                  _buildMenuCard(1, "Duo Connect", "초청 직접 대화\n초청 만능 통역",
                      Icons.people, const Color(0xFF3B82F6)),
                  _buildMenuCard(2, "Circle Talk", "서클 구성원 대화",
                      Icons.groups_rounded, const Color(0xFFA855F7)),
                  _buildMenuCard(3, "Scenario Talk", "실전 상황 대화",
                      Icons.smart_toy, const Color(0xFF22C55E)),
                  _buildMenuCard(4, "Step Expand", "점진적 문장 확장",
                      Icons.trending_up, const Color(0xFFF97316)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 홈·뒤로 / Study Room / 사용설명서.
  ///
  /// 옮긴 것은 자리뿐이다 — 가는 곳(`Lobby`·`pop`·`ChatHistory`)도, 도움말
  /// 팝업(`_showManualDialog`)도 예전에 쓰던 것 그대로다. 도움말만 제목 옆에서
  /// 이 줄 오른쪽 끝으로 자리를 옮겼다.
  Widget _buildMenuTopBar() {
    // 📏 이 줄에서 폭이 늘어나는 건 "STUDY ROOM" 알약 하나뿐이다. 아이콘 셋은
    //   크기가 고정이라, 폰 글꼴을 크게 써 두면 알약만 부풀어 오른쪽 사용설명서
    //   버튼을 화면 밖으로 밀어낸다(실기기 S25에서 RIGHT OVERFLOWED BY 14 PIXELS).
    //
    //   고치는 방향은 **글자를 줄이는 것이 아니라 자리를 만드는 것**이다.
    //   "STUDY ROOM"은 줄여 적을 이유가 없는 이름이고, `STUDY R…`로 잘리면
    //   그게 더 고장 나 보인다. 그래서 두 가지를 한다.
    //     1. 배율에 천장을 씌운다(§chat_history_list_master 필터 바와 같은 처방).
    //     2. IconButton 셋의 기본 여백을 걷어 40여 px을 되찾는다. 기본
    //        IconButton은 48x48 터치 영역을 잡는데 이 줄에는 그만큼이 필요 없다.
    //   둘을 합치면 알약은 어떤 배율에서도 제 글자를 다 적을 자리를 갖는다.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.home_outlined,
                  color: Color(0xFF22D3EE), size: 26),
              tooltip: '로비로',
              padding: const EdgeInsets.symmetric(horizontal: 8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => context.pushNamed('Lobby'),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF22D3EE), size: 22),
              tooltip: '이전 단계',
              padding: const EdgeInsets.symmetric(horizontal: 8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => context.pop(),
            ),
            const Spacer(),
            // 이름은 통째로 적힌다. 잘리지도, 줄임표가 붙지도 않는다.
            GestureDetector(
              onTap: () => context.pushNamed('ChatHistory'),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: const Text(
                  "STUDY ROOM",
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: Color(0xFFE7E9EE),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _showManualDialog,
              tooltip: '사용 설명서',
              padding: const EdgeInsets.only(left: 8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: const Icon(Icons.help_outline,
                  color: Colors.amberAccent, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  /// 🏫 [SR] 설정 페이지에서 곧장 공부방으로.
  ///
  /// 모드 메뉴의 "STUDY ROOM" 알약과 같은 문이다 — 가는 곳도 같다. 설정 줄은
  /// 뒤로가기와 사용설명서가 이미 양끝을 잡고 있어 자리가 좁아, 글자만 줄인다.
  Widget _buildStudyRoomChip() {
    return Tooltip(
      message: '공부방 (Study Room)',
      child: GestureDetector(
        onTap: () => context.pushNamed('ChatHistory'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: const Text(
            "SR",
            maxLines: 1,
            style: TextStyle(
              color: Color(0xFFE7E9EE),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
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
                  // Circle Talk 설정 페이지와 같은 자리에 같은 아이콘을 둔다.
                  // 방에 들어가기 전에도 사용법을 볼 수 있어야 한다.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStudyRoomChip(),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => showScenarioTalkGuide(context),
                        icon: const Icon(Icons.menu_book_rounded,
                            color: kScenarioGuideAccent, size: 25),
                        tooltip: 'Scenario Talk 사용설명서',
                      ),
                    ],
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStudyRoomChip(),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => showCircleTalkGuide(context),
                        icon: const Icon(Icons.menu_book_rounded,
                            color: Color(0xFFB46CFF), size: 25),
                        tooltip: 'Circle Talk 사용설명서',
                      ),
                    ],
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

  /// 모드 카드 한 장.
  ///
  /// 색은 테두리를 두르는 대신 **위쪽 띠 하나**로만 쓴다. 네 장이 저마다 다른
  /// 색으로 사방을 두르면 화면이 색으로 가득 차서, 정작 눌러야 할 곳이 어디인지
  /// 가 흐려졌다. 아이콘 원도 색을 옅게 깔고 아이콘만 제 색으로 남긴다.
  ///
  /// 🖐️ **카드 전체가 눌린다.** 예전에는 글자와 화살표만 눌렸고 아이콘 자리는
  ///   죽어 있었다 — 가장 크고 눈에 띄는 곳이 반응하지 않았다.
  Widget _buildMenuCard(
      int mode, String title, String desc, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _switchMode(mode),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 4, color: color),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(desc,
                              style: const TextStyle(
                                  color: Color(0xFF8C93A1),
                                  fontSize: 12.5,
                                  height: 1.45)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right,
                        color: Color(0xFF6B7280), size: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
