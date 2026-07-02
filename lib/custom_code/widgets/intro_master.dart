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
import 'trial/trial_flow_state.dart';
import 'trial/trial_device_gate.dart';
import 'trial/onboarding_guide_section.dart';
import 'shared_social_button.dart';
import '/auth/social_auth_service.dart';

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
  bool _isSignupMode = false;
  bool _showEmailInSignup = false;
  String _trialNativeLang = 'Korean';
  String _trialTargetLang = 'English';

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
    const trialLanguages = [
      'Korean',
      'English',
      'Japanese',
      'Chinese',
      'Spanish'
    ];
    _trialNativeLang = trialLanguages.contains(FFAppState().nativeLang)
        ? FFAppState().nativeLang
        : 'Korean';
    _trialTargetLang = trialLanguages.contains(FFAppState().targetLang)
        ? FFAppState().targetLang
        : 'English';
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

  Future<void> _startTrial(BuildContext context) async {
    setState(() => isLoading = true);
    try {
      TrialFlowState.instance.restoreFromAppState();
      final canTry = await TrialDeviceGate.canTrial();
      if (!canTry) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('무료 체험은 기기당 1회만 가능합니다. 로그인해 주세요.')),
          );
        }
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      await TrialDeviceGate.markUsed();

      if (!mounted) return;
      await _showLanguageSettingDialog();

      FFAppState().nativeLang = _trialNativeLang;
      FFAppState().targetLang = _trialTargetLang;

      if (!mounted) return;
      await _enterTrialAnyone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('체험을 시작할 수 없습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _enterTrialAnyone() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    final historyRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chat_history')
        .doc();
    await historyRef.set({
      'created_at': FieldValue.serverTimestamp(),
      'is_pinned': false,
    });
    TrialFlowState.instance.myHistoryRef = historyRef;
    TrialFlowState.instance.advanceTo(1);
    if (!mounted) return;
    context.pushNamed(
      'StealthRoom',
      queryParameters: {
        'historyRef': serializeParam(
          historyRef,
          ParamType.DocumentReference,
        ),
      }.withoutNulls,
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
        // [Welcome bonus removed] Replaced by the 30-second free trial flow.
        // await _claimWelcomeBonus();
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
    if (_isSignupMode) return _buildSignupView(context);

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF101017),
            Color(0xFF050507),
            Color(0xFF050507),
          ],
          stops: [0.0, 0.38, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.amber))
            : SafeArea(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(24, 22, 24,
                      34 + MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.record_voice_over,
                              size: 20, color: Color(0xFF58D6BD)),
                          const SizedBox(width: 8),
                          Text("StealthVox",
                              style: GoogleFonts.orbitron(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFF5F5F7))),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text("내 이야기로 배우는 영어",
                          style: GoogleFonts.roboto(
                              fontSize: 11,
                              fontWeight: FontWeight.w300,
                              color: const Color(0xFF6F6F78))),
                      const SizedBox(height: 24),
                      _buildBentoCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "당신의 이야기가\n최고의 영어 교재가\n됩니다",
                              style: TextStyle(
                                color: Color(0xFFF5F5F7),
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                height: 1.22,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "자율 학습 공부의 동반자",
                              style: TextStyle(
                                color: Color(0xFFA7A7AE),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildWaveform(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const OnboardingGuideSection(),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 66,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0x1A8176EA),
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            side: const BorderSide(
                                color: Color(0xFF8B7CFF), width: 1.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32),
                            ),
                          ),
                          onPressed: () => _startTrial(context),
                          child: const Text(
                            '30초 무료 체험 시작 →',
                            style: TextStyle(
                              color: Color(0xFFF5F5F7),
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Center(
                        child: Text(
                          '회원가입 없이 바로 · 기기당 1회',
                          style: TextStyle(
                            color: Color(0xFF6F6F78),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("AI는 30초",
                                style: GoogleFonts.roboto(
                                    fontSize: 12,
                                    color: const Color(0xFFA7A7AE))),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text("·",
                                  style: TextStyle(
                                      color: Color(0xFF8B7CFF), fontSize: 12)),
                            ),
                            Text("공부방 1분",
                                style: GoogleFonts.roboto(
                                    fontSize: 12,
                                    color: const Color(0xFFA7A7AE))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xCC6F66D8),
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: () {
                            if (_scrollController.hasClients) {
                              _scrollController.jumpTo(0);
                            }
                            setState(() {
                              _isSignupMode = true;
                              _showEmailInSignup = false;
                            });
                          },
                          child: const Text(
                            '회원 가입',
                            style: TextStyle(
                              color: Color(0xFFF5F5F7),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
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

  Future<void> _showLanguageSettingDialog() async {
    const languages = [
      'Korean',
      'English',
      'Japanese',
      'Chinese',
      'Spanish',
      'French',
      'German',
      'Hindi',
      'Russian',
      'Portuguese',
      'Italian',
      'Dutch',
    ];
    String nativeLang = _trialNativeLang;
    String targetLang = _trialTargetLang;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161616),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF2A3A36), width: 1),
              ),
              title: const Text(
                '언어 설정',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _languageDropdown(
                    label: '모국어',
                    value: nativeLang,
                    items: languages,
                    onChanged: (value) =>
                        setDialogState(() => nativeLang = value),
                  ),
                  const SizedBox(height: 14),
                  _languageDropdown(
                    label: '학습 언어',
                    value: targetLang,
                    items: languages,
                    onChanged: (value) =>
                        setDialogState(() => targetLang = value),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              actions: [
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      side: const BorderSide(
                          color: Color(0xFF7F77DD), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _trialNativeLang = nativeLang;
                        _trialTargetLang = targetLang;
                      });
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text(
                      '확인',
                      style: TextStyle(
                          color: Color(0xFFCECBF6),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _languageDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF2A2A2A),
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              items: items
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(item),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignupView(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.amber))
            : SafeArea(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(24, 18, 24,
                      24 + MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => setState(() {
                            _isSignupMode = false;
                            _showEmailInSignup = false;
                          }),
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white70),
                          tooltip: '뒤로',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text("StealthVox",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.orbitron(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      Text("자율 학습 공부의 동반자",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.roboto(
                              fontSize: 13, color: Colors.white54)),
                      const SizedBox(height: 28),
                      const Center(
                        child: Text('가입 방법 선택',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 16),
                      SharedSocialButton(
                        label: '카카오톡으로 가입하기',
                        backgroundColor: const Color(0xFFFEE500),
                        textColor: const Color(0xFF191919),
                        icon: const Icon(Icons.chat_bubble,
                            size: 20, color: Color(0xFF191919)),
                        onTap: () => _handleSocialAuth(
                            SocialAuthService.signInWithKakao),
                      ),
                      const SizedBox(height: 12),
                      SharedSocialButton(
                        label: 'Google 계정으로 가입하기',
                        backgroundColor: Colors.white,
                        textColor: Colors.black87,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                        icon: const Icon(Icons.g_mobiledata,
                            size: 22, color: Colors.blue),
                        onTap: () => _handleSocialAuth(
                            SocialAuthService.signInWithGoogle),
                      ),
                      const SizedBox(height: 12),
                      SharedSocialButton(
                        label: '이메일로 가입하기(비밀번호 필요)',
                        backgroundColor: const Color(0xFF333333),
                        textColor: Colors.white,
                        icon: const Icon(Icons.email_outlined,
                            size: 20, color: Colors.white70),
                        onTap: () => setState(
                            () => _showEmailInSignup = !_showEmailInSignup),
                      ),
                      if (_showEmailInSignup) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF222222),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  _emailTabBtn('로그인', isLoginMode,
                                      () => setState(() => isLoginMode = true)),
                                  const SizedBox(width: 8),
                                  _emailTabBtn(
                                      '회원가입',
                                      !isLoginMode,
                                      () =>
                                          setState(() => isLoginMode = false)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                emailController,
                                "이메일",
                                Icons.email_outlined,
                                false,
                                focusNode: _emailFocusNode,
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => FocusScope.of(context)
                                    .requestFocus(_passwordFocusNode),
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                passwordController,
                                "비밀번호",
                                Icons.lock_outline,
                                true,
                                focusNode: _passwordFocusNode,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _handleAuth(),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : _handleAuth,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD4AF37),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: Text(
                                    isLoginMode ? "로그인" : "가입하기",
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                              if (isLoginMode) ...[
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: _resetPassword,
                                  child: const Text(
                                    '비밀번호 찾기',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 12),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(Icons.lightbulb, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text("사용 가이드",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "1. 실전 AI 대화\n"
                        "• [AI Roleplay] 무작위 직업과 상황을 부여받고 예측 불가한 실전 회화를 연습하세요.\n"
                        "• [Anyone] 마음속에 떠올린 사람에게 말하듯 대화하면 AI가 점점 그 사람이 되어 응답합니다.\n\n"
                        "2. 심화 훈련 모드\n"
                        "• [Duo Connect] 글로벌 파트너와 각자의 모국어로 대화하면 동시에 통역해 줍니다.\n"
                        "• [Step Expand] 짧은 문장에서 시작해 고급 문법을 더하며 긴 문장을 완성하세요.\n\n"
                        "3. 스터디 룸\n"
                        "• 이전 대화를 복습하고 발음 교정 및 섀도잉 훈련을 진행합니다.\n"
                        "• 스터디룸의 일부 메뉴는 가격의 25%만 차감됩니다.\n\n"
                        "4. 합리적인 사용량 비례 과금\n"
                        "StealthVox는 사용한 만큼 최소 시간 단위로 과금합니다. 60초 이상 반응이 없으면 자동 일시정지됩니다.",
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _handleSocialAuth(Future<dynamic> Function() authFn) async {
    setState(() => isLoading = true);
    try {
      await authFn();
      if (mounted) context.goNamed('Lobby');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _emailTabBtn(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? const Color(0xFFD4AF37) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? Colors.white : Colors.white38,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaveform() {
    final heights = [
      12.0,
      20.0,
      30.0,
      16.0,
      34.0,
      26.0,
      18.0,
      32.0,
      14.0,
      28.0,
      22.0,
      10.0,
    ];
    final colors = [
      const Color(0xFF58D6BD),
      const Color(0xFF8B7CFF),
      const Color(0xFF45BFA5),
      const Color(0xFF7167D8),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(heights.length, (index) {
        return Container(
          width: 3.5,
          height: heights[index] * 0.88,
          margin: const EdgeInsets.symmetric(horizontal: 2.25),
          decoration: BoxDecoration(
            color: colors[index % colors.length],
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildBentoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B7CFF).withValues(alpha: 0.06),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
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
