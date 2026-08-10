// ====================================================================
// 🔥 [REALTIME-STT PREWARM] 방에 들어가기 전에 전사 소켓을 미리 열어 둔다
// --------------------------------------------------------------------
// DeepgramPrewarmSession과 같은 자리, 같은 역할이다. 없으면 첫 발화에
// WebSocket 핸드셰이크 + session.update 왕복이 그대로 얹힌다.
//
// 비용: 이 단계에서 나가는 건 세션 설정뿐이다. 오디오를 한 바이트도 보내지
// 않으므로 채택하지 못하고 버려도 전사 과금은 0이다.
// ====================================================================

import 'dart:async';

import 'openai_realtime_transcribe_session.dart';

class OpenAiRealtimePrewarmSession {
  OpenAiRealtimePrewarmSession._();

  static final OpenAiRealtimePrewarmSession instance =
      OpenAiRealtimePrewarmSession._();

  OpenAiRealtimeTranscribeSession? _session;
  String _apiKey = '';
  String _languageCode = '';
  Future<bool>? _preparing;

  /// 너무 오래 묵은 소켓은 채택하지 않는다. 서버가 유휴 연결을 닫아 두면
  /// 마이크를 붙인 직후 죽어서, 새로 연결하는 것보다 나쁘다.
  static const Duration _maxAdoptableAge = Duration(seconds: 45);

  Future<bool> prepare({
    required String apiKey,
    required String languageCode,
    void Function(String tag, String msg)? onLog,
  }) {
    if (apiKey.isEmpty) return Future<bool>.value(false);
    final existing = _session;
    if (existing != null &&
        existing.isConnected &&
        _apiKey == apiKey &&
        _languageCode == languageCode) {
      return Future<bool>.value(true);
    }
    final inFlight = _preparing;
    if (inFlight != null &&
        _apiKey == apiKey &&
        _languageCode == languageCode) {
      return inFlight;
    }

    _apiKey = apiKey;
    _languageCode = languageCode;
    final future = _prepareInternal(
      apiKey: apiKey,
      languageCode: languageCode,
      onLog: onLog,
    );
    _preparing = future;
    return future.whenComplete(() {
      if (identical(_preparing, future)) _preparing = null;
    });
  }

  Future<bool> _prepareInternal({
    required String apiKey,
    required String languageCode,
    void Function(String tag, String msg)? onLog,
  }) async {
    await discard(reason: 'replace');
    final session = OpenAiRealtimeTranscribeSession(
      apiKey: apiKey,
      languageCode: languageCode,
      onLog: onLog,
    );
    final ok = await session.connect();
    if (!ok) {
      await session.dispose();
      onLog?.call('🔥 [RT-PREWARM]', 'failed lang=$languageCode');
      return false;
    }
    _session = session;
    _apiKey = apiKey;
    _languageCode = languageCode;
    onLog?.call('🔥 [RT-PREWARM]', 'ready lang=$languageCode');
    return true;
  }

  /// 예열된 세션을 넘긴다. 조건이 안 맞으면 null — 호출부가 새로 연결한다.
  OpenAiRealtimeTranscribeSession? take({
    required String apiKey,
    required String languageCode,
    void Function(String tag, String msg)? onLog,
  }) {
    if (_apiKey != apiKey || _languageCode != languageCode) return null;
    final session = _session;
    if (session == null) return null;
    if (!session.isConnected) {
      onLog?.call('🔥 [RT-PREWARM]', 'stale reason=closed → fresh connect');
      _session = null;
      unawaited(session.dispose());
      return null;
    }
    if (session.age >= _maxAdoptableAge) {
      onLog?.call('🔥 [RT-PREWARM]',
          'stale ageMs=${session.age.inMilliseconds} → fresh connect');
      _session = null;
      unawaited(session.dispose());
      return null;
    }
    _session = null;
    onLog?.call('🔥 [RT-PREWARM]', 'adopted lang=$languageCode');
    return session;
  }

  Future<void> discard({String reason = 'discard'}) async {
    final session = _session;
    _session = null;
    if (session != null) await session.dispose();
  }
}
