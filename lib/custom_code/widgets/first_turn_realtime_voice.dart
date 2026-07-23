import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ====================================================================
// 🎙️ [FIRST-TURN REALTIME] 유저 "첫 대사" 전용 번역+음성 엔진
// --------------------------------------------------------------------
// 기존: Deepgram Nova-3 → GPT-4.1(첫 발화 문맥 판정) → gpt-4o-mini(번역)
//                                                    → tts-1(음성)
// 변경: Deepgram Nova-3 → GPT-4.1(첫 발화 문맥 판정)
//                       → gpt-realtime-2.1-mini(번역 + 음성 동시)
//
// 적용 범위
//   - 유저의 첫 대사(turn 1)에만 쓴다. 2턴부터는 기존 경로 그대로.
//   - Anyone / Step Expand 두 모드가 이 파일을 공유한다.
//
// 안전장치
//   - begin()이 false를 돌려주면 호출부는 아무것도 안 하고 기존 gpt-4o-mini
//     경로로 그대로 흘러간다. 즉 Realtime이 죽어도 앱 동작은 지금과 동일하다.
//   - 텍스트가 한 조각이라도 나온 뒤 끊기면 audioWav가 null이 되고, 호출부는
//     이미 받은 통문장을 기존 tts-1로 읽는다(음성만 폴백).
// ====================================================================

/// Realtime 모델 ID. 다른 스냅샷으로 갈아탈 땐 이 한 줄만 바꾸면 된다.
const String kFirstTurnRealtimeModel = 'gpt-realtime-2.1-mini';

const String kFirstTurnRealtimeEndpoint = 'wss://api.openai.com/v1/realtime';

/// Realtime 출력 PCM 샘플레이트(모노 16bit).
const int kFirstTurnRealtimeSampleRate = 24000;

const Duration kFirstTurnRealtimeConnectTimeout = Duration(seconds: 5);

/// 첫 텍스트 델타가 이 시간 안에 안 오면 실패로 보고 기존 경로로 폴백한다.
const Duration kFirstTurnRealtimeFirstDeltaTimeout = Duration(seconds: 8);

/// 응답 전체(텍스트+오디오) 상한. 첫 대사는 한 문장이라 넉넉한 값이다.
const Duration kFirstTurnRealtimeTotalTimeout = Duration(seconds: 25);

/// 로비 목소리(tts-1 계열) → Realtime 지원 목소리 매핑.
/// tts-1의 onyx/fable/nova는 Realtime에 없으므로 가장 가까운 음색으로 보낸다.
const Map<String, String> kFirstTurnRealtimeVoiceAliases = {
  'alloy': 'alloy',
  'ash': 'ash',
  'ballad': 'ballad',
  'cedar': 'cedar',
  'coral': 'coral',
  'echo': 'echo',
  'marin': 'marin',
  'sage': 'sage',
  'shimmer': 'shimmer',
  'verse': 'verse',
  'onyx': 'ash',
  'fable': 'ballad',
  'nova': 'shimmer',
};

String firstTurnRealtimeVoiceFor(String voice) =>
    kFirstTurnRealtimeVoiceAliases[voice.trim().toLowerCase()] ?? 'alloy';

/// PCM16(LE, 모노)을 그대로 재생 가능한 WAV 바이트로 감싼다.
/// TtsQueueManager가 mp3/wav 구분 없이 BytesSource로 재생하므로 헤더만 붙이면 된다.
Uint8List firstTurnPcm16ToWav(
  Uint8List pcm, {
  int sampleRate = kFirstTurnRealtimeSampleRate,
  int channels = 1,
}) {
  const int bitsPerSample = 16;
  final int blockAlign = channels * bitsPerSample ~/ 8;
  final int byteRate = sampleRate * blockAlign;
  final header = ByteData(44);
  void ascii(int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);

  final out = Uint8List(44 + pcm.length);
  out.setRange(0, 44, header.buffer.asUint8List());
  out.setRange(44, out.length, pcm);
  return out;
}

/// 첫 대사 1회용 Realtime 세션. 인스턴스는 턴마다 새로 만든다.
class FirstTurnRealtimeVoice {
  FirstTurnRealtimeVoice({
    required this.apiKey,
    required this.voice,
    this.model = kFirstTurnRealtimeModel,
    this.onLog,
  });

  final String apiKey;
  final String voice;
  final String model;
  final void Function(String tag, String msg)? onLog;

  final StreamController<String> _textCtl = StreamController<String>();
  final Completer<bool> _ready = Completer<bool>();
  final Completer<Uint8List?> _audio = Completer<Uint8List?>();
  final BytesBuilder _pcm = BytesBuilder(copy: false);

  WebSocket? _socket;
  StreamSubscription? _sub;
  Timer? _totalTimer;
  Timer? _firstDeltaTimer;
  Future<bool>? _connectFuture;

  bool _begun = false;
  bool _active = false;
  bool _emittedText = false;
  bool _closed = false;

  /// 선점 단계에서만 켜진다. 소켓이 죽어도 세션 자체는 살려 두고, begin()이
  /// 새 소켓으로 다시 연결하게 한다(자가치유).
  bool _prewarmBroken = false;
  int _audioTokens = 0;
  int _textTokens = 0;

  /// Realtime 경로가 실제로 살아 있는지. begin()이 true를 준 뒤에만 true.
  /// 호출부는 이 값으로 "유저 TTS(tts-1)를 쏠지 말지"를 판단한다.
  bool get active => _active;

  /// 번역문 델타 스트림. 기존 gpt-4o-mini 스트림과 동일하게 소비하면 된다.
  Stream<String> get textStream => _textCtl.stream;

  /// 낭독 오디오(WAV). 실패하면 null → 호출부가 기존 tts-1로 폴백한다.
  Future<Uint8List?> get audioWav => _audio.future;

  int get audioTokens => _audioTokens;
  int get textTokens => _textTokens;

  /// 🔥 [PREWARM] 발화 확정 대기창(commit wait) 동안 소켓만 미리 열어 둔다.
  ///
  /// 여기서 나가는 건 목소리/오디오 포맷 같은 세션 설정뿐이다. 발화 내용도,
  /// 시스템 프롬프트도 보내지 않는다. 따라서 발화가 합쳐지거나 고스트워드로
  /// 증발해서 이 소켓을 그냥 버려도 토큰 비용은 0원이다.
  ///
  /// GPT-4.1 문맥 판정 선시작과는 서로 await하지 않는 완전 독립 작업이다.
  Future<bool> prewarm() => _ensureConnected();

  /// 페이로드를 실어 보내고 첫 텍스트 델타가 도착할 때까지 기다린다.
  /// true = Realtime 사용, false = 호출부가 기존 gpt-4o-mini 경로로 폴백.
  ///
  /// 선점 소켓이 유휴 타임아웃 등으로 죽어 있으면 여기서 조용히 새로 연결한다.
  Future<bool> begin({
    required String instructions,
    required String userContent,
  }) async {
    if (_begun) return _ready.future;
    _begun = true;
    if (_closed) return _ready.future;

    // 선점 소켓 건강 확인 → 죽었으면 폐기하고 새 연결로 간다(자가치유).
    if (_prewarmBroken || (_socket != null && !_isSocketOpen)) {
      onLog?.call('🎙️ [RT-REWARM]', '선점 소켓이 닫혀 있음 → 신규 연결로 대체');
      _teardownSocket();
      _prewarmBroken = false;
      _connectFuture = null;
    }

    if (!await _ensureConnected()) {
      _abort('connect_failed');
      return _ready.future;
    }

    // 번역 지시문은 기존 gpt-4o-mini와 완전히 동일한 시스템 프롬프트를 쓴다.
    // 선점 단계에서 보내지 않고 여기(확정 시점)서 response.create에 실어 보낸다.
    // 출력은 오디오 모달리티 하나 — 낭독 전사(transcript)가 곧 번역문이다.
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': userContent},
        ],
      },
    });
    _send({
      'type': 'response.create',
      'response': {
        'instructions': instructions,
        'output_modalities': ['audio'],
        'audio': {
          'output': {
            'voice': firstTurnRealtimeVoiceFor(voice),
            'format': {
              'type': 'audio/pcm',
              'rate': kFirstTurnRealtimeSampleRate,
            },
          },
        },
      },
    });

    _totalTimer =
        Timer(kFirstTurnRealtimeTotalTimeout, () => _abort('total_timeout'));
    _firstDeltaTimer = Timer(kFirstTurnRealtimeFirstDeltaTimeout,
        () => _abort('first_delta_timeout'));
    return _ready.future;
  }

  /// 턴이 취소되면(제어 태그/바지인/세대 불일치) 즉시 정리한다.
  void cancel() => _abort('cancelled');

  bool get _isSocketOpen =>
      _socket != null && _socket!.readyState == WebSocket.open;

  /// 연결은 인스턴스당 1회만 시도한다. prewarm()과 begin()이 같은 Future를 공유하므로
  /// 확정 시점에 선점 연결이 아직 진행 중이면 그것을 그대로 기다린다(중복 연결 없음).
  Future<bool> _ensureConnected() {
    final existing = _connectFuture;
    if (existing != null) return existing;
    final started = _connect();
    _connectFuture = started;
    return started;
  }

  Future<bool> _connect() async {
    if (_closed) return false;
    final String mappedVoice = firstTurnRealtimeVoiceFor(voice);
    final sw = Stopwatch()..start();
    try {
      final socket = await WebSocket.connect(
        '$kFirstTurnRealtimeEndpoint?model=$model',
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(kFirstTurnRealtimeConnectTimeout);
      if (_closed) {
        unawaited(socket.close());
        return false;
      }
      _socket = socket;
      _sub = socket.listen(
        _handleEvent,
        onError: (e) => _onSocketLost('ws_error(${e.runtimeType})'),
        onDone: () => _onSocketLost('ws_closed'),
        cancelOnError: true,
      );
      // 발화와 무관한 세션 설정만 미리 확정해 둔다(선점 단계에서도 안전).
      _send({
        'type': 'session.update',
        'session': {
          'type': 'realtime',
          'output_modalities': ['audio'],
          'audio': {
            'output': {
              'voice': mappedVoice,
              'format': {
                'type': 'audio/pcm',
                'rate': kFirstTurnRealtimeSampleRate,
              },
              'speed': 1.0,
            },
          },
        },
      });
      onLog?.call('🎙️ [RT-01]',
          'connected model=$model voice=$mappedVoice stage=${_begun ? 'commit' : 'prewarm'} connect_ms=${sw.elapsedMilliseconds}');
      return true;
    } catch (e) {
      onLog?.call('🎙️ [RT-FAIL]',
          'connect_failed(${e.runtimeType}) stage=${_begun ? 'commit' : 'prewarm'} elapsed_ms=${sw.elapsedMilliseconds}');
      if (!_begun) _prewarmBroken = true;
      return false;
    }
  }

  /// 소켓이 끊겼을 때. 선점 단계면 세션을 죽이지 않고 재연결 가능 상태로만 표시한다.
  void _onSocketLost(String reason) {
    if (_closed) return;
    if (!_begun) {
      _prewarmBroken = true;
      _teardownSocket();
      onLog?.call(
          '🎙️ [RT-PREWARM-LOST]', 'reason=$reason — 확정 시점에 새로 연결한다(비용 0)');
      return;
    }
    _abort(reason);
  }

  void _send(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null || _closed) return;
    try {
      socket.add(jsonEncode(payload));
    } catch (e) {
      _onSocketLost('send_failed(${e.runtimeType})');
    }
  }

  void _handleEvent(dynamic raw) {
    if (_closed || raw is! String) return;
    Map<String, dynamic> event;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      event = decoded;
    } catch (_) {
      return;
    }
    final String type = event['type']?.toString() ?? '';

    if (type == 'error' || type == 'response.failed') {
      onLog?.call(
          '🎙️ [RT-ERR]', raw.length > 600 ? '${raw.substring(0, 600)}…' : raw);
      // 선점 단계 에러(세션 설정 거부 등)는 턴을 죽이지 않는다. 소켓만 버리고
      // 확정 시점에 새 연결로 다시 시도한다 — 전체 설정은 response.create가 싣는다.
      _onSocketLost('api_error');
      return;
    }

    // 오디오 델타: GA(response.output_audio.delta) / 구버전(response.audio.delta)
    if (type == 'response.output_audio.delta' ||
        type == 'response.audio.delta') {
      final delta = event['delta'];
      if (delta is String && delta.isNotEmpty) {
        try {
          _pcm.add(base64Decode(delta));
        } catch (_) {}
      }
      return;
    }

    // 텍스트 델타: 낭독 전사 우선, 텍스트 모달리티가 켜진 경우도 함께 받는다.
    if (type == 'response.output_audio_transcript.delta' ||
        type == 'response.audio_transcript.delta' ||
        type == 'response.output_text.delta' ||
        type == 'response.text.delta') {
      final delta = event['delta'];
      if (delta is String && delta.isNotEmpty) _emit(delta);
      return;
    }

    if (type == 'response.done') {
      _readUsage(event);
      final status = event['response'] is Map
          ? (event['response'] as Map)['status']?.toString()
          : null;
      if (status != null && status != 'completed') {
        onLog?.call('🎙️ [RT-ERR]', 'response.status=$status');
        _abort('response_$status');
        return;
      }
      _finish();
    }
  }

  void _emit(String delta) {
    if (_closed || _textCtl.isClosed) return;
    _textCtl.add(delta);
    if (_emittedText) return;
    _emittedText = true;
    _firstDeltaTimer?.cancel();
    _firstDeltaTimer = null;
    _active = true;
    if (!_ready.isCompleted) _ready.complete(true);
  }

  void _readUsage(Map<String, dynamic> event) {
    try {
      final usage = (event['response'] as Map?)?['usage'];
      final details = (usage as Map?)?['output_token_details'];
      if (details is Map) {
        _audioTokens = (details['audio_tokens'] as num?)?.toInt() ?? 0;
        _textTokens = (details['text_tokens'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    _teardown();
    final pcm = _pcm.takeBytes();
    final Uint8List? wav = pcm.isEmpty ? null : firstTurnPcm16ToWav(pcm);
    onLog?.call(
        '🎙️ [RT-02]',
        'done text_chars=${_emittedText ? 'yes' : 'none'} pcm_bytes=${pcm.length} '
            'audio_tokens=$_audioTokens text_tokens=$_textTokens');
    if (!_ready.isCompleted) _ready.complete(_emittedText);
    if (!_audio.isCompleted) _audio.complete(wav);
    if (!_textCtl.isClosed) _textCtl.close();
  }

  void _abort(String reason) {
    if (_closed) return;
    _closed = true;
    _active = false;
    _teardown();
    onLog?.call('🎙️ [RT-FALLBACK]',
        'reason=$reason emitted_text=$_emittedText → 기존 gpt-4o-mini/tts-1 경로 사용');
    if (!_ready.isCompleted) _ready.complete(false);
    if (!_audio.isCompleted) _audio.complete(null);
    if (!_textCtl.isClosed) _textCtl.close();
  }

  void _teardown() {
    _totalTimer?.cancel();
    _totalTimer = null;
    _firstDeltaTimer?.cancel();
    _firstDeltaTimer = null;
    _teardownSocket();
  }

  /// 소켓/구독만 정리한다. Completer와 텍스트 스트림은 건드리지 않으므로
  /// 선점 소켓이 끊겨도 같은 인스턴스로 재연결할 수 있다.
  void _teardownSocket() {
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel() ?? Future<void>.value());
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      unawaited(socket.close().catchError((_) => null));
    }
  }
}
