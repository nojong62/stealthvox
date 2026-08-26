// ════════════════════════════════════════════════════════════════════
// 👤 [ACCOUNT] 등록 정보 — 로그인 정보와 수정
// --------------------------------------------------------------------
// 어떤 계정으로 들어와 있는지, 무엇으로 로그인했는지를 한 화면에서 본다.
// 고칠 수 있는 것은 **표시 이름 하나뿐**이다 — 이메일과 로그인 방법은
// 로그인 제공자(Google)가 정하는 값이라 앱이 바꿀 수 없다.
//
// 회원 탈퇴는 여기 두지 않는다. 로비 하단 줄에 그대로 있다 — 되돌릴 수 없는
// 행동이라 문을 늘리지 않는다.
// ════════════════════════════════════════════════════════════════════

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '/auth/firebase_auth/auth_util.dart';

const Color _kSheetBg = Color(0xFF222222);
const Color _kRowBg = Colors.black;
const Color _kAccent = Color(0xFF22D3EE);

/// 로그인 방법을 사람 말로 옮긴다. 제공자 id는 Firebase가 정한 값이다.
String describeSignInMethod(User? user) {
  if (user == null) return '로그인 안 됨';
  if (user.isAnonymous) return '게스트 (체험)';
  final ids = user.providerData.map((p) => p.providerId).toList();
  if (ids.isEmpty) return '알 수 없음';
  return ids
      .map((id) {
        switch (id) {
          case 'google.com':
            return 'Google';
          case 'apple.com':
            return 'Apple';
          case 'password':
            return '이메일 · 비밀번호';
          case 'phone':
            return '전화번호';
          default:
            return id;
        }
      })
      .toSet()
      .join(' · ');
}

/// 👤 등록 정보를 아래에서 올라오는 시트로 연다.
void showAccountSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const _AccountSheet(),
  );
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet();

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: currentUserDisplayName);
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 표시 이름을 고친다. **두 곳에 함께 쓴다** — Firebase Auth 프로필과
  /// `users/{uid}` 문서. 한쪽만 쓰면 화면마다 다른 이름이 뜬다.
  Future<void> _saveDisplayName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('이름을 입력해 주세요.');
      return;
    }
    if (name == currentUserDisplayName) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      await currentUserReference?.update(<String, dynamic>{
        'display_name': name,
      });
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      _toast('이름을 바꿨습니다.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('바꾸지 못했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: const Color(0xFF2C2C2E),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final createdAt = user?.metadata.creationTime;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: _kSheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('등록 정보',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 20),

          // ── 프로필 + 표시 이름 ──
          Row(
            children: [
              _avatar(),
              const SizedBox(width: 14),
              Expanded(
                child: _editing ? _nameField() : _nameDisplay(),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── 로그인 정보 (바꿀 수 없는 것들) ──
          _infoRow(Icons.mail_outline_rounded, '이메일',
              currentUserEmail.isEmpty ? '-' : currentUserEmail),
          const SizedBox(height: 8),
          _infoRow(
              Icons.vpn_key_outlined, '로그인 방법', describeSignInMethod(user)),
          const SizedBox(height: 8),
          _infoRow(
            Icons.event_outlined,
            '가입일',
            createdAt == null
                ? '-'
                : DateFormat('yyyy.MM.dd').format(createdAt.toLocal()),
          ),
          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _saving ? null : _signOut,
              icon: const Icon(Icons.logout_rounded, size: 18),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white60,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              label: const Text('로그아웃'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() {
    final photo = currentUserPhoto;
    if (photo.isNotEmpty) {
      return CircleAvatar(radius: 26, backgroundImage: NetworkImage(photo));
    }
    final name = currentUserDisplayName.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 26,
      backgroundColor: _kAccent.withValues(alpha: 0.18),
      child: Text(initial,
          style: const TextStyle(
              color: _kAccent, fontSize: 20, fontWeight: FontWeight.bold)),
    );
  }

  Widget _nameDisplay() {
    final name = currentUserDisplayName.trim();
    return Row(
      children: [
        Expanded(
          child: Text(
            name.isEmpty ? '이름 없음' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: name.isEmpty ? Colors.white38 : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: '이름 바꾸기',
          icon: const Icon(Icons.edit_outlined, color: _kAccent, size: 19),
          onPressed: () => setState(() => _editing = true),
        ),
      ],
    );
  }

  Widget _nameField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _nameController,
            autofocus: true,
            enabled: !_saving,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              isDense: true,
              hintText: '표시할 이름',
              hintStyle: const TextStyle(color: Colors.white24),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: _kRowBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kAccent),
              ),
            ),
            onSubmitted: (_) => _saveDisplayName(),
          ),
        ),
        const SizedBox(width: 6),
        _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: _kAccent))
            : IconButton(
                tooltip: '저장',
                icon: const Icon(Icons.check_rounded, color: _kAccent),
                onPressed: _saveDisplayName,
              ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kRowBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 17),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    navigator.pop();
  }
}
