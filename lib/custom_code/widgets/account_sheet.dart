// ════════════════════════════════════════════════════════════════════
// 👤 [ACCOUNT] Account Info — 로그인 정보와 수정
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
import '/flutter_flow/flutter_flow_util.dart';
import 'lobby_master.dart' show LobbyBrain;

const Color _kSheetBg = Color(0xFF222222);
const Color _kRowBg = Colors.black;
const Color _kAccent = Color(0xFF22D3EE);

/// 로그인 방법을 사람 말로 옮긴다. 제공자 id는 Firebase가 정한 값이다.
String describeSignInMethod(User? user) {
  if (user == null) return 'Not Logged In';
  if (user.isAnonymous) return 'Guest (Trial)';
  final ids = user.providerData.map((p) => p.providerId).toList();
  if (ids.isEmpty) return 'Unknown';
  return ids
      .map((id) {
        switch (id) {
          case 'google.com':
            return 'Google';
          case 'apple.com':
            return 'Apple';
          case 'password':
            return 'Email · Password';
          case 'phone':
            return 'Phone';
          default:
            return id;
        }
      })
      .toSet()
      .join(' · ');
}

/// 👤 Account Info를 아래에서 올라오는 시트로 연다.
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
      _toast('Enter a name.');
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
      _toast('Name updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Unable to update the name. Please try again.');
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
      decoration: const BoxDecoration(
        color: _kSheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      // 📐 [스크롤] 이름을 고치려고 키보드를 올리면 남는 높이가 확 준다.
      //   예전에는 Column 하나뿐이라 갈 곳 없는 내용이 아래로 넘쳤다
      //   (실기기 글자 1.7배에서 15px 초과, 로그아웃 줄이 잘렸다,
      //   2026-08-27). 스크롤을 주면 모자란 만큼 밀어 올려 볼 수 있다.
      //   키보드 높이는 스크롤 안쪽 패딩으로 넣는다 — 바깥에 두면 스크롤
      //   범위가 키보드를 못 넘어간다.
      //
      //   SafeArea(top: false)로 아래 시스템 내비게이션 바를 비켜 준다.
      //   없으면 마지막 줄(로그아웃)이 내비 바에 반쯤 걸쳐 잘려 보인다
      //   (실기기 확인, 2026-08-27). SafeArea는 `padding`을 보므로 키보드가
      //   올라오면 알아서 0이 된다 — 아래 viewInsets와 겹쳐 밀지 않는다.
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text('Account Info',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white54),
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
              _infoRow(Icons.mail_outline_rounded, 'Email',
                  currentUserEmail.isEmpty ? '-' : currentUserEmail),
              const SizedBox(height: 8),
              _infoRow(Icons.vpn_key_outlined, 'Login Method',
                  describeSignInMethod(user)),
              const SizedBox(height: 8),
              _infoRow(
                Icons.event_outlined,
                'Joined',
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
                  label: const Text('Log Out'),
                ),
              ),
            ],
          ),
        ),
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
            name.isEmpty ? 'No Name' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: name.isEmpty ? Colors.white38 : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Change Name',
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
              hintText: 'Display Name',
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
                tooltip: 'Save',
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

  /// 로그아웃하면 **그 화면에 남지 않는다.**
  ///
  /// 예전에는 시트만 닫혔다. 스텔스룸에서 누르면 로그아웃된 채 그대로 방에
  /// 서 있었고, 그 화면은 계정이 있다는 전제로 그려진 자리라 무엇을 눌러도
  /// 앞뒤가 맞지 않았다.
  ///
  /// 가는 곳과 지우는 값은 **로비 하단 줄의 로그아웃과 똑같이** 맞춘다 —
  /// 같은 행동이 자리마다 다르게 끝나면 안 된다. 보유시간 캐시를 함께 비우지
  /// 않으면 다음 사람이 앞 사람의 잔여시간을 잠깐 보게 된다.
  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    FFAppState().remainingTime = 0;
    FFAppState().remainingTimeLoaded = false;
    LobbyBrain.lastSyncedUid = null;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    navigator.pop();
    if (!mounted) return;
    context.goNamed('Intro');
  }
}
