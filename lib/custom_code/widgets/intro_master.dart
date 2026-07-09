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
import 'auth_progress_view.dart';
import 'shared_social_button.dart';
import '/auth/social_auth_service.dart';

enum IntroScreen { welcome, auth }

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
  static const String _termsUrl =
      'https://docs.google.com/document/d/1KE4xrb63SDw1ZkiNQ_wxQjH7iyY6msTuVtazCTnR7KY/edit';
  static const String _privacyUrl =
      'https://docs.google.com/document/d/1qz1aCx6ZcxCkANFUSvbnE18H2-SbEhPUWlvZw27-DAQ/edit';
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool isLoginMode = true;
  bool isLoading = false;
  IntroScreen _currentScreen = IntroScreen.welcome;
  bool _showEmailForm = false;
  bool _trialStarting = false;
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
    if (FFAppState().trialCompleted) {
      _currentScreen = IntroScreen.auth;
    } else {
      _currentScreen = IntroScreen.welcome;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEntryStatus());
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
    // 3순위: 정식 회원(non-anonymous)만 Lobby로 라우팅
    // anonymous 체험 유저는 Intro에 머물러야 함 (Welcome 또는 Auth)
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      debugPrint(
          '[TrialDebug] _checkEntryStatus  routing non-anonymous user to Lobby via _routeAfterAuth, time=${DateTime.now().toIso8601String()}');
      _routeAfterAuth();
      return;
    }
    if (user != null && user.isAnonymous) {
      debugPrint(
          '[TrialDebug] _checkEntryStatus  anonymous user stays on Intro, trialCompleted=${FFAppState().trialCompleted}');
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
    if (_trialStarting) return;
    _trialStarting = true;
    setState(() => isLoading = true);
    try {
      TrialFlowState.instance.restoreFromAppState();

      final existingUser = FirebaseAuth.instance.currentUser;
      if (existingUser != null && existingUser.isAnonymous != true) {
        // 정식 회원은 체험 불가 -> signOut 하지 않고 Lobby로 이동
        debugPrint(
            '[Trial] existing member tried trial, redirecting to Lobby: ${existingUser.uid}');
        if (mounted) context.goNamed('Lobby');
        return;
      }

      // 정책 A: 체험 확정 -> pending invite 초기화 (체험과 Duo는 분리)
      FFAppState().pendingInviteType = '';
      FFAppState().duoRoomId = '';

      if (FirebaseAuth.instance.currentUser == null) {
        AppStateNotifier.instance.updateNotifyOnAuthChange(false);
        await FirebaseAuth.instance.signInAnonymously();
      }
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
      AppStateNotifier.instance.updateNotifyOnAuthChange(true);
      _trialStarting = false;
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
          await _cleanupTrialSandbox();
          await currentUser.linkWithCredential(credential);
        } else {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        }
      }
      // trialCompleted trigger moved to routine_mode_anyone.dart (Anyone 1-min timer natural expiry)
      // see: fix/trial-completed-trigger-point branch
      FFAppState().lastAuthProvider = 'email';
      if (!isLoginMode) {
        await _grantSignupBonusIfPossible();
      }
      // 가입/로그인 모두 연령 정보 확인 (birthYear 있으면 자동 통과)
      if (mounted) {
        await _checkAgeAndRoute();
      }
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
    switch (_currentScreen) {
      case IntroScreen.welcome:
        return _buildWelcomeView(context);
      case IntroScreen.auth:
        return _buildAuthView(context);
    }
  }

  Widget _buildWelcomeView(BuildContext context) {
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
            ? const SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28),
                    child: AuthProgressView(),
                  ),
                ),
              )
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
                              _currentScreen = IntroScreen.auth;
                              _showEmailForm = false;
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

  Widget _buildAuthView(BuildContext context) {
    return _buildAuthScaffold(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 뒤로가기: 체험 완료 전에만 표시
          if (!FFAppState().trialCompleted)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => setState(() {
                  _currentScreen = IntroScreen.welcome;
                  _showEmailForm = false;
                }),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: '뒤로',
              ),
            ),
          SizedBox(height: FFAppState().trialCompleted ? 60 : 24),
          // 제목 + 재방문 안내
          ..._buildAuthHeader(),
          const SizedBox(height: 34),
          // provider 버튼들 (재방문 시 이전 provider 강조)
          ..._buildProviderButtons(),
          // 이메일 폼
          if (_showEmailForm) ...[
            const SizedBox(height: 18),
            _buildEmailForm(isLogin: isLoginMode),
          ],
          const SizedBox(height: 32),
          // 약관 동의 인라인 텍스트
          _buildTermsInlineText(),
        ],
      ),
    );
  }

  List<Widget> _buildAuthHeader() {
    final lastProvider = FFAppState().lastAuthProvider;
    final providerLabel = switch (lastProvider) {
      'kakao' => '카카오',
      'google' => 'Google',
      'email' => '이메일',
      _ => '',
    };

    return [
      const Text(
        '계정으로 계속하기',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.32,
        ),
      ),
      if (lastProvider.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          '이전에 $providerLabel 계정으로 가입했습니다',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9C9CA6),
            fontSize: 13,
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildProviderButtons() {
    final lastProvider = FFAppState().lastAuthProvider;

    // 각 provider 버튼 정의
    Widget kakaoBtn() => SharedSocialButton(
          label: '카카오톡으로 계속하기',
          backgroundColor: const Color(0xFFFEE500),
          textColor: const Color(0xFF191919),
          icon: Image.asset(
            'assets/images/kakao_logo.png',
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.chat_bubble,
              size: 20,
              color: Color(0xFF191919),
            ),
          ),
          onTap: () => _handleUnifiedAuth(
            SocialAuthService.signInWithKakao,
            provider: 'kakao',
          ),
        );

    Widget googleBtn() => SharedSocialButton(
          label: 'Google로 계속하기',
          backgroundColor: Colors.white,
          textColor: Colors.black87,
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          icon: Image.asset(
            'assets/images/google_logo.png',
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.g_mobiledata,
              size: 24,
              color: Colors.blue,
            ),
          ),
          onTap: () => _handleUnifiedAuth(
            SocialAuthService.signInWithGoogle,
            provider: 'google',
          ),
        );

    Widget emailBtn() => SharedSocialButton(
          label: '이메일로 계속하기',
          backgroundColor: const Color(0xFF33333A),
          textColor: Colors.white,
          icon: const Icon(
            Icons.email_outlined,
            size: 20,
            color: Colors.white70,
          ),
          onTap: () => setState(() {
            _showEmailForm = !_showEmailForm;
          }),
        );

    if (lastProvider.isEmpty) {
      return [
        kakaoBtn(),
        const SizedBox(height: 12),
        googleBtn(),
        const SizedBox(height: 12),
        emailBtn(),
      ];
    }

    late final Widget primaryBtn;
    late final List<Widget> secondaryBtns;

    switch (lastProvider) {
      case 'kakao':
        primaryBtn = kakaoBtn();
        secondaryBtns = [googleBtn(), const SizedBox(height: 12), emailBtn()];
        break;
      case 'google':
        primaryBtn = googleBtn();
        secondaryBtns = [kakaoBtn(), const SizedBox(height: 12), emailBtn()];
        break;
      case 'email':
        primaryBtn = emailBtn();
        secondaryBtns = [kakaoBtn(), const SizedBox(height: 12), googleBtn()];
        break;
      default:
        primaryBtn = kakaoBtn();
        secondaryBtns = [googleBtn(), const SizedBox(height: 12), emailBtn()];
    }

    return [
      primaryBtn,
      const SizedBox(height: 24),
      const Text(
        '다른 계정으로 계속하기',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF9C9CA6),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      ...secondaryBtns,
    ];
  }

  Widget _buildAuthScaffold({
    required BuildContext context,
    required Widget child,
  }) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: isLoading
            ? const SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28),
                    child: AuthProgressView(),
                  ),
                ),
              )
            : SafeArea(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    18,
                    24,
                    24 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: child,
                ),
              ),
      ),
    );
  }

  Widget _buildEmailForm({required bool isLogin}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF222226),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // 로그인/가입 탭 전환
          Row(
            children: [
              _emailTabBtn('로그인', isLoginMode, () {
                setState(() => isLoginMode = true);
              }),
              _emailTabBtn('가입하기', !isLoginMode, () {
                setState(() => isLoginMode = false);
              }),
            ],
          ),
          const SizedBox(height: 14),
          _buildTextField(
            emailController,
            '이메일',
            Icons.email_outlined,
            false,
            focusNode: _emailFocusNode,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_passwordFocusNode),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            passwordController,
            '비밀번호',
            Icons.lock_outline,
            true,
            focusNode: _passwordFocusNode,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              isLoginMode = isLogin;
              _handleAuth();
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () {
                      isLoginMode = isLogin;
                      _handleAuth();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isLogin ? const Color(0xFF4A90D9) : const Color(0xFFD4AF37),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                isLogin ? '로그인' : '가입하기',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (isLogin) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _resetPassword,
              child: const Text(
                '비밀번호 찾기',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTermsInlineText() {
    const linkStyle = TextStyle(
      decoration: TextDecoration.underline,
      color: Color(0xFFAAAAAA),
      fontSize: 11.5,
      height: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            color: Color(0xFF8A8A94),
            fontSize: 11.5,
            height: 1.4,
          ),
          children: [
            const TextSpan(text: '가입하면 '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => launchURL(_termsUrl),
                child: const Text('이용약관', style: linkStyle),
              ),
            ),
            const TextSpan(text: ' 및 '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => launchURL(_privacyUrl),
                child: const Text('개인정보 처리방침', style: linkStyle),
              ),
            ),
            const TextSpan(text: '에 동의하는 것으로 간주합니다.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// 통합 소셜 인증: 약관 시트 없이 바로 소셜 로그인 -> 신규면 연령 확인
  Future<void> _handleUnifiedAuth(
    Future<dynamic> Function() authFn, {
    String provider = '',
  }) async {
    debugPrint('[Auth] _handleUnifiedAuth enter');
    final previousAuthProvider = FFAppState().lastAuthProvider;
    setState(() => isLoading = true);
    // Multi-step auth 동안 GoRouter 자동 네비게이션 억제
    // (anonymous -> custom token -> bonus 지급 완료까지 Lobby 이동 방지)
    AppStateNotifier.instance.updateNotifyOnAuthChange(false);
    try {
      await _cleanupTrialSandbox();
      await authFn();
      // trialCompleted trigger moved to routine_mode_anyone.dart (Anyone 1-min timer natural expiry)
      // see: fix/trial-completed-trigger-point branch
      if (provider.isNotEmpty) {
        FFAppState().lastAuthProvider = provider;
      }
      debugPrint(
          '[Auth] authFn complete, currentUser=${FirebaseAuth.instance.currentUser?.uid}');
      // 이전에 같은 provider로 로그인한 재방문자는 bonus 이미 지급됨 -> 스킵
      final isReturningUser =
          provider.isNotEmpty && previousAuthProvider == provider;
      if (!isReturningUser) {
        await _grantSignupBonusIfPossible();
      } else {
        debugPrint('[Auth] returning user - skip bonus check');
        // Firestore에서 최신 remainingTime 가져오기
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            final rt = doc.data()?['remainingTime'] as int?;
            if (rt != null) {
              FFAppState().remainingTime = rt;
              FFAppState().remainingTimeLoaded = true;
            }
          } catch (e) {
            debugPrint('[Auth] returning user time fetch failed: $e');
          }
        }
      }

      if (!mounted) return;
      await _checkAgeAndRoute();
    } catch (e, stack) {
      debugPrint('[Auth] _handleUnifiedAuth exception: $e');
      debugPrint('[Auth] stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인 실패: $e')),
        );
      }
    } finally {
      // GoRouter 알림 복원
      AppStateNotifier.instance.updateNotifyOnAuthChange(true);
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// 연령 확인 후 라우팅 (소셜/이메일 공통)
  Future<void> _checkAgeAndRoute() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final hasBirthYear =
          userDoc.exists && userDoc.data()?['birthYear'] != null;
      if (!hasBirthYear && mounted) {
        await _showBirthYearDialog();
      }
    } catch (e) {
      debugPrint('[Auth] birthYear check failed (non-blocking): $e');
    }

    if (mounted) _routeAfterAuth();
  }

  /// 신규 가입 시 태어난 해 확인 + 14세 미만 보호자 이메일 수집
  Future<void> _showBirthYearDialog() async {
    final currentYear = DateTime.now().year;
    int selectedYear = currentYear - 20;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161616),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF2A3A36), width: 1),
              ),
              title: const Text(
                '태어난 해를 알려주세요',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: SizedBox(
                height: 150,
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 42,
                  physics: const FixedExtentScrollPhysics(),
                  controller: FixedExtentScrollController(
                    initialItem: currentYear - 1940 - 20,
                  ),
                  onSelectedItemChanged: (index) {
                    setDialogState(() => selectedYear = 1940 + index);
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    builder: (context, index) {
                      final year = 1940 + index;
                      if (year < 1940 || year > currentYear - 4) {
                        return null;
                      }
                      return Center(
                        child: Text(
                          '$year년',
                          style: TextStyle(
                            color: year == selectedYear
                                ? Colors.white
                                : Colors.white38,
                            fontSize: year == selectedYear ? 20 : 16,
                            fontWeight: year == selectedYear
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                    childCount: currentYear - 4 - 1940 + 1,
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90D9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final age = currentYear - selectedYear;
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);

    if (age >= 14) {
      await userRef.set({'birthYear': selectedYear}, SetOptions(merge: true));
    } else {
      final parentEmail = await _showParentEmailDialog();
      if (parentEmail != null && parentEmail.isNotEmpty) {
        await userRef.set({
          'birthYear': selectedYear,
          'parentEmail': parentEmail,
          'parentConsentPending': true,
        }, SetOptions(merge: true));

        // 보호자에게 동의 요청 이메일 발송
        try {
          final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('sendParentConsentEmail');
          await callable.call({'parentEmail': parentEmail});
          debugPrint('[Auth] parent consent email sent to $parentEmail');
        } catch (e) {
          debugPrint('[Auth] parent consent email failed (non-blocking): $e');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '보호자에게 동의 요청을 보냈습니다.\n보호자가 동의하면 모든 기능을 이용할 수 있습니다.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Color(0xFF4A90D9),
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        await userRef.set({'birthYear': selectedYear}, SetOptions(merge: true));
      }
    }
  }

  /// 14세 미만: 보호자 이메일 입력 다이얼로그
  Future<String?> _showParentEmailDialog() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161616),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF2A3A36), width: 1),
          ),
          title: const Text(
            '보호자 동의가 필요합니다',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '만 14세 미만은 보호자 동의가 필요합니다.\n보호자의 이메일 주소를 입력해 주세요.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '보호자 이메일',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon:
                      const Icon(Icons.email_outlined, color: Colors.white38),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text(
                '나중에',
                style: TextStyle(color: Colors.white38),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                final email = controller.text.trim();
                Navigator.of(dialogContext).pop(email.isEmpty ? null : email);
              },
              child: const Text(
                '동의 요청 보내기',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  /// 샌드박스 폐기: 체험 중 생성된 임시 데이터를 삭제한다.
  /// anonymous 권한이 살아있는 상태에서 호출해야 한다 (UID 변경 전).
  Future<void> _cleanupTrialSandbox() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) return;

    TrialFlowState.instance.restoreFromAppState();
    final historyRef = TrialFlowState.instance.myHistoryRef;
    final hasTrialState = historyRef != null ||
        TrialFlowState.instance.isTrial ||
        FFAppState().trialCompleted ||
        FFAppState().trialStep > 0;
    if (!hasTrialState) return;

    if (historyRef != null) {
      try {
        final subDocs = await historyRef.collection('messages').get();
        for (final doc in subDocs.docs) {
          await doc.reference.delete();
        }
        await historyRef.delete();
        debugPrint('[TrialCleanup] deleted trial history: ${historyRef.path}');
      } catch (e) {
        // 삭제 실패해도 가입 진행은 막지 않음 (고아 문서는 추후 정리)
        debugPrint('[TrialCleanup] history delete failed (non-blocking): $e');
      }
    }

    // 체험 임시값만 초기화 (trialCompleted는 절대 false로 만들지 않음)
    TrialFlowState.instance.myHistoryRef = null;
    TrialFlowState.instance.step = 0;
    FFAppState().trialStep = 0;
    FFAppState().trialHistoryPath = '';

    // trialCompleted trigger moved to routine_mode_anyone.dart (Anyone 1-min timer natural expiry)
    // see: fix/trial-completed-trigger-point branch

    debugPrint('[TrialCleanup] sandbox cleanup complete');
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
      } else {
        debugPrint('[SignupBonus] remainingTime null, forcing lobby resync');
        FFAppState().remainingTimeLoaded = false;
        LobbyBrain.lastSyncedUid = null;
      }
      debugPrint(
          '[SignupBonus] grantSignupBonus complete, granted=$granted, remainingTime=$remainingTime');
    } catch (e, stack) {
      debugPrint('[SignupBonus] grantSignupBonus failed: $e');
      debugPrint('[SignupBonus] stack: $stack');
      // 보너스 확인 실패 -> Lobby 진입 시 Firestore 강제 재동기화
      FFAppState().remainingTimeLoaded = false;
      LobbyBrain.lastSyncedUid = null;
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
