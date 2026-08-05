// 🔊 [TTS-ADAPTER] 공통 TTS 어댑터 — guide4 8장.
//
// 앱의 모든 TTS 호출은 이 어댑터를 통해서만 나간다. 대화방/화면 코드는
// 모델명·출력형식·제공자 보이스명을 모른다. 모델 교체 시 수정 범위는
// TtsAdapterConfig 한곳이다.
//
// 책임 (guide4 8.3):
//   - 현재 설정된 TTS 모델 확인, 보이스 매핑
//   - PCM 스트리밍 수신 → 첫 청크부터 즉시 재생 (전체 생성 완료를 기다리지 않음)
//   - 오디오 청크 순서 보장 (단일 HTTP 스트림 + 단일 재생 세션이라 구조적으로 보장)
//   - 히스토리 저장용 버퍼 기록 → 정상 완료 시에만 WAV로 포장해 콜백 전달
//   - 요청 취소 / timeout / 재시도 / 완료 상태 전달
//
// 재생과 저장은 같은 PCM 스트림을 이중으로 소비한다:
//   PCM 청크 ──┬─ PcmStreamPlayer (실시간 재생)
//              └─ 히스토리 버퍼 (turnId 귀속, 완료 시에만 등록)

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;

import 'openai_connection_pool.dart';
import 'pcm_audio_utils.dart';

// ====================================================================
// 설정 — 모델 교체는 이 클래스만 수정한다
// ====================================================================
class TtsAdapterConfig {
  TtsAdapterConfig._();

  static const String provider = 'openai';

  /// 현재 TTS 모델. 교체 시 여기만 바꾼다 — 대화방 코드는 손대지 않는다.
  ///
  /// 3모드 AI 음성은 tts-1 + nova가 스펙이다. 한때 gpt-4o-mini-tts로 바꿨더니
  /// 한국어를 또박또박 읽어 영어보다 눈에 띄게 처졌다. tts-1은 가볍고 빠르며
  /// `speed` 파라미터가 실제로 먹는다(gpt-4o-mini-tts는 `instructions`로만
  /// 움직인다). 바꾸려면 speed/instructions 지원 여부부터 확인할 것.
  static const String model = 'tts-1';

  /// OpenAI /v1/audio/speech 의 pcm 출력 규격: 24kHz, 16-bit LE, mono.
  static const String outputFormat = 'pcm';
  static const int sampleRate = 24000;
  static const int channels = 1;
  static const bool streamingEnabled = true;

  /// PCM 스트림 종료 시 플레이어를 즉시 닫으며 생길 수 있는 팝/둔탁한
  /// 종료음을 막기 위해 붙이는 짧은 무음 꼬리.
  static const int tailSilenceMs = 50;
  static const int tailSilenceBytes =
      sampleRate * channels * 2 * tailSilenceMs ~/ 1000;

  /// 헤더 응답까지의 제한시간(시도당) / 청크 간 제한시간 / 재시도 횟수.
  static const Duration requestTimeout = Duration(seconds: 10);
  static const Duration chunkTimeout = Duration(seconds: 10);
  static const int maxAttempts = 2;

  /// 🎚️ [PREROLL] 재생 시작 전에 모아 둘 PCM 양.
  ///
  /// 첫 청크가 도착하는 즉시 재생을 시작하면 초반에 네트워크 공급이 실시간
  /// 재생 속도를 못 따라가 버퍼가 말라 소리가 끊긴다(실기기 2026-07-30:
  /// "몇 단어 하고 약간 쉬는" 증상. 로그상 재생 벽시계가 오디오 길이보다
  /// 0.3~0.7초 길었다 = 언더런). 이만큼 미리 채워 그 구간을 덮는다.
  ///
  /// 24kHz · 16bit · mono = 48,000 B/s → 36,000B ≈ 0.75초.
  /// 첫 음성이 그만큼 늦어지는 대신 끊김이 사라진다. 늘리면 더 안전하지만
  /// 체감 지연이 커진다.
  static const int prerollBytes = 36000;

  /// 첫 턴 유저 번역 전용 프리롤. 아래 64KB 링버퍼로 언더런 여유를 확보한
  /// 상태에서 시작 대기만 0.75초 → 0.5초로 줄인다. 다른 TTS에는 적용하지
  /// 않아 AI 음성 및 이후 턴의 안정성은 그대로 유지한다.
  static const int fastFirstTurnPrerollBytes = 24000;

  /// 네이티브 링버퍼 크기. 작으면 Dart 이벤트 루프 지터나 다음 TTS 조각의
  /// 네트워크 공급 지연 때 언더런이 나 단어 중간이 잘려 들린다.
  ///
  /// 65,536B ≈ 1.36초. 프리롤 양은 그대로이므로 첫 음성 시작 시각은 늦추지
  /// 않고, 플레이어가 미리 받아 둘 수 있는 여유만 두 배로 늘린다.
  static const int playerBufferSize = 65536;

  /// 화자별 체감 음량. tts-1의 nova(AI)가 로비에서 고른 유저
  /// 보이스보다 크게 들리므로 AI만 낮춘다. 기기 미디어/통화 볼륨 자체는
  /// 건드리지 않고, 이 재생 세션에만 적용된다.
  static const double userVolume = 1.0;
  static const double aiVolume = 0.62;
  static const double systemVolume = 0.82;

  static double volumeFor(TtsSpeakerType speakerType) {
    switch (speakerType) {
      case TtsSpeakerType.user:
        return userVolume;
      case TtsSpeakerType.ai:
        return aiVolume;
      case TtsSpeakerType.system:
        return systemVolume;
    }
  }

  /// 히스토리 저장 형식. 실시간 출력(PCM)과 분리해서 관리한다.
  static const String historyFormat = 'wav';

  /// 앱 내부 보이스 ID → 제공자 보이스명 매핑.
  /// 현재는 기존 저장값(nova/marin 등)이 제공자명과 일치하므로 passthrough가
  /// 대부분이지만, 미지원 값이 오면 세션을 죽이는 대신 기본 보이스로 강등한다
  /// (legacy voice를 그대로 보내 세션이 통째로 죽던 사고의 재발 방지).
  static const Set<String> _supportedVoices = {
    'alloy',
    'ash',
    'ballad',
    'coral',
    'echo',
    'fable',
    'onyx',
    'nova',
    'sage',
    'shimmer',
    'verse',
    'marin',
    'cedar',
  };
  static const String fallbackVoice = 'nova';
  static const String aiVoice = 'nova';
  static const String userVoice = 'verse';

  static String mapVoice(String voiceId) {
    final v = voiceId.trim().toLowerCase();
    return _supportedVoices.contains(v) ? v : fallbackVoice;
  }
}

Uint8List _withTailSilence(Uint8List pcm) {
  if (pcm.isEmpty) return pcm;
  final padded = Uint8List(pcm.length + TtsAdapterConfig.tailSilenceBytes);
  padded.setRange(0, pcm.length, pcm);
  return padded;
}

enum TtsSpeakerType { user, ai, system }

/// guide4 14장 TTS 상태.
enum TtsUtteranceStatus {
  pending,
  requesting,
  streaming,
  completed,
  cancelled,
  failed,
}

// ====================================================================
// 요청 — 대화방 코드는 이 정보만 전달한다 (모델명 전달 금지)
// ====================================================================
class TtsRequest {
  TtsRequest({
    required this.text,
    required this.voiceId,
    required this.speakerType,
    required this.turnId,
    required this.generationId,
    this.speakingInstruction,
    this.saveToHistory = false,
    this.historyVoiceKey,
    this.playbackCategory = 'main',
    this.continuesPreviousSegment = false,
    this.expectsMoreSegments = false,
    this.prerollBytes,
  });

  final String text;
  final String voiceId;
  final TtsSpeakerType speakerType;
  final String turnId;
  final int generationId;
  final String? speakingInstruction;
  final bool saveToHistory;

  /// 히스토리 캐시 키에 쓸 보이스명. 기존 히스토리 조회 규약(예: 유저 통문장은
  /// 'nova' 키)과 맞추기 위해 재생 보이스와 분리한다. null이면 voiceId 사용.
  final String? historyVoiceKey;
  final String playbackCategory;

  /// 🔗 [SEGMENT] 같은 발화의 앞 조각이 이미 재생 중이다 — 재생 세션을 새로
  /// 열지 않고 이어서 feed한다. 조각 사이에 끊김이 생기지 않게 하는 스위치다.
  final bool continuesPreviousSegment;

  /// 🔗 [SEGMENT] 뒤에 조각이 더 온다 — 재생 세션을 닫지 않고 열어 둔다.
  /// 마지막 조각은 이 값이 false여야 세션이 정리된다.
  final bool expectsMoreSegments;

  /// null이면 공통 안전 프리롤을 쓴다. 충분히 큰 링버퍼가 검증된 지연 민감
  /// 요청만 더 작은 값을 명시한다.
  final int? prerollBytes;
}

// ====================================================================
// 재생 핸들 — 파이프라인이 순서 보장에 쓰는 futures
// ====================================================================
class TtsUtterance {
  TtsUtterance._(this.request, [this._prefetch]);

  final TtsRequest request;
  final TtsPrefetch? _prefetch;
  TtsUtteranceStatus status = TtsUtteranceStatus.pending;

  final Completer<void> _firstAudio = Completer<void>();
  final Completer<bool> _done = Completer<bool>();
  bool _cancelRequested = false;

  /// 첫 PCM 청크가 재생기로 들어간 시점.
  Future<void> get firstAudio => _firstAudio.future;

  /// 재생까지 완전히 끝난 시점. true=정상 완료, false=취소/실패.
  Future<bool> get done => _done.future;

  bool get isSettled => _done.isCompleted;

  void cancel() {
    _cancelRequested = true;
    _prefetch?.cancel();
  }

  void _settleFirstAudio() {
    if (!_firstAudio.isCompleted) _firstAudio.complete();
  }

  void _settle(bool ok, TtsUtteranceStatus finalStatus) {
    status = finalStatus;
    _settleFirstAudio();
    if (!_done.isCompleted) _done.complete(ok);
  }
}

/// HTTP PCM 수신은 즉시 시작하고, 실제 재생은 FIFO 큐 차례까지 보류하는 핸들.
///
/// 단일 구독 컨트롤러가 재생 전에 도착한 청크를 버퍼링한다. 큐 차례가 오면
/// 버퍼된 PCM부터 소비하고 아직 수신 중인 나머지 청크를 그대로 이어 받는다.
class TtsPrefetch {
  TtsPrefetch._(this.request);

  final TtsRequest request;
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  bool _cancelRequested = false;
  bool _streamTaken = false;

  bool get isCancelled => _cancelRequested;

  void cancel() {
    _cancelRequested = true;
  }

  Stream<List<int>> _takeStream() {
    if (_streamTaken) {
      return Stream<List<int>>.error(
        StateError('TTS prefetch stream can only be consumed once.'),
      );
    }
    _streamTaken = true;
    return _controller.stream;
  }
}

// ====================================================================
// PCM 스트리밍 재생기 (flutter_sound)
// ====================================================================
class PcmStreamPlayer {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _opened = false;
  bool _sessionActive = false;
  int _fedBytes = 0;
  DateTime? _feedStartAt;
  int _sampleRate = TtsAdapterConfig.sampleRate;

  /// 이미 열린 재생 세션이 있는가 (같은 발화의 다음 조각을 이어붙일 수 있는지).
  bool get isSessionActive => _sessionActive;

  Future<void> begin({
    required int sampleRate,
    required double volume,
  }) async {
    if (!_opened) {
      await _player.openPlayer();
      _opened = true;
    }
    if (_sessionActive) await abort();
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true,
      numChannels: TtsAdapterConfig.channels,
      sampleRate: sampleRate,
      bufferSize: TtsAdapterConfig.playerBufferSize,
    );
    // 아직 PCM을 feed하기 전이므로 첫 샘플부터 이 화자의 음량으로 재생된다.
    await _player.setVolume(volume);
    _sessionActive = true;
    _fedBytes = 0;
    _feedStartAt = null;
    _sampleRate = sampleRate;
  }

  /// 조기 발사 후속 조각처럼 이미 열린 세션을 이어 쓸 때도 화자 음량을
  /// 재확인한다. 현재 구조상 같은 화자지만, 세션 재사용 변경에도 안전하다.
  Future<void> setVolume(double volume) async {
    if (!_opened) return;
    await _player.setVolume(volume);
  }

  /// 백프레셔 있는 feed — await가 풀리는 속도가 대략 재생 속도를 따라간다.
  Future<void> feed(Uint8List data) async {
    if (!_sessionActive || data.isEmpty) return;
    _feedStartAt ??= DateTime.now();
    _fedBytes += data.length;
    await _player.feedUint8FromStream(data);
  }

  /// 🔗 [SEGMENT] 조각 하나를 다 먹였지만 세션은 열어 둔다. 다음 조각이
  /// 도착할 때까지 이미 먹인 오디오가 계속 재생된다. 다음 조각의 네트워크
  /// 왕복(약 1.6초)이 이 재생 시간 안에 숨는 것이 조기 발사의 원리다.
  ///
  /// 남은 재생 시간(ms)을 돌려준다 — 호출부가 다음 조각을 그 안에 붙여야 한다.
  int remainingPlaybackMs() {
    final start = _feedStartAt;
    if (!_sessionActive || start == null) return 0;
    final totalMs = pcm16DurationMs(_fedBytes, sampleRate: _sampleRate);
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    final remain = totalMs - elapsed;
    return remain > 0 ? remain : 0;
  }

  /// 마지막 샘플까지 재생 완료를 추정 대기 후 세션을 닫는다.
  /// 스트림 재생은 완료 이벤트가 없으므로 feed 총량 기반으로 추정한다.
  Future<void> finish() async {
    if (!_sessionActive) return;
    await feed(Uint8List(TtsAdapterConfig.tailSilenceBytes));
    final start = _feedStartAt;
    if (start != null) {
      final totalMs = pcm16DurationMs(_fedBytes, sampleRate: _sampleRate);
      while (true) {
        final remain =
            totalMs - DateTime.now().difference(start).inMilliseconds;
        if (remain <= 0) break;
        await Future.delayed(Duration(milliseconds: remain.clamp(20, 500)));
      }
      // 네이티브 링버퍼에 남은 꼬리를 다 내보낼 여유.
      await Future.delayed(const Duration(milliseconds: 250));
    }
    await _stopSession();
  }

  Future<void> abort() => _stopSession();

  Future<void> _stopSession() async {
    if (!_sessionActive) return;
    _sessionActive = false;
    try {
      await _player.stopPlayer();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _stopSession();
    if (_opened) {
      _opened = false;
      try {
        await _player.closePlayer();
      } catch (_) {}
    }
  }
}

// ====================================================================
// 어댑터 본체
// ====================================================================
class TtsAdapter {
  TtsAdapter({
    required this.apiKeyProvider,
    this.onLog,
    this.onPlaybackStart,
    this.onPlaybackEnd,
    this.onHistoryAudioReady,
  });

  final String Function() apiKeyProvider;
  final void Function(String tag, String msg)? onLog;
  final void Function(TtsRequest request)? onPlaybackStart;
  final void Function(TtsRequest request, bool ok)? onPlaybackEnd;

  /// 정상 완료된 음원만 전달된다 (guide4 11장 — 불완전 음원 등록 금지).
  /// wav는 TtsAdapterConfig.historyFormat 규격.
  final void Function(TtsRequest request, Uint8List wav)? onHistoryAudioReady;

  final PcmStreamPlayer _pcmPlayer = PcmStreamPlayer();
  final List<TtsUtterance> _queue = [];
  final Set<TtsPrefetch> _prefetches = <TtsPrefetch>{};
  TtsUtterance? _current;
  bool _pumping = false;
  bool _disposed = false;
  int _minGenerationId = 0;

  // 같은 턴 TTS 중복 호출 방지 (guide4 14장).
  final Set<String> _servedTurnKeys = <String>{};

  // 🔗 [SEGMENT] 조기 발사로 쪼갠 조각들의 히스토리 누적. 조각별로 저장하면
  //   히스토리에서 통문장 조회가 안 되므로, 마지막 조각에서 합쳐 한 번만 넘긴다.
  //   재생 큐가 직렬이라 동시에 진행되는 발화는 하나뿐이므로 필드 하나로 족하다.
  final BytesBuilder _segmentPcm = BytesBuilder(copy: false);
  final StringBuffer _segmentText = StringBuffer();
  String? _segmentTurnId;
  TtsRequest? _segmentHistoryTemplate;

  void _resetSegmentAccumulator() {
    _segmentPcm.clear();
    _segmentText.clear();
    _segmentTurnId = null;
    _segmentHistoryTemplate = null;
  }

  void _log(String tag, String msg) => onLog?.call(tag, msg);

  /// 유저/AI 본 재생이 진행 중이거나 대기 중이면 busy.
  bool get isBusy => _current != null || _queue.isNotEmpty;

  /// 요청을 큐에 넣고 즉시 핸들을 돌려준다. 재생은 FIFO — 유저 음성과 AI 음성이
  /// 겹치지 않는 순서 보장은 이 직렬 큐가 담당한다.
  TtsUtterance speak(TtsRequest request) {
    return _enqueue(request);
  }

  /// TTS HTTP 요청과 PCM 수신을 즉시 시작하되 재생 큐에는 아직 넣지 않는다.
  TtsPrefetch prefetch(TtsRequest request) {
    final handle = TtsPrefetch._(request);
    if (_disposed || request.text.trim().isEmpty) {
      handle.cancel();
      unawaited(handle._controller.close());
      return handle;
    }
    _prefetches.add(handle);
    _log(
      '🔊 [TTS-PREFETCH]',
      'started speaker=${request.speakerType.name} turnId=${request.turnId} '
          'gen=${request.generationId} len=${request.text.length}',
    );
    unawaited(_runPrefetch(handle));
    return handle;
  }

  /// 선요청으로 받고 있는 PCM을 기존 FIFO 재생 큐에 연결한다.
  TtsUtterance speakPrefetched(TtsPrefetch prefetch) {
    return _enqueue(prefetch.request, prefetch: prefetch);
  }

  /// 음성을 재생하지 않고 끝까지 생성해 히스토리 캐시에만 전달한다.
  /// 실시간 재생 큐와 분리되어 AI 답변 재생 순서를 막지 않는다.
  Future<bool> synthesizeForHistory(TtsRequest request) async {
    if (_disposed ||
        request.text.trim().isEmpty ||
        !request.saveToHistory ||
        onHistoryAudioReady == null) {
      return false;
    }

    final apiKey = apiKeyProvider();
    if (apiKey.isEmpty) return false;
    final voice = request.speakerType == TtsSpeakerType.ai
        ? TtsAdapterConfig.aiVoice
        : TtsAdapterConfig.mapVoice(request.voiceId);
    final sw = Stopwatch()..start();
    Object? lastError;

    for (int attempt = 1; attempt <= TtsAdapterConfig.maxAttempts; attempt++) {
      final pcmBuilder = BytesBuilder(copy: false);
      try {
        final response = await OpenAiConnectionPool.instance.client
            .send(_buildSpeechRequest(
              apiKey: apiKey,
              request: request,
              voice: voice,
            ))
            .timeout(TtsAdapterConfig.requestTimeout);
        if (response.statusCode != 200) {
          lastError =
              StateError('History-only TTS HTTP ${response.statusCode}.');
          await response.stream.drain<void>();
          continue;
        }

        await for (final chunk
            in response.stream.timeout(TtsAdapterConfig.chunkTimeout)) {
          if (chunk.isNotEmpty) pcmBuilder.add(chunk);
        }
        final rawPcm = pcmBuilder.takeBytes();
        if (rawPcm.isEmpty) {
          lastError = StateError('History-only TTS returned an empty stream.');
          continue;
        }

        final Uint8List alignedPcm;
        if (rawPcm.length.isOdd) {
          alignedPcm = Uint8List(rawPcm.length + 1)
            ..setRange(0, rawPcm.length, rawPcm);
        } else {
          alignedPcm = rawPcm;
        }
        onHistoryAudioReady?.call(
          request,
          pcm16ToWav(
            _withTailSilence(alignedPcm),
            sampleRate: TtsAdapterConfig.sampleRate,
            channels: TtsAdapterConfig.channels,
          ),
        );
        sw.stop();
        _log(
          '🔊 [TTS-HISTORY-ONLY]',
          'completed turnId=${request.turnId} bytes=${alignedPcm.length} '
              'elapsedMs=${sw.elapsedMilliseconds}',
        );
        return true;
      } catch (error) {
        lastError = error;
        _log(
          '⚠️ [TTS-HISTORY-ONLY]',
          'attempt=$attempt/${TtsAdapterConfig.maxAttempts} '
              'failed reason=${error.runtimeType}',
        );
      }
    }

    sw.stop();
    _log(
      '❌ [TTS-HISTORY-ONLY]',
      'failed turnId=${request.turnId} elapsedMs=${sw.elapsedMilliseconds} '
          'reason=${lastError.runtimeType}',
    );
    return false;
  }

  TtsUtterance _enqueue(
    TtsRequest request, {
    TtsPrefetch? prefetch,
  }) {
    final utterance = TtsUtterance._(request, prefetch);
    if (_disposed || prefetch?.isCancelled == true) {
      prefetch?.cancel();
      utterance._settle(false, TtsUtteranceStatus.cancelled);
      return utterance;
    }
    if (request.text.trim().isEmpty) {
      prefetch?.cancel();
      utterance._settle(false, TtsUtteranceStatus.cancelled);
      return utterance;
    }
    // 중복 방지: 같은 turnId+speaker 조합은 한 번만 재생한다.
    // 🔗 [SEGMENT] 단, 같은 발화의 후속 조각은 중복이 아니다 — 검사에서 뺀다.
    final turnKey =
        '${request.generationId}:${request.turnId}:${request.speakerType.name}';
    if (request.turnId.isNotEmpty &&
        !request.continuesPreviousSegment &&
        !_servedTurnKeys.add(turnKey)) {
      prefetch?.cancel();
      _log('🔊 [TTS-DUP-BLOCKED]', 'adapter duplicate turnKey=$turnKey');
      utterance._settle(false, TtsUtteranceStatus.cancelled);
      return utterance;
    }
    while (_servedTurnKeys.length > 64) {
      _servedTurnKeys.remove(_servedTurnKeys.first);
    }
    _queue.add(utterance);
    _log(
      '🔊 [TTS-ADAPTER]',
      'queued speaker=${request.speakerType.name} turnId=${request.turnId} '
          'gen=${request.generationId} len=${request.text.length} '
          'queue=${_queue.length} prefetched=${prefetch != null}',
    );
    _pump();
    return utterance;
  }

  Future<void> _runPrefetch(TtsPrefetch handle) async {
    final request = handle.request;
    final apiKey = apiKeyProvider();
    // 실시간 AI 음성은 Anyone 메뉴에서 선택한 보이스를 그대로 사용한다.
    final voice = TtsAdapterConfig.mapVoice(request.voiceId);
    final sw = Stopwatch()..start();
    int totalBytes = 0;
    int? firstByteMs;
    Object? lastError;
    bool succeeded = false;

    try {
      if (apiKey.isEmpty) {
        lastError = StateError('OpenAI API key is empty.');
      } else {
        final client = OpenAiConnectionPool.instance.client;
        for (int attempt = 1;
            attempt <= TtsAdapterConfig.maxAttempts;
            attempt++) {
          if (handle.isCancelled || _disposed) break;
          try {
            final response = await client
                .send(_buildSpeechRequest(
                  apiKey: apiKey,
                  request: request,
                  voice: voice,
                ))
                .timeout(TtsAdapterConfig.requestTimeout);
            if (response.statusCode != 200) {
              lastError =
                  StateError('TTS prefetch HTTP ${response.statusCode}.');
              _log(
                '❌ [TTS-PREFETCH]',
                'status=${response.statusCode} '
                    'attempt=$attempt/${TtsAdapterConfig.maxAttempts}',
              );
              await response.stream.drain<void>();
              continue;
            }

            await for (final chunk
                in response.stream.timeout(TtsAdapterConfig.chunkTimeout)) {
              if (handle.isCancelled || _disposed) break;
              if (chunk.isEmpty) continue;
              firstByteMs ??= sw.elapsedMilliseconds;
              totalBytes += chunk.length;
              handle._controller.add(chunk);
            }
            if (handle.isCancelled || _disposed) break;
            succeeded = totalBytes > 0;
            if (succeeded) break;
            lastError = StateError('TTS prefetch returned an empty stream.');
          } catch (error) {
            lastError = error;
            _log(
              '⚠️ [TTS-PREFETCH]',
              'attempt=$attempt/${TtsAdapterConfig.maxAttempts} '
                  'failed reason=${error.runtimeType}',
            );
            if (totalBytes > 0) break;
          }
        }
      }

      if (!handle.isCancelled && !_disposed && !succeeded) {
        handle._controller.addError(
          lastError ?? StateError('TTS prefetch failed.'),
        );
      }
    } finally {
      sw.stop();
      if (!handle._controller.isClosed) {
        unawaited(handle._controller.close());
      }
      _prefetches.remove(handle);
      _log(
        '🔊 [TTS-PREFETCH]',
        'finished turnId=${request.turnId} ok=$succeeded '
            'cancelled=${handle.isCancelled} bytes=$totalBytes '
            'ttfbMs=${firstByteMs ?? -1} elapsedMs=${sw.elapsedMilliseconds}',
      );
    }
  }

  http.Request _buildSpeechRequest({
    required String apiKey,
    required TtsRequest request,
    required String voice,
  }) {
    final httpRequest = http.Request(
      'POST',
      Uri.parse('https://api.openai.com/v1/audio/speech'),
    );
    httpRequest.headers.addAll({
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    });
    httpRequest.body = jsonEncode({
      'model': TtsAdapterConfig.model,
      'input': request.text,
      'voice': voice,
      'response_format': TtsAdapterConfig.outputFormat,
      if ((request.speakingInstruction ?? '').trim().isNotEmpty)
        'instructions': request.speakingInstruction!.trim(),
    });
    return httpRequest;
  }

  /// 진행 중/대기 중 요청을 모두 취소한다. generationId 무관 전체 정리.
  void stopAll({String reason = 'stop'}) {
    for (final prefetch in _prefetches.toList(growable: false)) {
      prefetch.cancel();
    }
    for (final u in _queue) {
      u.cancel();
      u._settle(false, TtsUtteranceStatus.cancelled);
    }
    _queue.clear();
    final current = _current;
    if (current != null) current.cancel();
    unawaited(_pcmPlayer.abort());
    _resetSegmentAccumulator();
    _log('🔊 [TTS-ADAPTER]', 'stop_all reason=$reason');
  }

  /// 🔗 [SEGMENT] 뒤에 붙일 조각이 없을 때 열려 있는 재생 세션을 정상 종료한다.
  /// (조기 발사한 조각이 결국 전체였던 경우 — 세션이 열린 채 남지 않게 한다.)
  Future<void> closeOpenSegment() async {
    if (!_pcmPlayer.isSessionActive) {
      _resetSegmentAccumulator();
      return;
    }
    await _pcmPlayer.finish();
    final template = _segmentHistoryTemplate;
    final whole = _segmentPcm.takeBytes();
    final wholeText = _segmentText.toString().trim();
    final turnId = _segmentTurnId;
    _resetSegmentAccumulator();
    _log('🔊 [TTS-ADAPTER]', 'segment_closed turnId=${turnId ?? '-'}');
    if (template != null && whole.isNotEmpty && wholeText.isNotEmpty) {
      onPlaybackEnd?.call(template, true);
      onHistoryAudioReady?.call(
        TtsRequest(
          text: wholeText,
          voiceId: template.voiceId,
          speakerType: template.speakerType,
          turnId: template.turnId,
          generationId: template.generationId,
          saveToHistory: true,
          historyVoiceKey: template.historyVoiceKey,
          playbackCategory: template.playbackCategory,
        ),
        pcm16ToWav(_withTailSilence(whole),
            sampleRate: TtsAdapterConfig.sampleRate,
            channels: TtsAdapterConfig.channels),
      );
    }
  }

  /// 이 세대보다 오래된 요청은 재생 직전에 폐기된다 (늦게 도착한 이전 generation
  /// 응답이 현재 턴에 재생되는 것 방지 — guide4 14장).
  void invalidateGenerationsBefore(int generationId) {
    if (generationId > _minGenerationId) _minGenerationId = generationId;
  }

  Future<void> dispose() async {
    _disposed = true;
    stopAll(reason: 'dispose');
    await _pcmPlayer.dispose();
  }

  void _pump() {
    if (_pumping || _disposed) return;
    _pumping = true;
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    try {
      while (!_disposed && _queue.isNotEmpty) {
        final utterance = _queue.removeAt(0);
        _current = utterance;
        try {
          await _playUtterance(utterance);
        } catch (e) {
          _log('❌ [TTS-ADAPTER]', 'unexpected reason=${e.runtimeType}');
          utterance._settle(false, TtsUtteranceStatus.failed);
        } finally {
          _current = null;
        }
      }
    } finally {
      _pumping = false;
      // drain 중 새 요청이 들어왔으면 다시 돈다.
      if (!_disposed && _queue.isNotEmpty) _pump();
    }
  }

  Future<void> _playUtterance(TtsUtterance utterance) async {
    final request = utterance.request;
    if (utterance._cancelRequested || request.generationId < _minGenerationId) {
      utterance._settle(false, TtsUtteranceStatus.cancelled);
      _log('🔊 [TTS-DROP-LATE]',
          'stale utterance dropped turnId=${request.turnId}');
      return;
    }
    final apiKey = apiKeyProvider();
    if (apiKey.isEmpty) {
      utterance._settle(false, TtsUtteranceStatus.failed);
      return;
    }

    // 프리패치와 실제 재생이 반드시 같은 선택 보이스를 사용해야 한다.
    final voice = TtsAdapterConfig.mapVoice(request.voiceId);
    final playbackVolume = TtsAdapterConfig.volumeFor(request.speakerType);
    if (voice != request.voiceId.trim().toLowerCase()) {
      _log('🔊 [TTS-VOICE]', 'unsupported voiceId=${request.voiceId} → $voice');
    }

    final BytesBuilder historyBuffer = BytesBuilder(copy: false);
    // 🎚️ [PREROLL] 재생 시작 전에 모아 두는 구간.
    final BytesBuilder preroll = BytesBuilder(copy: false);
    // 🔗 [SEGMENT] 앞 조각이 재생 중이면 세션이 이미 열려 있다. 그 경우
    //   프리롤을 다시 쌓지 않고 도착하는 대로 흘려보낸다 — 이미 재생 중인
    //   오디오가 버퍼 역할을 하므로 언더런 걱정이 없고, 조각 사이 공백도 없다.
    final bool continuing =
        request.continuesPreviousSegment && _pcmPlayer.isSessionActive;
    bool audioStarted = continuing;
    bool playbackStartNotified = false;
    int? firstByteMs;
    if (continuing) {
      await _pcmPlayer.setVolume(playbackVolume);
      utterance._settleFirstAudio();
      _log(
        '🔊 [TTS-ADAPTER]',
        'segment_continue turnId=${request.turnId} '
            'remainingMs=${_pcmPlayer.remainingPlaybackMs()}',
      );
    } else if (request.continuesPreviousSegment) {
      // 앞 조각 재생이 이미 끝나 세션이 닫혔다 → 새 세션으로 처리(프리롤 필요).
      _log('🔊 [TTS-ADAPTER]',
          'segment_gap turnId=${request.turnId} reason=session_closed');
    }

    // 🔌 [POOL] 매 요청 새 클라이언트를 열면 TLS 연결 수립에 1~2초가 나간다
    //   (실측 2026-07-30: ttfb 113ms인데 queued→first_chunk 2.04s). 스텔스룸
    //   진입 때 워밍업되는 앱 수명 공유 클라이언트를 재사용해 연결을 아낀다.
    final client = OpenAiConnectionPool.instance.client;
    final prefetch = utterance._prefetch;
    final maxAttempts = prefetch == null ? TtsAdapterConfig.maxAttempts : 1;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      if (utterance._cancelRequested) break;
      utterance.status = TtsUtteranceStatus.requesting;
      try {
        late final Stream<List<int>> audioStream;
        if (prefetch != null) {
          audioStream = prefetch._takeStream();
          _log('🔊 [TTS-PREFETCH]',
              'playback_attached turnId=${request.turnId}');
        } else {
          final response = await client
              .send(_buildSpeechRequest(
                apiKey: apiKey,
                request: request,
                voice: voice,
              ))
              .timeout(TtsAdapterConfig.requestTimeout);
          if (response.statusCode != 200) {
            _log('❌ [TTS-API-ERR]',
                'status=${response.statusCode} attempt=$attempt/$maxAttempts');
            continue; // 오디오 시작 전이므로 재시도 안전
          }
          audioStream = response.stream;
        }

        utterance.status = TtsUtteranceStatus.streaming;
        int leftoverByte = -1; // PCM16 정렬: 홀수 바이트 청크 대비
        final sw = Stopwatch()..start();
        final int prerollTarget =
            request.prerollBytes ?? TtsAdapterConfig.prerollBytes;

        await for (final rawChunk
            in audioStream.timeout(TtsAdapterConfig.chunkTimeout)) {
          if (utterance._cancelRequested ||
              request.generationId < _minGenerationId ||
              _disposed) {
            break;
          }
          if (rawChunk.isEmpty) continue;

          Uint8List chunk;
          if (leftoverByte >= 0) {
            chunk = Uint8List(rawChunk.length + 1);
            chunk[0] = leftoverByte;
            chunk.setRange(1, chunk.length, rawChunk);
            leftoverByte = -1;
          } else {
            chunk =
                rawChunk is Uint8List ? rawChunk : Uint8List.fromList(rawChunk);
          }
          if (chunk.length.isOdd) {
            leftoverByte = chunk.last;
            chunk = Uint8List.sublistView(chunk, 0, chunk.length - 1);
          }
          if (chunk.isEmpty) continue;

          historyBuffer.add(chunk);
          firstByteMs ??= sw.elapsedMilliseconds;

          // 🎚️ [PREROLL] 재생 시작 전에는 아직 플레이어에 넣지 않고 모은다.
          //   목표량을 채우면 그때 세션을 열고 한꺼번에 밀어넣는다.
          if (!audioStarted) {
            preroll.add(chunk);
            if (preroll.length < prerollTarget) continue;
            audioStarted = true;
            await _pcmPlayer.begin(
              sampleRate: TtsAdapterConfig.sampleRate,
              volume: playbackVolume,
            );
            utterance._settleFirstAudio();
            playbackStartNotified = true;
            onPlaybackStart?.call(request);
            final buffered = preroll.takeBytes();
            _log(
              '🔊 [TTS-ADAPTER]',
              'playback_start speaker=${request.speakerType.name} '
                  'turnId=${request.turnId} ttfbMs=$firstByteMs '
                  'startMs=${sw.elapsedMilliseconds} '
                  'prerollMs=${pcm16DurationMs(buffered.length, sampleRate: TtsAdapterConfig.sampleRate)}',
            );
            await _pcmPlayer.feed(buffered);
            continue;
          }
          await _pcmPlayer.feed(chunk);
        }

        if (utterance._cancelRequested ||
            request.generationId < _minGenerationId ||
            _disposed) {
          await _pcmPlayer.abort();
          utterance._settle(false, TtsUtteranceStatus.cancelled);
          onPlaybackEnd?.call(request, false);
          _log('🔊 [TTS-ADAPTER]',
              'cancelled mid-stream turnId=${request.turnId}');
          return;
        }

        // PCM16은 한 샘플이 2바이트다. 서버 스트림이 홀수 바이트로 끝난
        // 경우 마지막 바이트를 버리지 않고 0x00을 붙여 완전한 샘플로 만든다.
        if (leftoverByte >= 0) {
          final alignedTail = Uint8List.fromList(<int>[leftoverByte, 0]);
          historyBuffer.add(alignedTail);
          if (audioStarted) {
            await _pcmPlayer.feed(alignedTail);
          } else {
            preroll.add(alignedTail);
          }
          leftoverByte = -1;
        }

        // 🎚️ [PREROLL] 목표량을 못 채운 짧은 음성 — 스트림이 끝났으니 지금 재생한다.
        if (!audioStarted && preroll.length > 0) {
          audioStarted = true;
          await _pcmPlayer.begin(
            sampleRate: TtsAdapterConfig.sampleRate,
            volume: playbackVolume,
          );
          utterance._settleFirstAudio();
          playbackStartNotified = true;
          onPlaybackStart?.call(request);
          final buffered = preroll.takeBytes();
          _log(
            '🔊 [TTS-ADAPTER]',
            'playback_start speaker=${request.speakerType.name} '
                'turnId=${request.turnId} ttfbMs=$firstByteMs '
                'startMs=${sw.elapsedMilliseconds} '
                'prerollMs=${pcm16DurationMs(buffered.length, sampleRate: TtsAdapterConfig.sampleRate)} '
                'reason=stream_end',
          );
          await _pcmPlayer.feed(buffered);
        }
        if (!audioStarted) {
          _log('❌ [TTS-ADAPTER]',
              'empty audio stream attempt=$attempt/$maxAttempts');
          continue;
        }

        // 🔗 [SEGMENT] 뒤에 조각이 더 오면 세션을 닫지 않는다. 이미 먹인
        //   오디오가 계속 재생되는 동안 다음 조각이 붙는다.
        final pcm = historyBuffer.takeBytes();
        // 🔗 [SEGMENT] 조각을 히스토리용으로 누적한다(통문장 저장을 위해).
        if (request.saveToHistory) {
          if (_segmentTurnId != request.turnId) {
            _resetSegmentAccumulator();
            _segmentTurnId = request.turnId;
          }
          _segmentHistoryTemplate = request;
          _segmentPcm.add(pcm);
          if (_segmentText.isNotEmpty) _segmentText.write(' ');
          _segmentText.write(request.text.trim());
        }

        if (request.expectsMoreSegments) {
          // 세션을 닫지 않고 반환 — 이미 먹인 오디오가 계속 재생된다.
          utterance._settle(true, TtsUtteranceStatus.completed);
          _log(
            '🔊 [TTS-ADAPTER]',
            'segment_fed turnId=${request.turnId} bytes=${pcm.length} '
                'audioMs=${pcm16DurationMs(pcm.length, sampleRate: TtsAdapterConfig.sampleRate)} '
                'remainingMs=${_pcmPlayer.remainingPlaybackMs()}',
          );
          return;
        }

        await _pcmPlayer.finish();
        utterance._settle(true, TtsUtteranceStatus.completed);
        onPlaybackEnd?.call(request, true);
        _log(
          '🔊 [TTS-ADAPTER]',
          'completed speaker=${request.speakerType.name} '
              'turnId=${request.turnId} bytes=${pcm.length} '
              'audioMs=${pcm16DurationMs(pcm.length, sampleRate: TtsAdapterConfig.sampleRate)}',
        );
        if (request.saveToHistory && _segmentTurnId == request.turnId) {
          final whole = _segmentPcm.takeBytes();
          final wholeText = _segmentText.toString().trim();
          _resetSegmentAccumulator();
          if (whole.isNotEmpty) {
            onHistoryAudioReady?.call(
              // 히스토리 키는 조각이 아니라 합쳐진 통문장이어야 한다.
              TtsRequest(
                text: wholeText,
                voiceId: request.voiceId,
                speakerType: request.speakerType,
                turnId: request.turnId,
                generationId: request.generationId,
                saveToHistory: true,
                historyVoiceKey: request.historyVoiceKey,
                playbackCategory: request.playbackCategory,
              ),
              pcm16ToWav(_withTailSilence(whole),
                  sampleRate: TtsAdapterConfig.sampleRate,
                  channels: TtsAdapterConfig.channels),
            );
          }
        }
        return;
      } on TimeoutException {
        _log('⚠️ [TTS-ADAPTER]',
            'timeout attempt=$attempt/$maxAttempts audioStarted=$audioStarted');
        if (audioStarted) break; // 재생 중 끊김 — 재시도하면 앞부분이 중복 재생됨
      } catch (e) {
        _log('⚠️ [TTS-ADAPTER]',
            'attempt=$attempt/$maxAttempts failed reason=${e.runtimeType}');
        if (audioStarted) break;
      }
      // 공유 클라이언트는 닫지 않는다 — 연결 재사용이 목적이다.
    }

    // 모든 시도 실패 또는 재생 중 끊김.
    await _pcmPlayer.abort();
    final cancelled = utterance._cancelRequested;
    utterance._settle(false,
        cancelled ? TtsUtteranceStatus.cancelled : TtsUtteranceStatus.failed);
    if (playbackStartNotified) onPlaybackEnd?.call(request, false);
    if (!cancelled) {
      _log('❌ [TTS-ADAPTER]',
          'failed turnId=${request.turnId} speaker=${request.speakerType.name}');
    }
  }
}
