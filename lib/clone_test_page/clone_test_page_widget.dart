import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/custom_code/widgets/index.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'clone_test_page_model.dart';
export 'clone_test_page_model.dart';

class CloneTestPageWidget extends StatefulWidget {
  const CloneTestPageWidget({super.key});

  static String routeName = 'CloneTestPage';
  static String routePath = '/cloneTestPage';

  @override
  State<CloneTestPageWidget> createState() => _CloneTestPageWidgetState();
}

class _CloneTestPageWidgetState extends State<CloneTestPageWidget> {
  late CloneTestPageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => CloneTestPageModel());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<FFAppState>();

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        body: SafeArea(
          top: true,
          child: SizedBox.expand(
            // 🛰️ [PHASE 2] 신규 보안 WebRTC 경로 실기기 연결 검증 진입점.
            child: RealtimeWebrtcProbe(
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }
}
