import 'package:cloud_functions/cloud_functions.dart';

const String kDuoInterpreterCallableRegion = 'asia-northeast3';

/// Thin client boundary for the callable transport. The server derives room
/// direction, languages, seq, and status; the client submits only immutable
/// identity plus the accepted transcript.
class DuoInterpreterCallableClient {
  DuoInterpreterCallableClient({
    FirebaseFunctions? functions,
    Future<Object?> Function(Map<String, dynamic> payload)? invoker,
  })  : _functions = functions,
        _invoker = invoker;

  /// ⚠️ **생성자에서 붙잡지 않는다.** 예전에는 여기서 곧바로
  /// `FirebaseFunctions.instanceFor`를 불렀는데, 그러면 [invoker]를 준
  /// 호출부에도 Firebase 초기화가 필요해진다. 이 파일의 테스트가 그것 때문에
  /// `[core/no-app]`으로 죽었다 — 주입구를 만들어 놓고 쓸 수 없게 해 둔
  /// 두 번째 층이었다.
  ///
  /// 실제로 필요한 순간은 [submit]에서 주입구가 없을 때 한 번뿐이다.
  final FirebaseFunctions? _functions;

  FirebaseFunctions get _callableFunctions =>
      _functions ??
      FirebaseFunctions.instanceFor(region: kDuoInterpreterCallableRegion);

  /// 호출을 대신하는 자리. **돌려주는 것은 응답 데이터 그 자체다.**
  ///
  /// 예전에는 `HttpsCallableResult`를 돌려주게 되어 있었는데, 그 타입은
  /// **공개 생성자가 없어서 테스트가 만들 수 없다.** 주입구를 만들어 놓고
  /// 쓸 수 없게 해 둔 셈이라, 이 파일의 테스트가 컴파일조차 안 됐다.
  ///
  /// [submit]이 실제로 쓰는 것도 `result.data` 하나뿐이다. 그래서 감싼 것을
  /// 주고받을 이유가 없다.
  final Future<Object?> Function(Map<String, dynamic> payload)? _invoker;

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
    final Object? raw = _invoker != null
        ? await _invoker!(payload)
        : (await _callableFunctions
                .httpsCallable(
                  'interpretUtterance',
                  options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 90),
                  ),
                )
                .call(payload))
            .data;
    if (raw is! Map) {
      throw StateError('interpretUtterance returned invalid data');
    }
    return Map<String, dynamic>.from(raw);
  }
}
