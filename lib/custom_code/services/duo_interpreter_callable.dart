import 'package:cloud_functions/cloud_functions.dart';

const String kDuoInterpreterCallableRegion = 'asia-northeast3';

/// Thin client boundary for the callable transport. The server derives room
/// direction, languages, seq, and status; the client submits only immutable
/// identity plus the accepted transcript.
class DuoInterpreterCallableClient {
  DuoInterpreterCallableClient({
    FirebaseFunctions? functions,
    Future<HttpsCallableResult<dynamic>> Function(Map<String, dynamic> payload)?
        invoker,
  })  : _functions = functions ??
            FirebaseFunctions.instanceFor(
                region: kDuoInterpreterCallableRegion),
        _invoker = invoker;

  final FirebaseFunctions _functions;
  final Future<HttpsCallableResult<dynamic>> Function(
      Map<String, dynamic> payload)? _invoker;

  Future<Map<String, dynamic>> submit({
    required String roomId,
    required String utteranceId,
    required String sourceText,
  }) async {
    final payload = <String, dynamic>{
      'roomId': roomId,
      'utteranceId': utteranceId,
      'sourceText': sourceText,
    };
    final result = _invoker != null
        ? await _invoker!(payload)
        : await _functions
            .httpsCallable(
              'interpretUtterance',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 90),
              ),
            )
            .call(payload);
    final raw = result.data;
    if (raw is! Map) {
      throw StateError('interpretUtterance returned invalid data');
    }
    return Map<String, dynamic>.from(raw);
  }
}
