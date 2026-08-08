import 'package:firebase_auth/firebase_auth.dart';

import '/flutter_flow/flutter_flow_util.dart';

class TrialFlowState {
  TrialFlowState._();

  static final TrialFlowState instance = TrialFlowState._();

  DocumentReference? myHistoryRef;
  int step = 0;

  /// 체험 상태는 익명 유저에게만 유효하다.
  ///
  /// `step`은 SharedPreferences(`ff_trialStep`)에 저장되는 **기기 값**이라
  /// 로그아웃해도 지워지지 않는다. 체험을 1분 완주하지 못하고 나가면 step=1이
  /// 그대로 남고, 그 뒤 정식 회원으로 로그인하면 아래가 전부 오작동했다.
  ///
  ///   · StealthRoom이 메뉴를 건너뛰고 서클톡으로 바로 들어감
  ///   · 서클톡이 60초 체험 타이머를 걸어 1분 만에 방이 닫힘
  ///   · 대화가 남의 체험 문서(`myHistoryRef`)에 쌓임
  ///   · `isTrial`이 true라 과금 티커가 안 돌아 유료 시간이 안 깎임
  ///
  /// 체험 진입(`intro_master._enterTrialAnyone`)은 익명 로그인이 끝난 뒤에만
  /// 일어나므로, 익명 여부로 거르면 정상 체험은 그대로 살아 있다.
  bool get _isAnonymousUser {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && user.isAnonymous;
  }

  bool get isTrial => _isAnonymousUser && step > 0 && step < 4;
  bool get isTrialAnyone => _isAnonymousUser && step == 1;
  bool get isTrialStudy => _isAnonymousUser && (step == 2 || step == 3);

  void saveToAppState() {
    FFAppState().trialStep = step;
    final ref = myHistoryRef;
    if (ref != null) {
      FFAppState().trialHistoryPath = ref.path;
    }
  }

  void restoreFromAppState() {
    step = FFAppState().trialStep;
    final path = FFAppState().trialHistoryPath;
    if (path.isNotEmpty) {
      myHistoryRef = FirebaseFirestore.instance.doc(path);
    }
  }

  void reset() {
    step = 0;
    myHistoryRef = null;
    FFAppState().trialStep = 0;
    FFAppState().trialHistoryPath = '';
  }

  void advanceTo(int newStep) {
    step = newStep;
    saveToAppState();
  }
}
