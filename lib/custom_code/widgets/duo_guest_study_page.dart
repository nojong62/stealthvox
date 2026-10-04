// ====================================================================
// 🚪 [GUEST-STUDY] 통화가 끝난 게스트가 **방금 한 대화를 보는 자리.**
// --------------------------------------------------------------------
// 예전에는 호스트가 나가도 게스트는 통화 화면에 그대로 남아 있었고, 나가면
// Intro로 튕겨서 방금 나눈 대화를 볼 방법이 없었다. 초대받아 처음 써 본
// 사람에게 남는 마지막 화면이 로그인 창이었다는 뜻이다.
//
// 이제 통화가 끝나면 여기로 자동 이동한다. **읽는 것은 다 열려 있고**,
// 익명 초대 게스트에게는 비용이 드는 학습 기능도 이 화면에서만 5분간 연다.
//
// 회원 게스트는 자기 History로 계속 이용한다. 초대 링크로 들어온 익명
// 비회원만 5분 동안 열어 주고, 시간이 끝나면 화면을 잠근 뒤 가입 화면으로
// 보낸다.
// ====================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '/custom_code/services/study_access.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'chat_history_master.dart';
import 'trial/trial_study_timer_overlay.dart';

class DuoGuestStudyPage extends StatelessWidget {
  const DuoGuestStudyPage({super.key, required this.historyRef});

  final DocumentReference historyRef;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final limitedGuestStudy = shouldLimitDuoGuestStudy(
      // 초대 세션인데 인증 복원 타이밍상 user가 잠시 null이어도 비회원
      // 체험으로 제한한다. null을 회원으로 간주하면 5분 제한이 풀릴 수 있다.
      isAnonymous: user == null || user.isAnonymous,
      isGuestSession: FFAppState().isGuestSession,
    );

    // 뒤로 가면 통화방이 아니라 Intro다. 통화는 이미 끝났고, 그 화면으로
    // 돌아가면 끝난 방에 다시 앉아 있게 된다.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.goNamed('Intro');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Stack(
          children: [
            ChatHistoryMaster(
              historyDoc: historyRef,
              allowDuoGuestStudyPreview: limitedGuestStudy,
            ),
            if (limitedGuestStudy)
              TrialStudyTimerOverlay(
                durationSeconds: kDuoAnonymousGuestStudySeconds,
                onTimeUp: () {
                  if (context.mounted) context.goNamed('Intro');
                },
              ),
          ],
        ),
      ),
    );
  }
}
