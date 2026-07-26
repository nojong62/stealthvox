import 'dart:async';

import 'realtime_client_secret_service.dart';
import 'stealth_vox_realtime_session.dart';

/// Small mode adapter for Anyone. UI and persistence stay outside transport.
class RealtimeAnyoneAdapter {
  RealtimeAnyoneAdapter({
    this.onUserTranscript,
    this.onAssistantTranscript,
    this.onResponseDone,
    this.onError,
    this.logger,
  });

  final void Function(String text)? onUserTranscript;
  final void Function(String text)? onAssistantTranscript;
  final VoidCallback? onResponseDone;
  final void Function(Object error)? onError;
  final RealtimeLogger? logger;

  late final StealthVoxRealtimeSession session =
      StealthVoxRealtimeSession(logger: logger);
  StreamSubscription<RealtimeSessionEvent>? _subscription;
  String _userText = '';
  String _assistantText = '';

  Future<void> start({required String modeSessionId}) async {
    _subscription = session.events.listen(_onEvent);
    await session.connect(
      mode: 'anyone',
      modeSessionId: modeSessionId,
      instructions:
          'You are a friendly English conversation partner. Speak naturally, '
          'keep replies concise, and wait for the user turn.',
    );
  }

  void requestResponse() => session.requestResponse();

  void cancelResponse() => session.cancelResponse();

  // ── B안: 턴 단위 번역 API (유저 발화 번역 텍스트+음성 구간 전용) ──────────
  // AI 클론 응답/과금/History는 여전히 어댑터 밖(기존 파이프라인)에서 처리한다.

  /// Connects the shared secure WebRTC session in text-driven mode for Anyone:
  /// no microphone track and server VAD disabled, so turns are driven purely by
  /// [requestTranslatedTurn] (Deepgram still owns the real microphone).
  Future<void> connectForTranslation({
    required String modeSessionId,
    String voice = 'marin',
    bool allowWhenDisabled = false,
  }) async {
    await session.connect(
      mode: 'anyone',
      modeSessionId: modeSessionId,
      voice: voice,
      allowWhenDisabled: allowWhenDisabled,
      captureMicrophone: false,
      disableServerVad: true,
    );
  }

  /// Requests one translation turn on the connected session.
  /// [suppressAudio] true → text-only draft (first-turn GPT-4.1 review).
  RealtimeTranslationTurn requestTranslatedTurn({
    required String turnId,
    required String sourceText,
    required String instructions,
    String voice = 'marin',
    bool suppressAudio = false,
  }) {
    return session.requestTranslatedTurn(
      turnId: turnId,
      sourceText: sourceText,
      instructions: instructions,
      voice: voice,
      suppressAudio: suppressAudio,
    );
  }

  void cancelActiveTurn() => session.cancelActiveTurn();

  Future<void> dispose() async {
    await _subscription?.cancel();
    await session.dispose();
  }

  void _onEvent(RealtimeSessionEvent event) {
    if (event.type == RealtimeEventType.error) {
      onError?.call(event.payload?['error'] ?? StateError('Realtime error'));
      return;
    }
    if (event.type != RealtimeEventType.serverEvent) return;
    final payload = event.payload;
    if (payload == null) return;
    final type = payload['type']?.toString() ?? '';
    final delta = payload['delta']?.toString() ?? '';
    if (delta.isNotEmpty &&
        (type.contains('input_audio_transcription') ||
            type == 'conversation.item.input_audio_transcription.delta')) {
      _userText += delta;
      onUserTranscript?.call(_userText);
    } else if (delta.isNotEmpty &&
        (type.contains('audio_transcript') ||
            type.contains('output_text'))) {
      _assistantText += delta;
      onAssistantTranscript?.call(_assistantText);
    }
    if (type == 'conversation.item.input_audio_transcription.completed') {
      final text = payload['transcript']?.toString() ?? _userText;
      if (text.isNotEmpty) {
        _userText = text;
        onUserTranscript?.call(text);
      }
    }
    if (type == 'response.audio_transcript.done' ||
        type == 'response.output_audio_transcript.done' ||
        type == 'response.done') {
      final text = payload['transcript']?.toString();
      if (text != null && text.isNotEmpty) {
        _assistantText = text;
        onAssistantTranscript?.call(text);
      }
    }
    if (type == 'response.done') {
      onResponseDone?.call();
      _userText = '';
      _assistantText = '';
    }
  }
}

typedef VoidCallback = void Function();
