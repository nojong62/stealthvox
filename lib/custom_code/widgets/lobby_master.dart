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
import 'dart:ui';
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
    if (!["Standard", "American", "British", "Native"]
        .contains(FFAppState().aiStyle)) {
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
  Widget _buildGlassContainer(
      {required Widget child, double? width, Color? borderColor}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: width ?? double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.02)
                ]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: borderColor ?? Colors.white.withValues(alpha: 0.1),
                width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 40,
                  offset: const Offset(0, 10))
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildTopNavBtn(
      {IconData? icon,
      required String label,
      required VoidCallback onTap,
      bool isHighlight = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            color: isHighlight
                ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isHighlight
                    ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
                    : Colors.white12)),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon,
                  color: isHighlight ? const Color(0xFF93C5FD) : Colors.white54,
                  size: 14),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: isHighlight ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSleekLangSelector(
      String label, String value, Function(String?) onChanged,
      {Color labelColor = Colors.white54,
      String? subtitle,
      bool subtitleBelow = false}) {
    Widget labelWidget;
    if (subtitle != null && !subtitleBelow) {
      labelWidget = Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(label,
                style: TextStyle(
                    color: labelColor,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text(subtitle,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 9, letterSpacing: 0.5)),
          ]);
    } else if (subtitle != null && subtitleBelow) {
      labelWidget =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                color: labelColor,
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: const TextStyle(
                color: Colors.white38, fontSize: 9, letterSpacing: 0.3)),
      ]);
    } else {
      labelWidget = Text(label,
          style: TextStyle(
              color: labelColor,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      labelWidget,
      const SizedBox(height: 10),
      Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12)),
          child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
            value: languages.contains(value) ? value : languages[0],
            dropdownColor: const Color(0xFF1E1E1E),
            isExpanded: true,
            icon: const Icon(Icons.unfold_more_rounded,
                color: Colors.white54, size: 20),
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            items: languages
                .map((String lang) =>
                    DropdownMenuItem<String>(value: lang, child: Text(lang)))
                .toList(),
            onChanged: onChanged,
          ))),
    ]);
  }

  Widget _buildPillToggle(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
        child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isSelected
                            ? const Color(0xFF60A5FA)
                            : Colors.white12,
                        width: 1)),
                child: Center(
                    child: Text(label,
                        style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.bold))))));
  }

  List<String> _availableAiStyles(String targetLanguage) =>
      targetLanguage == 'English'
          ? const ['Standard', 'American', 'British', 'Native']
          : const ['Standard', 'Native'];

  Widget _buildPillToggleGrid(
    List<String> options,
    String selectedValue,
    ValueChanged<String> onSelected,
  ) {
    return Column(
      children: [
        for (var index = 0; index < options.length; index += 2) ...[
          if (index > 0) const SizedBox(height: 12),
          Row(
            children: [
              _buildPillToggle(
                options[index],
                selectedValue == options[index],
                () => onSelected(options[index]),
              ),
              const SizedBox(width: 12),
              if (index + 1 < options.length)
                _buildPillToggle(
                  options[index + 1],
                  selectedValue == options[index + 1],
                  () => onSelected(options[index + 1]),
                )
              else
                const Spacer(),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFooterLink(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      child: Text(label,
          style: const TextStyle(
              color: Colors.white30,
              fontSize: 12,
              decoration: TextDecoration.underline)),
    );
  }

  // 📦 [Box 8: 메인 화면 빌더]
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
            colors: [Color(0xFF020617), Color(0xFF0F172A), Color(0xFF000000)]),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
            child: (isLoading || _isDuoInvitePending)
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
                : Column(children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildTopNavBtn(
                                  icon: Icons.storefront_rounded,
                                  label: "Store",
                                  onTap: () => context.pushNamed('Store')),
                              GestureDetector(
                                onTap: () => context.pushNamed('ChatHistory'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: const Color(0xFF3B82F6)
                                              .withValues(alpha: 0.5))),
                                  child: const Text("Study Room",
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ),
                              ),
                            ])),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildGlassContainer(
                                  child: Column(children: [
                                Text("REMAINING TIME",
                                    style: GoogleFonts.orbitron(
                                        color: const Color(0xFF60A5FA),
                                        fontSize: 12,
                                        letterSpacing: 3,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                appState.remainingTimeLoaded
                                    ? Text(displayTime,
                                        style: GoogleFonts.orbitron(
                                            color: appState.remainingTime > 60
                                                ? Colors.white
                                                : const Color(0xFFFF453A),
                                            fontSize: 48,
                                            fontWeight: FontWeight.bold,
                                            shadows: [
                                              Shadow(
                                                  color: const Color(0xFF3B82F6)
                                                      .withValues(alpha: 0.5),
                                                  blurRadius: 20)
                                            ]))
                                    : const SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Center(
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFF60A5FA),
                                            ),
                                          ),
                                        ),
                                      ),
                              ])),
                              const SizedBox(height: 20),
                              _buildGlassContainer(
                                  borderColor: const Color(0xFF3B82F6)
                                      .withValues(alpha: 0.3),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildSleekLangSelector(
                                            "ORIGIN",
                                            appState.nativeLang,
                                            (val) => setState(() =>
                                                appState.nativeLang = val!),
                                            labelColor: const Color(0xFF4ADE80),
                                            subtitle: "(My Language)",
                                            subtitleBelow: false),
                                        const SizedBox(height: 20),
                                        _buildSleekLangSelector(
                                            "TARGET",
                                            appState.targetLang,
                                            (val) => setState(() {
                                                  appState.targetLang = val!;
                                                  if (!_availableAiStyles(val)
                                                      .contains(
                                                          appState.aiStyle)) {
                                                    appState.aiStyle =
                                                        'Standard';
                                                  }
                                                }),
                                            labelColor: const Color(0xFF4ADE80),
                                            subtitle:
                                                "(Listening Language or Learning Language)",
                                            subtitleBelow: true),
                                        const SizedBox(height: 32),
                                        const Text("AI STYLE",
                                            style: TextStyle(
                                                color: Color(0xFF4ADE80),
                                                fontSize: 12,
                                                letterSpacing: 1,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 12),
                                        _buildPillToggleGrid(
                                          _availableAiStyles(
                                              appState.targetLang),
                                          appState.aiStyle,
                                          (style) => setState(
                                              () => appState.aiStyle = style),
                                        ),
                                        const SizedBox(height: 32),
                                        const Text("AI TONE",
                                            style: TextStyle(
                                                color: Color(0xFF4ADE80),
                                                fontSize: 12,
                                                letterSpacing: 1,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 12),
                                        _buildPillToggleGrid(
                                          const ["Formal", "Casual"],
                                          appState.tone,
                                          (tone) => setState(
                                              () => appState.tone = tone),
                                        ),
                                      ])),
                              const SizedBox(height: 30),
                            ]),
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        child: GestureDetector(
                          onTap: () => _handleEnterRoom(context),
                          child: Container(
                            height: 64,
                            decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF3B82F6),
                                      Color(0xFF2563EB)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: const Color(0xFF3B82F6)
                                          .withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8))
                                ]),
                            child: const Center(
                                child: Text("ENTER",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 3))),
                          ),
                        )),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildFooterLink(
                              "사용 설명서", () => _showUsageGuideDialog(context)),
                          _buildFooterLink("로그아웃", () async {
                            FFAppState().remainingTime = 0;
                            FFAppState().remainingTimeLoaded = false;
                            LobbyBrain.lastSyncedUid = null;
                            await FirebaseAuth.instance.signOut();
                            if (!context.mounted) return;
                            context.goNamed('Intro');
                          }),
                          _buildFooterLink(
                              "회원 탈퇴", () => _showDeleteAccountDialog(context)),
                        ],
                      ),
                    ),
                  ])),
      ),
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
