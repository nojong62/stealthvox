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

/// 🔥 [RT-PREWARM] client secret만 미리 받아두는 캐시.
///
/// Anyone 진입 시 6.6초 중 3.2초가 secret 발급에 쓰인다. StealthRoom 메뉴를
/// 보는 동안 미리 받아두면 그만큼 줄어든다. 여기서는 토큰 문자열만 들고 있을 뿐
/// 마이크를 켜거나 WebRTC를 열지 않으므로, 쓰지 않고 버려도 정리할 자원도
/// 과금도 없다. 다만 secret에는 만료 시각이 있어 쓰기 직전에 반드시 확인한다.
class RealtimeClientSecretPrewarm {
  RealtimeClientSecretPrewarm._();

  static final RealtimeClientSecretPrewarm instance =
      RealtimeClientSecretPrewarm._();

  /// 남은 유효시간이 이보다 짧으면 쓰지 않고 새로 받는다. 발급 후 연결까지의
  /// 시간(SDP/ICE 약 2.6초)을 견디도록 여유를 둔다.
  static const int _minRemainingSeconds = 30;

  final Map<String, RealtimeClientSecret> _cache =
      <String, RealtimeClientSecret>{};
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  Future<void> prewarm({
    required String mode,
    RealtimeClientSecretService? service,
    RealtimeLogger? logger,
  }) {
    if (_inFlight.containsKey(mode)) return _inFlight[mode]!;
    if (_isUsable(_cache[mode])) return Future<void>.value();
    final task = () async {
      try {
        final secret = await (service ?? RealtimeClientSecretService())
            .create(mode: mode, logger: logger);
        _cache[mode] = secret;
        logger?.call('[RT-PREWARM]', 'secret_ready mode=$mode');
      } catch (error) {
        // 실패해도 무해하다. 진입 시 기존 경로가 그대로 새로 발급한다.
        logger?.call('[RT-PREWARM]', 'secret_failed reason=${error.runtimeType}');
      } finally {
        _inFlight.remove(mode);
      }
    }();
    _inFlight[mode] = task;
    return task;
  }

  /// 유효한 secret이 있으면 꺼내 쓰고 캐시에서 제거한다. 없거나 만료가 임박하면
  /// null — 호출자는 평소대로 새로 발급하면 된다.
  RealtimeClientSecret? take(String mode, {RealtimeLogger? logger}) {
    final cached = _cache.remove(mode);
    if (cached == null) return null;
    if (!_isUsable(cached)) {
      logger?.call('[RT-PREWARM]', 'secret_expired mode=$mode → 새로 발급');
      return null;
    }
    logger?.call('[RT-PREWARM]', 'secret_reused mode=$mode');
    return cached;
  }

  void clear() => _cache.clear();

  bool _isUsable(RealtimeClientSecret? secret) {
    if (secret == null || secret.value.isEmpty) return false;
    if (secret.expiresAt <= 0) return false;
    final remaining =
        secret.expiresAt - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return remaining >= _minRemainingSeconds;
  }
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
      ).timeout(const Duration(seconds: 8));
      logger?.call('[RT-APPCHECK]', 'success');
    } catch (e) {
      logger?.call('[RT-APPCHECK]', 'failed reason=${e.runtimeType}');
      rethrow;
    }
    final packageInfo = await PackageInfo.fromPlatform()
        .timeout(const Duration(seconds: 5));
    final callable = _functions.httpsCallable('createRealtimeClientSecret');
    final Map<String, dynamic> data;
    try {
      final result = await callable
          .call(<String, dynamic>{
            'mode': mode,
            'appVersion': packageInfo.version,
          })
          .timeout(const Duration(seconds: 10));
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
