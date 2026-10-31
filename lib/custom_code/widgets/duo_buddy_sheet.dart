// ════════════════════════════════════════════════════════════════════
// 🤝 [DUO BUDDY] 계정정보 → Duo 버디 신청·그만두기
// --------------------------------------------------------------------
// Duo 버디(서버 이름 talk host)는 여러 사람과 대화하고 싶어 스스로 신청한
// 회원이다. 게시판에는 일반 글과 똑같이 보인다(배지 없음).
//
// 신청은 두 단계다: ① 하루 평균 대화할 수 있는 시간 → ② 건전 대화 서약 동의.
// 저장은 서버 callable(setDuoTalkHost)만 한다. 관리자 웹이 해제한 계정은
// 다시 켤 수 없다.
// ════════════════════════════════════════════════════════════════════

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '/custom_code/services/duo_board_service.dart';
import '/custom_code/services/duo_buddy_localization.dart';

const Color _kSheetBg = Color(0xFF222222);
const Color _kAccent = Color(0xFF52D4C3);

Future<void> showDuoBuddySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DuoBuddySheet(),
  );
}

class _DuoBuddySheet extends StatefulWidget {
  const _DuoBuddySheet();

  @override
  State<_DuoBuddySheet> createState() => _DuoBuddySheetState();
}

class _DuoBuddySheetState extends State<_DuoBuddySheet> {
  final DuoBuddyCopy copy = DuoBuddyCopy.forSystemLocale();
  DuoBuddyStatus? _status;
  int _hours = 2;
  bool _pledgeStep = false;
  bool _agreed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    DuoBoardService.fetchBuddyStatus().then((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  Future<void> _save({required bool enabled}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DuoBoardService.setBuddy(
          enabled: enabled, dailyHours: _hours, pledge: _agreed);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.pop(context);
      messenger?.showSnackBar(SnackBar(
          content: Text(enabled ? copy['buddyJoined'] : copy['buddyLeft'])));
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map ? details['reason']?.toString() : null;
      if (mounted) {
        setState(() {
          _saving = false;
          _error = reason == 'talk_host_admin_disabled'
              ? copy['buddyAdminDisabled']
              : copy['buddyFailed'];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = copy['buddyFailed'];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Container(
      decoration: const BoxDecoration(
        color: _kSheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.record_voice_over_rounded, color: _kAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      _pledgeStep ? copy['pledgeTitle'] : copy['buddyTitle'],
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 10),
              if (status == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (status.adminDisabled)
                _note(copy['buddyAdminDisabled'])
              else if (status.active)
                ..._activeView(status)
              else if (_pledgeStep)
                ..._pledgeView()
              else
                ..._introView(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(color: Color(0xFFFCA5A5))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _note(String text) => Text(text,
      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5));

  List<Widget> _activeView(DuoBuddyStatus status) => [
        Text(copy.fill('buddyOn', {'n': '${status.dailyHours}'}),
            style: const TextStyle(
                color: _kAccent, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _note(copy['buddyIntro']),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _saving ? null : () => _save(enabled: false),
            style: TextButton.styleFrom(foregroundColor: Colors.white60),
            child: Text(copy['buddyLeave']),
          ),
        ),
      ];

  List<Widget> _introView() => [
        _note(copy['buddyIntro']),
        const SizedBox(height: 16),
        Text(copy['buddyHoursLabel'],
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hours in DuoBoardService.buddyHourChoices)
              ChoiceChip(
                label: Text(copy.hours(hours)),
                selected: _hours == hours,
                onSelected: (_) => setState(() => _hours = hours),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => _pledgeStep = true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D8F83),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(copy['buddyNext']),
          ),
        ),
      ];

  List<Widget> _pledgeView() => [
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$i.',
                    style: const TextStyle(
                        color: _kAccent, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Expanded(child: _note(copy['pledge$i'])),
              ],
            ),
          ),
        CheckboxListTile(
          value: _agreed,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: _kAccent,
          onChanged: (value) => setState(() => _agreed = value == true),
          title: Text(copy['pledgeAgree'],
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _agreed && !_saving ? () => _save(enabled: true) : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D8F83),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(copy['buddyJoin']),
          ),
        ),
      ];
}
