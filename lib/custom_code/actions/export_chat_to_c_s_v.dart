// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

// Action Name: exportChatToCSV
// Arguments: chatHistory (List <ChatLine>)

import 'package:universal_io/io.dart'; // ★ dart:io 대체
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';

Future exportChatToCSV(List<dynamic>? chatHistory) async {
  // 웹에서는 파일 공유 불가 -> 중단
  if (kIsWeb || chatHistory == null || chatHistory.isEmpty) return;

  List<List<String>> rows = [];
  rows.add(["Role", "Korean", "English"]);

  for (var item in chatHistory) {
    rows.add([item.role ?? "Unknown", item.textKr ?? "", item.textEn ?? ""]);
  }

  String csvContent = const ListToCsvConverter().convert(rows);
  // 한글 깨짐 방지 BOM 추가
  String finalCsv = '\uFEFF' + csvContent;

  final directory = await getTemporaryDirectory();
  final path = "${directory.path}/stealth_chat.csv";
  final file = File(path);
  await file.writeAsString(finalCsv);

  await Share.shareXFiles([XFile(path)], text: '스텔스룸 대화 기록');
}
