import 'dart:math' as math;
import 'dart:typed_data';

// ====================================================================
// 🔊 [DUO-RELAY-GATE] 내가 말하지 않는 동안에는 상대에게 보내지 않는다.
// --------------------------------------------------------------------
// 직접 대화는 마이크에 들어온 프레임을 **전부** 릴레이로 보냈다. 통화니까
// 당연해 보이지만, 두 폰이 한 집에 있으면 되먹임 고리가 생긴다.
//
//   안방에서 낸 목소리 → (벽 너머 공기로) 거실 폰 마이크 → 릴레이 →
//   안방 폰 스피커 → 안방 사람이 자기 목소리를 늦게 다시 듣는다.
//
// 폰 안의 AEC는 **자기 스피커로 내보낸 신호**만 지운다. 벽을 넘어 마이크에
// 직접 들어온 실제 목소리는 참조 신호에 없어서 못 지운다. 2026-08-28 실기기
// (안방↔거실)에서 실장님이 울림으로 들었고, 릴레이 왕복이 13ms에 재생
// 프리버퍼가 100ms라 또렷한 메아리로 들린다.
//
// 그래서 **말하지 않는 쪽은 침묵을 보낸다.** 거실 폰이 아무 말도 안 하고
// 있으면 벽 넘어온 소리도 같이 안 나가므로 고리가 끊긴다.
//
// 잘라먹지 않기 위한 두 장치:
//   · 앞소리(prefix) — 게이트가 닫혀 있는 동안에도 최근 프레임을 물고 있다가,
//     말이 시작되면 물고 있던 것부터 함께 보낸다. 첫 음절이 살아남는다.
//   · 여운(hangover) — 말을 멈춰도 곧바로 닫지 않는다. 문장 사이 숨 쉬는
//     자리에서 끊기지 않는다.
//
// **전사(STT)에는 손대지 않는다.** 이 게이트는 릴레이 갈래에만 걸린다.
// 전사는 서버 VAD가 따로 보고 있고, 2026-08-28에 겨우 좋아진 자리라
// 같이 흔들지 않는다.
// ====================================================================

/// 말로 칠 최소 세기(RMS, 0.0~1.0). 마이크가 먼 자리를 감안해 낮게 잡는다 —
/// 잘못 열리면 울림이 조금 남을 뿐이지만, 잘못 닫히면 말이 안 간다.
const double kDuoRelayGateRms = 0.010;

/// 말이 시작될 때 되돌려 보낼 앞소리 길이.
const int kDuoRelayGatePrefixMs = 500;

/// 말이 멈춘 뒤에도 계속 보내는 여운.
const int kDuoRelayGateHangoverMs = 800;

/// 16-bit PCM 한 프레임의 RMS를 0.0~1.0으로 돌려준다.
double duoFrameRms(Uint8List frame) {
  final int samples = frame.lengthInBytes ~/ 2;
  if (samples == 0) return 0;
  final ByteData view = ByteData.sublistView(frame, 0, samples * 2);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final double v = view.getInt16(i * 2, Endian.little) / 32768.0;
    sum += v * v;
  }
  return math.sqrt(sum / samples);
}

/// 마이크 프레임을 받아 **상대에게 보낼 프레임만** 돌려준다.
///
/// 게이트가 닫혀 있으면 빈 목록이다. 열리는 순간에는 물고 있던 앞소리가
/// 함께 나오므로 목록이 여러 개일 수 있다.
class DuoRelayGate {
  DuoRelayGate({
    this.threshold = kDuoRelayGateRms,
    this.prefixMs = kDuoRelayGatePrefixMs,
    this.hangoverMs = kDuoRelayGateHangoverMs,
    required this.bytesPerMs,
    this.onGateChanged,
  });

  final double threshold;
  final int prefixMs;
  final int hangoverMs;
  final int bytesPerMs;

  /// 열리고 닫힐 때 한 번씩. `open`과 그 순간의 RMS를 넘긴다 — 문턱을
  /// 실기기에서 다시 잡으려면 이 값이 필요하다.
  final void Function(bool open, double rms)? onGateChanged;

  final List<Uint8List> _prefix = <Uint8List>[];
  int _prefixBytes = 0;
  bool _open = false;
  int _silentMs = 0;

  bool get isOpen => _open;

  /// 통화 한 판 동안 게이트가 막아 세운 바이트. 종료 로그가 읽는다.
  int get heldBytes => _heldBytes;
  int _heldBytes = 0;

  List<Uint8List> accept(Uint8List frame) {
    if (frame.isEmpty) return const <Uint8List>[];
    final double rms = duoFrameRms(frame);
    final bool voiced = rms >= threshold;
    final int frameMs =
        bytesPerMs > 0 ? frame.lengthInBytes ~/ bytesPerMs : 0;

    if (voiced) {
      _silentMs = 0;
      if (!_open) {
        _open = true;
        onGateChanged?.call(true, rms);
        // 물고 있던 앞소리를 먼저 흘려보낸다. 첫 음절이 여기 들어 있다.
        final List<Uint8List> out = <Uint8List>[..._prefix, frame];
        _prefix.clear();
        _prefixBytes = 0;
        return out;
      }
      return <Uint8List>[frame];
    }

    if (_open) {
      _silentMs += frameMs;
      if (_silentMs < hangoverMs) return <Uint8List>[frame];
      _open = false;
      _silentMs = 0;
      onGateChanged?.call(false, rms);
    }

    // 닫힌 동안에도 최근 [prefixMs]만큼은 물고 있는다.
    _heldBytes += frame.lengthInBytes;
    _prefix.add(frame);
    _prefixBytes += frame.lengthInBytes;
    final int budget = prefixMs * bytesPerMs;
    while (_prefix.length > 1 && _prefixBytes > budget) {
      _prefixBytes -= _prefix.removeAt(0).lengthInBytes;
    }
    return const <Uint8List>[];
  }

  void reset() {
    _prefix.clear();
    _prefixBytes = 0;
    _open = false;
    _silentMs = 0;
    _heldBytes = 0;
  }
}
