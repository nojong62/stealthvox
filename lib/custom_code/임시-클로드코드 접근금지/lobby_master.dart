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
import '/custom_code/actions/billing_ticker.dart';

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
    'Korean'
  ];

  bool isLoading = false;
  String _apiKey = "";
  bool _isKeyLoaded = false;

  // 💡 [핵심 뼈대] 버튼 연속 클릭 방지용 잠금장치
  bool _isActionLocked = false;

  // 📦 [Box 4: 라이프사이클 및 초기화 (LobbyBrain 분리)]
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Duo 초대 pending 상태이면 Lobby 스킵하고 바로 StealthRoom으로
      debugPrint('[Lobby] isGuestSession=${FFAppState().isGuestSession}, pendingInviteType=${FFAppState().pendingInviteType}, duoRoomId=${FFAppState().duoRoomId}');
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

  void _initAppState() {
    if (FFAppState().tone == null || FFAppState().tone.isEmpty)
      setState(() => FFAppState().tone = "Casual");
    if (FFAppState().nativeLang == null || FFAppState().nativeLang.isEmpty)
      setState(() => FFAppState().nativeLang = "Korean");
    if (FFAppState().targetLang == null || FFAppState().targetLang.isEmpty)
      setState(() => FFAppState().targetLang = "English");
    if (FFAppState().aiVoice.isEmpty)
      setState(() => FFAppState().aiVoice = "onyx");
  }

  Future<void> _initializeLobbyData() async {
    setState(() => isLoading = true);
    try {
      // 1. DB 통신 분리: 서버 시간 및 남은 시간 동기화
      int? serverRemainingTime =
          await LobbyBrain.getRemainingTime(FirebaseAuth.instance.currentUser);
      if (serverRemainingTime != null && mounted) {
        setState(() => FFAppState().remainingTime = serverRemainingTime);
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

      // 3. AppsFlyer SDK 초기화 (하드코딩 값 사용)
      await AppsFlyerManager.initialize(
        devKey: 'SQUmDTB2VzuPjrJGiy5SSC',
        appId: 'com.aienglishpractice.stealthvox',
        onDeepLink: (params) {
          if (mounted) _handleInviteDeepLink(params);
        },
      );
      if (!mounted) return;
    } catch (e) {
      print("Init Error: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      BillingTicker.instance.flushNow();
    }
  }

  // 📦 [Box 5: 룸 입장 관리 (Mutex Lock 적용)]
  void _handleEnterRoom(BuildContext context, var appState) async {
    if (_isActionLocked) return;
    _isActionLocked = true;
    try {
      FocusScope.of(context).unfocus();
      if (appState.remainingTime <= 0) {
        context.pushNamed('Store');
        return;
      }
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

  // 📦 [Box 5 추가: Duo 초대 Deep Link 처리]
  Future<void> _handleInviteDeepLink(Map<String, dynamic> params) async {
    if (_isActionLocked) return;

    // deepLink가 JSON string으로 내포된 경우 파싱
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

    if (deepLinkValue != 'duo_chat') {
      debugPrint('[DeepLink] Not duo_chat: $deepLinkValue');
      return;
    }

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
      debugPrint('[DeepLink] Missing parameters');
      return;
    }

    _isActionLocked = true;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

    try {
      if (isGuest) {
        await FirebaseAuth.instance.signInAnonymously();
        if (!mounted) return;
      }

      FFAppState().isGuestSession = true;
      FFAppState().inviterUid = inviterId;
      FFAppState().duoRoomId = roomId;
      FFAppState().pendingInviteType = 'duo';
      FFAppState().update(() {});

      if (!mounted) return;
      debugPrint('[Lobby] routing to StealthRoom for Duo invite');

      context.pushReplacementNamed('StealthRoom');
    } on FirebaseAuthException catch (e) {
      debugPrint('[DeepLink] Auth error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("네트워크를 확인해주세요",
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Color(0xFFFF453A)));
      }
    } catch (e) {
      debugPrint('[DeepLink] Unexpected error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("초대 처리 중 오류가 발생했습니다."),
            backgroundColor: Color(0xFFFF453A)));
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

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: const [
          Icon(Icons.article_outlined, color: Color(0xFF0A84FF)),
          SizedBox(width: 8),
          Text("[ 이용 약관 ]",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ]),
        content: const SingleChildScrollView(
          child: Text(
            "1. 서비스 목적\n본 약관은 Routine이 제공하는 AI 통역 및 통화 서비스의 이용 조건 및 절차를 규정합니다.\n\n"
            "2. 요금 및 환불\n• 본 서비스는 유료 시간제(분 단위 차감)로 운영됩니다.\n\n"
            "3. 사용자의 의무\n• 타인에게 피해를 주는 불법적인 사용을 금지합니다.\n\n"
            "4. 면책 조항\n• AI 번역은 100% 정확성을 보장하지 않습니다.",
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("동의 및 닫기",
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

  void _showBillingDebugLog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        final logs = BillingTicker.instance.billingLogs;
        final text = logs.isEmpty ? null : logs.join('\n');

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (_, controller) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'BILLING DEBUG LOG',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: logs.isEmpty
                    ? const Center(
                        child: Text(
                          '로그가 없습니다.',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.all(12),
                        itemCount: logs.length,
                        itemBuilder: (_, i) => Text(
                          logs[i],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ),
              ),
              const Divider(color: Colors.white12, height: 1),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: text == null
                            ? Colors.white12
                            : const Color(0xFF3B82F6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: text == null
                          ? null
                          : () {
                              Clipboard.setData(
                                  ClipboardData(text: text));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      '✅ BILLING 로그가 복사되었습니다'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                      child: const Text(
                        '로그 복사',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
                  Colors.white.withOpacity(0.06),
                  Colors.white.withOpacity(0.02)
                ]),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: borderColor ?? Colors.white.withOpacity(0.1),
                width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 40,
                  offset: const Offset(0, 10))
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSleekVoiceSelector(String value, Function(String?) onChanged) {
    final List<String> voices = ["shimmer", "echo", "onyx", "fable", "alloy"];
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12)),
      child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
        value: voices.contains(value) ? value : "onyx",
        dropdownColor: const Color(0xFF1E1E1E),
        isExpanded: true,
        icon: const Icon(Icons.record_voice_over_rounded,
            color: Colors.white54, size: 20),
        style: const TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        items: voices
            .map((String voice) =>
                DropdownMenuItem<String>(value: voice, child: Text(voice)))
            .toList(),
        onChanged: onChanged,
      )),
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
                ? const Color(0xFF3B82F6).withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isHighlight
                    ? const Color(0xFF3B82F6).withOpacity(0.5)
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
      {Color labelColor = Colors.white54}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              color: labelColor,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
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
                        : Colors.black.withOpacity(0.4),
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
    int displayMinutes = appState.remainingTime ~/ 60;

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
            child: isLoading
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
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: const Color(0xFF3B82F6)
                                              .withOpacity(0.5))),
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
                              GestureDetector(
                                onLongPress: () =>
                                    _showBillingDebugLog(context),
                                child: _buildGlassContainer(
                                    child: Column(children: [
                                  Text("REMAINING TIME",
                                      style: GoogleFonts.orbitron(
                                          color: const Color(0xFF60A5FA),
                                          fontSize: 12,
                                          letterSpacing: 3,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text("${displayMinutes}m",
                                      style: GoogleFonts.orbitron(
                                          color: appState.remainingTime > 60
                                              ? Colors.white
                                              : const Color(0xFFFF453A),
                                          fontSize: 48,
                                          fontWeight: FontWeight.bold,
                                          shadows: [
                                            Shadow(
                                                color: const Color(0xFF3B82F6)
                                                    .withOpacity(0.5),
                                                blurRadius: 20)
                                          ])),
                                ])),
                              ),
                              const SizedBox(height: 20),
                              _buildGlassContainer(
                                  borderColor:
                                      const Color(0xFF3B82F6).withOpacity(0.3),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildSleekLangSelector(
                                            "ORIGIN",
                                            appState.nativeLang,
                                            (val) => setState(() =>
                                                appState.nativeLang = val!),
                                            labelColor:
                                                const Color(0xFF93C5FD)),
                                        const SizedBox(height: 20),
                                        _buildSleekLangSelector(
                                            "TARGET",
                                            appState.targetLang,
                                            (val) => setState(() =>
                                                appState.targetLang = val!),
                                            labelColor:
                                                const Color(0xFF4ADE80)),
                                        const SizedBox(height: 32),
                                        const Text("AI TONE",
                                            style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                                letterSpacing: 1,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 12),
                                        Row(children: [
                                          _buildPillToggle(
                                              "Formal",
                                              appState.tone == "Formal",
                                              () => setState(() =>
                                                  appState.tone = "Formal")),
                                          const SizedBox(width: 12),
                                          _buildPillToggle(
                                              "Casual",
                                              appState.tone == "Casual",
                                              () => setState(() =>
                                                  appState.tone = "Casual"))
                                        ]),
                                        const SizedBox(height: 32),
                                        const Text("MY AI VOICE",
                                            style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                                letterSpacing: 1,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 12),
                                        _buildSleekVoiceSelector(
                                            appState.aiVoice,
                                            (val) => setState(
                                                () => appState.aiVoice = val!)),
                                      ])),
                              const SizedBox(height: 30),
                            ]),
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        child: GestureDetector(
                          onTap: () => _handleEnterRoom(context, appState),
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
                                          .withOpacity(0.4),
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
                              "이용 약관", () => _showTermsDialog(context)),
                          _buildFooterLink("로그아웃", () async {
                            await FirebaseAuth.instance.signOut();
                            if (mounted) context.goNamed('Intro');
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
      print("DB Fetch Error: $e");
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
    } catch (e) {
      print("Remote Config Error: $e");
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
    await newHistoryRef
        .set({'created_at': FieldValue.serverTimestamp(), 'is_pinned': false});
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
// 📦 [Box 10: AppsFlyerManager — Deferred/Direct Deep Link]
// =======================================================
class AppsFlyerManager {
  static AppsflyerSdk? _instance;
  static bool _isInitialized = false;
  // Callback replaced per screen without re-creating the SDK instance.
  static Function(Map<String, dynamic>)? _onDeepLink;

  static Future<void> initialize({
    required String devKey,
    required String appId,
    required Function(Map<String, dynamic>) onDeepLink,
  }) async {
    _onDeepLink = onDeepLink;
    if (_isInitialized) return;
    try {
      final AppsFlyerOptions options = AppsFlyerOptions(
        afDevKey: devKey,
        appId: appId,
        showDebug: false,
        timeToWaitForATTUserAuthorization: 60,
      );

      _instance = AppsflyerSdk(options);

      _instance!.onInstallConversionData((res) {
        final cb = _onDeepLink;
        if (cb != null) _routeCallback(res, cb);
      });

      _instance!.onAppOpenAttribution((res) {
        final cb = _onDeepLink;
        if (cb != null) _routeCallback(res, cb);
      });

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
            _onDeepLink?.call(params);
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

  static void _routeCallback(
    dynamic res,
    Function(Map<String, dynamic>) onDeepLink,
  ) {
    try {
      if (res == null) return;
      final Map<dynamic, dynamic> raw = res as Map<dynamic, dynamic>;
      if ((raw['status']?.toString() ?? '') != 'success') return;
      final dynamic payload = raw['data'] ?? raw;
      if (payload == null) return;
      onDeepLink(Map<String, dynamic>.from(payload as Map));
    } catch (e) {
      debugPrint('[AppsFlyerManager] callback error: $e');
    }
  }
}
