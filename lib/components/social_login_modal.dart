// lib/components/social_login_modal.dart
//
// Account creation/login modal shown before purchases for anonymous users.

import 'package:flutter/material.dart';

import '/custom_code/widgets/auth_progress_view.dart';
import '/custom_code/widgets/shared_social_button.dart';
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
      return '로그인을 취소했습니다.';
    }
    if (msg.contains('network')) {
      return '네트워크 오류가 발생했습니다.';
    }
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }
    if (msg.contains('user-not-found')) {
      return '가입된 계정이 없습니다.';
    }
    if (msg.contains('weak-password')) {
      return '비밀번호는 6자 이상이어야 합니다.';
    }
    if (msg.contains('invalid-email')) {
      return '이메일 형식을 확인해 주세요.';
    }
    if (msg.contains('email-already-in-use')) {
      return '이미 가입된 이메일입니다. 로그인으로 진행해 주세요.';
    }
    return '로그인에 실패했습니다. 다시 시도해 주세요.';
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
          onTap: () => _handleResult(SocialAuthService.signInWithKakao),
        ),
        const SizedBox(height: 12),
        SharedSocialButton(
          label: 'Google로 계속하기',
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
                '다른 방법으로 가입하기',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),
        SharedSocialButton(
          label: '이메일로 시작하기',
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
              text: '이미 계정이 있나요? ',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              children: const [
                TextSpan(
                  text: '바로 로그인하세요',
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
              '로그인',
              !_isSignUp,
              () => setState(() => _isSignUp = false),
            ),
            const SizedBox(width: 8),
            _tabButton(
              '회원가입',
              _isSignUp,
              () => setState(() => _isSignUp = true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: '이메일',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '비밀번호',
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
          child: Text(_isSignUp ? '가입하기' : '로그인'),
        ),
        TextButton(
          onPressed: () => setState(() => _showEmailForm = false),
          child: const Text('뒤로'),
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
