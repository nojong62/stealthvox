// ====================================================================
// 🚦 [DUO-GATE] 직접 대화 전사문이 버려지는 자리를 한곳에 모은 것.
// --------------------------------------------------------------------
// 판정 로직은 `routine_mode_duo.dart`에 흩어져 있던 것을 **그대로** 옮겼다.
// 동작을 바꾸지 않는다 — 옮긴 이유는 하나다:
//
//   "GPT가 틀렸는가, 앱이 버렸는가"를 가리려면 버린 사유에 이름이 있어야 하고,
//   그 이름을 시험으로 고정할 수 있어야 한다.
//
// 실기기 로그의 `[DuoSTT-DECISION] reason=` 값이 여기 상수들이다.
// ====================================================================

import 'dart:math' as math;
import 'dart:typed_data';

import 'pcm_audio_utils.dart';

/// 전사문 한 줄의 처리 결과 이름. 로그·시험이 같은 문자열을 본다.
class DuoDropReason {
  DuoDropReason._();

  /// 버리지 않았다. 저장까지 갔다.
  static const String accepted = 'accepted';

  /// 통화 세대가 어긋났다(방을 나갔거나 다시 열었다). 늦게 도착한 콜백.
  static const String staleGeneration = 'stale_generation';

  /// 소리 난 시간이 문턱보다 짧다. **환청 방어선.**
  static const String voicedMs = 'voiced_ms';

  /// GPT가 빈 문자열을 돌려줬다.
  static const String emptyText = 'empty_text';

  /// 글자는 있는데 잡음 필터의 문자 집합에 하나도 안 걸렸다.
  ///
  /// ⚠️ **여기가 조용히 위험한 자리다.** 아래 [_kNoiseKeepPattern]이
  /// ASCII `\w` + 공백 + 완성형 한글(가-힣)만 남긴다. 그래서
  ///   · 한글 자모만 있는 말("ㅋㅋ", "ㅇㅇ")
  ///   · 일본어 가나("はい"), 중국어 한자("好的")
  ///   · 아랍/키릴 밖 문자
  /// 는 전부 빈 문자열이 되어 **정상 발화인데 잡음으로 버려진다.**
  /// 한국어 완성형 문장은 걸리지 않는다.
  static const String emptyAfterClean = 'empty_after_clean';

  /// 자막 관용구(유튜브 엔딩 멘트 등). 무음 구간에서 전사기가 지어내는 문장.
  static const String hardGhost = 'hard_ghost';

  /// 같은 item_id가 두 번 왔다(`completed`와 `done`이 같은 발화로 온다).
  static const String duplicateItem = 'duplicate_item';

  /// 발화 구간의 소리가 너무 작다. **환청 방어선.**
  ///
  /// [voicedMs]와 다른 축이다. 그쪽은 "얼마나 오래 났는가"이고 이쪽은
  /// "얼마나 크게 났는가"다. 2026-08-30 실기기 두 통(25발화)에서 길이로는
  /// 하나도 못 갈랐다 — 환청 10건이 전부 1.3~2.0초였다.
  static const String lowLevel = 'low_level';

  /// 히스토리 쓰기가 실패했다. 저장 판정은 통과했는데 글이 남지 않은 경우.
  static const String historyWriteFailed = 'history_write_failed';
}

/// 잡음 필터가 **남기는** 문자. 지우는 쪽이 아니라 남기는 쪽을 적어 둔다 —
/// 무엇이 살아남는지가 [DuoDropReason.emptyAfterClean]의 전부라서다.
///
/// `\w`는 Dart 정규식에서 유니코드가 아니라 **ASCII [A-Za-z0-9_]**다.
final RegExp _kNoiseKeepPattern = RegExp(r'[^\w\s가-힣]');

/// 무음 구간에서 전사 모델이 지어내는 자막 관용구.
const List<String> kDuoHardGhostPhrases = <String>[
  'thank you for watching',
  'thanks for watching',
  'please subscribe',
  'subtitles by',
  '시청해 주셔서',
  '시청해주셔서',
  '구독과 좋아요',
];

/// 이 전사문을 잡음으로 볼 사유. 잡음이 아니면 null.
///
/// **글자 수로 버리지 않는다.** "네"·"응"·"왜"는 여기를 그대로 통과한다 —
/// 짧은 대답과 환청을 가르는 것은 글자 수가 아니라 소리 난 시간이고,
/// 그건 [belowVoicedGate]가 판단한다.
String? noiseTranscriptReason(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return DuoDropReason.emptyText;
  final String lower = trimmed.toLowerCase();
  final String clean = lower.replaceAll(_kNoiseKeepPattern, '').trim();
  if (clean.isEmpty) return DuoDropReason.emptyAfterClean;
  for (final String ghost in kDuoHardGhostPhrases) {
    if (lower.contains(ghost)) return DuoDropReason.hardGhost;
  }
  return null;
}

/// 🔉 발화 구간 평균 세기의 문턱(dBFS). 이보다 조용하면 전사문을 버린다.
///
/// **이 값은 보편 상수가 아니다.** 2026-08-30 실기기 두 통(SM-S931N,
/// 스피커폰, 상대 침묵 조건 포함)의 실측 분포에서 고른 출발점이다.
///
///   확실한 실제 발화   −23.3 ~ −25.9 dBFS  (10건, 전사 전부 정확)
///   중간(판단 보류)     −29.1 dBFS         (1건)
///   확실한 환청        −44.7 ~ −50.4 dBFS  (10건, 전사 전부 엉터리)
///
/// 두 무리 사이 18.8dB가 비어 있고, 그 한가운데를 잡았다. 실제 발화 최저에서
/// 9dB, 환청 최고에서 10dB 여유다. **애매한 것은 살리는 쪽**이므로 −29.1은
/// 통과시킨다 — 사람이 한 말을 지우는 것보다 이상한 줄 하나가 남는 편이 낫다.
///
/// ⚠️ 기기·거리·AEC 구현에 따라 분포가 달라질 수 있다. 버린 줄은 로그에
/// `rmsDbfs`와 `threshold`를 함께 남기므로, 실기기 로그가 쌓이면 이 값을
/// 근거로 다시 잡을 것. 지금은 **직접 대화 전용 보호선**이다.
const double kDuoMinUtteranceRmsDbfs = -35.0;

/// 발화 구간이 문턱보다 조용한가.
///
/// ⚠️ **`null`은 "조용했다"가 아니라 "모른다"다.** 세기를 못 잰 발화를
/// 조용하다고 보면 근거 없이 사람 말을 버리게 된다 — 그때는 통과시킨다.
/// ([belowVoicedGate]와 같은 원칙이다)
bool belowLevelGate(double? rmsDbfs, {required double minDbfs}) =>
    rmsDbfs != null && rmsDbfs < minDbfs;

/// 소리 난 시간이 문턱 미만인가.
///
/// ⚠️ **`null`은 "짧았다"가 아니라 "모른다"다.** 서버도 로컬도 길이를 못 잰
/// 발화를 짧다고 보면 근거 없이 사람 말을 버리게 된다 — 그때는 통과시킨다.
bool belowVoicedGate(int? voicedMs, {required int minMs}) =>
    voicedMs != null && voicedMs < minMs;

// ====================================================================
// 🔉 [DUO-LEVEL] 발화 한 건의 평균 세기를 재는 자리.
// --------------------------------------------------------------------
// **PCM을 보관하지 않는다.** 조각이 지나갈 때 제곱합과 샘플 수만 더한다.
// 그래서 통화가 길어져도 메모리가 늘지 않고, release에서도 부담이 없다.
//
// 진단기(A/B probe·WAV 저장)와 **완전히 분리돼 있다.** 그쪽이 꺼져 있어도
// 이 계측은 돌아야 한다 — 게이트는 진단이 아니라 보호 장치다.
//
//   speech_started      → beginUtterance()   누적 시작(이전 값은 버린다)
//   마이크 조각마다      → addPcm()           제곱합만 더한다
//   committed(item_id)  → commitUtterance()  그 순간의 평균을 item에 묶는다
//   transcript 도착      → rmsDbfsOf(item)    게이트가 이 값을 읽는다
//
// ⚠️ `beginUtterance` 없이 `commitUtterance`가 오면 **아무것도 남기지
//   않는다.** 직전 발화의 값을 물려주면 조용한 발화가 앞 발화의 세기로
//   통과해 버린다 — 게이트가 있으나 마나가 된다.
// ====================================================================

/// 발화 구간 평균 세기 계산기. 통화 한 번에 하나.
class DuoUtteranceRmsMeter {
  DuoUtteranceRmsMeter({this.maxTrackedItems = 32});

  /// 값을 들고 있을 발화 수의 상한. 진행 중인 턴은 많아야 몇 개다.
  final int maxTrackedItems;

  double _sumSquares = 0;
  int _samples = 0;
  bool _active = false;

  final Map<String, double> _rmsByItem = <String, double>{};
  final List<String> _itemOrder = <String>[];

  bool get isActive => _active;
  int get trackedItems => _rmsByItem.length;

  /// 서버 VAD가 발화 시작을 알렸다. **이전 누적은 버린다.**
  void beginUtterance() {
    _sumSquares = 0;
    _samples = 0;
    _active = true;
  }

  /// 마이크 조각 하나. 누적하지 않는 상태면 아무 일도 안 한다.
  void addPcm(Uint8List pcm) {
    if (!_active || pcm.isEmpty) return;
    final int samples = pcm.lengthInBytes ~/ 2;
    if (samples == 0) return;
    final ByteData view = ByteData.sublistView(pcm, 0, samples * 2);
    for (var i = 0; i < samples; i++) {
      final double v = view.getInt16(i * 2, Endian.little) / 32768.0;
      _sumSquares += v * v;
    }
    _samples += samples;
  }

  /// 서버가 구간을 확정했다. 그때까지의 평균 세기를 item에 묶는다.
  ///
  /// 시작을 못 본 발화(`beginUtterance` 없이 온 committed)나 소리가 한 조각도
  /// 없던 발화는 **아무것도 남기지 않는다** — 모르는 것은 모르는 채로 둔다.
  double? commitUtterance(String itemId) {
    final bool was = _active;
    final int samples = _samples;
    final double sum = _sumSquares;
    _active = false;
    _sumSquares = 0;
    _samples = 0;
    if (!was || samples == 0 || itemId.isEmpty) return null;

    final double rms = math.sqrt(sum / samples);
    final double dbfs = pcm16LinearToDbfs(rms);
    if (!_rmsByItem.containsKey(itemId)) _itemOrder.add(itemId);
    _rmsByItem[itemId] = dbfs;
    while (_itemOrder.length > maxTrackedItems) {
      _rmsByItem.remove(_itemOrder.removeAt(0));
    }
    return dbfs;
  }

  /// 이 발화의 평균 세기(dBFS). 모르면 null.
  ///
  /// **지우지 않는다.** `completed`와 `done`이 같은 발화로 두 번 오는데,
  /// 읽으면서 지우면 두 번째가 세기를 모른 채 게이트를 통과한다.
  double? rmsDbfsOf(String itemId) => _rmsByItem[itemId];

  /// 통화가 끊기거나 전사 소켓이 재접속할 때. **누적과 장부를 모두 비운다.**
  /// 끊긴 동안의 소리가 다음 발화에 섞이면 안 된다.
  void reset() {
    _sumSquares = 0;
    _samples = 0;
    _active = false;
    _rmsByItem.clear();
    _itemOrder.clear();
  }
}

// ====================================================================
// 🎚️ [AEC-PROBE] 에코 제거(AEC)가 실제로 일하는지 재는 자리.
// --------------------------------------------------------------------
// 만능 통역은 always-on이라 상대 발화가 **재생되는 동안에도 마이크는 돈다**
// (닫히는 것은 STT로 가는 통로뿐이다). 그래서 그 버려지는 조각의 세기를 재면
// 게이트를 한 줄도 건드리지 않고 AEC의 성적표를 얻을 수 있다.
//
//   재생 중(게이트 닫힘)                    → addDuringTts()
//   조용할 때(게이트 열림 + 내가 말하지 않음) → addIdle()
//
// 두 값의 차가 작으면 AEC가 스피커 소리를 지우고 있다는 뜻이고, 크면 그대로
// 새어 들어온다는 뜻이다. **이 계측은 아무것도 막지 않는다** — 게이트는 이
// 값과 무관하게 지금 그대로 돈다. 재생 중에도 통로를 열어 진짜 끼어들기를
// 허용할 수 있는지, 그 다음 판단의 재료일 뿐이다.
//
// ⚠️ idle 쪽에는 서버 VAD가 발화 시작을 알리기 **전**의 첫 순간이 섞일 수
//   있다. 그만큼 바닥이 높게 잡히고 차이는 작아 보인다 — 즉 이 계측은
//   "AEC가 잘 된다" 쪽으로 기운다. **차이가 크게 나오면 그건 진짜다.**
// ====================================================================

/// 재생 중 마이크와 잡음 바닥의 세기를 따로 모으는 계측기. 통화 한 번에 하나.
class DuoAecProbe {
  DuoAecProbe({this.sampleRate = 24000});

  /// 모은 시간을 ms로 환산할 때 쓰는 값. 만능 통역 캡처와 같아야 한다.
  final int sampleRate;

  double _ttsSumSquares = 0;
  int _ttsSamples = 0;
  double _idleSumSquares = 0;
  int _idleSamples = 0;

  void _add(Uint8List pcm, {required bool duringTts}) {
    final int samples = pcm.lengthInBytes ~/ 2;
    if (samples == 0) return;
    final ByteData view = ByteData.sublistView(pcm, 0, samples * 2);
    double sum = 0;
    for (var i = 0; i < samples; i++) {
      final double v = view.getInt16(i * 2, Endian.little) / 32768.0;
      sum += v * v;
    }
    if (duringTts) {
      _ttsSumSquares += sum;
      _ttsSamples += samples;
    } else {
      _idleSumSquares += sum;
      _idleSamples += samples;
    }
  }

  /// 상대 발화가 재생되는 동안(게이트가 닫힌 동안) 들어온 조각.
  void addDuringTts(Uint8List pcm) => _add(pcm, duringTts: true);

  /// 아무도 말하지 않는 동안 들어온 조각. 이것이 잡음 바닥이다.
  void addIdle(Uint8List pcm) => _add(pcm, duringTts: false);

  /// 이번 재생 구간의 평균 세기(dBFS). 한 조각도 없으면 null.
  double? get duringTtsDbfs => _ttsSamples == 0
      ? null
      : pcm16LinearToDbfs(math.sqrt(_ttsSumSquares / _ttsSamples));

  /// 통화 내내 쌓은 잡음 바닥(dBFS). 한 조각도 없으면 null.
  double? get idleDbfs => _idleSamples == 0
      ? null
      : pcm16LinearToDbfs(math.sqrt(_idleSumSquares / _idleSamples));

  int get duringTtsMs => (_ttsSamples * 1000) ~/ sampleRate;
  int get idleMs => (_idleSamples * 1000) ~/ sampleRate;

  /// 재생 구간 하나를 보고했다. **바닥은 그대로 두고** 재생 쪽만 비운다 —
  /// 바닥은 통화 내내 쌓아야 표본이 쌓이고, 재생은 턴마다 따로 봐야 한다.
  void resetDuringTts() {
    _ttsSumSquares = 0;
    _ttsSamples = 0;
  }

  /// 통화가 끊기거나 캡처가 다시 열릴 때. 둘 다 비운다.
  void reset() {
    resetDuringTts();
    _idleSumSquares = 0;
    _idleSamples = 0;
  }
}
