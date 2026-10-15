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
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math' as math;
import 'auth_progress_view.dart';
import 'duo_board_sheet.dart';
import '/custom_code/services/duo_board_host_presence.dart';
import '/auth/social_auth_service.dart';
import '/auth/account_discovery_service.dart';
// 익명으로 초대받아 대화한 뒤 기존 계정으로 돌아온 사람의 Duo 기록 복구.
import '/custom_code/services/duo_guest_handoff.dart';
import '/custom_code/services/duo_board_push_service.dart';
import '/custom_code/services/duo_board_intro_notice.dart';
import '/custom_code/services/origin_surface_localization.dart';
import '/custom_code/services/system_ui_language.dart';

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

class _IntroMasterState extends State<IntroMaster>
    with SingleTickerProviderStateMixin {
  static const List<String> _introLanguageFlags = [
    '🇺🇸',
    '🇯🇵',
    '🇨🇳',
    '🇪🇸',
    '🇫🇷',
    '🇩🇪',
    '🇰🇷',
    '🇮🇳',
    '🇷🇺',
    '🇵🇹',
    '🇮🇹',
    '🇳🇱',
  ];
  static const List<String> _introLanguageNames = [
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
    'Dutch',
  ];
  static const String _termsEnglishUrl =
      'https://docs.google.com/document/d/1vs2n7kF0GzlejNaZOa1ZnfKbuwuOzOCr7Q5ZvYqmbVs/edit';
  // 해외 테스터용 Google 바로가기는 종료했다.
  static const bool _showEnglishTesterGoogleEntry = false;

  static const String _privacyEnglishUrl =
      'https://docs.google.com/document/d/1AyK3KM9anwsVo7PaLdYRdxNnwa0MmRHuhxAN7yXbOjk/edit';
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  late final TapGestureRecognizer _termsTapRecognizer;
  late final TapGestureRecognizer _privacyTapRecognizer;
  late final AnimationController _welcomeMotionController;

  // ── 🎙️ [TAGLINE-PITCH] 타원을 누르면 뜨는 말풍선 ────────────────────
  //   같은 말을 세 가지로 바꿔 가며 보여 준다. 누를 때마다 다음 것으로
  //   넘어가고, 5초 뒤 저절로 사라진다. 말풍선을 누르면 그 자리에서 사라진다.
  //
  //   레이아웃에 끼우지 않고 Overlay로 띄운다 — 웰컴 화면은 Spacer로 자리를
  //   나눠 쓰고 있어서, 말풍선이 줄 하나를 차지하면 버튼과 문구가 통째로
  //   밀린다. 떠 있는 동안에도 화면은 그대로 만질 수 있어야 한다.
  static const List<List<String>> _kTaglinePitches = <List<String>>[
    <String>[
      '🎙️ Real-World AI Language Practice',
      'No grammar lectures. No pattern drills.\nJust real conversation.\nPay only for the time you use.',
    ],
    <String>[
      '🎙️ No Lessons, Just Real Practice',
      'Practice real conversations with AI.\nPay only for the time you use.',
    ],
    <String>[
      '🎙️ Your Personal AI Practice Room',
      'Learn through conversation, without lectures.\nPay only for the time you use.',
    ],
  ];
  static const Duration _kTaglineBubbleLife = Duration(seconds: 5);
  final GlobalKey _taglineKey = GlobalKey();
  OverlayEntry? _taglineBubble;
  Timer? _taglineBubbleTimer;
  int _taglinePitchIndex = 0;

  bool isLoginMode = true;
  bool isLoading = false;
  // Cold-start deep links arrive asynchronously. Keep the welcome/Duo-board
  // surface covered until the saved invite, Play referrer, and AppsFlyer
  // callbacks have had their first routing opportunity.
  bool _checkingEntryStatus = true;
  IntroScreen _currentScreen = IntroScreen.welcome;
  int _welcomePage = 0;
  bool _welcomeForward = true;
  bool _showEmailForm = false;
  bool _isValidatingDuoInvite = false;

  // =======================================================
  // [Account Discovery] Existing-account lookup state
  // =======================================================
  final List<AccountDiscoveryResult> _accountDiscoveryResults = [];
  String _accountDiscoveryMessage = '';
  String _accountDiscoveryBusyProvider = '';

  bool get _requiresAuthOnlyIntro => FFAppState().isGuestSession;

  @override
  void initState() {
    super.initState();
    _termsTapRecognizer = TapGestureRecognizer()
      ..onTap = () => _openLegalDocument(isTerms: true);
    _privacyTapRecognizer = TapGestureRecognizer()
      ..onTap = () => _openLegalDocument(isTerms: false);
    _welcomeMotionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _emailFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
    _clearInvalidLastAuthProvider();
    AppsFlyerManager.duoInviteSignal.addListener(_onDuoInviteSignal);
    if (_requiresAuthOnlyIntro) {
      _currentScreen = IntroScreen.auth;
    } else {
      _currentScreen = IntroScreen.welcome;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _runEntryStatusCheck());
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
  // (항상 맨 아래로 스크롤하면 Password 칸이 화면 밖으로 밀려나 다시 끌어내려야 했음 →
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
    AppsFlyerManager.duoInviteSignal.removeListener(_onDuoInviteSignal);
    _scrollController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _termsTapRecognizer.dispose();
    _privacyTapRecognizer.dispose();
    _hideTaglineBubble();
    _welcomeMotionController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _runEntryStatusCheck() async {
    try {
      await _checkEntryStatus();
    } catch (error) {
      debugPrint('[Intro] entry status check failed: $error');
    } finally {
      if (mounted) {
        setState(() => _checkingEntryStatus = false);
      }
    }
  }

  Future<void> _checkEntryStatus() async {
    // 1순위: Play 설치 referrer의 최신 초대를 먼저 복구한다.
    // Android 자동 백업이 과거 FFAppState 초대를 되살리는 경우보다 우선해야 한다.
    await AppsFlyerManager.recoverPlayInstallInvite();
    if (!mounted) return;

    // 저장된 초대는 서버에 활성 방이 있을 때만 사용한다.
    debugPrint(
      '[Intro] pendingInviteType=${FFAppState().pendingInviteType}, duoRoomId=${FFAppState().duoRoomId}',
    );
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
    // 익명(Duo 비회원 게스트)은 Intro에 머문다 (Welcome 또는 Auth)
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
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
      FFAppState().lastAuthProvider = 'email';
      if (!isLoginMode) {
        await _grantSignupBonusIfPossible();
      }
      // 가입/로그인 모두 연령 정보 확인 (birthYear 있으면 자동 통과)
      if (mounted) {
        await _checkAgeAndRoute();
      }
    } on FirebaseAuthException catch (e) {
      // 📏 화면 안내만 있고 로그가 없어 실패 이유를 못 찾았다(2026-10-15).
      debugPrint('[EMAIL-AUTH] failed mode=${isLoginMode ? 'login' : 'signup'} '
          'code=${e.code} anon=${FirebaseAuth.instance.currentUser?.isAnonymous}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? "An error occurred.",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
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
          content: Text(
            "Enter your email first.",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
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
          content: Text(
            "Reset email sent. Check your inbox and spam folder.",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
          SnackBar(content: Text("Failed to send: ${e.toString()}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [_buildMain(context)]);
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
      // Local recent-provider state can be lost during an app reinstall.
      // Always start in login mode so an existing user is not presented with
      // account creation unless they explicitly choose Sign Up.
      isLoginMode = true;
    });
  }

  void _goBackToStory() {
    if (_welcomePage == 0) return;
    _hideTaglineBubble();
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

  /// 시스템 글꼴 배율 상한. 본문에는 쓰지 않는다 — 읽을 글은 커져야 한다.
  /// 폭이 정해진 UI 조각(워드마크·버튼 라벨)에만 씌워서, 배율을 크게 쓰는
  /// 기기에서 줄이 삐져나가 화면이 깨지는 것을 막는다.
  /// (실기기 재현: font_scale 1.7 + 밀도 540 → 인증 헤더가 16px 초과)
  TextScaler _cappedScaler(BuildContext context, double maxFactor) {
    final factor = MediaQuery.textScalerOf(context).scale(1.0);
    return TextScaler.linear(factor > maxFactor ? maxFactor : factor);
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
        // 워드마크는 상표라 줄바꿈도 생략부호도 어울리지 않는다. 배율만
        // 묶어 두고, 그래도 모자라면 Flexible이 마지막으로 받아낸다.
        Flexible(
          child: Text(
            'StealthVox',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: _cappedScaler(context, 1.15),
            style: GoogleFonts.orbitron(
              fontSize: compact ? 15 : 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFF7F8FA),
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }

  void _showDuoPromo() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close Duo Preview',
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

  Widget _buildPageIndicator(int activeIndex, {bool tealActive = false}) {
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

  Widget _buildWelcomeDuoAction() {
    final copy = IntroWelcomePageCopy.forSystemLocale();
    return AnimatedBuilder(
      animation: _welcomeMotionController,
      builder: (context, child) {
        final shift = _welcomeMotionController.value * 4 - 3;
        return Container(
          width: double.infinity,
          // 📐 높이를 못 박지 않는다. 기기 글자 배율이 크면 라벨이 두 줄이
          //   되면서 52를 넘는다(실기기 2.0배에서 가로 106px 초과,
          //   2026-08-27). 최소 높이만 두고 내용만큼 자라게 한다.
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(shift, 0),
              end: Alignment(shift + 2, 0),
              colors: const [
                Color(0xFF45CDBD),
                Color(0xFF765EEB),
                Color(0xFF45CDBD),
              ],
            ),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF765EEB).withValues(alpha: 0.20),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            child: InkWell(
              onTap: _openDuoBoard,
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 라벨이 남는 폭을 쓰고, 모자라면 줄을 바꾼다.
                    // 화살표는 크기가 정해져 있어 그대로 둔다.
                    Flexible(
                      child: Text(
                        copy['duoInvite']!,
                        maxLines: 2,
                        style: TextStyle(
                          color: Color(0xFFF9FAFC),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.35,
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: Color(0xFFF9FAFC),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeLoginAction() {
    final copy = IntroWelcomePageCopy.forSystemLocale();
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
          Text(
            copy['loginOrJoin']!,
            style: const TextStyle(
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

  /// Temporary shortcut for overseas testers. It uses the normal Google auth
  /// and signup-bonus flow, then opens Lobby without the Korean age dialog.
  Widget _buildEnglishTesterGoogleAction() {
    final onTap = isLoading
        ? null
        : () => _handleUnifiedAuth(
              SocialAuthService.signInWithGoogle,
              provider: 'google',
              englishTesterDirectLobby: true,
            );

    return Semantics(
      button: true,
      label: 'Continue with Google - English tester access',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: isLoading ? 0.58 : 1,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(1.2),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4FD8C5), Color(0xFF7665F1)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF756BE8).withValues(alpha: 0.24),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: const Color(0xFF17191F),
            borderRadius: BorderRadius.circular(18.8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18.8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Image.asset(
                        'assets/images/google_logo.png',
                        width: 22,
                        height: 22,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.g_mobiledata_rounded,
                          size: 28,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isLoading
                                ? 'Signing in...'
                                : 'Continue with Google',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: _cappedScaler(context, 1.15),
                            style: const TextStyle(
                              color: Color(0xFFF6F7FA),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'English tester access',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: _cappedScaler(context, 1.15),
                            style: const TextStyle(
                              color: Color(0xFF9FA4B2),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFF756BE8).withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 17,
                        color: Color(0xFFC5C1FF),
                      ),
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

  Widget _buildPrimaryAction({
    required String label,
    required VoidCallback? onPressed,
    IconData icon = Icons.arrow_forward_rounded,
  }) {
    return ConstrainedBox(
      // 📐 높이를 못 박으면 라벨이 두 줄이 될 때 버튼 밖으로 잘린다
      //   (실기기 2.0배에서 긴 라벨의 끝이 사라졌던 이력이 있다,
      //   2026-08-27). 최소 높이만 두고 내용만큼 자라게 한다.
      constraints: const BoxConstraints(minHeight: 56),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            backgroundColor: const Color(0xFF756BE8),
            foregroundColor: const Color(0xFFF9F9FB),
            disabledBackgroundColor: const Color(
              0xFF756BE8,
            ).withValues(alpha: 0.45),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label, maxLines: 2, textAlign: TextAlign.center),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 19),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryAction({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return ConstrainedBox(
      // 📐 위 _buildPrimaryAction과 같은 이유로 높이를 열어 둔다.
      constraints: const BoxConstraints(minHeight: 50),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            foregroundColor: const Color(0xFFD9DAE1),
            side: BorderSide(
              color: const Color(0xFF756BE8).withValues(alpha: 0.72),
              width: 1.15,
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
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(label, maxLines: 2, textAlign: TextAlign.center),
              ),
            ],
          ),
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
      color: const Color(0xFF121212),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _IntroAmbientBackground(),
            if (isLoading || _checkingEntryStatus)
              const SafeArea(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28),
                    child: AuthProgressView(),
                  ),
                ),
              )
            else
              SafeArea(
                // 📐 [배율] 예전에는 여기서 웰컴 화면 전체를
                //   TextScaler.linear(1.0)으로 묶었다. 배율을 크게 쓰는
                //   기기에서 줄이 샐져나가는 걸 막으려던 것인데, 읽을
                //   글까지 통째로 고정돼 크게 보려는 사용자가 아무것도
                //   얻지 못했다. 이제 본문은 기기 설정을 그대로 따르고,
                //   폭이 정해진 조각(워드마크·버튼 라벨)만 _cappedScaler로
                //   따로 묶는다. 넘치는 높이는 스토리 페이지의 스크롤이
                //   받아낸다.
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
          ],
        ),
      ),
    );
  }

  void _goToGuidePage() {
    if (_welcomePage == 1) return;
    _hideTaglineBubble();
    setState(() {
      _welcomeForward = true;
      _welcomePage = 1;
    });
  }

  Future<void> _openDuoBoard() async {
    final notice = DuoBoardIntroNoticeCopy.forSystemLocale();
    final continueToBoard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(dialogContext, true),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E22),
          title: Text(
            notice.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              notice.body,
              style: const TextStyle(
                color: Color(0xFFCFD2DA),
                height: 1.55,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(notice.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(notice.openBoard),
            ),
          ],
        ),
      ),
    );
    if (continueToBoard != true || !mounted) return;
    final claim = await showDuoBoardSheet(
      context,
      showInactivePosts: true,
    );
    if (!mounted || claim == null) return;
    await DuoBoardHostPresence.instance.prepareForIncomingInvite(claim.roomId);
    if (!mounted) return;
    FFAppState().isGuestSession = true;
    FFAppState().inviterUid = claim.ownerUid;
    FFAppState().duoRoomId = claim.roomId;
    FFAppState().pendingInviteType = 'duo';
    FFAppState().update(() {});
    context.pushReplacementNamed('StealthRoom');
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

  Widget _buildHtmlWelcomeHeader() {
    return SizedBox(
      height: 94,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildWelcomeWaveMark(),
                const SizedBox(width: 15),
                Text(
                  'StealthVox',
                  maxLines: 1,
                  textScaler: _cappedScaler(context, 1.0),
                  style: const TextStyle(
                    color: Color(0xFFF7F7F8),
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2.3,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            // 배지는 그대로 보이지만 터치 박스가 166×59로 커졌다. 중심점이
            // 예전 126×27 배지와 같도록 위치를 절반 차이만큼 보정한다.
            right: -37,
            top: -13,
            child: _buildAnimatedDuoSnapshotBadge(),
          ),
        ],
      ),
    );
  }

  /// 앱이 지원하는 열두 언어. 첫 화면의 메시지를 먼저 읽을 수 있도록
  /// 주요 행동 버튼 아래, 페이지 안내 바로 위에 둔다.
  Widget _buildLanguageFlagCluster() {
    return Semantics(
      label: 'Twelve supported languages',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(2, (row) {
          return Padding(
            padding: EdgeInsets.only(bottom: row == 0 ? 4 : 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (column) {
                final index = row * 6 + column;
                return Padding(
                  padding: EdgeInsets.only(left: column == 0 ? 0 : 5),
                  child: Tooltip(
                    message: _introLanguageNames[index],
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1E27),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.11),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF756BE8,
                            ).withValues(alpha: 0.11),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        _introLanguageFlags[index],
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(fontSize: 18, height: 1),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  /// 첨부 레퍼런스의 여러 겹 선형 음파를 작은 브랜드 마크로 재해석했다.
  /// 선의 위상과 진폭이 천천히 이동해 말소리가 흐르는 인상을 준다.
  Widget _buildWelcomeWaveMark() {
    return AnimatedBuilder(
      animation: _welcomeMotionController,
      builder: (context, _) {
        return SizedBox(
          width: 30,
          height: 34,
          child: CustomPaint(
            painter: _IntroFlowWavePainter(
              progress: _welcomeMotionController.value,
            ),
          ),
        );
      },
    );
  }

  /// 타원 전체가 버튼이다 — 글자만 눌리면 눌러도 안 되는 것처럼 보인다.
  /// 숨 쉬는 결(세로·크기)에 좌우로 살짝 흔들리는 결을 얹어 "눌러도 되는 것"
  /// 임을 알린다. 흔들림은 숨보다 두 배 빠르되 ±1.6px·±0.9°로 얕게 둔다 —
  /// 크게 흔들면 글자가 읽히지 않는다(소리 구슬과 같은 시계를 쓴다).
  Widget _buildWelcomeTagline() {
    final copy = IntroWelcomePageCopy.forSystemLocale();
    return AnimatedBuilder(
      animation: _welcomeMotionController,
      builder: (context, child) {
        final phase = _welcomeMotionController.value * math.pi * 2;
        return Transform.translate(
          offset: Offset(math.sin(phase * 2) * 1.6, math.sin(phase) * 2.2),
          child: Transform.rotate(
            angle: math.sin(phase * 2 + 0.7) * 0.016,
            child: Transform.scale(
              scale: 1 + math.sin(phase) * 0.012,
              child: child,
            ),
          ),
        );
      },
      child: GestureDetector(
        key: _taglineKey,
        behavior: HitTestBehavior.opaque,
        onTap: _showNextTaglinePitch,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF171719),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: const Color(0xFFD8D8DC), width: 1),
          ),
          child: Text(
            copy['tagline']!,
            maxLines: 1,
            textScaler: _cappedScaler(context, 1.0),
            style: const TextStyle(
              color: Color(0xFF52D4C3),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  /// 누를 때마다 다음 한마디로 넘어간다. 떠 있는 말풍선은 먼저 걷는다 —
  /// 두 장이 겹쳐 뜨면 뒤엣것이 앞엣것을 가린다.
  void _showNextTaglinePitch() {
    _hideTaglineBubble();
    final anchor = _taglineKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context);
    if (anchor == null || !anchor.hasSize || overlay == null) return;
    final Offset topLeft = anchor.localToGlobal(Offset.zero);
    final double top = topLeft.dy + anchor.size.height + 10;
    final List<String> pitch =
        IntroTaglinePitchCopy.forSystemLocale(_taglinePitchIndex);
    // 다음 차례를 미리 올려 둔다. 저절로 사라졌든 눌러서 껐든, 다음에 누르면
    // 언제나 그다음 한마디가 나온다.
    _taglinePitchIndex = (_taglinePitchIndex + 1) % _kTaglinePitches.length;
    final entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: 16,
        right: 16,
        top: top,
        child: _TaglinePitchBubble(
          title: pitch[0],
          body: pitch[1],
          onTap: _hideTaglineBubble,
        ),
      ),
    );
    overlay.insert(entry);
    _taglineBubble = entry;
    _taglineBubbleTimer = Timer(_kTaglineBubbleLife, _hideTaglineBubble);
  }

  void _hideTaglineBubble() {
    _taglineBubbleTimer?.cancel();
    _taglineBubbleTimer = null;
    _taglineBubble?.remove();
    _taglineBubble = null;
  }

  /// 첫 박자에는 워드마크를 온전히 보여 주고, 뒤이어 광고 배지가
  /// 대각선으로 미끄러져 들어와 StealthVox 일부를 덮는다.
  Widget _buildAnimatedDuoSnapshotBadge() {
    return AnimatedBuilder(
      animation: _welcomeMotionController,
      child: Transform.rotate(
        angle: -math.pi / 4,
        child: _buildDuoSnapshotBadge(),
      ),
      builder: (context, child) {
        final progress = _welcomeMotionController.value;
        // 0~42%: 로고만 노출, 42~55%: 등장, 55~88%: 유지,
        // 88~100%: 퇴장. 다음 반복에서도 자연스럽게 다시 시작한다.
        final double visibility;
        if (progress < 0.42) {
          visibility = 0;
        } else if (progress < 0.55) {
          visibility = Curves.easeOutCubic.transform(
            (progress - 0.42) / 0.13,
          );
        } else if (progress < 0.88) {
          visibility = 1;
        } else {
          visibility =
              1 - Curves.easeInCubic.transform((progress - 0.88) / 0.12);
        }
        return IgnorePointer(
          // 막 나타나거나 사라지는 동안에도 보이는 배지를 누를 수 있다.
          // 완전히 숨은 구간만 입력을 통과시켜 뒤의 로고를 방해하지 않는다.
          ignoring: visibility < 0.15,
          child: Opacity(
            opacity: visibility.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(18 * (1 - visibility), -12 * (1 - visibility)),
              child: Transform.scale(
                scale: 0.94 + visibility * 0.06,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDuoSnapshotBadge() {
    return Semantics(
      button: true,
      label: 'Open Duo Snapshot preview',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showDuoPromo,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            // 시각 배지는 126×27 그대로 두고 터치 영역만 넓힌다.
            width: 166,
            height: 59,
            child: Center(
              child: Ink(
                width: 126,
                height: 27,
                decoration: BoxDecoration(
                  color: const Color(0xFF7661EA),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Center(
                  child: Text(
                    'AD · Duo Snapshot',
                    maxLines: 1,
                    textScaler: _cappedScaler(context, 1.0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHtmlSoundOrb(double size) {
    final coreSize = size * 0.60;
    return AnimatedBuilder(
      animation: _welcomeMotionController,
      builder: (context, child) {
        final phase = _welcomeMotionController.value * math.pi * 2;
        final pulse = 1 + math.sin(phase) * 0.025;
        return Transform.translate(
          offset: Offset(0, math.sin(phase) * 5),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _IntroOrbitPainter(
                      progress: _welcomeMotionController.value,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: coreSize,
                    height: coreSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.25, -0.25),
                        radius: 0.95,
                        colors: [
                          const Color(0xFF45CDBD).withValues(alpha: 0.32),
                          const Color(0xFF765EEB).withValues(alpha: 0.17),
                          const Color(0xFF1F1F1F),
                        ],
                        stops: const [0, 0.56, 1],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF45CDBD,
                          ).withValues(alpha: 0.14),
                          blurRadius: 52,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _buildAnimatedOrbBars(
                        phase: phase,
                        height: coreSize * 0.36,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedOrbBars({
    required double phase,
    required double height,
  }) {
    const colors = <Color>[
      Color(0xFF45CDBD),
      Color(0xFF62D8C9),
      Color(0xFF765EEB),
      Color(0xFF76F7E6),
      Color(0xFF67E9D9),
    ];
    const factors = <double>[0.50, 0.84, 0.62, 0.98, 0.40];
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(colors.length, (index) {
          final movement =
              0.84 + math.sin(phase * (1.1 + index * 0.09) + index) * 0.16;
          return Container(
            width: 6,
            height: height * factors[index] * movement,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: colors[index],
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                BoxShadow(
                  color: colors[index].withValues(alpha: 0.28),
                  blurRadius: 9,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWelcomeStoryPage() {
    final copy = IntroWelcomePageCopy.forSystemLocale();
    return LayoutBuilder(
      key: const ValueKey('welcome-story'),
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final veryCompact = constraints.maxHeight < 620;
        final headlineSize = constraints.maxWidth < 350 ? 25.0 : 28.0;
        final headlineScaler = _cappedScaler(context, 1.15);
        final scaledHeadline = headlineScaler.scale(headlineSize);
        final storyGradient = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF45CDBD), Color(0xFF765EEB)],
        ).createShader(
          Rect.fromLTWH(
            scaledHeadline * 3.2,
            0,
            scaledHeadline * 3,
            scaledHeadline * 1.6,
          ),
        );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, compact ? 12 : 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - (compact ? 12 : 18),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHtmlWelcomeHeader(),
                  SizedBox(height: veryCompact ? 8 : 18),
                  Center(child: _buildWelcomeTagline()),
                  SizedBox(height: veryCompact ? 30 : 52),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: copy['headlineBefore']!),
                        TextSpan(
                          text: copy['headlineAccent']!,
                          style: TextStyle(
                            foreground: Paint()..shader = storyGradient,
                          ),
                        ),
                        TextSpan(text: copy['headlineAfter']!),
                      ],
                    ),
                    textAlign: TextAlign.left,
                    textScaler: headlineScaler,
                    style: TextStyle(
                      color: const Color(0xFFF7F8FA),
                      fontSize: headlineSize,
                      fontWeight: FontWeight.w900,
                      height: 1.38,
                      letterSpacing: -0.8,
                    ),
                  ),
                  SizedBox(height: veryCompact ? 28 : 42),
                  const Spacer(flex: 5),
                  _showEnglishTesterGoogleEntry
                      ? _buildEnglishTesterGoogleAction()
                      : _buildWelcomeDuoAction(),
                  SizedBox(height: compact ? 4 : 8),
                  _buildWelcomeLoginAction(),
                  const Spacer(flex: 2),
                  Center(child: _buildPageIndicator(0, tealActive: true)),
                  const Spacer(flex: 2),
                  _buildWelcomePageFooter(copy['swipeContinue']!),
                  SizedBox(height: compact ? 8 : 12),
                  _buildLanguageFlagCluster(),
                  SizedBox(height: compact ? 2 : 6),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeGuidePage() {
    final copy = DuoBoardGuidePageCopy.forSystemLocale();
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
                        tooltip: copy['back'],
                        style: IconButton.styleFrom(
                          foregroundColor: const Color(0xFFE6E7EA),
                          backgroundColor: Colors.white.withValues(
                            alpha: 0.045,
                          ),
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 21),
                      ),
                      const Spacer(),
                      _buildPageIndicator(1),
                      const Spacer(),
                      TextButton(
                        onPressed: _openAuthScreen,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          foregroundColor: const Color(0xFFBFC1C9),
                        ),
                        child: Text(
                          copy['login']!,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 24 : 36),
                  Text(
                    copy['headline']!,
                    style: const TextStyle(
                      color: Color(0xFFF7F8FA),
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.9,
                    ),
                  ),
                  SizedBox(height: compact ? 22 : 30),
                  // 제목 바로 아래가 시작 버튼이다. 사이에 있던 부제·소개
                  // 카드는 아래 단계 안내와 같은 말을 반복하고 있었다.
                  _buildPrimaryAction(
                    label: copy['browse']!,
                    icon: Icons.forum_outlined,
                    onPressed: _openDuoBoard,
                  ),
                  SizedBox(height: compact ? 16 : 20),
                  _buildUsageGuideSection(copy),
                  const Spacer(),
                  SizedBox(height: compact ? 18 : 28),
                  _buildSecondaryAction(
                    label: copy['findAccount']!,
                    icon: Icons.manage_search_rounded,
                    onPressed: () => setState(() {
                      _currentScreen = IntroScreen.accountDiscovery;
                      _showEmailForm = false;
                      _accountDiscoveryMessage = '';
                    }),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    copy['phoneSetup']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF9297A5),
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    copy['microphone']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF737680), fontSize: 11.5),
                  ),
                  const SizedBox(height: 10),
                  _buildWelcomePageFooter(copy['swipeBack']!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 회원이 올린 Duo 초대글을 비회원도 찾아 참여하는 게시판 흐름.
  Widget _buildUsageGuideSection(Map<String, String> copy) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF17191F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGuideStep(
            number: 1,
            title: copy['step1Title']!,
            description: copy['step1Body']!,
          ),
          const SizedBox(height: 16),
          _buildGuideStep(
            number: 2,
            title: copy['step2Title']!,
            description: copy['step2Body']!,
          ),
          const SizedBox(height: 16),
          _buildGuideStep(
            number: 3,
            title: copy['step3Title']!,
            description: copy['step3Body']!,
          ),
          const SizedBox(height: 16),
          _buildGuideStep(
            number: 4,
            title: copy['step4Title']!,
            description: copy['step4Body']!,
          ),
          const SizedBox(height: 16),
          _buildGuideStep(
            number: 5,
            title: copy['step5Title']!,
            description: copy['step5Body']!,
          ),
        ],
      ),
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
                  tooltip: 'Back',
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFE6E7EA),
                    backgroundColor: Colors.white.withValues(alpha: 0.045),
                    minimumSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 21),
                )
              else
                const SizedBox(width: 44, height: 44),
              const Spacer(),
              // 양옆 Spacer가 남는 폭을 다 가져가지 않도록 워드마크에 자리를
              // 준다. Flexible이 없으면 워드마크가 자기 크기를 고집해 Row가
              // 넘친다 — 화면 우상단 노란 빗금이 그 자국이었다.
              Flexible(child: _buildBrandMark(compact: true)),
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
          const SizedBox(height: 26),
          _buildTermsInlineText(),
        ],
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
              tooltip: 'Back',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Find My Account',
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
            'Check each login method you may have used. Accounts and their data are kept separate.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFB7B7C2),
              fontSize: 13,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 28),
          _buildDiscoveryActionButton(
            provider: 'google',
            label: 'Check Google Account',
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
            label: 'Check Kakao Account',
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
            label: 'Check Email Account',
            icon: const Icon(Icons.email_outlined, size: 20),
            onTap: _showEmailDiscoveryGuide,
          ),
          if (_accountDiscoveryMessage.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              _accountDiscoveryMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFD7D7DE),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
          if (foundResults.isNotEmpty) ...[
            const SizedBox(height: 28),
            if (foundResults.length > 1) ...[
              const Text(
                'Multiple accounts found. Their time and learning history cannot be combined. Choose one account.',
                style: TextStyle(
                  color: Color(0xFFB7B7C2),
                  fontSize: 13,
                  height: 1.45,
                ),
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
            label: const Text('Create New Account'),
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
                : () => launchURL('mailto:stealthvox.app@gmail.com'),
            icon: const Icon(Icons.support_agent, size: 18),
            label: const Text('Contact Support'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB9D7FF),
            ),
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
    return ConstrainedBox(
      // 📐 높이 고정 해제 — 기기 글자 배율이 크면 라벨이 버튼 밖으로
      //   잘렸다(2.0배 순회, 2026-08-27). 최소 높이만 둔다.
      constraints: const BoxConstraints(minHeight: 50),
      child: ElevatedButton.icon(
        onPressed: _accountDiscoveryBusyProvider.isNotEmpty ? null : onTap,
        icon: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor,
                ),
              )
            : icon,
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.55),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.65),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildDiscoveredAccountCard(AccountDiscoveryResult account) {
    final minutes = (account.remainingTime / 60).floor();
    final lastUsed = account.lastUsedAt == null
        ? 'Unavailable'
        : '${account.lastUsedAt!.year}.${account.lastUsedAt!.month.toString().padLeft(2, '0')}.${account.lastUsedAt!.day.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F242A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF4A90D9).withValues(alpha: 0.34),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            account.providerLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            account.maskedIdentifier.isEmpty
                ? 'Verified Account'
                : account.maskedIdentifier,
            style: const TextStyle(color: Color(0xFFD7D7DE), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            'Time left: $minutes min\nLearning history: ${account.historyCount}\nLast used: $lastUsed',
            style: const TextStyle(
              color: Color(0xFFB7B7C2),
              fontSize: 13,
              height: 1.55,
            ),
          ),
          if (account.parentConsentPending) ...[
            const SizedBox(height: 8),
            const Text(
              'Waiting for Parental Consent',
              style: TextStyle(
                color: Color(0xFFFFD166),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ConstrainedBox(
            // 📐 높이 고정 해제 — 기기 글자 배율이 크면 라벨이 버튼 밖으로
            //   잘렸다(2.0배 순회, 2026-08-27). 최소 높이만 둔다.
            constraints: const BoxConstraints(
              minHeight: 48,
              minWidth: double.infinity,
            ),
            child: ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () => _continueWithDiscoveredAccount(account),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Continue with This Account',
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
        _accountDiscoveryResults.removeWhere(
          (item) =>
              item.provider == result.provider &&
              item.maskedIdentifier == result.maskedIdentifier,
        );
        if (result.found) {
          _accountDiscoveryResults.add(result);
          _accountDiscoveryMessage =
              'We found existing StealthVox data. Choose the account you want to use.';
        } else {
          _accountDiscoveryMessage =
              'No StealthVox data was found for this account. Try another account or login method.';
        }
      });
    } on AccountDiscoveryCancelledException {
      if (!mounted) return;
      setState(() => _accountDiscoveryMessage = 'Account check canceled.');
    } catch (e) {
      debugPrint('[AccountDiscovery] lookup failed: $e');
      if (!mounted) return;
      setState(() {
        _accountDiscoveryMessage =
            'Unable to check account information. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _accountDiscoveryBusyProvider = '');
    }
  }

  Future<void> _continueWithDiscoveredAccount(
    AccountDiscoveryResult account,
  ) async {
    setState(() => isLoading = true);
    AppStateNotifier.instance.updateNotifyOnAuthChange(false);
    try {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
            content: Text('Unable to continue with this account: $e')));
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
        title: const Text('Create a New Account?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Time and learning history from your previous account will not transfer. Sign up with this login method?',
          style: TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Find Previous Account'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign Up with This Account'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _currentScreen = IntroScreen.auth;
        _accountDiscoveryMessage = '';
        _showEmailForm = false;
        isLoginMode = false;
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
      'kakao' => OriginSurfaceCopy.forSystemLocale()['previouslySignedUpKakao'],
      'google' =>
        OriginSurfaceCopy.forSystemLocale()['previouslySignedUpGoogle'],
      'email' => OriginSurfaceCopy.forSystemLocale()['previouslySignedUpEmail'],
      _ => OriginSurfaceCopy.forSystemLocale()['chooseLoginMethod'],
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
        // 질문과 안내문이 붙어 보이지 않도록 제목 아래 간격을 둔다.
        const SizedBox(height: 20),
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
    final isRecent = _validLastAuthProvider() == provider;

    late final String label;
    late final Color backgroundColor;
    late final Color foregroundColor;
    late final Widget icon;
    BoxBorder? border;
    VoidCallback? onTap;

    switch (provider) {
      case 'kakao':
        label = OriginSurfaceCopy.forSystemLocale()['continueKakao'];
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
        label = OriginSurfaceCopy.forSystemLocale()['continueGoogle'];
        backgroundColor = const Color(0xFFF7F7F8);
        foregroundColor = const Color(0xFF17181B);
        border = Border.all(color: Colors.white.withValues(alpha: 0.12));
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
        label = _showEmailForm
            ? OriginSurfaceCopy.forSystemLocale()['cancel']
            : OriginSurfaceCopy.forSystemLocale()['continueEmail'];
        backgroundColor = const Color(0xFF24262D);
        foregroundColor = const Color(0xFFF2F3F6);
        border = Border.all(color: Colors.white.withValues(alpha: 0.08));
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
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: isRecent && provider != 'kakao'
                  ? Border.all(color: const Color(0xFF8B82F5), width: 1.3)
                  : border,
            ),
            // 높이를 56으로 못 박으면 배율이 큰 기기에서 라벨이 한 줄에
            // 갇혀 "카카오톡으로 …"처럼 잘린다. 최소 높이만 지키고 글자가
            // 늘면 버튼이 같이 자라게 한다.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(left: 20, child: icon),
                  Padding(
                    // 아이콘 오른쪽 끝이 40이라 48이면 겹치지 않는다.
                    // 56에서 줄여 라벨이 쓸 폭을 넓혔다.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 10,
                    ),
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: _cappedScaler(context, 1.3),
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
                          OriginSurfaceCopy.forSystemLocale()['recent'],
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

  Map<String, String> _authIntroCopy() {
    return switch (systemUiLanguageName()) {
      'Korean' => {
          'title': '로그인 또는 가입',
          'description': '기존 회원은 이전에 사용한 방법으로 로그인해 주세요.',
        },
      'Japanese' => {
          'title': 'ログイン・新規登録',
          'description': 'すでにご利用の方は、以前使用した方法でログインしてください。',
        },
      'Chinese' => {
          'title': '登录或注册',
          'description': '已有用户请使用之前的方式登录。',
        },
      'Spanish' => {
          'title': 'Iniciar sesión o registrarse',
          'description':
              'Los usuarios existentes pueden iniciar sesión con el método anterior.',
        },
      'French' => {
          'title': 'Se connecter ou s’inscrire',
          'description':
              'Les utilisateurs existants peuvent se connecter avec leur méthode habituelle.',
        },
      'German' => {
          'title': 'Anmelden oder registrieren',
          'description':
              'Bestehende Nutzer können sich mit ihrer bisherigen Methode anmelden.',
        },
      'Hindi' => {
          'title': 'लॉग इन या साइन अप करें',
          'description':
              'मौजूदा उपयोगकर्ता अपनी पहले की विधि से लॉग इन कर सकते हैं।',
        },
      'Russian' => {
          'title': 'Войти или зарегистрироваться',
          'description':
              'Зарегистрированные пользователи могут войти прежним способом.',
        },
      'Portuguese' => {
          'title': 'Entrar ou cadastrar-se',
          'description':
              'Usuários existentes podem entrar com o método usado anteriormente.',
        },
      'Italian' => {
          'title': 'Accedi o iscriviti',
          'description':
              'Gli utenti esistenti possono accedere con il metodo usato in precedenza.',
        },
      'Dutch' => {
          'title': 'Inloggen of aanmelden',
          'description':
              'Bestaande gebruikers kunnen inloggen met hun eerdere methode.',
        },
      _ => {
          'title': 'Log In or Sign Up',
          'description':
              'Existing users can log in with their previous method.',
        },
    };
  }

  List<Widget> _buildAuthHeader() {
    final copy = _authIntroCopy();
    final lastProvider = _validLastAuthProvider();
    if (lastProvider == null) {
      return [
        _authSectionTitle(
          title: copy['title']!,
          description: copy['description']!,
        ),
      ];
    }

    return [
      _authSectionTitle(
        title: OriginSurfaceCopy.forSystemLocale()['continueWithAccount'],
        description: _providerDescription(lastProvider),
      ),
    ];
  }

  List<Widget> _buildProviderButtons() {
    final lastProvider = _validLastAuthProvider();
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
          colors: [Color(0xFF0C0D12), Color(0xFF050608), Color(0xFF030405)],
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
    final copy = OriginSurfaceCopy.forSystemLocale();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF15171D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
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
                _emailTabBtn(copy['logIn'], isLoginMode, () {
                  setState(() => isLoginMode = true);
                }),
                _emailTabBtn(copy['signUp'], !isLoginMode, () {
                  setState(() => isLoginMode = false);
                }),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildTextField(
            emailController,
            copy['email'],
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
            copy['password'],
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
              child: Text(
                  isLoginMode ? copy['continueEmail'] : copy['signupEmail']),
            ),
          ),
          if (isLoginMode) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _resetPassword,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9FA2AC),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(
                'Forgot your password?',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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
            const TextSpan(text: 'By joining, you agree to the '),
            TextSpan(
              text: 'Terms of Use',
              style: linkStyle,
              recognizer: _termsTapRecognizer,
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: linkStyle,
              recognizer: _privacyTapRecognizer,
            ),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _openLegalDocument({required bool isTerms}) async {
    final String url = isTerms ? _termsEnglishUrl : _privacyEnglishUrl;
    final bool opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.inAppBrowserView,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open the document.'),
        ),
      );
    }
  }

  /// 통합 소셜 인증: 약관 시트 없이 바로 소셜 로그인 -> 신규면 연령 확인
  Future<void> _handleUnifiedAuth(
    Future<dynamic> Function() authFn, {
    String provider = '',
    bool englishTesterDirectLobby = false,
  }) async {
    debugPrint('[Auth] _handleUnifiedAuth enter');
    setState(() => isLoading = true);
    // Multi-step auth 동안 GoRouter 자동 네비게이션 억제
    // (anonymous -> custom token -> bonus 지급 완료까지 Lobby 이동 방지)
    AppStateNotifier.instance.updateNotifyOnAuthChange(false);
    try {
      await authFn();
      if (provider.isNotEmpty) {
        FFAppState().lastAuthProvider = provider;
      }
      debugPrint(
        '[Auth] authFn complete, currentUser=${FirebaseAuth.instance.currentUser?.uid}',
      );
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
      await _checkAgeAndRoute(
        skipAgeCheck: englishTesterDirectLobby,
        forceLobby: englishTesterDirectLobby,
      );
    } catch (e, stack) {
      debugPrint('[Auth] _handleUnifiedAuth exception: $e');
      debugPrint('[Auth] stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Login failed: $e')));
      }
    } finally {
      // GoRouter 알림 복원
      AppStateNotifier.instance.updateNotifyOnAuthChange(true);
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// 연령 확인 후 라우팅 (소셜/이메일 공통)
  Future<void> _checkAgeAndRoute({
    bool skipAgeCheck = false,
    bool forceLobby = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    if (!skipAgeCheck) {
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
            await DuoBoardPushService.signOut();
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
    }

    // 🎫 [GUEST-EXIT] **복구보다 먼저 게스트 딱지를 뗀다.**
    //
    //   순서가 중요하다. `isGuestSession`이 남아 있으면 회원으로 로그인한
    //   사람이 자기 History에서 공부 기능을 못 쓴다(게스트로 판정되어
    //   잠긴다). 반대로 딱지가 남은 채 복구된 방을 열면 차감도 안 도는
    //   무료 구간이 되어 버린다 — 둘 다 같은 플래그에서 나온다.
    //
    //   기다리는 초대(pendingInviteType == 'duo')가 있으면 손대지 않는다.
    //   그 사람은 지금 막 새 통화의 게스트로 들어가는 길이고,
    //   `_routeAfterAuth`가 StealthRoom으로 보낸다.
    final bool joiningDuoNext = !forceLobby &&
        FFAppState().pendingInviteType == 'duo' &&
        FFAppState().duoRoomId.isNotEmpty;
    if (!joiningDuoNext && FFAppState().isGuestSession) {
      FFAppState().isGuestSession = false;
      FFAppState().inviterUid = '';
      FFAppState().duoRoomId = '';
      debugPrint('[Auth] duo guest flags cleared before restore');
    }

    // 🔁 [DUO-HANDOFF] 익명으로 Duo 초대를 받아 대화하고, 그 뒤 **자기 기존
    //   계정**으로 로그인한 경우다. uid가 바뀌어 방금 그 대화가 안 보이므로,
    //   공유 결과를 근거로 이 계정 아래에 다시 짓는다.
    //
    //   기다리지 않는다 — 공유 결과가 아직 안 만들어졌으면 안에서 몇 번 더
    //   두드리고, 히스토리 목록은 스트림이라 다 지어지면 저절로 나타난다.
    //   되찾을 표가 없는 보통의 로그인은 첫 줄에서 그대로 빠져나온다.
    //
    //   ⚠️ 표(`duoGuestClaim`)는 위에서 지우는 값에 들어 있지 않다. 그것을
    //   같이 지우면 복구할 근거가 사라진다.
    unawaited(restoreDuoHistoryAfterLogin(uid: user.uid));

    if (!mounted) return;
    if (forceLobby) {
      FFAppState().isGuestSession = false;
      context.goNamed('Lobby');
    } else {
      _routeAfterAuth();
    }

    // The auth-state listener can receive the member before this Intro route
    // finishes being replaced. Recheck on the settled member screen so the Duo
    // invitation decision is not dismissed by the route transition.
    if (!joiningDuoNext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(DuoBoardHostPresence.instance.recheckAfterLogin());
      });
    }
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
              title: Text(
                'What year were you born?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: SizedBox(
                height: 225,
                child: Column(
                  children: [
                    Text(
                      'This is required to verify your age.\nMinors may sign up with a parent or guardian\'s consent.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
                                '$year',
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
                ConstrainedBox(
                  // 📐 높이 고정 해제 — 기기 글자 배율이 크면 라벨이 버튼 밖으로
                  //   잘렸다(2.0배 순회, 2026-08-27). 최소 높이만 둔다.
                  constraints: const BoxConstraints(
                    minHeight: 48,
                    minWidth: double.infinity,
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90D9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(
                      'Confirm',
                      style: const TextStyle(
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
            SnackBar(
              content: Text(
                'A consent request was sent to your parent or guardian.\nAll features will be available after they approve it.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFF4A90D9),
              duration: const Duration(seconds: 4),
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
        title: Text(
          'Age verification is required',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Selecting your birth year is required to verify whether you are a minor.\n\nMinors may sign up with a parent or guardian\'s consent.\nYou will return to the login page.',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          ConstrainedBox(
            // 📐 높이 고정 해제 — 기기 글자 배율이 크면 라벨이 버튼 밖으로
            //   잘렸다(2.0배 순회, 2026-08-27). 최소 높이만 둔다.
            constraints: const BoxConstraints(
              minHeight: 48,
              minWidth: double.infinity,
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Confirm',
                style: const TextStyle(
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
          title: Text(
            'Parent or guardian consent is required',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Users under 14 need consent from a parent or guardian.\nEnter their email address.',
                style: const TextStyle(
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
                  hintText: 'Parent or guardian email',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(
                    Icons.email_outlined,
                    color: Colors.white38,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(
                'Later',
                style: const TextStyle(color: Colors.white38),
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
              child: Text(
                'Send consent request',
                style: const TextStyle(
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

  Future<void> _grantSignupBonusIfPossible() async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('grantSignupBonus');
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
        '[SignupBonus] grantSignupBonus complete, granted=$granted, remainingTime=$remainingTime',
      );
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
      style: const TextStyle(color: Color(0xFFF2F3F5), fontSize: 14.5),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF8F929C), size: 20),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6F727C), fontSize: 14),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.24),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF756BE8), width: 1.3),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
      ),
    );
  }
}

class _IntroAmbientBackground extends StatelessWidget {
  const _IntroAmbientBackground();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(
        painter: _IntroAmbientPainter(),
        child: SizedBox.expand(),
      ),
    );
  }
}

class _IntroAmbientPainter extends CustomPainter {
  const _IntroAmbientPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF121212),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-1.05, -1.05),
          radius: 1.15,
          colors: [
            const Color(0xFF45CDBD).withValues(alpha: 0.075),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(1.12, 1.05),
          radius: 1.28,
          colors: [
            const Color(0xFF765EEB).withValues(alpha: 0.075),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _IntroAmbientPainter oldDelegate) => false;
}

/// 첨부된 네온 음파처럼 여러 개의 가는 선이 한 덩어리로 흐르는 파형.
/// 중심에서 멀수록 진폭이 조금씩 달라져 입체적인 리본 결을 만든다.
class _IntroFlowWavePainter extends CustomPainter {
  const _IntroFlowWavePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final phase = progress * math.pi * 2;
    const strandCount = 15;
    final gradient = const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xFF49E2D0),
        Color(0xFF65D7E5),
        Color(0xFF8970F4),
        Color(0xFFB05BEE),
      ],
      stops: [0, 0.38, 0.7, 1],
    ).createShader(rect);

    // 한 겹의 흐린 빛을 먼저 깔아 작은 크기에서도 파형이 또렷하게 보인다.
    final glowPath = _wavePath(size, phase, 0);
    canvas.drawPath(
      glowPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..shader = gradient
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..color = Colors.white.withValues(alpha: 0.22),
    );

    for (var strand = 0; strand < strandCount; strand++) {
      final normalized = strand / (strandCount - 1);
      final offset = (normalized - 0.5) * 18;
      canvas.drawPath(
        _wavePath(size, phase, offset),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strand == strandCount ~/ 2 ? 1.35 : 0.75
          ..strokeCap = StrokeCap.round
          ..shader = gradient
          ..color = Colors.white.withValues(
            alpha: 0.34 + (1 - (normalized - 0.5).abs() * 2) * 0.54,
          ),
      );
    }
  }

  Path _wavePath(Size size, double phase, double strandOffset) {
    final path = Path();
    const samples = 72;
    for (var index = 0; index <= samples; index++) {
      final t = index / samples;
      final x = t * size.width;
      // 가장자리는 잔잔하고 가운데에서 크게 솟는 레퍼런스의 실루엣.
      final envelope = math.pow(math.sin(t * math.pi), 1.35).toDouble();
      final breathing = 0.92 + math.sin(phase + t * math.pi * 2) * 0.08;
      final carrier = math.sin(t * math.pi * 3.7 + phase * 0.34);
      final detail = math.sin(t * math.pi * 7.2 - phase * 0.22) * 0.18;
      final strandShape = strandOffset *
          envelope *
          (0.44 + 0.56 * math.sin(t * math.pi * 2.15 + phase * 0.12));
      final y = size.height / 2 +
          (carrier + detail) * size.height * 0.29 * envelope * breathing +
          strandShape;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _IntroFlowWavePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _IntroOrbitPainter extends CustomPainter {
  const _IntroOrbitPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.shortestSide * 0.49;
    final innerRadius = size.shortestSide * 0.43;
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF45CDBD).withValues(alpha: 0.25);
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF765EEB).withValues(alpha: 0.32);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * math.pi * 2);
    const dashCount = 54;
    const gapRatio = 0.48;
    const sweep = math.pi * 2 / dashCount;
    final rect = Rect.fromCircle(center: Offset.zero, radius: outerRadius);
    for (var index = 0; index < dashCount; index++) {
      canvas.drawArc(rect, index * sweep, sweep * gapRatio, false, outerPaint);
    }
    canvas.restore();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-progress * math.pi * 2 * 0.72);
    canvas.drawCircle(Offset.zero, innerRadius, innerPaint);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: innerRadius),
      0,
      math.pi * 0.44,
      false,
      innerPaint
        ..strokeWidth = 1.6
        ..color = const Color(0xFF67E9D9).withValues(alpha: 0.42),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IntroOrbitPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ====================================================================
// 🔍 [Duo 한 컷 뷰어] 손가락으로 벌려 확대해 보는 홍보 이미지
// --------------------------------------------------------------------
//   글자가 작아 원본 크기로는 읽기 어렵다는 얘기가 있어 확대를 붙였다.
//   두 손가락으로 벌리거나 두 번 두드리면 커지고, 커진 채로 끌어서
//   구석까지 볼 수 있다.
// ====================================================================
/// 🎙️ 타원을 누르면 그 아래 뜨는 한마디.
///
/// 살짝 떠오르며 나타나고, 누르면 그 자리에서 사라진다. 사라지는 애니메이션은
/// 두지 않는다 — 잠깐 뜨는 알림이라 나가는 모습까지 보고 있을 이유가 없다.
class _TaglinePitchBubble extends StatelessWidget {
  const _TaglinePitchBubble({
    required this.title,
    required this.body,
    required this.onTap,
  });

  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * -8),
          child: Transform.scale(scale: 0.96 + t * 0.04, child: child),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 꼭지. 타원이 화면 한가운데 있으므로 여기도 가운데다.
              CustomPaint(
                size: const Size(18, 9),
                painter: _TaglineBubbleTailPainter(),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF171719),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF52D4C3).withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF52D4C3),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      body,
                      style: const TextStyle(
                        color: Color(0xFFD8D8DC),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.55,
                      ),
                    ),
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

class _TaglineBubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF52D4C3).withValues(alpha: 0.35),
    );
    final inner = Path()
      ..moveTo(size.width / 2, 1.6)
      ..lineTo(size.width - 1.6, size.height)
      ..lineTo(1.6, size.height)
      ..close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFF171719));
  }

  @override
  bool shouldRepaint(covariant _TaglineBubbleTailPainter oldDelegate) => false;
}

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
