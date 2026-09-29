import 'dart:async';

import 'package:http/http.dart' as http;

/// App-lifetime OpenAI connection pool used by latency-sensitive first-turn
/// requests. Keeping one Client alive lets Dart reuse DNS/TLS/HTTP state.
class OpenAiConnectionPool {
  OpenAiConnectionPool._();

  static final OpenAiConnectionPool instance = OpenAiConnectionPool._();

  final http.Client client = http.Client();
  Future<void>? _warmupInFlight;
  DateTime? _lastWarmupAt;

  Future<void> warmUp(
    String apiKey, {
    void Function(String message)? onLog,
  }) {
    if (apiKey.trim().isEmpty) return Future<void>.value();

    final lastWarmupAt = _lastWarmupAt;
    if (lastWarmupAt != null &&
        DateTime.now().difference(lastWarmupAt) <
            const Duration(minutes: 1)) {
      return Future<void>.value();
    }

    final running = _warmupInFlight;
    if (running != null) return running;

    final future = _runWarmUp(apiKey, onLog: onLog);
    _warmupInFlight = future;
    return future.whenComplete(() {
      if (identical(_warmupInFlight, future)) _warmupInFlight = null;
    });
  }

  Future<void> _runWarmUp(
    String apiKey, {
    void Function(String message)? onLog,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('https://api.openai.com/v1/models/gpt-4o-mini'),
      );
      request.headers['Authorization'] = 'Bearer $apiKey';

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 5));
      await response.stream.drain().timeout(const Duration(seconds: 5));
      _lastWarmupAt = DateTime.now();
      onLog?.call(
          '[OPENAI-WARMUP] ready status=${response.statusCode} ${stopwatch.elapsedMilliseconds}ms');
    } catch (error) {
      // Warm-up is opportunistic. First-turn requests retain their normal
      // fallback behavior when the network is unavailable.
      onLog?.call(
          '[OPENAI-WARMUP] skipped ${error.runtimeType} ${stopwatch.elapsedMilliseconds}ms');
    } finally {
      stopwatch.stop();
    }
  }
}
