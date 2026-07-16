import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '/auth/social_auth_service.dart';
import '/components/social_login_modal.dart';
import '/custom_code/widgets/auth_progress_view.dart';
import '/custom_code/widgets/shared_social_button.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';

/// 체험 완료 후 로그인 유도 하단 시트.
class TrialSignupSheet extends StatefulWidget {
  const TrialSignupSheet({
    super.key,
    required this.onLoginSuccess,
  });

  final VoidCallback onLoginSuccess;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onLoginSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TrialSignupSheet(onLoginSuccess: onLoginSuccess),
    );
  }

  @override
  State<TrialSignupSheet> createState() => _TrialSignupSheetState();
}

class _TrialSignupSheetState extends State<TrialSignupSheet> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleLogin(Future<dynamic> Function() authAction) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await authAction();
      await _grantSignupBonusIfPossible();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        if (!mounted) return;
        Navigator.of(context).pop();
        widget.onLoginSuccess();
        return;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '로그인 상태를 확인하지 못했습니다. 다시 시도해 주세요.';
      });
    } catch (e) {
      debugPrint('[TrialSignupSheet] login error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  Future<void> _grantSignupBonusIfPossible() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('grantSignupBonus');
      final result = await callable.call<Map<String, dynamic>>({});
      final remainingTime = (result.data['remainingTime'] as num?)?.toInt();
      if (remainingTime != null) {
        FFAppState().remainingTime = remainingTime;
        FFAppState().remainingTimeLoaded = true;
      }
    } catch (e) {
      debugPrint('[TrialSignupSheet] signup bonus skipped: $e');
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('cancelled') || msg.contains('cancel')) {
      return '로그인을 취소했습니다.';
    }
    if (msg.contains('network')) {
      return '네트워크 오류가 발생했습니다.';
    }
    return '로그인에 실패했습니다. 다시 시도해 주세요.';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    final theme = FlutterFlowTheme.of(context);

    return PopScope(
      canPop: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(24, 28, 24, bottomPad + 24),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '회원가입 후 이용해 주세요',
              textAlign: TextAlign.center,
              style: theme.titleMedium.override(
                fontFamily: theme.titleMediumFamily,
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                lineHeight: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: AuthProgressView(
                  compact: true,
                  showStepLabel: false,
                ),
              )
            else ...[
              SharedSocialButton(
                label: '카카오로 시작하기',
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
                onTap: () => _handleLogin(SocialAuthService.signInWithKakao),
              ),
              const SizedBox(height: 12),
              SharedSocialButton(
                label: 'Google로 시작하기',
                backgroundColor: Colors.white,
                textColor: Colors.black87,
                border: Border.all(color: Colors.grey.shade300),
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
                onTap: () => _handleLogin(SocialAuthService.signInWithGoogle),
              ),
              const SizedBox(height: 12),
              SharedSocialButton(
                label: '이메일로 회원가입',
                backgroundColor: const Color(0xFF2C2C32),
                textColor: Colors.white,
                border: Border.all(color: Colors.white24),
                icon: const Icon(
                  Icons.email_outlined,
                  size: 20,
                  color: Colors.white70,
                ),
                onTap: () => _handleLogin(() async {
                  final success = await showDialog<bool>(
                    context: context,
                    builder: (_) => const SocialLoginModal(
                      startWithEmailSignUp: true,
                    ),
                  );
                  if (success != true) {
                    throw Exception('cancelled');
                  }
                }),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.bodySmall.override(
                  fontFamily: theme.bodySmallFamily,
                  color: Colors.red.shade300,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
