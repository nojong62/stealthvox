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

// 📦 [Box 1: Imports 및 패키지]
import '/auth/firebase_auth/auth_util.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/custom_code/actions/billing_ticker.dart';
import 'dart:async'; // unawaited
import 'routine_mode_roleplay.dart' show TtsCache; // 캐시 정리 진입점

import 'package:purchases_flutter/purchases_flutter.dart';
import 'dart:io' show Platform;

// ============================================================================
// 🎨 [Lobby 색] 화면 전체가 쓰는 색을 한곳에 모은다. 예전에는 같은 파랑이
//   0xFF3B82F6으로 열몇 군데 흩어져 있어서, 강조색 하나 바꾸려면 전부 찾아야
//   했다. **여기 있는 건 색뿐이다 — 어떤 값도 상태가 아니다.**
// ============================================================================
const Color _kLobbyBgTop = Color(0xFF05070D);
const Color _kLobbyBgMid = Color(0xFF0B1120);
const Color _kLobbySurface = Color(0xFF12151D);
const Color _kLobbySurfaceHi = Color(0xFF1A1F2A);
const Color _kLobbyBorder = Color(0x14FFFFFF);
const Color _kLobbyCyan = Color(0xFF22D3EE);
const Color _kLobbyBlue = Color(0xFF3B82F6);
const Color _kLobbyBlueLine = Color(0xFF60A5FA);
const Color _kLobbyViolet = Color(0xFFA78BFA);
const Color _kLobbyTextHi = Color(0xFFF1F5F9);
const Color _kLobbyTextMid = Color(0xFF94A3B8);
const Color _kLobbyTextLow = Color(0xFF64748B);
const Color _kLobbyDanger = Color(0xFFFF453A);

/// 넓은 화면(태블릿·웹)에서 본문이 끝없이 늘어나지 않게 잡는 상한.
/// 폰에서는 화면 폭이 이보다 좁아 아무 영향이 없다.
const double _kLobbyMaxContentWidth = 560;

/// ENTER와 하단 줄을 고정한 채로 그릴 수 있는 최소 높이.
/// 이보다 짧으면 화면째 스크롤로 넘어간다(실제 폰에서는 닿지 않는 값이다).
const double _kLobbyMinPinnedHeight = 380;

/// AI STYLE 선택지. **영어 전용 설정이라 언제나 이 넷뿐이다.**
/// 비영어 TARGET에서는 선택지를 줄이는 게 아니라 영역째 감춘다
/// ([_kAiStyleTargetLang] 참고).
const List<String> _kAiStyles = ['Standard', 'American', 'British', 'Native'];

/// AI STYLE을 보여 주는 유일한 TARGET 언어.
const String _kAiStyleTargetLang = 'English';

/// 📦 [Box 2: 클래스 선언부]
class LobbyMaster extends StatefulWidget {
  const LobbyMaster({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);
  final double? width;
  final double? height;

  @override
  _LobbyMasterState createState() => _LobbyMasterState();
}

class _LobbyMasterState extends State<LobbyMaster> with WidgetsBindingObserver {
  // 📦 [Box 3: 상태 변수 및 잠금장치]
  final List<String> languages = [
    'English',
    'Japanese',
    'Chinese',
    'Spanish',
    'French',
    'German',
    'Korean',
    'Hindi',
    'Russian',
    'Portuguese',
    'Italian',
    'Dutch'
  ];

  bool isLoading = false;
  String _apiKey = "";
  bool _isKeyLoaded = false;

  // 💡 [핵심 뼈대] 버튼 연속 클릭 방지용 잠금장치
  bool _isActionLocked = false;

  // 🧭 Duo 초대 pending 상태 시 Lobby UI 차단용
  bool get _isDuoInvitePending =>
      FFAppState().isGuestSession &&
      FFAppState().pendingInviteType == 'duo' &&
      FFAppState().duoRoomId.isNotEmpty;

  // 📦 [Box 4: 라이프사이클 및 초기화 (LobbyBrain 분리)]
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppsFlyerManager.duoInviteSignal.addListener(_onDuoInviteSignal);
    // TTS 캐시는 상한 없이 쌓이기만 했다. 앱 실행당 한 번 정리한다.
    // (모드별 TtsCache가 같은 tts_cache 폴더를 공유하므로 한 번이면 된다.)
    unawaited(TtsCache.cleanupOnce());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Duo 초대 pending 상태이면 Lobby 스킵하고 바로 StealthRoom으로
      debugPrint(
          '[Lobby] isGuestSession=${FFAppState().isGuestSession}, pendingInviteType=${FFAppState().pendingInviteType}, duoRoomId=${FFAppState().duoRoomId}');
      if (FFAppState().isGuestSession &&
          FFAppState().pendingInviteType == 'duo' &&
          FFAppState().duoRoomId.isNotEmpty) {
        debugPrint('[Lobby] routing to StealthRoom for Duo invite');
        if (mounted) context.pushReplacementNamed('StealthRoom');
        return;
      }
      _initAppState();
      _initializeLobbyData();
    });
  }

  void _onDuoInviteSignal() {
    if (!mounted) return;
    if (FFAppState().isGuestSession &&
        FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Lobby] duoInviteSignal - routing to StealthRoom');
      context.pushReplacementNamed('StealthRoom');
    }
  }

  void _initAppState() {
    if (FFAppState().tone == null || FFAppState().tone.isEmpty)
      setState(() => FFAppState().tone = "Casual");
    // ⚠️ TARGET과 무관하게 4개 전부를 유효값으로 본다. 비영어 TARGET으로
    //   앱을 껐다 켜도 마지막 영어 선택값(American 등)이 살아남아야 한다.
    if (!_kAiStyles.contains(FFAppState().aiStyle)) {
      setState(() => FFAppState().aiStyle = "Standard");
    }
    if (FFAppState().nativeLang == null || FFAppState().nativeLang.isEmpty)
      setState(() => FFAppState().nativeLang = "Korean");
    if (FFAppState().targetLang == null || FFAppState().targetLang.isEmpty)
      setState(() => FFAppState().targetLang = "English");
    // 로비에서 음성을 선택하지 않는다. 사용자 역할 음성이 필요한 기존
    // 화면(Duo/History Practice)은 항상 verse를 사용한다.
    if (FFAppState().aiVoice != "verse") {
      setState(() => FFAppState().aiVoice = "verse");
    }
  }

  Future<void> _initializeLobbyData() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isSameAccountAsLastSync =
        currentUid != null && currentUid == LobbyBrain.lastSyncedUid;
    final alreadyLoaded = FFAppState().remainingTimeLoaded;
    debugPrint(
        '[Lobby] _initializeLobbyData enter, alreadyLoaded=$alreadyLoaded, sameAccount=$isSameAccountAsLastSync, remainingTime=${FFAppState().remainingTime}');
    setState(() {
      isLoading = true;
      // 계정이 바뀐 경우(다른 uid 또는 최초 동기화)에만 로딩 상태로 되돌린다.
      // 같은 계정으로 재진입한 경우에는 이미 세팅된 값을 그대로 유지한다.
      if (!isSameAccountAsLastSync) {
        FFAppState().remainingTimeLoaded = false;
      }
    });
    try {
      // 1. DB 통신 분리: 서버 시간 및 남은 시간 동기화
      int? serverRemainingTime =
          await LobbyBrain.getRemainingTime(FirebaseAuth.instance.currentUser);
      debugPrint('[Lobby] Firestore remainingTime=$serverRemainingTime');
      if (mounted) {
        setState(() {
          if (serverRemainingTime != null) {
            FFAppState().remainingTime = serverRemainingTime;
          }
          FFAppState().remainingTimeLoaded = true;
        });
      }
      if (currentUid != null) {
        LobbyBrain.lastSyncedUid = currentUid;
      }
      if (serverRemainingTime != null) {
        BillingTicker.instance.remainingSecondsNotifier.value =
            serverRemainingTime;
        BillingTicker.instance.start();
        BillingTicker.instance.pause(); // 로비는 과금 없음
      }

      // 2. DB 통신 분리: 버전 체크 및 API 키 로드
      Map<String, dynamic> configData = await LobbyBrain.fetchRemoteConfig();
      _apiKey = configData['apiKey'] ?? "";
      if (_apiKey.isNotEmpty) _isKeyLoaded = true;

      // 앱 강제 업데이트 체크
      int currentBuildNumber = await LobbyBrain.getCurrentBuildNumber();
      int minBuildNumber = configData['minBuildNumber'] ?? 1;
      if (minBuildNumber > currentBuildNumber && mounted) {
        _showForceUpdateDialog();
      }

      // 3. RevenueCat 초기화
      final rcKey = configData['revenueCatAndroidKey'] ?? '';
      if (rcKey.isNotEmpty && Platform.isAndroid) {
        await Purchases.setLogLevel(LogLevel.error);
        await Purchases.configure(PurchasesConfiguration(rcKey));
        debugPrint('[Lobby] RevenueCat configured');
      }

      // 3. AppsFlyer SDK 초기화 (전역 딥링크 핸들러 사용)
      await AppsFlyerManager.initialize(
        devKey: 'SQUmDTB2VzuPjrJGiy5SSC',
        appId: 'com.aienglishpractice.stealthvox',
      );
      if (!mounted) return;
    } catch (e) {
      debugPrint("Init Error: $e");
      if (mounted) {
        setState(() => FFAppState().remainingTimeLoaded = true);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    AppsFlyerManager.duoInviteSignal.removeListener(_onDuoInviteSignal);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      BillingTicker.instance.flushNow();
    }
  }

  // 📦 [Box 5: 룸 입장 관리 (Mutex Lock 적용)]
  void _handleEnterRoom(BuildContext context) async {
    if (_isActionLocked) return;
    _isActionLocked = true;
    try {
      FocusScope.of(context).unfocus();
      if (!guardBillingEntry(context)) return;
      if (currentUserReference == null) return;

      // DB 통신 분리: 대화방 히스토리 문서 생성
      final newHistoryRef =
          await LobbyBrain.createHistoryDoc(currentUserReference!);
      if (mounted) {
        context.pushNamed('StealthRoom',
            queryParameters: {
              'historyRef':
                  serializeParam(newHistoryRef, ParamType.DocumentReference)
            }.withoutNulls);
      }
    } finally {
      _isActionLocked = false;
    }
  }

  // 📦 [Box 6: 시스템 알림 팝업]
  void _showForceUpdateDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
                backgroundColor: const Color(0xFF1C1C1E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Text("🚀 업데이트 안내",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                content: const Text("새로운 기능이 추가되었습니다!\n스토어에서 앱을 업데이트해 주세요.",
                    style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                      onPressed: () async {
                        final Uri url = Uri.parse(
                            'https://play.google.com/store/apps/details?id=com.aienglishpractice.stealthvox');
                        if (await canLaunchUrl(url))
                          await launchUrl(url,
                              mode: LaunchMode.externalApplication);
                      },
                      child: const Text("스토어로 이동",
                          style: TextStyle(
                              color: Color(0xFF0A84FF),
                              fontWeight: FontWeight.bold)))
                ])));
  }

  void _showUsageGuideDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: const [
          Icon(Icons.menu_book_outlined, color: Color(0xFF0A84FF)),
          SizedBox(width: 8),
          Text("[ 사용 설명서 ]",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ]),
        content: const SingleChildScrollView(
          child: Text(
            "1. 한국어로 편하게 대화하세요\n"
            "StealthVox는 사용자가 한국어로 AI와 자연스럽게 대화하면서, 그 대화를 영어 공부방 교재로 만드는 공간입니다.\n\n"
            "2. 영어를 자유롭게 섞어도 됩니다\n"
            "한국어로 말해도 되고, 영어로 말하거나 한국어와 영어를 섞어서 말해도 됩니다. 완벽한 문장을 만들려고 부담 갖지 말고 평소 말하듯 이야기하세요.\n\n"
            "3. 대화가 학습 자료가 됩니다\n"
            "대화에서 만들어진 원문, 목표 언어 번역, AI 답변과 음성은 히스토리에 정리됩니다. 다양한 공부방에서 다시 듣기, 따라 말하기, 복습 자료로 활용할 수 있습니다.\n\n"
            "4. 영어를 생활 언어로 연습하세요\n"
            "정답을 맞히는 공부보다 내가 실제로 하고 싶은 말을 반복해 보세요. 만들어진 자료를 부담 없이 즐기다 보면 영어를 일상에서 쓰는 생활 언어로 연습할 수 있습니다.\n\n"
            "5. 잘못 알아들었을 때\n"
            "음성 인식이나 번역이 뜻과 다르면 “그게 아니라, 내 말은…”이라고 말한 뒤 원하는 내용을 다시 이야기하세요. 직전 대화를 바꾸고 새 뜻으로 이어갈 수 있습니다.\n\n"
            "6. Duo Connect로 함께 대화하고 연습하세요\n"
            "지인이나 가족을 대화에 초대해 전화 통화하듯 편하게 일상 이야기를 나눌 수 있습니다. 통화가 끝나면 대화 내용이 영어 학습 자료로 남아, 실제로 사용한 대화 패턴을 효율적으로 연습할 수 있습니다.\n\n"
            "외국어를 배우고 싶은 사람과 통화하며 서로의 언어를 연습할 수도 있습니다. 초대받은 상대도 자신이 말할 언어와 배우고 싶은 언어를 직접 선택할 수 있어, 두 사람이 각자 원하는 언어를 따로 학습할 수 있습니다. 대화 중에는 만능 통역기처럼 서로 다른 언어로도 자연스럽게 소통할 수 있습니다.\n\n"
            "한국인 지인과 자연스럽게 통화하면서 한국어를 배우고 싶은 분들에게도 도움이 되기를 바랍니다.",
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("확인",
                  style: TextStyle(
                      color: Color(0xFF0A84FF), fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: const [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFFF453A)),
          SizedBox(width: 8),
          Text("회원 탈퇴",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
            "정말 탈퇴하시겠습니까?\n모든 정보(잔여 시간, 히스토리 등)가 영구적으로 삭제되며 복구할 수 없습니다.",
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소",
                  style: TextStyle(
                      color: Colors.white54, fontWeight: FontWeight.bold))),
          TextButton(
            onPressed: () async {
              if (_isActionLocked) return;
              _isActionLocked = true;
              try {
                Navigator.pop(context);
                await FirebaseAuth.instance.currentUser?.delete();
                if (mounted) context.goNamed('Intro');
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("보안을 위해 로그아웃 후 다시 로그인하신 뒤 탈퇴를 진행해주세요.",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: Color(0xFFFF453A)));
              } finally {
                _isActionLocked = false;
              }
            },
            child: const Text("탈퇴하기",
                style: TextStyle(
                    color: Color(0xFFFF453A), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 📦 [Box 7: UI 컴포넌트 헬퍼]
  //
  // 여기 아래는 **그리는 코드만** 있다. 상태·콜백·이동은 Box 3~6이 그대로
  // 쥐고 있고, 이 아래에서는 그것들을 부르기만 한다. 새 상태를 만들거나
  // 기존 상태를 복제하지 않는다.

  /// 카드 한 장.
  ///
  /// 예전 `_buildGlassContainer`의 `BackdropFilter`를 걷어냈다. 카드가 겹칠
  /// 때마다 블러가 한 겹씩 더 도는 구조였는데, 그 값이 웹과 저사양 안드로이드에서
  /// 비쌌다. 어두운 배경 위 어두운 면이라 블러가 만들던 차이도 거의 없었다.
  Widget _buildSurfaceCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
    Color? borderColor,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _kLobbySurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? _kLobbyBorder),
      ),
      child: child,
    );
  }

  /// 섹션 제목(LANGUAGE / AI STYLE / AI TONE).
  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 9),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _kLobbyTextMid,
          fontSize: 11,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  /// Store / Study Room.
  ///
  /// ⚠️ 모양만 세그먼트 컨트롤을 빌렸을 뿐, **토글이 아니다.** 누르면 그 자리에서
  /// 선택이 바뀌는 게 아니라 각자 다른 화면으로 넘어간다. 지금 화면이 로비이므로
  /// 강조는 로비에서 이어지는 Study Room 쪽에 둔다(기존 화면과 같다).
  Widget _buildTopSegments() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kLobbySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kLobbyBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegment(
              icon: Icons.storefront_rounded,
              label: 'Store',
              highlighted: false,
              onTap: () => context.pushNamed('Store'),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildSegment(
              icon: Icons.auto_stories_rounded,
              label: 'Study Room',
              highlighted: true,
              onTap: () => context.pushNamed('ChatHistory'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment({
    required IconData icon,
    required String label,
    required bool highlighted,
    required VoidCallback onTap,
  }) {
    return Material(
      color: highlighted ? _kLobbySurfaceHi : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          // 글꼴 배율을 크게 쓰는 기기에서 "Study Room"이 밀려 나가지 않게
          // 폭이 모자라면 글자를 줄인다. 잘라내지는 않는다.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 15,
                    color: highlighted ? _kLobbyCyan : _kLobbyTextLow),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: highlighted ? _kLobbyTextHi : _kLobbyTextMid,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 남은 시간.
  ///
  /// 값과 규칙은 예전 그대로다 — `remainingTime`을 **시:분**으로 읽고,
  /// 아직 Firestore에서 못 받았으면 숫자 대신 스피너를, 60초 이하이면 빨강을
  /// 쓴다. 바뀐 건 숫자에 입힌 그라디언트뿐이다(경고 색일 때는 입히지 않는다).
  ///
  /// 📐 라벨과 숫자를 **한 줄에** 놓는다. 위아래로 쌓으면 카드 하나가 세로를
  ///   너무 많이 먹어서, 글꼴 배율이 큰 기기(화면 확대를 켠 폰)에서는 첫
  ///   화면에 이 카드와 드롭다운 하나밖에 안 들어왔다. 정보는 그대로다.
  Widget _buildTimeLeftCard(FFAppState appState, String displayTime) {
    final bool isLow = appState.remainingTime <= 60;

    Widget numberText(Color color) => Text(
          displayTime,
          maxLines: 1,
          style: GoogleFonts.orbitron(
            color: color,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        );

    Widget value;
    if (!appState.remainingTimeLoaded) {
      value = const SizedBox(
        height: 30,
        width: 30,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: _kLobbyCyan),
          ),
        ),
      );
    } else if (isLow) {
      value = numberText(_kLobbyDanger);
    } else {
      value = ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          colors: [_kLobbyCyan, Color(0xFFBFDBFE), _kLobbyViolet],
        ).createShader(rect),
        blendMode: BlendMode.srcIn,
        child: numberText(Colors.white),
      );
    }

    return _buildSurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'TIME LEFT',
                maxLines: 1,
                style: GoogleFonts.orbitron(
                  color: _kLobbyTextMid,
                  fontSize: 11,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: value)),
        ],
      ),
    );
  }

  /// ORIGIN / TARGET 한 칸.
  ///
  /// 선택지(`languages`)도 저장 위치(`FFAppState`)도 예전 그대로다.
  /// [onChanged]는 호출부가 넘겨준 기존 콜백을 그대로 받는다.
  Widget _buildLangField(
    String label,
    String subtitle,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kLobbyTextMid,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _kLobbyTextLow, fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: _kLobbySurfaceHi,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kLobbyBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: languages.contains(value) ? value : languages[0],
              dropdownColor: _kLobbySurfaceHi,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _kLobbyTextMid, size: 22),
              style: const TextStyle(
                color: _kLobbyTextHi,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              items: languages
                  .map((String lang) => DropdownMenuItem<String>(
                        value: lang,
                        child: Text(lang,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  /// 고른 것 하나만 은은하게 빛난다.
  Widget _buildPill(String label, bool isSelected, VoidCallback onTap) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: isSelected ? _kLobbyBlue : _kLobbySurfaceHi,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSelected ? _kLobbyBlueLine : _kLobbyBorder),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: _kLobbyBlue.withValues(alpha: 0.32),
                  blurRadius: 16,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
            child: Center(
              // 360dp에서 한 줄에 세 칸이 들어가야 한다. 폭이 모자라면
              // 잘라내지 말고 글자를 줄인다 — "American"이 기준이다.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: isSelected ? Colors.white : _kLobbyTextMid,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// AI STYLE 배치.
  ///
  /// **선택지는 언제나 [_kAiStyles] 넷이다**(영어에서만 보이는 설정이라
  /// 언어별로 갈릴 일이 없다). 여기서는 줄만 나눈다 — 첫 줄에 셋,
  /// 둘째 줄에 Native 하나가 전체 폭. 폭에 맡겨 흘려 담지 않는다.
  /// 개수가 넷이 아니게 되더라도 화면이 깨지지 않도록 2열로 담는 길은
  /// 남겨 둔다.
  Widget _buildAiStyleSelector(
    List<String> options,
    String selectedValue,
    ValueChanged<String> onSelected,
  ) {
    Widget pill(String option) =>
        _buildPill(option, selectedValue == option, () => onSelected(option));

    if (options.length == 4) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: pill(options[0])),
              const SizedBox(width: 10),
              Expanded(child: pill(options[1])),
              const SizedBox(width: 10),
              Expanded(child: pill(options[2])),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: pill(options[3])),
        ],
      );
    }
    return Column(
      children: [
        for (int i = 0; i < options.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: pill(options[i])),
              const SizedBox(width: 10),
              if (i + 1 < options.length)
                Expanded(child: pill(options[i + 1]))
              else
                const Spacer(),
            ],
          ),
        ],
      ],
    );
  }

  /// AI TONE — 언제나 둘, 같은 폭.
  Widget _buildAiToneSelector(
      String selectedValue, ValueChanged<String> onSelected) {
    const List<String> options = ['Formal', 'Casual'];
    return Row(
      children: [
        Expanded(
          child: _buildPill(options[0], selectedValue == options[0],
              () => onSelected(options[0])),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildPill(options[1], selectedValue == options[1],
              () => onSelected(options[1])),
        ),
      ],
    );
  }

  /// 이 화면에서 가장 중요한 버튼. 누르면 기존 `_handleEnterRoom`이 그대로 돈다
  /// (중복탭 잠금 → 잔여시간 확인 → 히스토리 문서 생성 → StealthRoom).
  Widget _buildEnterButton() {
    return SizedBox(
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kLobbyCyan, _kLobbyBlue, _kLobbyViolet],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _kLobbyBlue.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handleEnterRoom(context),
            borderRadius: BorderRadius.circular(18),
            child: const Center(
              child: Text(
                'ENTER',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 화면 맨 아래 고정 줄.
  ///
  /// 기능은 예전 푸터 링크 셋과 **완전히 같다** — 다이얼로그 둘과 로그아웃
  /// 클로저를 그대로 부른다. 제스처 바 영역은 여기서 직접 피한다(본문 쪽
  /// `SafeArea`는 `bottom: false`라 아래를 비워 두지 않는다).
  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: _kLobbySurface,
        border: Border(top: BorderSide(color: _kLobbyBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: _buildBottomBarItem(
                  Icons.help_outline_rounded,
                  '사용 설명서',
                  () => _showUsageGuideDialog(context),
                ),
              ),
              Expanded(
                child: _buildBottomBarItem(
                  Icons.logout_rounded,
                  '로그아웃',
                  () async {
                    FFAppState().remainingTime = 0;
                    FFAppState().remainingTimeLoaded = false;
                    LobbyBrain.lastSyncedUid = null;
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    context.goNamed('Intro');
                  },
                ),
              ),
              Expanded(
                child: _buildBottomBarItem(
                  Icons.person_remove_alt_1_outlined,
                  '회원 탈퇴',
                  () => _showDeleteAccountDialog(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBarItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: _kLobbyTextMid),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(color: _kLobbyTextMid, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📦 [Box 8: 메인 화면 빌더]
  //
  // 세로 구성은 위에서부터 **워드마크 → 탭 → 스크롤 본문 → ENTER → 하단 줄**이다.
  // ENTER와 하단 줄은 고정이고, 그 위 본문만 스크롤한다. 그래서 화면이 아무리
  // 짧아도 ENTER가 하단 줄에 가리거나 스크롤 밖으로 밀려나지 않는다.
  @override
  Widget build(BuildContext context) {
    var appState = FFAppState();
    final int _lobbyTotalSec = appState.remainingTime.toInt().clamp(0, 999999);
    final int _lobbyH = _lobbyTotalSec ~/ 3600;
    final int _lobbyM = (_lobbyTotalSec % 3600) ~/ 60;
    final String displayTime =
        '${_lobbyH.toString().padLeft(2, '0')}:${_lobbyM.toString().padLeft(2, '0')}';

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kLobbyBgTop, _kLobbyBgMid, _kLobbyBgTop],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          // 아래는 하단 줄이 직접 피한다 — 그래야 줄의 배경이 제스처 바까지
          // 이어지고, 그 위 콘텐츠는 줄에 가리지 않는다.
          bottom: false,
          child: (isLoading || _isDuoInvitePending)
              ? const Center(
                  child: CircularProgressIndicator(color: _kLobbyCyan))
              : Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _kLobbyMaxContentWidth),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final Widget content =
                            _buildLobbyBody(appState, displayTime);
                        // 세로가 아주 짧으면(창을 줄인 웹, 분할 화면) 고정
                        // 영역만으로도 화면을 넘긴다. 그때는 고정을 포기하고
                        // 화면째 스크롤한다 — ENTER가 잘려 보이는 것보다
                        // 스크롤해서라도 온전히 닿는 편이 낫다.
                        if (constraints.maxHeight >= _kLobbyMinPinnedHeight) {
                          return content;
                        }
                        return SingleChildScrollView(
                          child: SizedBox(
                            height: _kLobbyMinPinnedHeight,
                            child: content,
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// 로비 본문 한 벌. 세로가 짧을 때 통째로 스크롤에 담기 위해 갈라 뒀다.
  Widget _buildLobbyBody(FFAppState appState, String displayTime) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              ShaderMask(
                shaderCallback: (rect) =>
                    const LinearGradient(colors: [_kLobbyCyan, _kLobbyViolet])
                        .createShader(rect),
                blendMode: BlendMode.srcIn,
                child: const Text(
                  'StealthVox',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: _buildTopSegments(),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTimeLeftCard(appState, displayTime),
                const SizedBox(height: 22),
                _buildSectionLabel('LANGUAGE'),
                _buildSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLangField(
                        'ORIGIN',
                        '(Chat Lang)',
                        appState.nativeLang,
                        (val) => setState(() => appState.nativeLang = val!),
                      ),
                      const SizedBox(height: 18),
                      _buildLangField(
                        'TARGET',
                        '(Learn Lang)',
                        appState.targetLang,
                        // ⚠️ AI STYLE은 여기서 건드리지 않는다. 비영어로
                        //   가면 아래 영역이 통째로 사라지지만, 저장값은
                        //   마지막 영어 선택 그대로 남겨 뒀다가 다시
                        //   English로 돌아왔을 때 복원한다.
                        (val) => setState(() => appState.targetLang = val!),
                      ),
                    ],
                  ),
                ),
                // AI STYLE은 영어 대화에만 쓰는 설정이다. TARGET이 영어가
                // 아니면 영역째 감춘다(선택지를 줄이지 않는다).
                if (appState.targetLang == _kAiStyleTargetLang) ...[
                  const SizedBox(height: 22),
                  _buildSectionLabel('AI STYLE'),
                  _buildAiStyleSelector(
                    _kAiStyles,
                    appState.aiStyle,
                    (style) => setState(() => appState.aiStyle = style),
                  ),
                ],
                const SizedBox(height: 22),
                _buildSectionLabel('AI TONE'),
                _buildAiToneSelector(
                  appState.tone,
                  (tone) => setState(() => appState.tone = tone),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: _buildEnterButton(),
        ),
        _buildBottomBar(),
      ],
    );
  }
}

// =======================================================
// 📦 [Box 9: DB 매니저 (LobbyBrain) - UI 로직 완벽 분리]
// =======================================================
class LobbyBrain {
  // 💡 마지막으로 remainingTime을 동기화한 사용자 uid (계정 전환 감지용)
  static String? lastSyncedUid;

  // 💡 서버 남은 시간 동기화
  static Future<int?> getRemainingTime(User? user) async {
    if (user == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.containsKey('remainingTime')) {
          return data['remainingTime'] as int;
        }
      }
    } catch (e) {
      debugPrint("DB Fetch Error: $e");
    }
    return null;
  }

  // 💡 파이어베이스 원격 구성 및 키 호출
  static Future<Map<String, dynamic>> fetchRemoteConfig() async {
    Map<String, dynamic> result = {'apiKey': '', 'minBuildNumber': 1};
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
          fetchTimeout: const Duration(minutes: 1),
          minimumFetchInterval: const Duration(seconds: 0)));
      await remoteConfig.fetchAndActivate();

      result['apiKey'] = remoteConfig.getString('OpenAIAPIKey');
      result['minBuildNumber'] = remoteConfig.getInt('min_build_number');
      result['revenueCatAndroidKey'] =
          remoteConfig.getString('RevenueCatAndroidKey');
    } catch (e) {
      debugPrint("Remote Config Error: $e");
    }
    return result;
  }

  // 💡 앱 버전 체크용
  static Future<int> getCurrentBuildNumber() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      return int.tryParse(packageInfo.buildNumber) ?? 1;
    } catch (e) {
      return 1;
    }
  }

  // 💡 대화방(History) 문서 신규 생성
  static Future<DocumentReference> createHistoryDoc(
      DocumentReference userRef) async {
    final newHistoryRef = userRef.collection('chat_history').doc();
    await newHistoryRef.set({
      'created_at': FieldValue.serverTimestamp(),
      'is_pinned': false,
      // 세션 생성 당시 언어 식별값 보존(History 동일 언어 판정용)
      'native_lang': FFAppState().nativeLang,
      'target_lang': FFAppState().targetLang,
    });
    return newHistoryRef;
  }

  // 💡 Duo 초대용 OneLink URL 생성
  static String createDuoInviteLink({
    required String roomId,
    required String inviterId,
    String? customCampaign,
  }) {
    const String baseUrl = 'https://stealthvox.onelink.me/31o1/fipsp75p';
    final Map<String, String> params = {
      'deep_link_value': 'duo_chat',
      'deep_link_sub1': inviterId,
      'deep_link_sub2': roomId,
      'inviter_id': inviterId,
      'room_id': roomId,
      'pid': 'friend_invite',
      'c': customCampaign ?? 'duo_share',
      'af_dp': 'stealthvox://',
      'af_force_deeplink': 'true',
    };
    final Uri uri = Uri.parse(baseUrl).replace(queryParameters: params);
    return uri.toString();
  }

  static Future<String?> generateInviteLinkForCurrentRoom(String roomId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return createDuoInviteLink(
      roomId: roomId,
      inviterId: user.uid,
      customCampaign: 'in_app_share',
    );
  }
}

// =======================================================
// 📦 [Box 10: AppsFlyerManager — Global Deep Link Handler]
// 화면 mounted 여부에 의존하지 않고 Duo 초대 딥링크를 전역 처리한다.
// FFAppState 세팅 후 duoInviteSignal을 발동해 현재 활성 화면이 라우팅한다.
// =======================================================
class AppsFlyerManager {
  static AppsflyerSdk? _instance;
  static bool _isInitialized = false;
  static const MethodChannel _installReferrerChannel =
      MethodChannel('stealthvox/install_referrer');
  static const String _consumedReferrerKey =
      'duo_consumed_play_install_referrer';
  static const String _completedDuoRoomsKey = 'duo_completed_guest_room_ids';

  /// Duo 초대 딥링크 처리 완료 후 증가하는 신호.
  static final ValueNotifier<int> duoInviteSignal = ValueNotifier<int>(0);

  /// Google Play가 이번 설치에 기록한 초대를 AppsFlyer/Android 백업 상태보다
  /// 먼저 적용한다. 동일 referrer는 한 번만 소비해 일반 실행 때 재입장하지 않는다.
  static Future<bool> recoverPlayInstallInvite() async {
    if (!Platform.isAndroid) return false;
    try {
      final String? referrer = await _installReferrerChannel
          .invokeMethod<String>('getInstallReferrer');
      if (referrer == null || referrer.isEmpty) return false;

      final params = Uri.splitQueryString(referrer);
      if (params['deep_link_value'] != 'duo_chat') return false;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_consumedReferrerKey) == referrer) return false;

      final applied = await handleDuoDeepLink(params, emitSignal: false);
      if (!applied) return false;
      await prefs.setString(_consumedReferrerKey, referrer);
      debugPrint(
          '[AppsFlyerManager] Play install referrer applied - roomId: ${params['deep_link_sub2']}');
      return true;
    } catch (e) {
      debugPrint('[AppsFlyerManager] install referrer error: $e');
      return false;
    }
  }

  /// 저장/복원된 초대가 아직 서버에 존재하는 활성 방인지 확인한다.
  /// 네트워크 오류는 입장 화면의 기존 재시도 경로에 맡기기 위해 유효로 취급한다.
  static Future<bool> validatePendingDuoInvite() async {
    if (FFAppState().pendingInviteType != 'duo' ||
        FFAppState().duoRoomId.isEmpty) return false;
    final roomId = FFAppState().duoRoomId;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('duo_sessions')
          .doc(roomId)
          .get(const GetOptions(source: Source.server));
      final data = snap.data();
      final valid = snap.exists && data?['isDuoEnabled'] == true;
      if (!valid && FFAppState().duoRoomId == roomId) {
        clearPendingDuoInvite();
        debugPrint(
            '[AppsFlyerManager] stale Duo invite cleared - roomId: $roomId');
      }
      return valid;
    } catch (e) {
      debugPrint('[AppsFlyerManager] invite validation deferred: $e');
      return true;
    }
  }

  static void clearPendingDuoInvite() {
    FFAppState().isGuestSession = false;
    FFAppState().inviterUid = '';
    FFAppState().duoRoomId = '';
    FFAppState().pendingInviteType = '';
    FFAppState().update(() {});
  }

  /// 게스트가 실제로 소비했거나 종료한 Duo 방을 기록한다.
  /// AppsFlyer가 동일 초대를 재전달하더라도 Intro에서 다시 열리지 않게 한다.
  static Future<void> markDuoInviteCompleted(String? roomId) async {
    if (roomId == null || roomId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final completedRoomIds =
          List<String>.from(prefs.getStringList(_completedDuoRoomsKey) ?? []);
      completedRoomIds.remove(roomId);
      completedRoomIds.add(roomId);
      if (completedRoomIds.length > 20) {
        completedRoomIds.removeRange(0, completedRoomIds.length - 20);
      }
      await prefs.setStringList(_completedDuoRoomsKey, completedRoomIds);
      debugPrint(
          '[AppsFlyerManager] completed Duo room recorded - roomId: $roomId');
    } catch (e) {
      debugPrint('[AppsFlyerManager] failed to record completed Duo room: $e');
    }
  }

  static Future<void> initialize({
    required String devKey,
    required String appId,
  }) async {
    if (_isInitialized) return;
    try {
      final AppsFlyerOptions options = AppsFlyerOptions(
        afDevKey: devKey,
        appId: appId,
        showDebug: false,
        timeToWaitForATTUserAuthorization: 60,
      );

      _instance = AppsflyerSdk(options);

      _instance!.onInstallConversionData((res) => _routeCallback(res));
      _instance!.onAppOpenAttribution((res) => _routeCallback(res));

      _instance!.onDeepLinking((DeepLinkResult dp) {
        if (dp.status == Status.FOUND) {
          try {
            final clickEvent = dp.deepLink?.clickEvent;
            final params = clickEvent == null
                ? <String, dynamic>{}
                : Map<String, dynamic>.from(clickEvent);
            if (dp.deepLink?.deepLinkValue != null) {
              params['deep_link_value'] = dp.deepLink!.deepLinkValue!;
            }
            handleDuoDeepLink(params);
          } catch (e) {
            debugPrint('[AppsFlyerManager] onDeepLinking error: $e');
          }
        }
      });

      await _instance!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );

      _isInitialized = true;
    } catch (e) {
      debugPrint('[AppsFlyerManager] init error: $e');
    }
  }

  static void _routeCallback(dynamic res) {
    try {
      if (res == null) return;
      final Map<dynamic, dynamic> raw = res as Map<dynamic, dynamic>;
      if ((raw['status']?.toString() ?? '') != 'success') return;
      final dynamic payload = raw['data'] ?? raw;
      if (payload == null) return;
      handleDuoDeepLink(Map<String, dynamic>.from(payload as Map));
    } catch (e) {
      debugPrint('[AppsFlyerManager] callback error: $e');
    }
  }

  /// Duo 초대 딥링크를 전역 처리한다.
  static Future<bool> handleDuoDeepLink(Map<String, dynamic> params,
      {bool emitSignal = true}) async {
    Map<String, dynamic> deepLinkData = {};
    if (params['deepLink'] is String) {
      try {
        deepLinkData =
            jsonDecode(params['deepLink'] as String) as Map<String, dynamic>;
      } catch (_) {}
    } else if (params['deepLink'] is Map) {
      deepLinkData = Map<String, dynamic>.from(params['deepLink'] as Map);
    }

    final String? deepLinkValue = params['deep_link_value']?.toString() ??
        deepLinkData['deep_link_value']?.toString();
    if (deepLinkValue != 'duo_chat') return false;

    final String? inviterId = params['deep_link_sub1']?.toString() ??
        deepLinkData['deep_link_sub1']?.toString() ??
        params['inviter_id']?.toString() ??
        deepLinkData['inviter_id']?.toString() ??
        params['inviterId']?.toString() ??
        params['af_sub1']?.toString();

    final String? roomId = params['deep_link_sub2']?.toString() ??
        deepLinkData['deep_link_sub2']?.toString() ??
        params['room_id']?.toString() ??
        deepLinkData['room_id']?.toString() ??
        params['duo_room_id']?.toString() ??
        deepLinkData['duo_room_id']?.toString() ??
        params['duoRoomId']?.toString() ??
        deepLinkData['duoRoomId']?.toString() ??
        params['roomId']?.toString() ??
        params['af_sub2']?.toString();

    if (inviterId == null ||
        inviterId.isEmpty ||
        roomId == null ||
        roomId.isEmpty) {
      debugPrint('[AppsFlyerManager] handleDuoDeepLink: missing params');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final completedRoomIds =
          prefs.getStringList(_completedDuoRoomsKey) ?? const <String>[];

      if (completedRoomIds.contains(roomId)) {
        debugPrint(
            '[AppsFlyerManager] replayed completed Duo invite ignored - roomId: $roomId');
        return false;
      }

      if (FFAppState().isGuestSession &&
          FFAppState().pendingInviteType == 'duo' &&
          FFAppState().duoRoomId == roomId) {
        debugPrint(
            '[AppsFlyerManager] duplicate pending Duo invite ignored - roomId: $roomId');
        return true;
      }

      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      FFAppState().isGuestSession = true;
      FFAppState().inviterUid = inviterId;
      FFAppState().duoRoomId = roomId;
      FFAppState().pendingInviteType = 'duo';
      FFAppState().update(() {});
      debugPrint(
          '[AppsFlyerManager] Duo invite ready - roomId: $roomId, signal++');
      if (emitSignal) duoInviteSignal.value++;
      return true;
    } catch (e) {
      debugPrint('[AppsFlyerManager] handleDuoDeepLink error: $e');
      return false;
    }
  }
}
