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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'dart:convert';

class IntroMaster extends StatefulWidget {
  const IntroMaster({
    Key? key,
    this.width,
    this.height,
    this.roomId,
    this.primaryColor,
  }) : super(key: key);

  final double? width;
  final double? height;
  final String? roomId;
  final Color? primaryColor;

  @override
  _IntroMasterState createState() => _IntroMasterState();
}

class _IntroMasterState extends State<IntroMaster> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoginMode = true;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEntryStatus());
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkEntryStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    // 이미 로그인된 회원이면 무조건 로비로 이동 (로비에서 AppsFlyer 초기화)
    if (user != null) {
      context.goNamed('Lobby');
      return;
    }
    // 비회원 첫 실행: Duo 초대 딥링크 수신을 위해 AppsFlyer 초기화
    _initAppsFlyer();
  }

  Future<void> _initAppsFlyer() async {
    // AppsFlyerManager의 static _isInitialized로 중복 초기화 방지
    // 이미 초기화된 경우 콜백만 현재 화면(IntroMaster)으로 교체됨
    await AppsFlyerManager.initialize(
      devKey: 'SQUmDTB2VzuPjrJGiy5SSC',
      appId: 'com.aienglishpractice.stealthvox',
      onDeepLink: (params) {
        if (mounted) _handleInviteDeepLink(params);
      },
    );
  }

  Future<void> _handleInviteDeepLink(Map<String, dynamic> params) async {
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

    if (deepLinkValue != 'duo_chat') return;

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
        params['roomId']?.toString() ??
        params['af_sub2']?.toString();

    if (inviterId == null ||
        inviterId.isEmpty ||
        roomId == null ||
        roomId.isEmpty) {
      debugPrint('[IntroMaster] DeepLink: missing parameters');
      return;
    }

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
        if (!mounted) return;
      }

      FFAppState().isGuestSession = true;
      FFAppState().inviterUid = inviterId;
      FFAppState().duoRoomId = roomId;

      if (!mounted) return;
      debugPrint('[IntroMaster] DeepLink success → roomId: $roomId');
      context.pushReplacementNamed('StealthRoom');
    } on FirebaseAuthException catch (e) {
      debugPrint('[IntroMaster] Auth error: $e');
    } catch (e) {
      debugPrint('[IntroMaster] DeepLink error: $e');
    }
  }

  Future<void> _handleAuth() async {
    setState(() => isLoading = true);
    try {
      if (isLoginMode) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      }
      if (mounted) context.goNamed('Lobby');
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? "오류가 발생했습니다.",
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("위에 이메일을 먼저 입력해주세요.",
                style: TextStyle(fontWeight: FontWeight.bold))),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: emailController.text.trim(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("재설정 메일을 보냈습니다! 메일함(혹시 스팸함)을 확인하세요.",
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("전송 실패: ${e.toString()}")),
      );
    }
  }

  // 💡 [업데이트 완료] 현재 앱 스펙 및 새로운 과금/스토어 정책에 맞춰 가이드 전면 개편
  void _showGuideDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.lightbulb, color: Colors.amber),
            SizedBox(width: 8),
            Text("[ 사용 가이드 ]",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: const Text(
            "1. 실전 AI 대화 🤖\n"
            "• [AI Roleplay] 무작위 직업과 상황을 부여받고, 예측 불가한 실전 회화를 연습하세요.\n"
            "• [Clone AI] 지인의 카톡을 분석해 완벽하게 성격을 복제한 AI와 편하게 대화해 보세요.\n\n"
            "2. 심화 훈련 모드 📈\n"
            "• [Duo Connect] 글로벌 파트너와 각자의 모국어로 대화하면 딜레이 없이 동시통역해 줍니다.\n"
            "• [Step Expand] 짧은 기초 문장에서 시작해, AI의 유도에 따라 고급 문법을 더하며 원어민처럼 유창하고 긴 문장을 완성하세요.\n\n"
            "3. 스터디 룸 (History & Practice) 📚\n"
            "• 이전 대화를 복습하고 발음 교정 및 섀도잉 훈련을 진행합니다.\n"
            "• 🔥 꿀팁: 스터디룸에서 연습할 때는 가격의 25%만 차감됩니다! (동일 비용으로 무려 4배 더 오래 훈련 가능)\n\n"
            "4. 💎 스토어: 합리적인 사용량 비례 과금\n"
            "StealthVox은 사용자가 딱 사용한 만큼만 최소 시간 단위로 과금되어 비용 부담이 없습니다!",
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("닫기",
                style: TextStyle(
                    color: Colors.amber, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.amber))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 40),
                      _buildBentoCard(
                        child: Column(
                          children: [
                            const Icon(Icons.record_voice_over,
                                size: 50, color: Colors.amber),
                            const SizedBox(height: 16),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                "StealthVox",
                                style: GoogleFonts.orbitron(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text("Real-Life Shadowing",
                                style: GoogleFonts.roboto(
                                    fontSize: 14, color: Colors.white54)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 로그인/회원가입 구역
                      _buildBentoCard(
                        child: Column(
                          children: [
                            _buildTextField(emailController, "Email Address",
                                Icons.email_outlined, false),
                            const SizedBox(height: 16),
                            _buildTextField(passwordController, "Password",
                                Icons.lock_outline, true),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _handleAuth,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                                child: Text(
                                  isLoginMode ? "LOGIN" : "SIGN UP",
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      letterSpacing: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () =>
                                  setState(() => isLoginMode = !isLoginMode),
                              child: Text(
                                isLoginMode
                                    ? "계정이 없으신가요? 회원가입"
                                    : "이미 계정이 있으신가요? 로그인",
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _resetPassword,
                              child: _buildBentoCard(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.lock_reset,
                                        color: Colors.amber, size: 26),
                                    SizedBox(height: 8),
                                    Text("비밀번호 찾기",
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _showGuideDialog(context),
                              child: _buildBentoCard(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.help_outline,
                                        color: Colors.amber, size: 26),
                                    SizedBox(height: 8),
                                    Text("사용 설명서",
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBentoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint,
      IconData icon, bool isObscure) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white38),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: Colors.black.withOpacity(0.5),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }
}

// =======================================================
// AppsFlyerManager — IntroMaster 전용 (self-contained)
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
