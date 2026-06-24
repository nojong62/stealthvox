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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:io';
import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class IntroMaster extends StatefulWidget {
  const IntroMaster({
    super.key,
    this.width,
    this.height,
    this.roomId,
    this.primaryColor,
  });

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
  final ScrollController _scrollController = ScrollController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool isLoginMode = true;
  bool isLoading = false;

  // ── Promo popup ──
  bool _promoVisible = false;
  bool _promoMounted = false;
  Timer? _promoFadeTimer;
  Timer? _promoRemoveTimer;
  static const _promoShownKey = 'promo_free_trial_shown';

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
    AppsFlyerManager.duoInviteSignal.addListener(_onDuoInviteSignal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEntryStatus());
    _initPromoPopup();
  }

  void _onDuoInviteSignal() {
    if (!mounted) return;
    if (FFAppState().isGuestSession &&
        FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] duoInviteSignal - routing to StealthRoom');
      context.pushReplacementNamed('StealthRoom');
    }
  }

  Future<void> _initPromoPopup() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_promoShownKey) ?? false;
    if (shown || !mounted) return;
    await prefs.setBool(_promoShownKey, true);
    if (!mounted) return;
    setState(() {
      _promoMounted = true;
      _promoVisible = true;
    });
    _promoFadeTimer = Timer(const Duration(milliseconds: 4400), () {
      if (mounted) setState(() => _promoVisible = false);
    });
    _promoRemoveTimer = Timer(const Duration(milliseconds: 5000), () {
      if (mounted) setState(() => _promoMounted = false);
    });
  }

  void _dismissPromo() {
    _promoFadeTimer?.cancel();
    _promoRemoveTimer?.cancel();
    if (!mounted) return;
    setState(() => _promoVisible = false);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _promoMounted = false);
    });
  }

  // 키보드가 올라올 때 로그인 버튼이 보이도록 자동 스크롤
  void _onFocusChange() {
    if (_emailFocusNode.hasFocus || _passwordFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    AppsFlyerManager.duoInviteSignal.removeListener(_onDuoInviteSignal);
    _promoFadeTimer?.cancel();
    _promoRemoveTimer?.cancel();
    _scrollController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkEntryStatus() async {
    // 1순위: FFAppState에 pending invite가 있으면 바로 StealthRoom
    debugPrint(
        '[Intro] isGuestSession=${FFAppState().isGuestSession}, pendingInviteType=${FFAppState().pendingInviteType}, duoRoomId=${FFAppState().duoRoomId}');
    if (FFAppState().isGuestSession &&
        FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] routing to StealthRoom for Duo invite');
      if (mounted) context.pushReplacementNamed('StealthRoom');
      return;
    }
    // 2순위: 항상 AppsFlyer 초기화 (로그인 여부와 무관하게 딥링크 콜백 등록)
    await _initAppsFlyer();
    if (!mounted) return;
    // 3순위: 이미 로그인된 회원이면 로비로 이동
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      context.goNamed('Lobby');
      return;
    }
    // 4순위: 비회원은 Intro에서 로그인 가능 상태로 대기
  }

  Future<void> _initAppsFlyer() async {
    await AppsFlyerManager.initialize(
      devKey: 'SQUmDTB2VzuPjrJGiy5SSC',
      appId: 'com.aienglishpractice.stealthvox',
    );
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
        final email = emailController.text.trim();
        final password = passwordController.text.trim();
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null && currentUser.isAnonymous) {
          final credential = EmailAuthProvider.credential(
            email: email,
            password: password,
          );
          await currentUser.linkWithCredential(credential);
        } else {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        }
        await _claimWelcomeBonus();
      }
      if (mounted) context.goNamed('Lobby');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
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

  Future<void> _claimWelcomeBonus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final deviceId = await _getDeviceId();
      if (deviceId.isEmpty) {
        debugPrint('[IntroMaster] welcome bonus skipped: empty deviceId');
        return;
      }

      final idToken = await user.getIdToken();
      final projectId = FirebaseFirestore.instance.app.options.projectId;
      final response = await http
          .post(
            Uri.parse(
              'https://us-central1-$projectId.cloudfunctions.net/claimWelcomeBonus',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'data': {'deviceId': deviceId},
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
          '[IntroMaster] welcome bonus HTTP ${response.statusCode}: ${response.body}',
        );
        return;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>?;
      final granted = result?['granted'] as bool? ?? false;

      if (!granted) {
        debugPrint('[IntroMaster] welcome bonus skipped: ${result?['reason']}');
        return;
      }

      final remainingTime =
          (result?['remainingTime'] as num?)?.toInt() ?? 18000;
      FFAppState().remainingTime = remainingTime;
      FFAppState().update(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "신규 회원 10분 무료 체험이 지급되었습니다!\n테스트 기간 중 참여 테스터에게는 5시간이 부여됩니다.",
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('[IntroMaster] claimWelcomeBonus error: $e');
    }
  }

  Future<String> _getDeviceId() async {
    if (Platform.isAndroid) {
      const androidIdPlugin = AndroidId();
      return await androidIdPlugin.getId() ?? '';
    }
    if (Platform.isIOS) {
      final iosInfo = await DeviceInfoPlugin().iosInfo;
      return iosInfo.identifierForVendor ?? '';
    }
    return '';
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("재설정 메일을 보냈습니다! 메일함(혹시 스팸함)을 확인하세요.",
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
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
        title: const Row(
          children: [
            Icon(Icons.lightbulb, color: Colors.amber),
            SizedBox(width: 8),
            Text("[ 사용 가이드 ]",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            "1. 실전 AI 대화 🤖\n"
            "• [AI Roleplay] 무작위 직업과 상황을 부여받고, 예측 불가한 실전 회화를 연습하세요.\n"
            "• [Free Talk] AI와 자유롭게 영어 대화를 나누며 실전 회화를 연습하세요.\n\n"
            "2. 심화 훈련 모드 📈\n"
            "• [Duo Connect] 글로벌 파트너와 각자의 모국어로 대화하면 딜레이 없이 동시통역해 줍니다. 초청받은 비회원이나 회원은 대화 시간 동안 구독료 차감이 없으며, 초청하는 회원만 차감됩니다.\n"
            "• [Step Expand] 짧은 기초 문장에서 시작해, AI의 유도에 따라 고급 문법을 더하며 원어민처럼 유창하고 긴 문장을 완성하세요.\n\n"
            "3. 스터디 룸 (History & Practice) 📚\n"
            "• 이전 대화를 복습하고 발음 교정 및 섀도잉 훈련을 진행합니다.\n"
            "• 스터디룸의 일부 메뉴는 가격의 25%만 차감됩니다. (동일 비용으로 4배 더 오래 훈련 가능)\n\n"
            "4. 💎 스토어: 합리적인 사용량 비례 과금\n"
            "StealthVox은 사용자가 딱 사용한 만큼만 최소 시간 단위로 과금되어 비용 부담이 없습니다!\n"
            "• ⏸️ Auto Pause: 60초 이상 반응이 없으면 자동으로 일시정지되어 과금이 멈춥니다. 다시 말을 시작하면 자동으로 재개됩니다.",
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
    return Stack(
      children: [
        _buildMain(context),
        if (_promoMounted) _buildPromoPopup(),
      ],
    );
  }

  Widget _buildMain(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.amber))
            : SafeArea(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(24, 24, 24,
                      24 + MediaQuery.of(context).viewInsets.bottom),
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
                            _buildTextField(
                              emailController,
                              "Email Address",
                              Icons.email_outlined,
                              false,
                              focusNode: _emailFocusNode,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => FocusScope.of(context)
                                  .requestFocus(_passwordFocusNode),
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              passwordController,
                              "Password",
                              Icons.lock_outline,
                              true,
                              focusNode: _passwordFocusNode,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _handleAuth(),
                            ),
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
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
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
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
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

  Widget _buildPromoPopup() {
    return GestureDetector(
      onTap: _dismissPromo,
      child: AnimatedOpacity(
        opacity: _promoVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black.withValues(alpha: 0.80),
          child: Center(
            child: GestureDetector(
              onTap: _dismissPromo,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 36),
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.20),
                      blurRadius: 48,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── NEW MEMBER badge ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'NEW MEMBER',
                        style: GoogleFonts.orbitron(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // ── Gift icon ──
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.amber.withValues(alpha: 0.10),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: const Icon(Icons.card_giftcard_rounded,
                          size: 34, color: Colors.amber),
                    ),
                    const SizedBox(height: 20),
                    // ── FREE / 10분 / TRIAL ──
                    Text(
                      'FREE',
                      style: GoogleFonts.orbitron(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white38,
                        letterSpacing: 5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFFFFD740), Color(0xFFFFA000)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ).createShader(bounds),
                      child: Text(
                        '10분',
                        style: GoogleFonts.orbitron(
                          fontSize: 60,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.05,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'TRIAL',
                      style: GoogleFonts.orbitron(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white38,
                        letterSpacing: 5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '신규 회원가입 즉시 지급',
                      style: GoogleFonts.roboto(
                        fontSize: 13,
                        color: Colors.white60,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '테스트 기간 중 참여 테스터에게 5시간 부여',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // ── 5초 countdown bar ──
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 1.0, end: 0.0),
                      duration: const Duration(milliseconds: 5000),
                      builder: (context, value, _) {
                        final secLeft = (value * 5).ceil();
                        return Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: value,
                                minHeight: 3,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.08),
                                valueColor:
                                    const AlwaysStoppedAnimation(Colors.amber),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$secLeft초 후 사라집니다  •  탭하면 닫힘',
                              style: const TextStyle(
                                  color: Colors.white30, fontSize: 11),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon,
    bool isObscure, {
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white38),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.5),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }
}
