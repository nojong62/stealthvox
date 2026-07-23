import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_util.dart';

import '../chat_history_master.dart';
import 'trial_flow_state.dart';
import 'trial_signup_sheet.dart';
import 'trial_study_timer_overlay.dart';

class TrialStudyPage extends StatefulWidget {
  const TrialStudyPage({super.key, required this.historyRef});

  final DocumentReference historyRef;

  @override
  State<TrialStudyPage> createState() => _TrialStudyPageState();
}

class _TrialStudyPageState extends State<TrialStudyPage>
    with WidgetsBindingObserver {
  bool _leftAppWhileInStudy = false;
  bool _isLeavingForAuth = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _goToAuthIntro() {
    if (!mounted || _isLeavingForAuth) return;
    _isLeavingForAuth = true;
    context.goNamed('Intro');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _leftAppWhileInStudy = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _leftAppWhileInStudy) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToAuthIntro());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToAuthIntro();
      },
      child: Scaffold(
        body: Stack(
          children: [
            ChatHistoryMaster(historyDoc: widget.historyRef),
            TrialStudyTimerOverlay(
              durationSeconds: 120,
              onTimeUp: () {
                TrialFlowState.instance.advanceTo(4);
                // trialCompleted trigger moved to routine_mode_anyone.dart (Anyone 1-min timer natural expiry)
                // see: fix/trial-completed-trigger-point branch
                TrialSignupSheet.show(
                  context,
                  onLoginSuccess: () {
                    TrialFlowState.instance.reset();
                    context.pushReplacementNamed('Lobby');
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
