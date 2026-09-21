import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '/custom_code/services/app_update_policy.dart';

/// 모든 라우트 위에서 동작하는 앱 업데이트 게이트.
///
/// 권장 업데이트의 "나중에" 상태는 이 State에만 보관하므로 앱을 완전히
/// 종료했다가 다시 실행하면 다시 안내할 수 있다.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.decision,
    required this.child,
  });

  final AppUpdateDecision decision;
  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  bool _recommendedDismissedForSession = false;

  Future<void> _openStore() async {
    final uri = Uri.parse(widget.decision.storeUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final requirement = widget.decision.requirement;
    final visible = requirement == AppUpdateRequirement.required ||
        (requirement == AppUpdateRequirement.recommended &&
            !_recommendedDismissedForSession);
    if (!visible) return widget.child;

    final isRequired = requirement == AppUpdateRequirement.required;
    return PopScope(
      canPop: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          const ModalBarrier(dismissible: false, color: Colors.black54),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Material(
                  color: Colors.transparent,
                  child: AlertDialog(
                    backgroundColor: const Color(0xFF1C1C1E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text(
                      '업데이트 안내',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    content: Text(
                      widget.decision.message,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      if (!isRequired)
                        TextButton(
                          onPressed: () => setState(
                            () => _recommendedDismissedForSession = true,
                          ),
                          child: const Text(
                            '나중에',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                      TextButton(
                        onPressed: _openStore,
                        child: const Text(
                          '업데이트',
                          style: TextStyle(
                            color: Color(0xFF0A84FF),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
