import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_invite_localization.dart';

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

    test('a newly posted topic records the host Origin language', () {
      expect(board,
          contains('final originLanguage = widget.directLanguage.trim()'));
      expect(board, contains('topicLanguage: originLanguage'));
      expect(board, contains('? duoBoardViewerLanguage()'));
    });

    // 2026-10-13: the composer disposed its controller as soon as the sheet
    // future returned, while the closing sheet still rebuilt the TextField —
    // red screen right after a successful publish.
    test('composer controller is disposed with the sheet, not after its future',
        () {
      final start = board.indexOf('Future<bool> showDuoBoardComposer(');
      final end = board.indexOf('\n}\n', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final launcher = board.substring(start, end);
      expect(launcher, isNot(contains('.dispose()')));
      expect(launcher, isNot(contains('TextEditingController')));
      expect(board, contains('void dispose() {\n    topic.dispose();'));
      expect(board, contains("debugPrint('[DuoBoard] post published: \$postId');"));
    });

    test('restore-post dialog is translated for every supported language', () {
      const languages = <String>[
        'Korean',
        'Japanese',
        'Chinese',
        'Spanish',
        'French',
        'German',
        'Hindi',
        'Russian',
        'Portuguese',
        'Italian',
        'Dutch',
      ];
      const keys = <String>[
        'restorePostTitle',
        'restorePostBody',
        'continuePost',
        'endPost',
      ];
      final english = DuoInviteCopy.forLanguage('English');

      for (final language in languages) {
        final copy = DuoInviteCopy.forLanguage(language);
        for (final key in keys) {
          expect(
            copy[key],
            isNot(equals(english[key])),
            reason: '$language must provide its own $key translation',
          );
        }
      }
    });
  });
}
