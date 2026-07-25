import 'dart:async';

import 'stealth_vox_realtime_session.dart';

/// Small mode adapter for Anyone. UI and persistence stay outside transport.
class RealtimeAnyoneAdapter {
  RealtimeAnyoneAdapter({
    this.onUserTranscript,
    this.onAssistantTranscript,
    this.onResponseDone,
    this.onError,
  });

  final void Function(String text)? onUserTranscript;
  final void Function(String text)? onAssistantTranscript;
  final VoidCallback? onResponseDone;
  final void Function(Object error)? onError;

  final StealthVoxRealtimeSession session = StealthVoxRealtimeSession();
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
