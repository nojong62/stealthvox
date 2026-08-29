// ====================================================================
// 🚪 [GUEST-STUDY] 통화가 끝난 게스트가 **방금 한 대화를 보는 자리.**
// --------------------------------------------------------------------
// 예전에는 호스트가 나가도 게스트는 통화 화면에 그대로 남아 있었고, 나가면
// Intro로 튕겨서 방금 나눈 대화를 볼 방법이 없었다. 초대받아 처음 써 본
// 사람에게 남는 마지막 화면이 로그인 창이었다는 뜻이다.
//
// 이제 통화가 끝나면 여기로 온다. **읽는 것은 다 열려 있다** — 비용이 드는
// 학습 기능만 잠긴다(`services/study_access.dart`가 그 판정을 쥔다).
//
// 맛보기 공부방(`trial/trial_study_page.dart`)과 같은 모양이되 5분 타이머가
// 없다. 게스트에게는 시간 제한이 아니라 기능 제한이 걸린다.
// ====================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/flutter_flow/flutter_flow_util.dart';
import 'chat_history_master.dart';

class DuoGuestStudyPage extends StatelessWidget {
  const DuoGuestStudyPage({super.key, required this.historyRef});

  final DocumentReference historyRef;

  @override
  Widget build(BuildContext context) {
    // 뒤로 가면 통화방이 아니라 Intro다. 통화는 이미 끝났고, 그 화면으로
    // 돌아가면 끝난 방에 다시 앉아 있게 된다.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.goNamed('Intro');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: ChatHistoryMaster(historyDoc: historyRef),
      ),
    );
  }
}
