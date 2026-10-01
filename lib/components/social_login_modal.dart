// lib/components/social_login_modal.dart
//
// Account creation/login modal shown before purchases for anonymous users.

import 'package:flutter/material.dart';

import '/custom_code/widgets/auth_progress_view.dart';
import '/custom_code/widgets/shared_social_button.dart';
import '/custom_code/services/origin_surface_localization.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '../auth/social_auth_service.dart';

class SocialLoginModal extends StatefulWidget {
  const SocialLoginModal({
    super.key,
    this.startWithEmailSignUp = false,
  });

  final bool startWithEmailSignUp;

  @override
  State<SocialLoginModal> createState() => _SocialLoginModalState();
}

class _SocialLoginModalState extends State<SocialLoginModal> {
  OriginSurfaceCopy get _copy =>
      OriginSurfaceCopy.forLanguage(FFAppState().chatLang);
  bool _isLoading = false;
  bool _showEmailForm = false;
  bool _isSignUp = false;
  String? _errorMessage;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.startWithEmailSignUp) {
      _showEmailForm = true;
      _isSignUp = true;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleResult(Future<dynamic> Function() action) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('[SocialLoginModal] auth error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(e);
        _isLoading = false;
      });
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('cancelled') || msg.contains('cancel')) {
      return _copy['loginCanceled'];
    }
    if (msg.contains('network')) {
      return _copy['networkError'];
    }
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return _copy['incorrectCredentials'];
    }
    if (msg.contains('user-not-found')) {
      return _copy['accountNotFound'];
    }
    if (msg.contains('weak-password')) {
      return _copy['weakPassword'];
    }
    if (msg.contains('invalid-email')) {
      return _copy['invalidEmail'];
    }
    if (msg.contains('email-already-in-use')) {
      return _copy['emailInUse'];
    }
    return _copy['loginFailed'];
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading)
                const AuthProgressView(compact: true)
              else if (_showEmailForm)
                _buildEmailForm()
              else
                _buildButtons(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade600, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Column(
      children: [
        SharedSocialButton(
          label: _copy['continueKakao'],
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
          onTap: () => _handleResult(SocialAuthService.signInWithKakao),
        ),
        const SizedBox(height: 12),
        SharedSocialButton(
          label: _copy['continueGoogle'],
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
          onTap: () => _handleResult(SocialAuthService.signInWithGoogle),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _copy['otherSignupOptions'],
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),
        SharedSocialButton(
          label: _copy['continueEmail'],
          backgroundColor: Colors.grey.shade100,
          textColor: Colors.black87,
          icon: const Icon(
            Icons.email_outlined,
            size: 20,
            color: Colors.black54,
          ),
          onTap: () => setState(() {
            _showEmailForm = true;
            _isSignUp = true;
          }),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() {
            _showEmailForm = true;
            _isSignUp = false;
          }),
          child: RichText(
            text: TextSpan(
              text: _copy['alreadyAccount'] + ' ',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              children: [
                TextSpan(
                  text: _copy['logIn'],
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _tabButton(
              _copy['logIn'],
              !_isSignUp,
              () => setState(() => _isSignUp = false),
            ),
            const SizedBox(width: 8),
            _tabButton(
              _copy['signUp'],
              _isSignUp,
              () => setState(() => _isSignUp = true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: _copy['email'],
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: _copy['password'],
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => _handleResult(
            () => SocialAuthService.signInWithEmail(
              _emailCtrl.text.trim(),
              _passwordCtrl.text,
              isSignUp: _isSignUp,
            ),
          ),
          child: Text(_isSignUp ? _copy['signUp'] : _copy['logIn']),
        ),
        TextButton(
          onPressed: () => setState(() => _showEmailForm = false),
          child: Text(_copy['back']),
        ),
      ],
    );
  }

  Widget _tabButton(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? Colors.black : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.black : Colors.grey,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
