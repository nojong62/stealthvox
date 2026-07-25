import 'package:cloud_functions/cloud_functions.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'realtime_app_check.dart';

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
  }) async {
    await RealtimeAppCheck.initialize(debugProvider: debugAppCheck);
    final packageInfo = await PackageInfo.fromPlatform();
    final callable = _functions.httpsCallable('createRealtimeClientSecret');
    final result = await callable.call(<String, dynamic>{
      'mode': mode,
      'appVersion': packageInfo.version,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final value = data['value']?.toString() ?? '';
    if (value.isEmpty) {
      throw StateError('Realtime client secret response was empty.');
    }
    return RealtimeClientSecret(
      value: value,
      expiresAt: (data['expires_at'] as num?)?.toInt() ?? 0,
    );
  }
}
