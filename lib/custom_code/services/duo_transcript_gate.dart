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
/// **이 값은 보편 상수가 아니다.** 실기기 실측으로 두 번 잡았다.
///
/// **1차 (2026-08-30, SM-S931N 직접 대화 두 통) — −35.0으로 출발**
///
///   확실한 실제 발화   −23.3 ~ −25.9 dBFS  (10건, 전사 전부 정확)
///   중간(판단 보류)     −29.1 dBFS         (1건)
///   확실한 환청        −44.7 ~ −50.4 dBFS  (10건, 전사 전부 엉터리)
///
/// **2차 (2026-09-01, SM-S931N + SM-F946N 만능 통역/직접 대화 여러 통)
/// — −42.0으로 내림**
///
///   실제 발화(통과)      −22.8 ~ −29.5 dBFS
///   **실제 발화인데 잘림  −38.5 dBFS**  ← 유저가 "마지막 말이 빠졌다"고 확인
///   환청(거리 벌린 뒤)   −47.6 dBFS
///   환청(직접 대화)      −50.3 / −61.5 / **−160.0** dBFS (무음에서 4글자)
///
/// −35는 **실제 발화보다 위에 있었다.** 폰과 거리가 조금만 벌어져도(같은 방
/// 안에서 −22.8~−27.1이던 목소리가 −28.0~−29.5로 내려갔다) 사람 말이 잘린다.
/// 새 값은 실제 발화 최저에서 3.5dB, 확실한 환청 최고에서 5.6dB 여유다.
/// 직접 대화 쪽 환청은 −50 아래라 이 값으로도 그대로 잡힌다.
///
/// ⚠️ **−42도 최종이 아니다.** 더 멀리서·더 작게 말하면 실제 발화가 여기
/// 아래로 내려간다. 고정 문턱의 한계이고, 언젠가는 통화마다 잡음 바닥을
/// 재서 상대적으로 판단해야 한다 — `[AEC-PROBE]`의 `idle`이 이미 그 재료다
/// (같은 폰이 환경에 따라 −37과 −46을 오갔다).
/// 버린 줄은 로그에 `rmsDbfs`와 `threshold`를, 받은 줄은 `[INTERP-LEVEL]`에
/// 같은 값을 남긴다. **실제 발화의 최저치**가 더 쌓이면 다시 잡을 것.
const double kDuoMinUtteranceRmsDbfs = -42.0;

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

/// 🕰️ [DUO-LEVEL-PREROLL] `speech_started`가 **도착하기 전** 소리를 얼마나
/// 거슬러 올라가 셈에 넣을 것인가.
///
/// 서버 VAD의 `prefix_padding_ms`와 같은 뜻이고 같은 크기다
/// (`kDuoAbPreRollMs`와도 같다 — 세 곳이 같은 소리를 보아야 비교가 성립한다).
///
/// **이 값이 0이면 게이트가 실제 발화를 버린다.** 2026-09-02 실기기(SM-S931N)
/// 릴레이 통화 한 통에서 5건 중 3건이 그렇게 사라졌다:
///
///   "지금은"   voicedMs=1460  rmsDbfs=**−160.0**  → low_level로 폐기
///   "때문에"   voicedMs=1428  rmsDbfs=**−160.0**  → low_level로 폐기
///
/// 서버는 1.4초씩 사람 목소리를 들었는데 우리 계측기는 완전 무음을 쟀다.
/// `speech_started`는 네트워크 왕복과 서버 VAD 지연을 거쳐 **늦게** 오고,
/// 그 사이 삼성 AEC는 비발화 구간을 정확히 0으로 눌러 버린다. 그래서 계측기가
/// 실제 음성은 통째로 놓치고 AEC가 0으로 만든 뒷꼬리만 셌다.
///
/// 문턱(−42dBFS)의 문제가 아니다 — 실측값이 −160이라 문턱을 아무리 내려도
/// 안 걸린다. 고칠 곳은 **재는 구간**이다.
const int kDuoRmsPreRollMs = 600;

/// 이보다 짧은 구간으로는 세기를 판정하지 않는다.
///
/// 조각 몇 개로 낸 평균은 발화를 대표하지 못한다. 그런 값으로 사람 말을
/// 버리는 것보다 **모른다고 말하는 편이 낫다** — `belowLevelGate`는 null을
/// 통과시킨다. 이것이 "측정 실패"와 "진짜 조용함"을 가르는 자리다.
const int kDuoRmsMinWindowMs = 150;

/// 발화 구간 평균 세기 계산기. 통화 한 번에 하나.
class DuoUtteranceRmsMeter {
  DuoUtteranceRmsMeter({
    this.maxTrackedItems = 32,
    this.sampleRate = kStealthVoxSttSampleRate,
  });

  /// 값을 들고 있을 발화 수의 상한. 진행 중인 턴은 많아야 몇 개다.
  final int maxTrackedItems;

  /// 고리(pre-roll)와 최소 창을 ms로 환산하는 데 쓴다. 마이크 설정과 같아야 한다.
  final int sampleRate;

  double _sumSquares = 0;
  int _samples = 0;
  bool _active = false;

  /// 🕰️ 아직 발화가 시작되기 전 조각들의 **제곱합과 샘플 수만** 담아 두는 고리.
  ///
  /// ⚠️ **PCM은 담지 않는다.** 이 클래스가 통화 길이와 무관하게 메모리가
  ///   평평한 이유가 그것이고, 그 성질을 pre-roll 때문에 잃으면 안 된다.
  ///   조각 하나당 double 하나 + int 하나만 쌓인다.
  final List<_RmsChunk> _preRoll = <_RmsChunk>[];
  int _preRollSamples = 0;

  int get _preRollMaxSamples => kDuoRmsPreRollMs * sampleRate ~/ 1000;
  int get _minWindowSamples => kDuoRmsMinWindowMs * sampleRate ~/ 1000;

  final Map<String, double> _rmsByItem = <String, double>{};
  final List<String> _itemOrder = <String>[];

  bool get isActive => _active;
  int get trackedItems => _rmsByItem.length;

  /// 지금 고리에 담긴 소리의 길이(ms). 진단용.
  int get preRollMs => _preRollSamples * 1000 ~/ sampleRate;

  /// 서버 VAD가 발화 시작을 알렸다.
  ///
  /// **고리에 담아 둔 직전 소리를 셈의 출발점으로 삼는다.** 서버가 이미
  /// `prefix_padding_ms`만큼 앞소리를 전사에 쓰고 있으므로, 우리도 같은
  /// 구간을 봐야 "서버가 들은 소리"와 "우리가 잰 소리"가 같아진다.
  void beginUtterance() {
    _sumSquares = 0;
    _samples = 0;
    for (final chunk in _preRoll) {
      _sumSquares += chunk.sumSquares;
      _samples += chunk.samples;
    }
    _preRoll.clear();
    _preRollSamples = 0;
    _active = true;
  }

  /// 마이크 조각 하나.
  ///
  /// 발화 중이면 곧바로 누적하고, 아니면 고리에 담아 둔다 —
  /// **발화가 시작되기 전 소리도 곧 필요해진다.**
  void addPcm(Uint8List pcm) {
    if (pcm.isEmpty) return;
    final int samples = pcm.lengthInBytes ~/ 2;
    if (samples == 0) return;
    final ByteData view = ByteData.sublistView(pcm, 0, samples * 2);
    double sum = 0;
    for (var i = 0; i < samples; i++) {
      final double v = view.getInt16(i * 2, Endian.little) / 32768.0;
      sum += v * v;
    }

    if (_active) {
      _sumSquares += sum;
      _samples += samples;
      return;
    }

    // 발화 전 — 고리에 담고 오래된 것부터 버린다.
    _preRoll.add(_RmsChunk(sum, samples));
    _preRollSamples += samples;
    while (_preRollSamples > _preRollMaxSamples && _preRoll.length > 1) {
      _preRollSamples -= _preRoll.removeAt(0).samples;
    }
  }

  /// 서버가 구간을 확정했다. 그때까지의 평균 세기를 item에 묶는다.
  ///
  /// **null을 돌려주는 경우가 셋이다. 셋 다 "조용했다"가 아니라 "모른다"다.**
  ///   · 시작을 못 본 발화(`beginUtterance` 없이 온 committed)
  ///   · 소리가 한 조각도 없던 발화
  ///   · 잰 구간이 [kDuoRmsMinWindowMs]보다 짧아 대표성이 없는 경우
  ///
  /// 마지막 것이 **측정 실패와 진짜 저음량을 가르는 자리**다. 창이 충분히
  /// 길었는데도 −160이 나왔다면 그건 정말 무음이고, 무음에서 나온 글자는
  /// 환청이므로 그대로 걸러야 한다(2026-09-01 실측: 무음에서 4글자).
  double? commitUtterance(String itemId) {
    final bool was = _active;
    final int samples = _samples;
    final double sum = _sumSquares;
    _active = false;
    _sumSquares = 0;
    _samples = 0;
    if (!was || samples == 0 || itemId.isEmpty) return null;
    // 너무 짧은 창으로는 판정하지 않는다 — 모르는 것으로 사람 말을 버리지 않는다.
    if (samples < _minWindowSamples) return null;

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
    // 고리도 비운다. 끊기기 전 소리가 다음 발화의 pre-roll이 되면 안 된다.
    _preRoll.clear();
    _preRollSamples = 0;
    _rmsByItem.clear();
    _itemOrder.clear();
  }
}

/// 조각 하나의 셈. **PCM은 들고 있지 않다** — 제곱합과 샘플 수뿐이다.
class _RmsChunk {
  const _RmsChunk(this.sumSquares, this.samples);
  final double sumSquares;
  final int samples;
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
