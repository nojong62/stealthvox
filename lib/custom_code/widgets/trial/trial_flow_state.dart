import 'package:cloud_firestore/cloud_firestore.dart';
import '/flutter_flow/flutter_flow_util.dart';

class TrialFlowState {
  TrialFlowState._();

  static final TrialFlowState instance = TrialFlowState._();

  DocumentReference? myHistoryRef;
  int step = 0;

  bool get isTrial => step > 0 && step < 4;
  bool get isTrialAnyone => step == 1;
  bool get isTrialStudy => step == 2 || step == 3;

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
