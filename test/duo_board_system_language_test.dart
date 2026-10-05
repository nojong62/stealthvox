import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final translation =
      _read('lib/custom_code/services/duo_board_topic_translation.dart');
  final board = _read('lib/custom_code/widgets/duo_board_sheet.dart');

  group('Duo Board public language', () {
    test('viewer language always comes from the phone system locale', () {
      expect(translation,
          contains('duoBoardViewerLanguage() => systemUiLanguageName()'));
      expect(translation, isNot(contains('FFAppState')));
      expect(translation, isNot(contains('app.chatLang')));
    });

    test('a newly posted topic records that same system UI language', () {
      expect(board, contains('topicLanguage: duoBoardViewerLanguage()'));
      expect(board, isNot(contains('topicLanguage: FFAppState')));
    });
  });
}
