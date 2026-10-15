// ====================================================================
// 🎟️ [STUDY-TRIAL] 인트로 "공부방 체험"으로 들어온 사람의 5분 공부방.
// --------------------------------------------------------------------
// 서버(`startStudyTrial`)가 이 사람 계정에 복사해 준 체험 대화 **하나만** 연다.
// Duo 게스트 5분 공부방(`duo_guest_study_page.dart`)과 같은 틀이다.
//
//   · 다른 대화로 옮기는 길은 없다(ChatHistoryMaster.studyTrial).
//   · 이 화면이 떠 있는 동안만 차감이 멈춘다(StudyTrialSession.active).
//     AI 자격은 서버가 같은 5분으로 따로 묶는다.
//   · 시간이 끝나면 Intro로 돌아간다. 같은 폰에서는 다시 체험할 수 없다.
// ====================================================================

import 'package:flutter/material.dart';

import '/custom_code/services/study_access.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'chat_history_master.dart';
import 'study_timer_overlay.dart';

class StudyTrialPage extends StatefulWidget {
  const StudyTrialPage({
    super.key,
    required this.historyRef,
    required this.remainingSeconds,
  });

  final DocumentReference historyRef;

  /// 서버가 잰 남은 시간. 중간에 나갔다 오면 5분보다 짧다.
  final int remainingSeconds;

  @override
  State<StudyTrialPage> createState() => _StudyTrialPageState();
}

class _StudyTrialPageState extends State<StudyTrialPage> {
  @override
  void initState() {
    super.initState();
    StudyTrialSession.active = true;
  }

  @override
  void dispose() {
    StudyTrialSession.active = false;
    super.dispose();
  }

  void _backToIntro() {
    if (mounted) context.goNamed('Intro');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToIntro();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(
          children: [
            ChatHistoryMaster(
              historyDoc: widget.historyRef,
              studyTrial: true,
            ),
            StudyTimerOverlay(
              durationSeconds: widget.remainingSeconds,
              onTimeUp: _backToIntro,
            ),
          ],
        ),
      ),
    );
  }
}
