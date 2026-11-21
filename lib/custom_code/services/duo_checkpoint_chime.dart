// ====================================================================
// 🔔 [DUO-CHECKPOINT] 직접 통화 10분 저장 안내 — "딩동"
// --------------------------------------------------------------------
// 직접 통화의 대화 줄은 발화마다 바로 저장된다. 통화가 길어져도 사용자가
// "지금까지 저장돼 있다"는 것을 알 수 있도록 10분마다 짧은 소리와 안내를 낸다.
//
// 서클톡은 화면 표시만 있지만, 직접 통화는 통화 중에 화면을 안 보는 일이 많아
// 소리가 필요하다. 소리 파일을 따로 두지 않고 코드로 만든다(자산 추가 없음).
//
// ⚠️ 이 소리가 마이크로 되돌아가 글자로 전사되지 않도록, 호출부는 [kDuoChimeMuteMs]
//   동안 내 마이크 전사를 막는다.
// ====================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'pcm_audio_utils.dart';

const int _kDebugCheckpointSeconds =
    int.fromEnvironment('DUO_CHECKPOINT_SECONDS');

/// 안내 간격. 서클톡의 대화 세션 길이와 같다. 디버그 빌드에서만
/// `--dart-define=DUO_CHECKPOINT_SECONDS=40`으로 줄여 실기기에서 바로 볼 수 있다.
final Duration kDuoCheckpointEvery =
    (kDebugMode && _kDebugCheckpointSeconds > 0)
        ? Duration(seconds: _kDebugCheckpointSeconds)
        : const Duration(minutes: 10);

/// 소리가 울리는 동안(+ 꼬리) 내 마이크 전사를 막는 시간.
const int kDuoChimeMuteMs = 1800;

const int _kChimeSampleRate = 24000;

/// "딩동" — 높은 음(880Hz) 뒤에 낮은 음(660Hz). 부드럽게 줄어드는 사인파.
/// 순수 함수라 시험할 수 있다.
Uint8List buildDuoChimePcm() {
  Float64List tone(double hz, double seconds, double peak) {
    final int n = (_kChimeSampleRate * seconds).round();
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      final double t = i / _kChimeSampleRate;
      // 앞 10ms는 올리고(클릭 방지), 뒤로 갈수록 지수로 줄인다.
      final double attack = math.min(1.0, t / 0.01);
      final double decay = math.exp(-4.0 * t / seconds);
      out[i] = math.sin(2 * math.pi * hz * t) * peak * attack * decay;
    }
    return out;
  }

  final first = tone(880, 0.28, 0.45);
  final gap = Float64List((_kChimeSampleRate * 0.04).round());
  final second = tone(660, 0.42, 0.45);
  final total = first.length + gap.length + second.length;
  final pcm = Uint8List(total * 2);
  final view = ByteData.sublistView(pcm);
  var o = 0;
  for (final part in [first, gap, second]) {
    for (final v in part) {
      view.setInt16(o, (v * 32767).round().clamp(-32768, 32767), Endian.little);
      o += 2;
    }
  }
  return pcm;
}

Uint8List buildDuoChimeWav() =>
    pcm16ToWav(buildDuoChimePcm(), sampleRate: _kChimeSampleRate);

/// 소리를 한 번 낸다. 실패해도 통화에는 영향이 없다.
Future<void> playDuoCheckpointChime() async {
  final player = AudioPlayer();
  try {
    player.onPlayerComplete.listen((_) => player.dispose());
    await player.play(BytesSource(buildDuoChimeWav()), volume: 0.6);
  } catch (error) {
    debugPrint('[DUO-CHECKPOINT] chime_failed=${error.runtimeType}');
    await player.dispose();
  }
}
