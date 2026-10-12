import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:stealth_vox/custom_code/actions/billing_ticker.dart';

void main() {
  group('deductRemainingTime HTTP response', () {
    test('accepts a valid callable result', () {
      final response = http.Response('{"result":{"remainingTime":119}}', 200);

      expect(parseDeductRemainingTimeResponse(response), 119);
    });

    test('rejects a non-200 response so pending seconds are retried', () {
      final response = http.Response(
        '{"error":{"message":"temporary failure"}}',
        503,
      );

      expect(
        () => parseDeductRemainingTimeResponse(response),
        throwsStateError,
      );
    });

    test('rejects a successful response without remainingTime', () {
      final response = http.Response('{"result":{}}', 200);

      expect(
        () => parseDeductRemainingTimeResponse(response),
        throwsStateError,
      );
    });

    test('rejects malformed JSON', () {
      final response = http.Response('not-json', 200);

      expect(
        () => parseDeductRemainingTimeResponse(response),
        throwsStateError,
      );
    });
  });
}
