import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'realtime_app_check.dart';

/// Structured Realtime log sink. Never pass secrets/tokens/App Check tokens
/// through it — only stage/status strings.
typedef RealtimeLogger = void Function(String tag, String detail);

class RealtimeClientSecret {
  const RealtimeClientSecret({required this.value, required this.expiresAt});

  final String value;
  final int expiresAt;
}

class RealtimeClientSecretService {
  RealtimeClientSecretService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<RealtimeClientSecret> create({
    required String mode,
    bool debugAppCheck = false,
    RealtimeLogger? logger,
  }) async {
    try {
      await RealtimeAppCheck.initialize(
        debugProvider: debugAppCheck || kDebugMode,
      );
      logger?.call('[RT-APPCHECK]', 'success');
    } catch (e) {
      logger?.call('[RT-APPCHECK]', 'failed reason=${e.runtimeType}');
      rethrow;
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final callable = _functions.httpsCallable('createRealtimeClientSecret');
    final Map<String, dynamic> data;
    try {
      final result = await callable.call(<String, dynamic>{
        'mode': mode,
        'appVersion': packageInfo.version,
      });
      data = Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      logger?.call('[RT-SECRET]', 'failed reason=${e.runtimeType}');
      rethrow;
    }
    final value = data['value']?.toString() ?? '';
    if (value.isEmpty) {
      logger?.call('[RT-SECRET]', 'failed reason=empty_response');
      throw StateError('Realtime client secret response was empty.');
    }
    logger?.call('[RT-SECRET]', 'success');
    return RealtimeClientSecret(
      value: value,
      expiresAt: (data['expires_at'] as num?)?.toInt() ?? 0,
    );
  }
}
