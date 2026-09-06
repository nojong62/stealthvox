// ====================================================================
// 🔬 [DUO-OBSERVE] **GPT에 실제로 보낸 그 소리**를 귀와 눈으로 확인하는 자리
// --------------------------------------------------------------------
// 예전 이름은 A/B 비교였다. 스트리밍(live)과 파일(file) 두 경로에 같은 소리를
// 넣어 어느 쪽이 틀렸는지 가리는 장치였고, 그래서 소리도 **자기가 따로**
// 모았다.
//
// 이제 전사 경로는 하나뿐이다(Deepgram 경계 → gpt-transcribe). 비교할 상대가
// 없어졌으므로 이 장치의 일도 바뀐다.
//
//   "전사가 틀렸다. 소리가 나빴나, 모델이 틀렸나?"
//
// 답하려면 **모델이 받은 바로 그 소리**를 들어 봐야 한다.
//
// 🚫 그래서 **소리를 다시 모으지 않는다.** 버퍼를 따로 두면 이벤트 순서나
//   조각 전달이 한 번만 어긋나도
//
//       본선이 보낸 PCM  ≠  진단이 저장한 PCM
//
//   이 되고, 그러면 "WAV는 멀쩡한데 전사만 틀렸다"는 관찰 자체를 믿을 수
//   없다. 확정은 본선(`DuoUtteranceCapture`)에서 **한 번만** 일어나고,
//   여기는 그 결과를 건네받아 보기만 한다.
//
// ⚠️ **개발 빌드 전용이다.** WAV를 남기고 전사문 원문을 로그에 싣는다.
//   release에서는 만들어지지도 않는다([kDuoSttAbProbeEnabled]).
//
// 통화 경로에는 손대지 않는다. 이 클래스가 던지든 늦든 릴레이 송신과 전사는
// 이미 지나간 뒤다.
// ====================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'duo_utterance_capture.dart';
import 'pcm_audio_utils.dart';

/// A/B 비교를 켤 것인가. 개발 빌드에서 끄고 싶을 때 쓴다.
/// `--dart-define=DUO_STT_AB_PROBE=false`
const bool kDuoSttAbProbeEnabled =
    bool.fromEnvironment('DUO_STT_AB_PROBE', defaultValue: true);

/// 🔴 **release 빌드에서 진단을 강제로 켜는 스위치.**
///
/// 기본값은 꺼짐이다. **평범한 배포 빌드는 이 값을 절대 켜지 않는다** —
/// 켜면 전사문 원문이 logcat에 실리고, 발화마다 전사 요청이 한 번 더 나가
/// 비용이 두 배가 된다.
///
/// 켜는 경우는 하나뿐이다: 딥링크가 살아 있어야 게스트가 입장할 수 있어
/// **진단을 트랙 빌드로 올려야 할 때**(App Links는 트랙 배포만 산다).
/// 그 빌드는 진단이 끝나면 반드시 내린다.
///
///   flutter build appbundle --dart-define=DUO_STT_DIAG=true
const bool kDuoSttDiagForced =
    bool.fromEnvironment('DUO_STT_DIAG', defaultValue: false);

/// 발화 앞에 붙여 두는 소리. Server VAD의 `prefix_padding_ms`(듀오 500ms)가
/// 하는 일을 파일 쪽에서도 해 줘야 **같은 소리**를 견주는 것이 된다.
/// 안 붙이면 파일 쪽만 첫 음절이 잘린 채 비교되어 결론이 뒤집힌다.
const int kDuoAbPreRollMs = 600;

/// 한 발화의 상한. 이보다 길면 앞쪽을 버린다 — 진단용 버퍼가 메모리를
/// 끝없이 먹으면 안 된다.
const int kDuoAbMaxUtteranceMs = 30000;

/// 전사문을 기다리는 발화의 최대 개수. 넘으면 오래된 것부터 버린다.
const int kDuoAbMaxPending = 4;

/// 파일 전사 상한. 스트리밍보다 느려도 진단이라 넉넉히 준다.
const Duration kDuoAbFileTimeout = Duration(seconds: 20);

/// 한 발화의 소리와 그것을 잰 값.
class DuoAbUtterance {
  DuoAbUtterance({
    required this.itemId,
    required this.pcm,
    required this.sampleRate,
    required this.voicedMs,
    required this.voicedSource,
    required this.frames,
    required this.maxFrameGapMs,
  });

  final String itemId;
  final Uint8List pcm;
  final int sampleRate;

  /// 서버 VAD가 잰 발화 길이. 없으면 null.
  final int? voicedMs;
  final String voicedSource;

  /// 이 발화 동안 마이크에서 받은 조각 수.
  final int frames;

  /// 조각과 조각 사이의 최대 공백(ms). 오디오가 실제로 끊겼는지 본다 —
  /// 조각 하나가 20ms 분량인데 공백이 200ms면 그 사이 소리는 없는 것이다.
  final int maxFrameGapMs;

  int get durationMs => pcm16DurationMs(pcm.length, sampleRate: sampleRate);
}

/// PCM16 한 덩어리의 상태. **소리의 내용이 아니라 상태만** 잰다.
class DuoAbPcmStats {
  const DuoAbPcmStats({
    required this.rmsDbfs,
    required this.peakDbfs,
    required this.clippedPercent,
    required this.silentPercent,
  });

  /// 평균 세기(dBFS). 말소리는 대개 -30~-15 언저리다.
  /// -45보다 조용하면 마이크가 멀거나 AEC가 과하게 깎은 것이다.
  final double rmsDbfs;

  /// 최대 세기(dBFS). 0에 붙으면 클리핑이다.
  final double peakDbfs;

  /// 최대치에 닿은 샘플 비율(%). 1%만 넘어도 전사가 무너진다.
  final double clippedPercent;

  /// 거의 무음인 샘플 비율(%). AEC가 발화를 통째로 눌렀는지 본다.
  final double silentPercent;

  @override
  String toString() => 'rmsDbfs=${rmsDbfs.toStringAsFixed(1)} '
      'peakDbfs=${peakDbfs.toStringAsFixed(1)} '
      'clippedPct=${clippedPercent.toStringAsFixed(2)} '
      'silentPct=${silentPercent.toStringAsFixed(1)}';
}

/// PCM16 LE mono 한 덩어리를 잰다.
DuoAbPcmStats measurePcm16(Uint8List pcm) {
  final int samples = pcm.lengthInBytes ~/ 2;
  if (samples == 0) {
    return const DuoAbPcmStats(
      rmsDbfs: -160,
      peakDbfs: -160,
      clippedPercent: 0,
      silentPercent: 100,
    );
  }
  final ByteData view = ByteData.sublistView(pcm, 0, samples * 2);
  var sumSquares = 0.0;
  var peak = 0;
  var clipped = 0;
  var silent = 0;
  for (var i = 0; i < samples; i++) {
    final int raw = view.getInt16(i * 2, Endian.little);
    final int magnitude = raw.abs();
    if (magnitude > peak) peak = magnitude;
    // 32767/-32768에 닿은 샘플. 여유를 조금 두고 본다.
    if (magnitude >= 32700) clipped++;
    // 16비트에서 이 아래는 사실상 무음이다(약 -60dBFS).
    if (magnitude <= 32) silent++;
    final double v = raw / 32768.0;
    sumSquares += v * v;
  }
  // 게이트(`DuoUtteranceRmsMeter`)와 **같은 식**을 쓴다. 두 벌이면 로그의
  // 세기와 판정의 세기가 어긋난다.
  return DuoAbPcmStats(
    rmsDbfs: pcm16LinearToDbfs(math.sqrt(sumSquares / samples)),
    peakDbfs: pcm16LinearToDbfs(peak / 32768.0),
    clippedPercent: clipped * 100.0 / samples,
    silentPercent: silent * 100.0 / samples,
  );
}

/// 견주기 전에 지우는 것들. 공백·문장부호·대소문자 차이는 "다른 말"이 아니다.
final RegExp _kCompareStrip = RegExp('[\\s.,!?~…"\'·、。！？]');

String _normalizeForCompare(String s) =>
    s.toLowerCase().replaceAll(_kCompareStrip, '').trim();

/// 두 전사문이 같은 말인가. **정확도 판정이 아니라 눈에 띄는 차이만** 가린다.
bool sameTranscript(String a, String b) =>
    _normalizeForCompare(a) == _normalizeForCompare(b);

/// 파일 전사 함수의 모양. 시험에서 갈아 끼우려고 따로 이름을 준다.
typedef DuoAbFileTranscriber = Future<String?> Function({
  required String apiKey,
  required Uint8List pcm,
  int sampleRate,
  String? language,
  String model,
  Duration timeout,
  void Function(String tag, String msg)? onLog,
  bool trimLeadingSilence,
});

/// 한 통화짜리 A/B 비교기.
class DuoSttAbProbe {
  DuoSttAbProbe({
    required this.speakerRole,
    required this.languageCode,
    this.sampleRate = kStealthVoxSttSampleRate,
    this.onLog,
    this.saveWavDir,
  });

  final String speakerRole;

  /// 최종 전사에 넘긴 것과 **같은 값**. 로그에서 어느 언어로 들었는지 본다.
  final String languageCode;

  final int sampleRate;
  final void Function(String tag, String msg)? onLog;

  /// 소리를 WAV로 남길 자리. null이면 남기지 않는다.
  /// 남기면 **GPT가 실제로 받은 소리를 귀로** 확인할 수 있다.
  final Directory? saveWavDir;

  /// 확정됐지만 아직 전사문이 안 온 발화들. 도착 순서가 아니라 발화 id로 잇는다.
  final Map<String, DuoAbUtterance> _pending = <String, DuoAbUtterance>{};
  final List<String> _pendingOrder = <String>[];

  int _savedFiles = 0;
  bool _disposed = false;

  int get pendingCount => _pending.length;
  int get savedFiles => _savedFiles;

  void _lg(String tag, String msg) => onLog?.call(tag, msg);

  /// 본선이 **확정한 그 발화**를 건네받는다. 소리를 다시 모으지 않는다.
  ///
  /// 여기 들어온 PCM은 `gpt-transcribe`에 간 것과 **같은 바이트**다. 그래야
  /// 나중에 저장된 WAV를 듣고 "모델이 이걸 듣고 그렇게 적었다"고 말할 수 있다.
  void observe(
    DuoCapturedUtterance utterance, {
    int? voicedMs,
    String voicedSource = 'local',
  }) {
    if (_disposed || utterance.isEmpty) return;
    _pending[utterance.utteranceId] = DuoAbUtterance(
      itemId: utterance.utteranceId,
      pcm: utterance.pcm,
      sampleRate: utterance.sampleRate,
      voicedMs: voicedMs,
      voicedSource: voicedSource,
      frames: utterance.frames,
      maxFrameGapMs: utterance.maxFrameGapMs,
    );
    _pendingOrder.add(utterance.utteranceId);
    while (_pendingOrder.length > kDuoAbMaxPending) {
      _pending.remove(_pendingOrder.removeAt(0));
    }
  }

  /// 최종 전사문이 나왔다. 소리의 상태를 남기고 WAV를 떨군다.
  ///
  /// **호출부는 흘려보내면 된다.** 결과는 로그로만 나온다 — 통화도 저장도
  /// 이 future를 기다리지 않는다.
  Future<void> noteTranscript(String utteranceId, String text) async {
    if (_disposed) return;
    final DuoAbUtterance? utterance = _pending.remove(utteranceId);
    _pendingOrder.remove(utteranceId);
    if (utterance == null) {
      _lg('🔬 [DuoSTT-OBS]', 'skipped utt=$utteranceId reason=no_audio');
      return;
    }

    final DuoAbPcmStats stats = measurePcm16(utterance.pcm);
    // 소리의 상태부터 남긴다. WAV 저장이 실패해도 이 줄은 남아야 한다.
    _lg(
        '🔬 [DuoSTT-PCM]',
        'speaker=$speakerRole utt=$utteranceId rate=$sampleRate '
            'bytes=${utterance.pcm.length} durationMs=${utterance.durationMs} '
            'voicedMs=${utterance.voicedMs ?? -1} src=${utterance.voicedSource} '
            'frames=${utterance.frames} maxFrameGapMs=${utterance.maxFrameGapMs} '
            '$stats');

    final String? wavPath = await _saveWav(utterance);
    if (wavPath != null) {
      _lg('🔬 [DuoSTT-WAV]', 'utt=$utteranceId path=$wavPath');
    }

    _lg(
        '🔬 [DuoSTT-OBS]',
        'speaker=$speakerRole utt=$utteranceId language=$languageCode '
            'durationMs=${utterance.durationMs} '
            'text="${text.trim()}"');
  }

  Future<String?> _saveWav(DuoAbUtterance utterance) async {
    final Directory? dir = saveWavDir;
    if (dir == null) return null;
    try {
      final Uint8List wav =
          pcm16ToWav(utterance.pcm, sampleRate: utterance.sampleRate);
      final String name =
          '${speakerRole.toLowerCase()}_${_savedFiles.toString().padLeft(3, '0')}'
          '_${utterance.durationMs}ms.wav';
      final File file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(wav, flush: true);
      _savedFiles++;
      return file.path;
    } catch (e) {
      _lg('🔬 [DuoSTT-WAV]', 'save_failed(${e.runtimeType})');
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    _pendingOrder.clear();
  }
}

// ====================================================================
// 🎙️ [DUO-AB-CALL] 통화 한 통을 통째로 남기는 녹음기.
// --------------------------------------------------------------------
// 발화 단위 A/B([DuoSttAbProbe])만으로는 **못 가리는 경우가 하나** 있다.
//
//   Server VAD가 한 문장을 두 조각으로 잘랐다면, live도 file도 그 잘린
//   조각을 받는다. 둘 다 똑같이 틀리고 `match=true`가 나온다 — 그러면
//   "소리가 나쁘다"로 잘못 읽게 된다. 실제 범인은 분절인데.
//
// 그래서 통화 전체를 한 벌 더 남긴다. 이 WAV 하나를 같은 모델에 통째로
// 넣어 보면 분절이 원인인지 바로 갈린다.
//
//   통짜 파일은 맞는데 조각들이 틀림 → Server VAD 분절 문제
//   통짜 파일도 틀림               → 소리 자체(마이크·AEC·리샘플) 문제
//
// ⚠️ 개발 빌드 전용이다. 24kHz mono PCM16은 1분에 약 2.9MB다.
// ====================================================================

/// 통짜 녹음의 상한. 넘으면 더 안 쓰고 로그만 남긴다(약 29MB).
const int kDuoAbCallRecordMaxMs = 10 * 60 * 1000;

/// 통화 한 통을 WAV 한 개로 남긴다. **오디오 콜백을 절대 막지 않는다** —
/// 쓰기는 Future 사슬로 뒤에서 돈다.
class DuoAbCallRecorder {
  DuoAbCallRecorder({
    required this.file,
    this.sampleRate = kStealthVoxSttSampleRate,
    this.onLog,
    this.maxMs = kDuoAbCallRecordMaxMs,
  });

  final File file;
  final int sampleRate;
  final void Function(String tag, String msg)? onLog;
  final int maxMs;

  RandomAccessFile? _raf;
  Future<void> _chain = Future<void>.value();
  int _dataBytes = 0;
  bool _capped = false;
  bool _stopped = false;

  int get dataBytes => _dataBytes;
  bool get isCapped => _capped;
  int get durationMs => pcm16DurationMs(_dataBytes, sampleRate: sampleRate);

  int get _maxBytes => maxMs * (sampleRate * 2 ~/ 1000);

  /// 자리를 잡고 44바이트 헤더 자리를 비워 둔다. 크기는 [stop]에서 채운다.
  Future<bool> start() async {
    try {
      _raf = await file.open(mode: FileMode.write);
      // 길이가 0인 채로 써 두고 닫을 때 덮어쓴다.
      await _raf!.writeFrom(pcm16ToWav(Uint8List(0), sampleRate: sampleRate));
      return true;
    } catch (e) {
      onLog?.call('🎙️ [DuoSTT-CALLWAV]', 'open_failed(${e.runtimeType})');
      _raf = null;
      return false;
    }
  }

  /// 마이크 조각 하나. 여기서 기다리지 않는다.
  void add(Uint8List pcm) {
    if (_raf == null || _stopped || pcm.isEmpty) return;
    if (_dataBytes >= _maxBytes) {
      if (!_capped) {
        _capped = true;
        onLog?.call('🎙️ [DuoSTT-CALLWAV]',
            'capped at ${maxMs ~/ 1000}s — 이후 소리는 안 남는다');
      }
      return;
    }
    _dataBytes += pcm.length;
    _chain = _chain.then((_) async {
      final raf = _raf;
      if (raf == null) return;
      try {
        await raf.writeFrom(pcm);
      } catch (_) {
        // 조각 하나 실패로 통화를 죽이지 않는다.
      }
    });
  }

  /// 헤더의 크기를 실제 값으로 채우고 닫는다. 파일 경로를 돌려준다.
  Future<String?> stop() async {
    if (_stopped) return null;
    _stopped = true;
    final raf = _raf;
    if (raf == null) return null;
    try {
      await _chain;
      // 완성된 크기로 헤더를 다시 만들어 앞 44바이트에 덮어쓴다.
      final Uint8List header = pcm16ToWav(
        Uint8List(0),
        sampleRate: sampleRate,
      );
      final ByteData patched = ByteData.sublistView(header);
      patched.setUint32(4, 36 + _dataBytes, Endian.little); // RIFF chunk size
      patched.setUint32(40, _dataBytes, Endian.little); // data chunk size
      await raf.setPosition(0);
      await raf.writeFrom(header);
      await raf.flush();
      await raf.close();
      _raf = null;
      onLog?.call(
          '🎙️ [DuoSTT-CALLWAV]',
          'saved path=${file.path} bytes=$_dataBytes '
              'durationMs=$durationMs capped=$_capped');
      return file.path;
    } catch (e) {
      onLog?.call('🎙️ [DuoSTT-CALLWAV]', 'close_failed(${e.runtimeType})');
      try {
        await raf.close();
      } catch (_) {}
      _raf = null;
      return null;
    }
  }
}
