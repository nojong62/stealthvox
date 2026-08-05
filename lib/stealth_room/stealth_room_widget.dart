import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import '/custom_code/widgets/index.dart' as custom_widgets;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'stealth_room_model.dart';
export 'stealth_room_model.dart';

class StealthRoomWidget extends StatefulWidget {
  const StealthRoomWidget({
    super.key,
    required this.historyRef,
    this.roomId,
  });

  final DocumentReference? historyRef;
  final String? roomId;

  static String routeName = 'StealthRoom';
  static String routePath = '/stealthRoom';

  @override
  State<StealthRoomWidget> createState() => _StealthRoomWidgetState();
}

class _StealthRoomWidgetState extends State<StealthRoomWidget> {
  late StealthRoomModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => StealthRoomModel());

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
        body: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // ⌨️ 예전에는 여기에 화면 전체 높이를 고정으로 박아 뒀다. 자판이
            //    올라오면 Scaffold는 body를 그만큼 줄이는데 이 칸만 전체 높이를
            //    고집해서, 설정 페이지에서 글자를 입력할 때 아래가 넘쳤다.
            //    남는 만큼만 쓰게 두면 자판이 뜬 높이와 저절로 맞는다.
            Expanded(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 1.0,
                child: custom_widgets.StealthRoomMaster(
                  width: MediaQuery.sizeOf(context).width * 1.0,
                  height: MediaQuery.sizeOf(context).height * 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
