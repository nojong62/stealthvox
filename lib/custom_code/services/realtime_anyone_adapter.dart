import 'dart:async';

import 'realtime_client_secret_service.dart';
import 'stealth_vox_realtime_session.dart';

/// Small mode adapter for Anyone. UI and persistence stay outside transport.
class RealtimeAnyoneAdapter {
  RealtimeAnyoneAdapter({
    this.onUserTranscript,
    this.onUserTranscriptDelta,
    this.onUserTranscriptCompleted,
    this.onSpeechStarted,
    this.onSpeechStopped,
    this.onConnectionStateChanged,
    this.onIceStateChanged,
    this.onAssistantTranscript,
    this.onResponseStarted,
    this.onResponseDone,
    this.onError,
    this.logger,
  });

  final void Function(String text)? onUserTranscript;
  final void Function(
    String itemId,
    String delta,
    String accumulatedText,
  )? onUserTranscriptDelta;
  final void Function(String itemId, String transcript)?
      onUserTranscriptCompleted;
  final void Function(String itemId)? onSpeechStarted;
  final void Function(String itemId)? onSpeechStopped;
  final void Function(RealtimeConnectionState state)? onConnectionStateChanged;
  final void Function(String state)? onIceStateChanged;
  final void Function(String text)? onAssistantTranscript;
  final VoidCallback? onResponseStarted;
  final VoidCallback? onResponseDone;
  final void Function(Object error)? onError;
  final RealtimeLogger? logger;

  late final StealthVoxRealtimeSession session =
      StealthVoxRealtimeSession(logger: logger);
  StreamSubscription<RealtimeSessionEvent>? _subscription;
  String _userText = '';
  String _assistantText = '';
  final Map<String, StringBuffer> _userTranscriptBuffers =
      <String, StringBuffer>{};
  final Set<String> _completedTranscriptItemIds = <String>{};

  Future<void> start({
    required String modeSessionId,
    String circleDescription = '편안한 일상 대화 커뮤니티',
  }) async {
    _ensureEventSubscription();
    await session.connect(
      mode: 'anyone',
      modeSessionId: modeSessionId,
      instructions: 'Participate as a natural member of this circle: '
          '"$circleDescription". Speak concise natural Korean from inside the '
          'community, not as an outside explainer or assistant.',
    );
  }

  /// Connects Anyone to a microphone-publishing Realtime session. Server VAD
  /// produces speech boundaries and final input transcription events, while
  /// automatic assistant responses remain disabled at the transport layer.
  Future<void> connectForMicrophoneTranscription({
    required String modeSessionId,
    String voice = 'marin',
    String mode = 'anyone',
    bool allowWhenDisabled = false,
    String? transcriptionLanguage,
    String transcriptionModel =
        StealthVoxRealtimeSession.kLightTranscriptionModel,

    /// 세션에 한 번만 실리는 역할 지시문. 턴마다 전체 프롬프트를 다시 보내면
    /// 세션이 이미 가진 대화 기억과 경쟁해 문장 감각이 죽는다. 역할은 여기,
    /// 턴에는 상태만 보내는 구성을 위한 것이다. 비워 두면 기존 동작 그대로다.
    String instructions = '',
  }) async {
    _ensureEventSubscription();
    await session.connect(
      mode: mode,
      modeSessionId: modeSessionId,
      voice: voice,
      instructions: instructions,
      allowWhenDisabled: allowWhenDisabled,
      captureMicrophone: true,
      disableServerVad: false,
      transcriptionLanguage: transcriptionLanguage,
      transcriptionModel: transcriptionModel,
    );
  }

  /// 🎧 [RT-TRANSCRIPTION] 첫 발화 뒤 경량 모델로 내릴 때 쓴다.
  void setTranscriptionModel(String model) =>
      session.setTranscriptionModel(model);

  /// 🗣️ [RT-CONV] 음성 직결 대화 모드. 마이크 오디오를 그대로 모델에 보내고,
  /// server VAD가 발화 종료를 감지하면 모델이 곧바로 영어 음성으로 응답한다.
  /// 입력 전사(gpt-4o-mini-transcribe)를 사용하지 않으므로 사용자 원문 텍스트는
  /// 제공되지 않는다.
  Future<void> connectForConversation({
    required String modeSessionId,
    required String instructions,
    String voice = 'marin',
    bool allowWhenDisabled = false,
  }) async {
    _ensureEventSubscription();
    await session.connect(
      mode: 'anyone',
      modeSessionId: modeSessionId,
      voice: voice,
      instructions: instructions,
      allowWhenDisabled: allowWhenDisabled,
      captureMicrophone: true,
      disableServerVad: false,
      autoRespond: true,
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
    String instructions = '',
  }) async {
    _ensureEventSubscription();
    await session.connect(
      mode: 'anyone',
      modeSessionId: modeSessionId,
      voice: voice,
      instructions: instructions,
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

  /// Sends a finalized user transcript to Realtime and receives a spoken
  /// assistant reply. The transport is identical to a text-driven translation
  /// turn, but this name makes the Anyone conversation boundary explicit.
  RealtimeTranslationTurn requestConversationTurn({
    required String turnId,
    required String userText,
    required String instructions,
    String voice = 'marin',
  }) {
    return session.requestTranslatedTurn(
      turnId: turnId,
      sourceText: userText,
      instructions: instructions,
      voice: voice,
    );
  }

  /// 🎙️ [SPEECH-FIRST] 전사 대기 없이, 방금 끝난 유저 발화 오디오로 바로 번역
  /// 음성 턴을 요청한다.
  RealtimeTranslationTurn requestSpeechTranslatedTurn({
    required String turnId,
    required String instructions,
    String voice = 'marin',
  }) {
    return session.requestSpeechTranslationTurn(
      turnId: turnId,
      instructions: instructions,
      voice: voice,
    );
  }

  void cancelActiveTurn() => session.cancelActiveTurn();

  void setMicrophoneEnabled(bool enabled) =>
      session.setMicrophoneEnabled(enabled);

  Future<void> dispose() async {
    await _subscription?.cancel();
    await session.dispose();
  }

  void _ensureEventSubscription() {
    _subscription ??= session.events.listen(_onEvent);
  }

  void _onEvent(RealtimeSessionEvent event) {
    if (event.type == RealtimeEventType.error) {
      onError?.call(event.payload?['error'] ?? StateError('Realtime error'));
      return;
    }
    if (event.type == RealtimeEventType.stateChanged) {
      final state = event.connectionState;
      if (state != null) onConnectionStateChanged?.call(state);
      return;
    }
    if (event.type == RealtimeEventType.iceStateChanged) {
      onIceStateChanged?.call(event.payload?['state']?.toString() ?? '');
      return;
    }
    if (event.type != RealtimeEventType.serverEvent) return;
    final payload = event.payload;
    if (payload == null) return;
    final type = payload['type']?.toString() ?? '';
    final delta = payload['delta']?.toString() ?? '';
    final itemId = payload['item_id']?.toString() ?? '';
    if (type == 'input_audio_buffer.speech_started') {
      onSpeechStarted?.call(itemId);
      return;
    }
    if (type == 'input_audio_buffer.speech_stopped') {
      onSpeechStopped?.call(itemId);
      return;
    }
    if (type == 'response.created') {
      _assistantText = '';
      onResponseStarted?.call();
      return;
    }
    if (type == 'conversation.item.input_audio_transcription.delta') {
      if (delta.isEmpty) return;
      final buffer =
          _userTranscriptBuffers.putIfAbsent(itemId, StringBuffer.new);
      buffer.write(delta);
      _userText = buffer.toString();
      onUserTranscriptDelta?.call(itemId, delta, _userText);
      onUserTranscript?.call(_userText);
      return;
    }
    if (type == 'conversation.item.input_audio_transcription.completed') {
      if (!_completedTranscriptItemIds.add(itemId)) {
        logger?.call(
            '[RT-TRANSCRIBE]', 'duplicate_completed_dropped itemId=$itemId');
        return;
      }
      final bufferedText =
          _userTranscriptBuffers.remove(itemId)?.toString() ?? '';
      final text = payload['transcript']?.toString().trim() ?? '';
      final finalText = text.isNotEmpty ? text : bufferedText.trim();
      _userText = finalText;
      onUserTranscriptCompleted?.call(itemId, finalText);
      if (finalText.isNotEmpty) {
        onUserTranscript?.call(finalText);
      }
      return;
    }
    if (delta.isNotEmpty &&
        (type.contains('audio_transcript') || type.contains('output_text'))) {
      _assistantText += delta;
      onAssistantTranscript?.call(_assistantText);
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
