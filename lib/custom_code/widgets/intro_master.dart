// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'trial/trial_flow_state.dart';
import 'auth_progress_view.dart';
import '/auth/social_auth_service.dart';
import '/auth/account_discovery_service.dart';

enum IntroScreen { welcome, auth, accountDiscovery }

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
  late final TapGestureRecognizer _termsTapRecognizer;
  late final TapGestureRecognizer _privacyTapRecognizer;

  bool isLoginMode = true;
  bool isLoading = false;
  IntroScreen _currentScreen = IntroScreen.welcome;
  int _welcomePage = 0;
  bool _welcomeForward = true;
  bool _showEmailForm = false;
  bool _trialStarting = false;
  int _trialRequestGeneration = 0;
  bool _isValidatingDuoInvite = false;
  String _trialNativeLang = 'Korean';
  String _trialTargetLang = 'English';

  // =======================================================
  // [Account Discovery] Existing-account lookup state
  // =======================================================
  final List<AccountDiscoveryResult> _accountDiscoveryResults = [];
  String _accountDiscoveryMessage = '';
  String _accountDiscoveryBusyProvider = '';

  bool get _requiresAuthOnlyIntro =>
      FFAppState().trialCompleted || FFAppState().isGuestSession;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[TrialDebug] IntroMaster initState, time=${DateTime.now().toIso8601String()}');
    _termsTapRecognizer = TapGestureRecognizer()
      ..onTap = () => launchURL(_termsUrl);
    _privacyTapRecognizer = TapGestureRecognizer()
      ..onTap = () => launchURL(_privacyUrl);
    _emailFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
    _clearInvalidLastAuthProvider();
    AppsFlyerManager.duoInviteSignal.addListener(_onDuoInviteSignal);
    if (_requiresAuthOnlyIntro) {
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

  void _onDuoInviteSignal() async {
    if (!mounted || _isValidatingDuoInvite) return;
    if (FFAppState().pendingInviteType != 'duo' ||
        FFAppState().duoRoomId.isEmpty) {
      return;
    }

    final roomId = FFAppState().duoRoomId;
    _isValidatingDuoInvite = true;
    try {
      final isValid = await AppsFlyerManager.validatePendingDuoInvite();
      if (!mounted ||
          !isValid ||
          FFAppState().pendingInviteType != 'duo' ||
          FFAppState().duoRoomId != roomId) {
        return;
      }
      debugPrint('[Intro] validated duoInviteSignal - routing to StealthRoom');
      context.pushReplacementNamed('StealthRoom');
    } finally {
      _isValidatingDuoInvite = false;
    }
  }

  // 키보드가 올라올 때 포커스된 입력창이 보이도록 자동 스크롤
  // (항상 맨 아래로 스크롤하면 비밀번호 칸이 화면 밖으로 밀려나 다시 끌어내려야 했음 →
  //  포커스된 필드 자체를 기준으로 스크롤)
  void _onFocusChange() {
    final FocusNode? focused = _emailFocusNode.hasFocus
        ? _emailFocusNode
        : (_passwordFocusNode.hasFocus ? _passwordFocusNode : null);
    if (focused == null) return;
    Future.delayed(const Duration(milliseconds: 350), () {
      final fieldContext = focused.context;
      if (mounted && fieldContext != null) {
        Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    });
  }

  @override
  void dispose() {
    ++_trialRequestGeneration;
    AppsFlyerManager.duoInviteSignal.removeListener(_onDuoInviteSignal);
    _scrollController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _termsTapRecognizer.dispose();
    _privacyTapRecognizer.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkEntryStatus() async {
    debugPrint(
        '[TrialDebug] _checkEntryStatus enter, currentUser=${FirebaseAuth.instance.currentUser?.uid}, isAnonymous=${FirebaseAuth.instance.currentUser?.isAnonymous}, time=${DateTime.now().toIso8601String()}');
    // 1순위: Play 설치 referrer의 최신 초대를 먼저 복구한다.
    // Android 자동 백업이 과거 FFAppState 초대를 되살리는 경우보다 우선해야 한다.
    await AppsFlyerManager.recoverPlayInstallInvite();
    if (!mounted) return;

    // 저장된 초대는 서버에 활성 방이 있을 때만 사용한다.
    debugPrint(
        '[Intro] pendingInviteType=${FFAppState().pendingInviteType}, duoRoomId=${FFAppState().duoRoomId}');
    if (FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty) {
      final isValid = await AppsFlyerManager.validatePendingDuoInvite();
      if (!mounted) return;
      if (isValid) {
        debugPrint('[Intro] routing to StealthRoom for Duo invite');
        context.pushReplacementNamed('StealthRoom');
        return;
      }
    }
    // 완료된 Duo 초대 게스트는 회원 계정이 살아 있어도 자동 Lobby 이동 없이
    // Intro에 머문다. 사용자가 체험 또는 로그인을 선택하면 플래그를 해제한다.
    if (FFAppState().isGuestSession) {
      debugPrint('[Intro] completed Duo guest session stays on Intro');
      await _initAppsFlyer();
      return;
    }
    // 2순위: AppsFlyer 초기화 (로그인 여부와 무관하게 딥링크 콜백 등록)
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
      // 초대 상태는 여기서 지우지 않음 — StealthRoom initState가 이 값을 보고
      // Duo 자동 진입을 판단한다. 삭제는 _joinAsGuest 성공 후에만.
      context.pushReplacementNamed('StealthRoom');
    } else {
      FFAppState().isGuestSession = false;
      context.goNamed('Lobby');
    }
  }

  Future<void> _initAppsFlyer() async {
    await AppsFlyerManager.initialize(
      devKey: 'SQUmDTB2VzuPjrJGiy5SSC',
      appId: 'com.aienglishpractice.stealthvox',
    );
  }

  Future<void> _startTrial() async {
    debugPrint(
        '[TrialDebug] _startTrial enter, currentUser=${FirebaseAuth.instance.currentUser?.uid}, isAnonymous=${FirebaseAuth.instance.currentUser?.isAnonymous}, time=${DateTime.now().toIso8601String()}');
    if (_trialStarting) return;
    _trialStarting = true;
    final requestGeneration = ++_trialRequestGeneration;
    var authNotificationSuppressed = false;
    try {
      FFAppState().isGuestSession = false;
      TrialFlowState.instance.restoreFromAppState();

      final existingUser = FirebaseAuth.instance.currentUser;
      if (existingUser != null && existingUser.isAnonymous != true) {
        // 정식 회원은 체험 불가 -> signOut 하지 않고 Lobby로 이동
        debugPrint(
            '[Trial] existing member tried trial, redirecting to Lobby: ${existingUser.uid}');
        if (mounted) context.goNamed('Lobby');
        return;
      }

      // 언어 선택은 익명 로그인보다 먼저 띄운다. 첫 익명 로그인에서 인증 상태가
      // 바뀌며 Intro가 재구성되더라도 첫 탭의 사용자 흐름이 끊기지 않게 한다.
      final languageConfirmed = await _showLanguageSettingDialog();
      if (!languageConfirmed ||
          !_isCurrentTrialRequest(requestGeneration)) {
        return;
      }
      debugPrint(
          '[TrialDebug] language dialog confirmed, native=$_trialNativeLang, target=$_trialTargetLang');
      setState(() => isLoading = true);

      // 정책 A: 체험 확정 -> pending invite 초기화 (체험과 Duo는 분리)
      FFAppState().pendingInviteType = '';
      FFAppState().duoRoomId = '';

      if (FirebaseAuth.instance.currentUser == null) {
        AppStateNotifier.instance.updateNotifyOnAuthChange(false);
        authNotificationSuppressed = true;
        await FirebaseAuth.instance.signInAnonymously();
      }
      if (!_isCurrentTrialRequest(requestGeneration)) return;
      debugPrint(
          '[TrialDebug] anonymous auth ready, uid=${FirebaseAuth.instance.currentUser?.uid}, stateMounted=$mounted');
      FFAppState().nativeLang = _trialNativeLang;
      FFAppState().targetLang = _trialTargetLang;

      await _enterTrialAnyone(requestGeneration);
    } catch (e) {
      final errorContext = mounted ? context : appNavigatorKey.currentContext;
      if (errorContext != null && errorContext.mounted) {
        ScaffoldMessenger.of(errorContext).showSnackBar(
          SnackBar(content: Text('체험을 시작할 수 없습니다: $e')),
        );
      }
    } finally {
      if (authNotificationSuppressed) {
        AppStateNotifier.instance.updateNotifyOnAuthChange(true);
      }
      _trialStarting = false;
      if (mounted) setState(() => isLoading = false);
    }
  }

  bool _isCurrentTrialRequest(int requestGeneration) {
    return mounted &&
        requestGeneration == _trialRequestGeneration &&
        (ModalRoute.of(context)?.isCurrent ?? false);
  }

  Future<void> _enterTrialAnyone(int requestGeneration) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !_isCurrentTrialRequest(requestGeneration)) return;
    final historyRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chat_history')
        .doc();
    await historyRef.set({
      'created_at': FieldValue.serverTimestamp(),
      'is_pinned': false,
      // 세션 생성 당시 언어 식별값 보존(History 동일 언어 판정용)
      'native_lang': FFAppState().nativeLang,
      'target_lang': FFAppState().targetLang,
    });
    TrialFlowState.instance.myHistoryRef = historyRef;
    TrialFlowState.instance.advanceTo(1);
    if (!mounted ||
        requestGeneration != _trialRequestGeneration ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
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
      case IntroScreen.accountDiscovery:
        return _buildAccountDiscoveryView(context);
    }
  }

  void _openAuthScreen() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {
      _currentScreen = IntroScreen.auth;
      _showEmailForm = false;
    });
  }

  void _goBackToStory() {
    if (_welcomePage == 0) return;
    setState(() {
      _welcomeForward = false;
      _welcomePage = 0;
    });
  }

  /// 좌우로 밀어서 웰컴 페이지 사이만 이동한다. 왼쪽으로 밀면 다음, 오른쪽으로 밀면 이전.
  /// 인증 화면으로는 제스처로 넘어가지 않는다 — 잘못 밀거나 눌러서 넘어가는 사고를 막기 위해
  /// 인증 진입은 버튼으로만 열어 둔다.
  void _onWelcomeHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 120) return;
    if (velocity < 0) {
      _goToGuidePage();
    } else {
      _goBackToStory();
    }
  }

  Widget _buildBrandMark({bool compact = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 30 : 36,
          height: compact ? 30 : 36,
          decoration: BoxDecoration(
            color: const Color(0xFF58D6BD).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
            border: Border.all(
              color: const Color(0xFF58D6BD).withValues(alpha: 0.22),
            ),
          ),
          child: Icon(
            Icons.record_voice_over_rounded,
            size: compact ? 17 : 20,
            color: const Color(0xFF58D6BD),
          ),
        ),
        SizedBox(width: compact ? 9 : 11),
        Text(
          'StealthVox',
          style: GoogleFonts.orbitron(
            fontSize: compact ? 15 : 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF7F8FA),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildDuoPromoBadge() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showDuoPromo,
        borderRadius: BorderRadius.circular(99),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(7, 6, 11, 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF2D2760),
                Color(0xFF173F66),
              ],
            ),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: const Color(0xFF7B71F4).withValues(alpha: 0.58),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6A60E8).withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFE96479),
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'AD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 6),
              Icon(
                Icons.photo_camera_rounded,
                size: 13,
                color: Color(0xFF9EDFF5),
              ),
              SizedBox(width: 4),
              Text(
                'Duo 한 컷',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDuoPromo() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Duo 한 컷 닫기',
      barrierColor: Colors.black.withValues(alpha: 0.88),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return const Material(
          color: Colors.transparent,
          child: SafeArea(child: _DuoPromoViewer()),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildPageIndicator(
    int activeIndex, {
    bool tealActive = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(2, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: active ? 22 : 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active
                ? (tealActive
                    ? const Color(0xFF52D4C3)
                    : const Color(0xFF7B71F4))
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(99),
            boxShadow: active && tealActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF52D4C3).withValues(alpha: 0.26),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }

  Widget _buildWelcomeTrialAction() {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF45CDBD),
            Color(0xFF5C9DDB),
            Color(0xFF765EEB),
          ],
          stops: [0.0, 0.52, 1.0],
        ),
        borderRadius: BorderRadius.circular(19),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF53CBBB).withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(-8, 10),
          ),
          BoxShadow(
            color: const Color(0xFF755FE9).withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(8, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: _goToGuidePage,
          borderRadius: BorderRadius.circular(19),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '1분 체험 알아보기',
                style: TextStyle(
                  color: Color(0xFFF9FAFC),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                ),
              ),
              SizedBox(width: 17),
              Icon(
                Icons.arrow_forward_rounded,
                size: 25,
                color: Color(0xFFF9FAFC),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeLoginAction() {
    return TextButton(
      onPressed: _openAuthScreen,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: const Color(0xFFB7BAC3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '이미 계정이 있어요',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.15,
            ),
          ),
          const SizedBox(height: 7),
          Container(
            width: 58,
            height: 1.5,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF43CCBD), Color(0xFF7661EA)],
              ),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction({
    required String label,
    required VoidCallback? onPressed,
    IconData icon = Icons.arrow_forward_rounded,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: const Color(0xFF756BE8),
          foregroundColor: const Color(0xFFF9F9FB),
          disabledBackgroundColor:
              const Color(0xFF756BE8).withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text(label)),
            const SizedBox(width: 8),
            Icon(icon, size: 19),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryAction({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFD9DAE1),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.13),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep({
    required int number,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF756BE8).withValues(alpha: 0.17),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Color(0xFFC7C2FF),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFF5F6F8),
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFFAAADB7),
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
            Color(0xFF0C0D12),
            Color(0xFF050608),
            Color(0xFF030405),
          ],
          stops: [0.0, 0.52, 1.0],
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
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: _onWelcomeHorizontalDragEnd,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(_welcomeForward ? 0.16 : -0.16, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _welcomePage == 0
                          ? _buildWelcomeStoryPage()
                          : _buildWelcomeGuidePage(),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  void _goToGuidePage() {
    if (_welcomePage == 1) return;
    setState(() {
      _welcomeForward = true;
      _welcomePage = 1;
    });
  }

  /// 페이지마다 스와이프로 갈 수 있는 방향이 달라서 안내 문구를 받아 쓴다.
  Widget _buildWelcomePageFooter(String hint) {
    return Center(
      child: Text(
        hint,
        style: const TextStyle(
          color: Color(0xFF777780),
          fontSize: 11.5,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildWelcomeStoryPage() {
    return LayoutBuilder(
      key: const ValueKey('welcome-story'),
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 660;
        final headlineSize = constraints.maxWidth < 340 ? 33.0 : 36.0;
        final storyGradient = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF48CEBD),
            Color(0xFF4FAFCE),
            Color(0xFF7763E9),
          ],
        ).createShader(const Rect.fromLTWH(82, 0, 132, 52));

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            compact ? 20 : 33,
            24,
            compact ? 14 : 18,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - (compact ? 30 : 38),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildBrandMark(),
                      _buildDuoPromoBadge(),
                    ],
                  ),
                  SizedBox(height: compact ? 56 : 78),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF43CCBD).withValues(alpha: 0.035),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: const Color(0xFF4BCDBD).withValues(alpha: 0.54),
                      ),
                    ),
                    child: const Text(
                      '말한 순간, 바로 복습으로',
                      style: TextStyle(
                        color: Color(0xFF62D8C9),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 26 : 35),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '당신의 '),
                        TextSpan(
                          text: '이야기',
                          style: TextStyle(
                            foreground: Paint()..shader = storyGradient,
                          ),
                        ),
                        const TextSpan(
                          text: '가\n최고의 영어 교재가\n됩니다',
                        ),
                      ],
                    ),
                    style: TextStyle(
                      color: const Color(0xFFF7F8FA),
                      fontSize: headlineSize,
                      fontWeight: FontWeight.w800,
                      height: 1.16,
                      letterSpacing: -1.4,
                    ),
                  ),
                  SizedBox(height: compact ? 16 : 20),
                  SizedBox(
                    width: double.infinity,
                    height: compact ? 58 : 72,
                    child: Center(child: _buildWaveform()),
                  ),
                  const Spacer(),
                  SizedBox(height: compact ? 22 : 34),
                  _buildWelcomeTrialAction(),
                  SizedBox(height: compact ? 8 : 14),
                  _buildWelcomeLoginAction(),
                  SizedBox(height: compact ? 8 : 13),
                  Center(child: _buildPageIndicator(0, tealActive: true)),
                  SizedBox(height: compact ? 10 : 17),
                  _buildWelcomePageFooter('옆으로 밀어 계속하기'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeGuidePage() {
    return LayoutBuilder(
      key: const ValueKey('welcome-guide'),
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            compact ? 14 : 20,
            24,
            compact ? 16 : 22,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - (compact ? 30 : 42),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _goBackToStory,
                        tooltip: '이전',
                        style: IconButton.styleFrom(
                          foregroundColor: const Color(0xFFE6E7EA),
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.045),
                          minimumSize: const Size(44, 44),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 21),
                      ),
                      const Spacer(),
                      _buildPageIndicator(1),
                      const Spacer(),
                      TextButton(
                        onPressed: _openAuthScreen,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          foregroundColor: const Color(0xFFBFC1C9),
                        ),
                        child: const Text(
                          '로그인',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 24 : 36),
                  const Text(
                    '회원가입 없이\n바로 체험해 보세요',
                    style: TextStyle(
                      color: Color(0xFFF7F8FA),
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.9,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '1분 동안 편하게 말하면,\n방금 대화가 영어 복습으로 이어집니다.',
                    style: TextStyle(
                      color: Color(0xFFA7ABB5),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: compact ? 22 : 30),
                  _buildTrialGuideCard(
                    onTrialPressed: () {
                      debugPrint(
                        '[TrialDebug] trial button tapped, time=${DateTime.now().toIso8601String()}',
                      );
                      _startTrial();
                    },
                  ),
                  SizedBox(height: compact ? 16 : 20),
                  _buildUsageGuideSection(),
                  const Spacer(),
                  SizedBox(height: compact ? 18 : 28),
                  _buildSecondaryAction(
                    label: '로그인해서 시작하기',
                    icon: Icons.login_rounded,
                    onPressed: _openAuthScreen,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '체험 시작 시 마이크 권한을 요청합니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF737680),
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildWelcomePageFooter('옆으로 밀면 이전 화면으로'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Anyone 이용 방법 안내. 팝업이 아니라 가이드 페이지에 그대로 얹는다.
  Widget _buildUsageGuideSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF17191F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.lightbulb_rounded,
                  color: Color(0xFFFFC857),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Anyone 이용 방법',
                  style: TextStyle(
                    color: Color(0xFFF7F8FA),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildGuideStep(
            number: 1,
            title: '대화할 사람을 떠올리세요',
            description: '그 사람이 앞에 있다고 생각하고, 하고 싶었던 말을 편하게 꺼내세요.',
          ),
          const SizedBox(height: 16),
          _buildGuideStep(
            number: 2,
            title: '평소처럼 자연스럽게 말하세요',
            description: 'AI가 그 사람이 되어 대답합니다. 반응이 다르면 이유를 다시 물어보세요.',
          ),
          const SizedBox(height: 16),
          _buildGuideStep(
            number: 3,
            title: '대화가 끝나면 영어로 복습하세요',
            description: '방금 나눈 이야기가 영어 표현과 복습 자료로 자동 정리됩니다.',
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFF756BE8).withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF756BE8).withValues(alpha: 0.15),
              ),
            ),
            child: const Text(
              '예: “왜 그렇게 느껴?”처럼 이유를 다시 물어보세요.',
              style: TextStyle(
                color: Color(0xFFC9C6EA),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showLanguageSettingDialog() async {
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

    final confirmed = await showDialog<bool>(
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
                      if (mounted) {
                        setState(() {
                          _trialNativeLang = nativeLang;
                          _trialTargetLang = targetLang;
                        });
                      }
                      Navigator.of(dialogContext).pop(true);
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
    return confirmed == true;
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
          Row(
            children: [
              if (!_requiresAuthOnlyIntro)
                IconButton(
                  onPressed: () => setState(() {
                    _currentScreen = IntroScreen.welcome;
                    _showEmailForm = false;
                  }),
                  tooltip: '뒤로',
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFE6E7EA),
                    backgroundColor: Colors.white.withValues(alpha: 0.045),
                    minimumSize: const Size(44, 44),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 21),
                )
              else
                const SizedBox(width: 44, height: 44),
              const Spacer(),
              _buildBrandMark(compact: true),
              const Spacer(),
              const SizedBox(width: 44, height: 44),
            ],
          ),
          const SizedBox(height: 38),
          ..._buildAuthHeader(),
          const SizedBox(height: 26),
          ..._buildProviderButtons(),
          if (_showEmailForm) ...[
            const SizedBox(height: 16),
            _buildEmailForm(isLogin: isLoginMode),
          ],
          const SizedBox(height: 22),
          _buildAccountDiscoveryEntrySection(),
          const SizedBox(height: 26),
          _buildTermsInlineText(),
        ],
      ),
    );
  }

  Widget _buildAccountDiscoveryEntrySection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: TextButton.icon(
        onPressed: isLoading
            ? null
            : () => setState(() {
                  _currentScreen = IntroScreen.accountDiscovery;
                  _showEmailForm = false;
                  _accountDiscoveryMessage = '';
                }),
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: const Color(0xFFBFD8FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        icon: const Icon(Icons.manage_search_rounded, size: 20),
        label: const Text(
          '로그인 방법이 기억나지 않나요?  계정 찾기',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildAccountDiscoveryView(BuildContext context) {
    final foundResults =
        _accountDiscoveryResults.where((r) => r.found).toList();
    return _buildAuthScaffold(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _accountDiscoveryBusyProvider.isNotEmpty
                  ? null
                  : () => setState(() => _currentScreen = IntroScreen.auth),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: '뒤로',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '내 계정 찾아보기',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '이전에 사용했던 로그인 방법을 하나씩 확인해 보세요. 계정은 자동으로 합쳐지지 않으며, 남은 시간과 학습 기록은 별도로 유지됩니다.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Color(0xFFB7B7C2), fontSize: 13, height: 1.55),
          ),
          const SizedBox(height: 28),
          _buildDiscoveryActionButton(
            provider: 'google',
            label: 'Google 계정 확인',
            icon: Image.asset(
              'assets/images/google_logo.png',
              width: 20,
              height: 20,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.g_mobiledata, size: 24),
            ),
            onTap: () =>
                _lookupAccount('google', AccountDiscoveryService.lookupGoogle),
          ),
          const SizedBox(height: 12),
          _buildDiscoveryActionButton(
            provider: 'kakao',
            label: '카카오 계정 확인',
            backgroundColor: const Color(0xFFFEE500),
            foregroundColor: const Color(0xFF191919),
            icon: Image.asset(
              'assets/images/kakao_logo.png',
              width: 20,
              height: 20,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.chat_bubble, size: 20),
            ),
            onTap: () =>
                _lookupAccount('kakao', AccountDiscoveryService.lookupKakao),
          ),
          const SizedBox(height: 12),
          _buildDiscoveryActionButton(
            provider: 'email',
            label: '이메일 계정 확인',
            icon: const Icon(Icons.email_outlined, size: 20),
            onTap: _showEmailDiscoveryGuide,
          ),
          if (_accountDiscoveryMessage.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              _accountDiscoveryMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFD7D7DE), fontSize: 13, height: 1.45),
            ),
          ],
          if (foundResults.isNotEmpty) ...[
            const SizedBox(height: 28),
            if (foundResults.length > 1) ...[
              const Text(
                '두 개 이상의 기존 계정을 찾았습니다. 각 계정의 남은 시간과 학습 기록은 서로 합쳐지지 않습니다. 사용할 계정을 직접 선택해 주세요.',
                style: TextStyle(
                    color: Color(0xFFB7B7C2), fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 12),
            ],
            ...foundResults.map(_buildDiscoveredAccountCard),
          ],
          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: _accountDiscoveryBusyProvider.isNotEmpty
                ? null
                : _confirmNewAccountFromDiscovery,
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('새 계정 만들기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _accountDiscoveryBusyProvider.isNotEmpty
                ? null
                : () => launchURL('mailto:support@stealthvox.app'),
            icon: const Icon(Icons.support_agent, size: 18),
            label: const Text('고객지원 문의'),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFB9D7FF)),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryActionButton({
    required String provider,
    required String label,
    required Widget icon,
    required VoidCallback onTap,
    Color backgroundColor = const Color(0xFF33333A),
    Color foregroundColor = Colors.white,
  }) {
    final busy = _accountDiscoveryBusyProvider == provider;
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _accountDiscoveryBusyProvider.isNotEmpty ? null : onTap,
        icon: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: foregroundColor),
              )
            : icon,
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.55),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.65),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildDiscoveredAccountCard(AccountDiscoveryResult account) {
    final minutes = (account.remainingTime / 60).floor();
    final lastUsed = account.lastUsedAt == null
        ? '확인 불가'
        : '${account.lastUsedAt!.year}.${account.lastUsedAt!.month.toString().padLeft(2, '0')}.${account.lastUsedAt!.day.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F242A),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFF4A90D9).withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            account.providerLabel,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            account.maskedIdentifier.isEmpty
                ? '인증된 계정'
                : account.maskedIdentifier,
            style: const TextStyle(color: Color(0xFFD7D7DE), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            '남은 시간: $minutes분\n학습 기록: ${account.historyCount}개\n마지막 사용: $lastUsed',
            style: const TextStyle(
                color: Color(0xFFB7B7C2), fontSize: 13, height: 1.55),
          ),
          if (account.parentConsentPending) ...[
            const SizedBox(height: 8),
            const Text(
              '보호자 동의 대기 중',
              style: TextStyle(
                  color: Color(0xFFFFD166),
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () => _continueWithDiscoveredAccount(account),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                '이 계정으로 계속하기',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _lookupAccount(
    String provider,
    Future<AccountDiscoveryResult> Function() lookup,
  ) async {
    setState(() {
      _accountDiscoveryBusyProvider = provider;
      _accountDiscoveryMessage = '';
    });
    try {
      final result = await lookup();
      if (!mounted) return;
      setState(() {
        _accountDiscoveryResults.removeWhere((item) =>
            item.provider == result.provider &&
            item.maskedIdentifier == result.maskedIdentifier);
        if (result.found) {
          _accountDiscoveryResults.add(result);
          _accountDiscoveryMessage =
              '기존 StealthVox 기록을 찾았습니다. 사용할 계정을 직접 선택해 주세요.';
        } else {
          _accountDiscoveryMessage =
              '이 계정에서는 기존 StealthVox 기록을 찾지 못했습니다. 다른 계정이나 다른 로그인 방법을 확인해 보세요.';
        }
      });
    } on AccountDiscoveryCancelledException {
      if (!mounted) return;
      setState(() => _accountDiscoveryMessage = '계정 확인이 취소되었습니다.');
    } catch (e) {
      debugPrint('[AccountDiscovery] lookup failed: $e');
      if (!mounted) return;
      setState(() {
        _accountDiscoveryMessage =
            '계정 정보를 확인하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.';
      });
    } finally {
      if (mounted) setState(() => _accountDiscoveryBusyProvider = '');
    }
  }

  Future<void> _continueWithDiscoveredAccount(
      AccountDiscoveryResult account) async {
    setState(() => isLoading = true);
    AppStateNotifier.instance.updateNotifyOnAuthChange(false);
    try {
      await _cleanupTrialSandbox();
      await AccountDiscoveryService.signInWithDiscoveredAccount(account);
      FFAppState().hasLinkedAccount = true;
      FFAppState().lastAuthProvider = account.provider;
      FFAppState().remainingTime = account.remainingTime;
      FFAppState().remainingTimeLoaded = true;
      LobbyBrain.lastSyncedUid = null;
      if (!mounted) return;
      await _checkAgeAndRoute();
    } catch (e, stack) {
      debugPrint('[AccountDiscovery] final login failed: $e');
      debugPrint('[AccountDiscovery] stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('계정으로 계속할 수 없습니다: $e')),
        );
      }
    } finally {
      AppStateNotifier.instance.updateNotifyOnAuthChange(true);
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showEmailDiscoveryGuide() {
    setState(() {
      _accountDiscoveryMessage = '';
      _currentScreen = IntroScreen.auth;
      _showEmailForm = true;
      isLoginMode = true;
    });
  }

  Future<void> _confirmNewAccountFromDiscovery() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: const Text('새 계정을 만들까요?', style: TextStyle(color: Colors.white)),
        content: const Text(
          '새 계정을 만들면 이전 계정의 남은 시간과 학습 기록은 자동으로 옮겨지지 않습니다. 현재 선택한 로그인 방법으로 새로 가입하시겠습니까?',
          style: TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('이전 계정 다시 찾기'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('이 계정으로 새로 가입'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _currentScreen = IntroScreen.auth;
        _accountDiscoveryMessage = '';
      });
    }
  }

  String? _validLastAuthProvider() {
    final provider = FFAppState().lastAuthProvider;
    return switch (provider) {
      'kakao' || 'google' || 'email' => provider,
      _ => null,
    };
  }

  void _clearInvalidLastAuthProvider() {
    final provider = FFAppState().lastAuthProvider;
    if (provider.isNotEmpty && _validLastAuthProvider() == null) {
      FFAppState().lastAuthProvider = '';
    }
  }

  String _providerDescription(String provider) {
    return switch (provider) {
      'kakao' => '이전에 카카오 계정으로 가입했습니다.',
      'google' => '이전에 Google 계정으로 가입했습니다.',
      'email' => '이전에 이메일 계정으로 가입했습니다.',
      _ => '사용할 로그인 방법을 선택해 주세요.',
    };
  }

  Widget _authSectionTitle({
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFF7F8FA),
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.2,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: const TextStyle(
            color: Color(0xFFA7ABB5),
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _providerButton(String provider) {
    final isRecent =
        !_requiresAuthOnlyIntro && _validLastAuthProvider() == provider;

    late final String label;
    late final Color backgroundColor;
    late final Color foregroundColor;
    late final Widget icon;
    BoxBorder? border;
    VoidCallback? onTap;

    switch (provider) {
      case 'kakao':
        label = '카카오톡으로 계속하기';
        backgroundColor = const Color(0xFFFEE500);
        foregroundColor = const Color(0xFF191919);
        icon = Image.asset(
          'assets/images/kakao_logo.png',
          width: 20,
          height: 20,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.chat_bubble_rounded,
            size: 20,
            color: Color(0xFF191919),
          ),
        );
        onTap = () => _handleUnifiedAuth(
              SocialAuthService.signInWithKakao,
              provider: 'kakao',
            );
        break;
      case 'google':
        label = 'Google로 계속하기';
        backgroundColor = const Color(0xFFF7F7F8);
        foregroundColor = const Color(0xFF17181B);
        border = Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        );
        icon = Image.asset(
          'assets/images/google_logo.png',
          width: 20,
          height: 20,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.g_mobiledata_rounded,
            size: 25,
            color: Colors.blue,
          ),
        );
        onTap = () => _handleUnifiedAuth(
              SocialAuthService.signInWithGoogle,
              provider: 'google',
            );
        break;
      case 'email':
        label = _showEmailForm ? '이메일 입력 닫기' : '이메일로 계속하기';
        backgroundColor = const Color(0xFF24262D);
        foregroundColor = const Color(0xFFF2F3F6);
        border = Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        );
        icon = const Icon(
          Icons.email_outlined,
          size: 20,
          color: Color(0xFFC4C6CE),
        );
        onTap = () => setState(() => _showEmailForm = !_showEmailForm);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            height: 56,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: isRecent && provider != 'kakao'
                  ? Border.all(
                      color: const Color(0xFF8B82F5),
                      width: 1.3,
                    )
                  : border,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(left: 20, child: icon),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 56),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.25,
                    ),
                  ),
                ),
                if (isRecent)
                  Positioned(
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: provider == 'kakao'
                            ? Colors.black.withValues(alpha: 0.08)
                            : const Color(0xFF756BE8).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '최근',
                        style: TextStyle(
                          color: provider == 'kakao'
                              ? const Color(0xFF3B3B36)
                              : const Color(0xFFB9B4FF),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
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

  List<Widget> _spacedProviderButtons(List<String> providers) {
    final widgets = <Widget>[];
    for (final provider in providers) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 12));
      widgets.add(_providerButton(provider));
    }
    return widgets;
  }

  List<Widget> _buildAuthHeader() {
    // 1분 체험을 마친 사용자는 재방문 계정 기록과 관계없이
    // 세 가지 가입/로그인 방법을 모두 선택할 수 있어야 한다.
    final lastProvider =
        _requiresAuthOnlyIntro ? null : _validLastAuthProvider();
    if (lastProvider == null) {
      return [
        _authSectionTitle(
          title: '새로 방문하신 분',
          description: '사용할 로그인 방법을 선택해 주세요.',
        ),
      ];
    }

    return [
      _authSectionTitle(
        title: '계정으로 계속하기',
        description: _providerDescription(lastProvider),
      ),
    ];
  }

  List<Widget> _buildProviderButtons() {
    final lastProvider =
        _requiresAuthOnlyIntro ? null : _validLastAuthProvider();
    if (lastProvider != null) {
      return [_providerButton(lastProvider)];
    }

    return _spacedProviderButtons(['kakao', 'google', 'email']);
  }

  Widget _buildAuthScaffold({
    required BuildContext context,
    required Widget child,
  }) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0C0D12),
            Color(0xFF050608),
            Color(0xFF030405),
          ],
        ),
      ),
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
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      18,
                      24,
                      26 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: child,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEmailForm({required bool isLogin}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF15171D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.075),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _emailTabBtn('로그인', isLoginMode, () {
                  setState(() => isLoginMode = true);
                }),
                _emailTabBtn('가입하기', !isLoginMode, () {
                  setState(() => isLoginMode = false);
                }),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildTextField(
            emailController,
            '이메일 주소',
            Icons.email_outlined,
            false,
            focusNode: _emailFocusNode,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_passwordFocusNode),
          ),
          const SizedBox(height: 11),
          _buildTextField(
            passwordController,
            '비밀번호',
            Icons.lock_outline_rounded,
            true,
            focusNode: _passwordFocusNode,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleAuth(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: isLoading ? null : _handleAuth,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF756BE8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(isLoginMode ? '이메일로 로그인' : '이메일로 가입하기'),
            ),
          ),
          if (isLoginMode) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _resetPassword,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9FA2AC),
                minimumSize: const Size.fromHeight(42),
              ),
              child: const Text(
                '비밀번호를 잊으셨나요?',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTermsInlineText() {
    const baseStyle = TextStyle(
      color: Color(0xFF8A8A94),
      fontSize: 11.5,
      height: 1.4,
    );
    final linkStyle = baseStyle.copyWith(
      decoration: TextDecoration.underline,
      color: const Color(0xFFAAAAAA),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: '가입하면 '),
            TextSpan(
              text: '이용약관',
              style: linkStyle,
              recognizer: _termsTapRecognizer,
            ),
            const TextSpan(text: ' 및 '),
            TextSpan(
              text: '개인정보 처리방침',
              style: linkStyle,
              recognizer: _privacyTapRecognizer,
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
      // provider가 달라도 같은 계정이면 재방문자.
      // signup_bonus_given 서버 플래그로 판정 (grantSignupBonus CF의 idempotency 보장).
      final currentUser = FirebaseAuth.instance.currentUser;
      bool isReturningUser = false;
      if (currentUser != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
          isReturningUser =
              userDoc.exists && userDoc.data()?['signup_bonus_given'] == true;
        } catch (e) {
          debugPrint('[Auth] returning user check failed: $e');
        }
      }
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
        // provider 전환 시 UID가 이전 세션과 같더라도 lobby 재동기화 강제
        LobbyBrain.lastSyncedUid = null;
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
        final ageCheckCompleted = await _showBirthYearDialog();
        if (!ageCheckCompleted) {
          await _showAgeCheckRequiredDialog();
          await FirebaseAuth.instance.signOut();
          FFAppState().remainingTime = 0;
          FFAppState().remainingTimeLoaded = false;
          LobbyBrain.lastSyncedUid = null;
          if (mounted) {
            setState(() => isLoginMode = true);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('[Auth] birthYear check failed (non-blocking): $e');
    }

    if (mounted) _routeAfterAuth();
  }

  /// 신규 가입 시 태어난 해 확인 + 14세 미만 보호자 이메일 수집
  Future<bool> _showBirthYearDialog() async {
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
                height: 225,
                child: Column(
                  children: [
                    const Text(
                      '미성년자 확인을 위한 필수 절차입니다.\n미성년자는 부모님 동의 후 가입할 수 있습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
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
                  ],
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

    if (confirmed != true || !mounted) return false;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final age = currentYear - selectedYear;
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);

    if (age >= 14) {
      await userRef.set({'birthYear': selectedYear}, SetOptions(merge: true));
      return true;
    } else {
      final parentEmail = await _showParentEmailDialog();
      if (parentEmail != null && parentEmail.isNotEmpty) {
        await userRef.set({
          'birthYear': selectedYear,
          'parentEmail': parentEmail,
          'parentConsentPending': true,
        }, SetOptions(merge: true));

        // 보호자 동의 이메일은 users/{uid} 변경을 감지하는 Cloud Function에서 발송한다.

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
        return true;
      } else {
        return false;
      }
    }
  }

  Future<void> _showAgeCheckRequiredDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF2A3A36), width: 1),
        ),
        title: const Text(
          '연령 확인이 필요합니다',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: const Text(
          '탄생년 선택은 미성년자 확인을 위한 필수 절차입니다.\n\n미성년자는 부모님 동의 후 가입할 수 있습니다.\n로그인 페이지로 돌아갑니다.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
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
              onPressed: () => Navigator.of(dialogContext).pop(),
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
      ),
    );
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2A2D36) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? const Color(0xFFF3F4F6) : const Color(0xFF7E818B),
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaveform() {
    final heights = [
      5.0,
      4.0,
      8.0,
      11.0,
      8.0,
      6.0,
      5.0,
      7.0,
      12.0,
      23.0,
      35.0,
      49.0,
      57.0,
      52.0,
      43.0,
      31.0,
      20.0,
      12.0,
      9.0,
      15.0,
      24.0,
      31.0,
      27.0,
      20.0,
      13.0,
      9.0,
      7.0,
      6.0,
      8.0,
      14.0,
      27.0,
      36.0,
      42.0,
      34.0,
      23.0,
      14.0,
      9.0,
      7.0,
      11.0,
      15.0,
      10.0,
      6.0,
      5.0,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(heights.length, (index) {
        final progress = index / (heights.length - 1);
        final color = Color.lerp(
          const Color(0xFF45D1C0),
          const Color(0xFF7963EA),
          progress,
        )!;
        final edgeOpacity = 0.30 + (heights[index] / 57 * 0.35);
        return Container(
          width: index % 3 == 0 ? 2.4 : 2.0,
          height: heights[index] * 0.68,
          margin: const EdgeInsets.symmetric(horizontal: 1.25),
          decoration: BoxDecoration(
            color: color.withValues(alpha: edgeOpacity),
            borderRadius: BorderRadius.circular(99),
            boxShadow: heights[index] > 20
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.08),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }

  Widget _buildTrialGuideCard({VoidCallback? onTrialPressed}) {
    Widget featureRow(IconData icon, String title, String detail) {
      return Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF756BE8).withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 19,
              color: const Color(0xFFB9B4FF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(
                      color: Color(0xFFEFF0F3),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: '  $detail',
                    style: const TextStyle(
                      color: Color(0xFF969AA5),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF15171D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.075),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF58D6BD).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  '무료 체험',
                  style: TextStyle(
                    color: Color(0xFF70DFC9),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mic_none_rounded,
                    size: 15,
                    color: Color(0xFF8E929C),
                  ),
                  SizedBox(width: 5),
                  Text(
                    '마이크 사용',
                    style: TextStyle(
                      color: Color(0xFF8E929C),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '1분만 말해 보세요',
            style: TextStyle(
              color: Color(0xFFF7F8FA),
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '방금 나눈 대화를 역할 교환 영어 대화와 맞춤 튜터링으로 이어가며, 더 다양한 표현을 익혀보세요.',
            style: TextStyle(
              color: Color(0xFFA7ABB5),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          featureRow(
            Icons.forum_outlined,
            '1분 대화',
            '떠오르는 사람과 편하게 대화',
          ),
          const SizedBox(height: 13),
          featureRow(
            Icons.auto_stories_outlined,
            '2분 복습',
            '방금 대화를 영어로 다시 학습',
          ),
          const SizedBox(height: 13),
          featureRow(
            Icons.person_outline_rounded,
            '가입 없이',
            '바로 체험 후 계정 선택',
          ),
          if (onTrialPressed != null) ...[
            const SizedBox(height: 22),
            _buildPrimaryAction(
              label: '1분 무료 체험 시작',
              icon: Icons.mic_rounded,
              onPressed: onTrialPressed,
            ),
          ],
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
      style: const TextStyle(
        color: Color(0xFFF2F3F5),
        fontSize: 14.5,
      ),
      decoration: InputDecoration(
        prefixIcon: Icon(
          icon,
          color: const Color(0xFF8F929C),
          size: 20,
        ),
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF6F727C),
          fontSize: 14,
        ),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.24),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.07),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(
            color: Color(0xFF756BE8),
            width: 1.3,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
        ),
      ),
    );
  }
}

// ====================================================================
// 🔍 [Duo 한 컷 뷰어] 손가락으로 벌려 확대해 보는 홍보 이미지
// --------------------------------------------------------------------
//   글자가 작아 원본 크기로는 읽기 어렵다는 얘기가 있어 확대를 붙였다.
//   두 손가락으로 벌리거나 두 번 두드리면 커지고, 커진 채로 끌어서
//   구석까지 볼 수 있다.
// ====================================================================
class _DuoPromoViewer extends StatefulWidget {
  const _DuoPromoViewer();

  @override
  State<_DuoPromoViewer> createState() => _DuoPromoViewerState();
}

class _DuoPromoViewerState extends State<_DuoPromoViewer> {
  static const double _zoomedScale = 2.5;

  final TransformationController _controller = TransformationController();
  Offset? _lastDoubleTapPoint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isZoomed => _controller.value.getMaxScaleOnAxis() > 1.01;

  void _resetZoom() => _controller.value = Matrix4.identity();

  /// 두 번 두드린 지점이 화면에 그대로 남도록 그 점을 중심으로 당긴다.
  void _toggleZoom() {
    if (_isZoomed) {
      _resetZoom();
      return;
    }
    final point = _lastDoubleTapPoint;
    if (point == null) return;
    _controller.value = Matrix4.identity()
      ..translateByDouble(
        -point.dx * (_zoomedScale - 1),
        -point.dy * (_zoomedScale - 1),
        0,
        1,
      )
      ..scaleByDouble(_zoomedScale, _zoomedScale, _zoomedScale, 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 확대해 둔 상태에서 무심코 두드렸다고 닫아 버리면 다시 확대해야 한다.
      // 먼저 원래 크기로 돌리고, 그 상태에서 두드릴 때 닫는다.
      onTap: () {
        if (_isZoomed) {
          _resetZoom();
          return;
        }
        Navigator.of(context).pop();
      },
      onDoubleTapDown: (details) => _lastDoubleTapPoint = details.localPosition,
      onDoubleTap: _toggleZoom,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: 4,
              child: Image.asset(
                'assets/images/duo_promo_one_cut.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
