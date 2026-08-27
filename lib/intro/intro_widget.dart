import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/custom_code/widgets/index.dart' as custom_widgets;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'intro_model.dart';
export 'intro_model.dart';

class IntroWidget extends StatefulWidget {
  const IntroWidget({
    super.key,
    this.roomId,
  });

  final String? roomId;

  static String routeName = 'Intro';
  static String routePath = '/intro';

  @override
  State<IntroWidget> createState() => _IntroWidgetState();
}

class _IntroWidgetState extends State<IntroWidget> {
  late IntroModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => IntroModel());

    WidgetsBinding.instance.addPostFrameCallback((_) => safeSetState(() {}));
  }

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        resizeToAvoidBottomInset: false,
        body: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // ⌨️ 화면 전체 높이를 박지 않는다. Scaffold body는 상태바와
            //    자판만큼 줄어드는데 이 칸만 전체 높이를 고집하면 아래가
            //    넘친다(실기기: 로비에서 배율과 무관하게 상시 25px 초과,
            //    2026-08-27). stealth_room_widget.dart이 쓰는 것과 같은 모양.
            Expanded(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 1.0,
                child: custom_widgets.IntroMaster(
                  width: MediaQuery.sizeOf(context).width * 1.0,
                  height: MediaQuery.sizeOf(context).height * 1.0,
                  roomId: widget!.roomId,
                  primaryColor: FlutterFlowTheme.of(context).secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
