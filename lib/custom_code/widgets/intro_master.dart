// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'trial/trial_flow_state.dart';
import 'trial/trial_device_gate.dart';
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
  State<IntroMaster> createState() => _IntroMasterState();
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

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[TrialDebug] IntroMaster initState, time=${DateTime.now().toIso8601String()}');
    _emailFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
    AppsFlyerManager.duoInviteSignal.addListener(_onDuoInviteSignal);
    if (TrialFlowState.instance.consumeSignupOnEntry()) {
      _isSignupMode = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkEntryStatus());
    }
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
    if (FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] duoInviteSignal - routing to StealthRoom');
      context.pushReplacementNamed('StealthRoom');
    }
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
    _scrollController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkEntryStatus() async {
    debugPrint(
        '[TrialDebug] _checkEntryStatus enter, currentUser=${FirebaseAuth.instance.currentUser?.uid}, isAnonymous=${FirebaseAuth.instance.currentUser?.isAnonymous}, time=${DateTime.now().toIso8601String()}');
    // 1순위: FFAppState에 pending invite가 있으면 바로 StealthRoom
    debugPrint(
        '[Intro] pendingInviteType=${FFAppState().pendingInviteType}, duoRoomId=${FFAppState().duoRoomId}');
    if (FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] routing to StealthRoom for Duo invite');
      if (mounted) context.pushReplacementNamed('StealthRoom');
      return;
    }
    // 2순위: 항상 AppsFlyer 초기화 (로그인 여부와 무관하게 딥링크 콜백 등록)
    await _initAppsFlyer();
    if (!mounted) return;
    // 3순위: 이미 로그인된 회원도 pending invite 우선 체크
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      debugPrint(
          '[TrialDebug] _checkEntryStatus  routing existing user to Lobby via _routeAfterAuth, time=${DateTime.now().toIso8601String()}');
      _routeAfterAuth();
      return;
    }
    // 4순위: 비회원은 Intro에서 로그인 가능 상태로 대기
  }

  /// pending Duo 초대가 있으면 StealthRoom, 없으면 Lobby로 라우팅.
  void _routeAfterAuth() {
    if (FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      debugPrint('[Intro] routing -> StealthRoom (pending duo invite)');
      FFAppState().pendingInviteType = '';
      FFAppState().duoRoomId = '';
      context.pushReplacementNamed('StealthRoom');
    } else {
      context.goNamed('Lobby');
    }
  }

  Future<void> _initAppsFlyer() async {
    await AppsFlyerManager.initialize(
      devKey: 'SQUmDTB2VzuPjrJGiy5SSC',
      appId: 'com.aienglishpractice.stealthvox',
    );
  }

  Future<void> _startTrial(BuildContext context) async {
    debugPrint(
        '[TrialDebug] _startTrial enter, currentUser=${FirebaseAuth.instance.currentUser?.uid}, isAnonymous=${FirebaseAuth.instance.currentUser?.isAnonymous}, time=${DateTime.now().toIso8601String()}');
    setState(() => isLoading = true);
    try {
      TrialFlowState.instance.restoreFromAppState();
      final canTry = await TrialDeviceGate.canTrial();
      if (!canTry) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('무료 체험은 기기당 1회만 가능합니다. 로그인해 주세요.')),
          );
        }
        return;
      }

      final existingUser = FirebaseAuth.instance.currentUser;
      if (existingUser != null && existingUser.isAnonymous != true) {
        debugPrint(
            '[TrialDebug] non-anonymous session detected, signing out, time=${DateTime.now().toIso8601String()}');
        debugPrint(
            '[Trial] non-anonymous session detected, signing out before trial: ${existingUser.uid}');
        await FirebaseAuth.instance.signOut();
      }
      if (FirebaseAuth.instance.currentUser == null) {
        AppStateNotifier.instance.updateNotifyOnAuthChange(false);
        await FirebaseAuth.instance.signInAnonymously();
      }
      await TrialDeviceGate.markUsed();

      if (!context.mounted) return;
      await _showLanguageSettingDialog();

      FFAppState().nativeLang = _trialNativeLang;
      FFAppState().targetLang = _trialTargetLang;

      if (!context.mounted) return;
      await _enterTrialAnyone(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('체험을 시작할 수 없습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _enterTrialAnyone(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !context.mounted) return;
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
    if (!context.mounted) return;
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
      }
      if (mounted) _routeAfterAuth();
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
                  padding: EdgeInsets.fromLTRB(24, 18, 24,
                      28 + MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
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
                      const SizedBox(height: 18),
                      _buildBentoCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "당신의 이야기가\n최고의 영어 교재가\n됩니다",
                              style: TextStyle(
                                color: Color(0xFFF5F5F7),
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "",
                              style: TextStyle(
                                color: Color(0xFFA7A7AE),
                                fontSize: 12,
                                height: 1.36,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildWaveform(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTrialGuideCard(),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 62,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0x1A8176EA),
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            side: const BorderSide(
                                color: Color(0xFF8B7CFF), width: 1.25),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: () {
                            debugPrint(
                                '[TrialDebug] trial button tapped, time=${DateTime.now().toIso8601String()}');
                            _startTrial(context);
                          },
                          child: const Text(
                            '1분 무료 체험 시작 →',
                            style: TextStyle(
                              color: Color(0xFFF5F5F7),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Center(
                        child: Text(
                          '회원가입 없이 바로 · 체험 하기',
                          style: TextStyle(
                            color: Color(0xFF6F6F78),
                            fontSize: 10.5,
                            height: 1.28,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("대화 1분",
                                style: GoogleFonts.roboto(
                                    fontSize: 11,
                                    color: const Color(0xFFA7A7AE))),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text("·",
                                  style: TextStyle(
                                      color: Color(0xFF8B7CFF), fontSize: 11)),
                            ),
                            Text("공부방 2분",
                                style: GoogleFonts.roboto(
                                    fontSize: 11,
                                    color: const Color(0xFFA7A7AE))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Row(
                        children: [
                          Icon(Icons.lightbulb, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text("이용 방법",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '대화하고 싶은 사람을 한 명 마음속에 떠올려 보세요. 그리고 그 사람이 바로 지금 눈앞에 있다고 생각하고, 하고 싶었던 말을 편하게 꺼내보세요. AI가 그 사람과 다르게 반응한다면, 그냥 넘기지 말고 "왜 그렇게 느껴?"하고 되물어 보세요. 묻고 답하다 보면, AI는 점점 더 그 사람에 가까워집니다. 진짜 그 사람과 마주 앉은 것처럼요.',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.6),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0x996F66D8),
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
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
                            '로그인',
                            style: TextStyle(
                              color: Color(0xFFF5F5F7),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
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
                      Text("자율 어학 연습의 동반자",
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
                        label: '카카오톡으로 계속하기',
                        backgroundColor: const Color(0xFFFEE500),
                        textColor: const Color(0xFF191919),
                        icon: const Icon(Icons.chat_bubble,
                            size: 20, color: Color(0xFF191919)),
                        onTap: () => _handleSocialAuth(
                            SocialAuthService.signInWithKakao),
                      ),
                      const SizedBox(height: 12),
                      SharedSocialButton(
                        label: 'Google 계정으로 계속하기',
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
                        label: '이메일로 계속하기(비밀번호 필요)',
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
    debugPrint('[KakaoAuth] _handleSocialAuth enter');
    setState(() => isLoading = true);
    try {
      await authFn();
      debugPrint(
          '[KakaoAuth] authFn complete, currentUser=${FirebaseAuth.instance.currentUser?.uid}, pendingInviteType=${FFAppState().pendingInviteType}');
      await _grantSignupBonusIfPossible();
      if (mounted) _routeAfterAuth();
      debugPrint('[KakaoAuth] _routeAfterAuth call complete');
    } catch (e, stack) {
      debugPrint('[KakaoAuth] _handleSocialAuth exception: $e');
      debugPrint('[KakaoAuth] stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _grantSignupBonusIfPossible() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('grantSignupBonus');
      final result = await callable.call<Map<String, dynamic>>({});
      final remainingTime = (result.data['remainingTime'] as num?)?.toInt();
      final granted = result.data['granted'] == true;
      if (remainingTime != null) {
        FFAppState().remainingTime = remainingTime;
        FFAppState().remainingTimeLoaded = true;
        LobbyBrain.lastSyncedUid = FirebaseAuth.instance.currentUser?.uid;
      }
      debugPrint(
          '[SignupBonus] grantSignupBonus complete, granted=$granted, remainingTime=$remainingTime');
    } catch (e, stack) {
      debugPrint('[SignupBonus] grantSignupBonus failed: $e');
      debugPrint('[SignupBonus] stack: $stack');
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
          width: 3.2,
          height: heights[index] * 0.78,
          margin: const EdgeInsets.symmetric(horizontal: 2.1),
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
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B7CFF).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildTrialGuideCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF17171B),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF27233C).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF8B7CFF).withValues(alpha: 0.16),
              ),
            ),
            child: const Text(
              '처음 오셨나요',
              style: TextStyle(
                color: Color(0xFF58D6BD),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 11),
          const Text(
            '1분 동안\nAnyone 모드를\n체험해 보세요',
            style: TextStyle(
              color: Color(0xFFF5F5F7),
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              height: 1.22,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '대화가 끝나면\n방금 그 대화가\n영어 교재로 바뀝니다.',
            style: TextStyle(
              color: Color(0xFFA7A7AE),
              fontSize: 12,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_none, size: 13, color: Color(0xFF8D8D96)),
                SizedBox(width: 5),
                Text(
                  '마이크를 사용합니다',
                  style: TextStyle(
                    color: Color(0xFF8D8D96),
                    fontSize: 10.5,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
