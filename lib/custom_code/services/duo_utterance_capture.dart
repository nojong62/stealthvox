// ====================================================================
// 🎙️ [DUO-CAPTURE] 발화 하나의 소리를 앞뒤 여유까지 담아 두는 자리
// --------------------------------------------------------------------
// 이 클래스가 지키는 약속은 하나다.
//
//   **판정으로 PCM을 버리지 않는다.**
//
// 말이 시작됐다는 신호는 언제나 소리보다 늦게 온다. 그래서 평소에도 최근
// 소리를 짧은 고리에 담아 두고, 시작 신호가 오면 그 고리를 발화 앞에 붙인다.
// 이것이 없으면 "안녕하세요"의 첫 `안`이 전사 쪽에서만 사라진다.
//
//   평소        → 최근 [preRollMs]만 고리에 유지 (그 앞은 흘려보낸다)
//   문 닫힘     → 고리를 [kDuoCaptureGateClosedRingMs]까지 늘린다
//   begin()     → 고리를 통째로 발화 앞에 붙이고 수집 시작
//   수집 중     → 들어오는 조각을 그대로 쌓는다
//   commit()    → 지금까지 모인 것을 한 덩이 PCM으로 확정
//
// 🚪 **전사로 가는 문(gate)은 여기를 막지 않는다.** 문이 닫혀 있어도 소리는
//   계속 담는다 — 문이 정하는 것은 "Deepgram으로 보낼 것인가"이지 "소리를
//   보존할 것인가"가 아니다(`DuoSttPipeline.addPcm`).
//
// ⚠️ **speech/non-speech를 여기서 판정하지 않는다.** 이 클래스는 귀가 아니라
//   손이다. 무엇이 말이고 무엇이 아닌지는 바깥(Deepgram)이 정하고, 여기는
//   시키는 대로 담고 내줄 뿐이다. 여기에 VAD를 넣는 순간 "프레임을 미리
//   버리는 gate"가 되어, 작은 음절과 짧은 대답이 조용히 사라진다.
//
// 🧠 메모리는 평평해야 한다. 고리는 [preRollMs]로, 발화는 [maxUtteranceMs]로
//   상한을 둔다. 24kHz·16bit·mono 기준 1초 = 48KB이므로 고리 1000ms ≈ 48KB,
//   발화 30초 ≈ 1.4MB다. 상한을 넘으면 **앞쪽부터** 버린다 — 뒤쪽(방금 한
//   말)이 더 중요하다.
//
// 📌 이 규칙을 진단(`duo_stt_ab_probe.dart`)과 본선이 **함께 쓴다.** 두 곳이
//   각자 담으면 "진단에서는 되는데 본선에서는 안 된다"가 생긴다.
// ====================================================================

import 'dart:typed_data';

import 'pcm_audio_utils.dart';

/// 발화 시작 신호보다 앞선 소리를 얼마나 들고 있을 것인가.
///
/// Server VAD의 `prefix_padding_ms`가 하던 일을 파일 쪽에서도 해 주는 값이다.
/// 진단이 쓰던 600ms로 시작했다가 1000ms로 올렸다 — `SpeechStarted`는
/// Deepgram의 VAD 지연에 네트워크 왕복까지 얹혀 **소리보다 늦게** 온다.
/// 그 지연이 600ms를 넘는 순간 첫 음절이 고리에서 밀려나고, 통화에는 멀쩡히
/// 들린 말이 **전사 쪽에서만** 첫 글자를 잃는다.
///
/// 값을 키워도 메모리는 발화당 29KB → 48KB뿐이다(24kHz·16bit·mono).
/// 앞을 더 담는 대가는 이 정도이고, 잘린 첫 음절은 되돌릴 방법이 없다.
const int kDuoCapturePreRollMs = 1000;

/// 🚪 [GATE-CLOSED RING] 전사로 가는 문이 닫혀 있는 동안 고리를 얼마까지
/// 늘릴 것인가.
///
/// 평소 고리는 [kDuoCapturePreRollMs]면 충분하다 — 시작 신호가 소리보다 늦게
/// 오는 그 지연만 덮으면 되기 때문이다. 그런데 문이 닫히는 구간은 그보다 길다.
///
///   마이크 기동 ~ 문 열림   수백 ms   → 1000ms로 덮인다
///   상대 목소리 재생 중      수 초     → **안 덮인다**
///
/// 재생 중에 한 말은 문이 닫혀 있어 Deepgram으로 안 가고, 그래서 경계도 안
/// 잡힌다. 그건 에코 방어의 대가라 이 판에서 바꾸지 않는다. 다만 **소리까지
/// 잃을 이유는 없다** — 통화가 끝난 뒤 다시 들을 수 있어야 한다.
///
/// 그래서 문이 닫혀 있는 동안만 고리를 늘리고, 열리는 순간 평소 길이로
/// 돌아간다. 24kHz·16bit 기준 10초는 480KB다.
///
/// ⚠️ **무한 가변이 아니다.** 문이 오래 닫혀 있어도 여기서 멈춘다.
const int kDuoCaptureGateClosedRingMs = 10000;

/// 한 발화의 상한. 이보다 길면 앞쪽을 버린다.
///
/// 사람이 30초를 쉬지 않고 말하는 일은 드물다. 그보다 길어지는 것은 대개
/// 종료 신호를 놓친 경우이고, 그때 메모리가 통화를 죽이면 안 된다.
const int kDuoCaptureMaxUtteranceMs = 30000;

/// 확정된 발화 하나. 소리와 그 소리가 어떻게 모였는지가 함께 온다.
class DuoCapturedUtterance {
  const DuoCapturedUtterance({
    required this.utteranceId,
    required this.pcm,
    required this.sampleRate,
    required this.preRollBytes,
    required this.frames,
    required this.maxFrameGapMs,
  });

  /// 이 앱이 발급한 발화 id. **외부 서비스 id를 쓰지 않는다** —
  /// Deepgram·OpenAI가 주는 값은 각자의 사정으로 바뀌고, 한 발화를 끝까지
  /// 따라가야 하는 것은 이 앱이다.
  final String utteranceId;

  /// 앞 여유를 포함한 발화 전체.
  final Uint8List pcm;
  final int sampleRate;

  /// [pcm] 앞쪽 중 고리에서 온 몫. 로그가 "앞을 얼마나 지켰나"를 말할 수 있다.
  final int preRollBytes;

  /// 담은 조각 수와 조각 사이 최대 간격. 소리가 끊겨 들어왔는지 본다.
  final int frames;
  final int maxFrameGapMs;

  int get durationMs => pcm16DurationMs(pcm.length, sampleRate: sampleRate);
  int get preRollMs => pcm16DurationMs(preRollBytes, sampleRate: sampleRate);
  int get bodyMs => durationMs - preRollMs;
  bool get isEmpty => pcm.isEmpty;
}

/// 통화 한 통 = 이 객체 한 개. 발화마다 [begin] → [commit]을 한 번씩 탄다.
class DuoUtteranceCapture {
  DuoUtteranceCapture({
    required this.idPrefix,
    this.sampleRate = kStealthVoxSttSampleRate,
    this.preRollMs = kDuoCapturePreRollMs,
    this.maxUtteranceMs = kDuoCaptureMaxUtteranceMs,
    this.gateClosedRingMs = kDuoCaptureGateClosedRingMs,
  });

  /// 발급하는 id의 머리말. 모드를 구별해 로그에서 바로 읽히게 한다
  /// (`duo_direct` / `duo_interp`).
  final String idPrefix;
  final int sampleRate;
  final int preRollMs;
  final int maxUtteranceMs;

  /// 문이 닫혀 있는 동안의 고리 상한([kDuoCaptureGateClosedRingMs]).
  final int gateClosedRingMs;

  int get _bytesPerMs => sampleRate * 2 ~/ 1000;

  final List<Uint8List> _preRoll = <Uint8List>[];
  int _preRollBytes = 0;

  final List<Uint8List> _current = <Uint8List>[];
  int _currentBytes = 0;
  int _currentFrames = 0;

  /// 이번 발화가 시작될 때 고리에서 가져온 몫.
  int _openingPreRollBytes = 0;

  bool _capturing = false;

  /// 🚪 전사로 가는 문이 닫혀 있는가. **고리 길이만 가른다** — 담고 안 담고는
  ///   여기서 정하지 않는다(이 클래스는 언제나 담는다).
  bool _gateClosed = false;

  String? _currentId;
  int _seq = 0;

  DateTime? _lastFrameAt;
  int _maxFrameGapMs = 0;

  bool get isCapturing => _capturing;

  /// 지금 담고 있는 발화의 id. 담고 있지 않으면 null이다.
  String? get currentId => _currentId;

  /// 지금까지 담은 길이(앞 여유 포함).
  int get currentMs => pcm16DurationMs(_currentBytes, sampleRate: sampleRate);

  /// 고리에 들고 있는 앞소리 길이.
  int get preRollBufferedMs =>
      pcm16DurationMs(_preRollBytes, sampleRate: sampleRate);

  /// 마이크 조각 하나. **여기서는 아무것도 판정하지 않는다.**
  void addPcm(Uint8List pcm) {
    if (pcm.isEmpty) return;

    final DateTime now = DateTime.now();
    final DateTime? last = _lastFrameAt;
    if (last != null && _capturing) {
      final int gap = now.difference(last).inMilliseconds;
      if (gap > _maxFrameGapMs) _maxFrameGapMs = gap;
    }
    _lastFrameAt = now;

    if (_capturing) {
      _current.add(pcm);
      _currentBytes += pcm.length;
      _currentFrames++;
      // 상한을 넘으면 앞쪽을 버린다. 뒤쪽(방금 한 말)이 더 중요하다.
      final int maxBytes = maxUtteranceMs * _bytesPerMs;
      while (_currentBytes > maxBytes && _current.length > 1) {
        final int dropped = _current.removeAt(0).length;
        _currentBytes -= dropped;
        // 버린 몫이 고리에서 온 것이면 그만큼 앞 여유도 줄어든 것이다.
        if (_openingPreRollBytes > 0) {
          _openingPreRollBytes =
              (_openingPreRollBytes - dropped).clamp(0, _openingPreRollBytes);
        }
      }
      return;
    }

    _preRoll.add(pcm);
    _preRollBytes += pcm.length;
    final int maxPreRoll = _ringMs * _bytesPerMs;
    while (_preRollBytes > maxPreRoll && _preRoll.length > 1) {
      _preRollBytes -= _preRoll.removeAt(0).length;
    }
  }

  /// 🚪 전사로 가는 문이 닫혔다. 고리를 [gateClosedRingMs]까지 늘린다.
  ///
  /// **소리를 더 들고 있을 뿐 아무것도 판정하지 않는다.** 문이 닫힌 동안의
  /// 소리도 통화가 끝난 뒤에는 다시 들을 수 있어야 한다.
  void onGateClosed() {
    if (_gateClosed) return;
    _gateClosed = true;
  }

  /// 🚪 문이 열렸다. **평소 길이로 곧바로 돌아간다.**
  ///
  /// 늘어난 고리를 그대로 두면 다음 발화 앞에 몇 초짜리 앞소리가 붙는다.
  /// 여기서 줄이되, 줄이는 것은 **가장 오래된 쪽**이다 — 문이 열리기 직전
  /// 소리가 다음 발화의 첫 음절일 수 있다.
  void onGateOpened() {
    if (!_gateClosed) return;
    _gateClosed = false;
    final int maxPreRoll = _ringMs * _bytesPerMs;
    while (_preRollBytes > maxPreRoll && _preRoll.length > 1) {
      _preRollBytes -= _preRoll.removeAt(0).length;
    }
  }

  /// 지금 고리가 들고 있어야 할 길이.
  int get _ringMs => _gateClosed ? gateClosedRingMs : preRollMs;

  /// 말이 시작됐다. 고리에 담아 둔 앞소리를 발화 앞에 붙이고 담기 시작한다.
  ///
  /// 이미 담는 중이면 **새로 시작하지 않고** 지금 id를 그대로 돌려준다 —
  /// 시작 신호가 두 번 와도 한 발화는 하나다.
  String begin() {
    if (_capturing) return _currentId!;
    _seq++;
    _currentId = '${idPrefix}_utt_$_seq';
    _capturing = true;
    _current
      ..clear()
      ..addAll(_preRoll);
    _currentBytes = _preRollBytes;
    _currentFrames = _preRoll.length;
    _openingPreRollBytes = _preRollBytes;
    _maxFrameGapMs = 0;
    _preRoll.clear();
    _preRollBytes = 0;
    return _currentId!;
  }

  /// 발화가 끝났다. 지금까지 모인 소리를 한 덩이로 확정한다.
  ///
  /// 담고 있지 않았거나 담긴 것이 없으면 **null이다** — 빈 발화를 만들어
  /// 내보내면 전사기가 무음에서 문장을 지어낸다.
  DuoCapturedUtterance? commit() {
    if (!_capturing) return null;
    _capturing = false;
    final String id = _currentId ?? '';
    _currentId = null;
    if (_currentBytes == 0 || id.isEmpty) {
      _clearCurrent();
      return null;
    }

    final Uint8List pcm = Uint8List(_currentBytes);
    var offset = 0;
    for (final chunk in _current) {
      pcm.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    final utterance = DuoCapturedUtterance(
      utteranceId: id,
      pcm: pcm,
      sampleRate: sampleRate,
      preRollBytes: _openingPreRollBytes,
      frames: _currentFrames,
      maxFrameGapMs: _maxFrameGapMs,
    );
    _clearCurrent();
    return utterance;
  }

  /// 담던 것을 버린다. 소켓이 끊겼다 붙는 등, 어느 발화의 것도 아닌 소리를
  /// 다음 발화에 붙이지 않기 위해서다. **id는 다시 쓰지 않는다.**
  void abort() {
    _capturing = false;
    _currentId = null;
    _clearCurrent();
  }

  /// 통화가 끝났다. 고리까지 비운다.
  void reset() {
    abort();
    _preRoll.clear();
    _preRollBytes = 0;
    _lastFrameAt = null;
    _gateClosed = false;
  }

  void _clearCurrent() {
    _current.clear();
    _currentBytes = 0;
    _currentFrames = 0;
    _openingPreRollBytes = 0;
    _maxFrameGapMs = 0;
  }
}
