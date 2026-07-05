import 'package:flutter/material.dart';
import '/flutter_flow/flutter_flow_util.dart';

import '../chat_history_master.dart';
import 'trial_flow_state.dart';
import 'trial_signup_sheet.dart';
import 'trial_study_timer_overlay.dart';

class TrialStudyPage extends StatelessWidget {
  const TrialStudyPage({super.key, required this.historyRef});

  final DocumentReference historyRef;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ChatHistoryMaster(historyDoc: historyRef),
          TrialStudyTimerOverlay(
            durationSeconds: 120,
            onTimeUp: () {
              TrialFlowState.instance.advanceTo(4);
              TrialFlowState.instance.requestSignupOnEntry();
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
    );
  }
}
