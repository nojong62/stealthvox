import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File('lib/custom_code/widgets/routine_mode_duo.dart').readAsStringSync();

  test('Duo no longer provides a robot solo practice entry point', () {
    expect(source, isNot(contains('duo_robot.dart')));
    expect(source, isNot(contains('_robot')));
    expect(source, isNot(contains('Duo Robot')));
    expect(source, isNot(contains('Practice alone without a partner')));
    expect(
        File('lib/custom_code/services/duo_robot.dart').existsSync(), isFalse);
  });

  test('Duo requires an actual online partner', () {
    expect(source, contains('_hasConversationPartner => _isPartnerOnline;'));
    expect(source, contains('if (!_isPartnerOnline) return;'));
    expect(source, contains('bool useWebrtcNow = _useWebrtcTransport;'));
    expect(
        source, contains('String get _directSttSource => _useWebrtcTransport'));
  });
}
