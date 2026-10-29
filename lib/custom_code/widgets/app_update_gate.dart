import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '/custom_code/services/app_update_policy.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/services/origin_surface_localization.dart';

/// 모든 라우트 위에서 동작하는 앱 Update 게이트.
///
/// 권장 Update의 "Later" 상태는 이 State에만 보관하므로 앱을 완전히
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
  // Play가 "새 버전 있음"이라고 답한 경우. Remote Config 값을 올리지 않아도
  // 상위 버전이 나오면 권장 Update로 안내한다.
  bool _playUpdateAvailable = false;

  OriginSurfaceCopy get _copy =>
      OriginSurfaceCopy.forSystemLocale();

  @override
  void initState() {
    super.initState();
    _checkPlayUpdate();
  }

  Future<void> _checkPlayUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (!mounted) return;
      if (info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.immediateUpdateAllowed) {
        setState(() => _playUpdateAvailable = true);
      }
    } catch (_) {
      // Play 설치본이 아니거나 Play 서비스를 못 쓰면 조용히 넘어간다.
    }
  }

  Future<void> _update() async {
    if (_playUpdateAvailable) {
      try {
        final result = await InAppUpdate.performImmediateUpdate();
        if (result == AppUpdateResult.success) return;
        if (result == AppUpdateResult.userDeniedUpdate) return;
      } catch (_) {
        // 아래 스토어 열기로 넘어간다.
      }
    }
    await _openStore();
  }

  Future<void> _openStore() async {
    var opened = false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        opened = await launchUrl(
          Uri.parse('market://details?id=com.aienglishpractice.stealthvox'),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        opened = false;
      }
    }
    if (!opened) {
      try {
        opened = await launchUrl(
          Uri.parse(widget.decision.storeUrl),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_copy['playStoreUnavailable']),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var requirement = widget.decision.requirement;
    if (requirement == AppUpdateRequirement.none && _playUpdateAvailable) {
      requirement = AppUpdateRequirement.recommended;
    }
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
                    title: Text(
                      _copy['updateAvailable'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    content: Text(
                      _copy['updateMessage'],
                      style: const TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      if (!isRequired)
                        TextButton(
                          onPressed: () => setState(
                            () => _recommendedDismissedForSession = true,
                          ),
                          child: Text(
                            _copy['later'],
                            style: const TextStyle(color: Colors.white60),
                          ),
                        ),
                      TextButton(
                        onPressed: _update,
                        child: Text(
                          _copy['update'],
                          style: const TextStyle(
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
