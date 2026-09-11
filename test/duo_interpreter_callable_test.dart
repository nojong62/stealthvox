import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_interpreter_callable.dart';

void main() {
  test('submits only immutable callable payload fields', () async {
    Map<String, dynamic>? payload;
    final client = DuoInterpreterCallableClient(
      invoker: (value) async {
        payload = value;
        return <String, dynamic>{'utteranceId': 'u1', 'seq': 7, 'status': 'processing'};
      },
    );
    final result = await client.submit(
      roomId: 'r', utteranceId: 'u1', sourceText: 'hello',
    );
    expect(result['seq'], 7);
    expect(payload, <String, dynamic>{'roomId': 'r', 'utteranceId': 'u1', 'sourceText': 'hello'});
  });

  test('rejects malformed callable response', () async {
    final client = DuoInterpreterCallableClient(
      invoker: (_) async => 'bad',
    );
    expect(() => client.submit(roomId: 'r', utteranceId: 'u', sourceText: 'x'), throwsStateError);
  });
}
