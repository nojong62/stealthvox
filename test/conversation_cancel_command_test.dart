import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/conversation_cancel_command.dart';

void main() {
  group('isConversationCancelCommand', () {
    test('accepts the exact Korean command with common STT punctuation', () {
      expect(isConversationCancelCommand('취소합니다.'), isTrue);
      expect(isConversationCancelCommand(' 취소 합니다! '), isTrue);
      expect(isConversationCancelCommand('“취소합니다”'), isTrue);
    });

    test('does not treat a sentence containing the phrase as a command', () {
      expect(isConversationCancelCommand('이 요청은 취소합니다'), isFalse);
      expect(isConversationCancelCommand('취소해 주세요'), isFalse);
      expect(isConversationCancelCommand('cancel'), isFalse);
    });
  });

  group('removeFromLastUserTurn', () {
    test('removes the latest host and every message after it', () {
      final messages = <Map<String, dynamic>>[
        <String, dynamic>{'role': 'SYSTEM', 'target': 'opener'},
        <String, dynamic>{'role': 'HOST', 'target': 'first'},
        <String, dynamic>{'role': 'SYSTEM', 'target': 'reply'},
        <String, dynamic>{'role': 'HOST_TEMP', 'target': '취소합니다'},
      ];

      expect(removeFromLastUserTurn(messages), isTrue);
      expect(messages, <Map<String, dynamic>>[
        <String, dynamic>{'role': 'SYSTEM', 'target': 'opener'},
      ]);
    });

    test('only clears temporary speech when no prior user turn exists', () {
      final messages = <Map<String, dynamic>>[
        <String, dynamic>{'role': 'SYSTEM', 'target': 'opener'},
        <String, dynamic>{'role': 'HOST_TEMP', 'target': '취소합니다'},
      ];

      expect(removeFromLastUserTurn(messages), isFalse);
      expect(messages.single['role'], 'SYSTEM');
    });
  });
}
