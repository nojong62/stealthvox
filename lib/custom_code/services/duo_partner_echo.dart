// ====================================================================
// 📢 [PARTNER-ECHO] 상대 폰 스피커가 낸 소리를 전사문에서 골라낸다
// --------------------------------------------------------------------
// 만능 통역의 정상 사용은 **두 사람이 마주 앉는 것**이다. 그러면 서로의
// 폰 스피커 소리가 상대 마이크로 들어간다.
//
// 내 폰이 내는 소리는 이미 두 겹으로 막혀 있다 — 재생 동안 오디오 게이트를
// 닫고(`INTERP-GATE close reason=tts_playing`), 그래도 새면 최근에 내가 만든
// 문장과 대조한다(`_looksLikeEcho`). 둘 다 **내 재생 시각**이 기준이다.
//
// 상대 폰이 내는 소리는 어느 쪽도 못 잡는다. 내 시계에는 그 재생이 없고,
// 그 문장(내 언어로 번역된 상대의 말)도 내 손에 없다.
//
// 2026-09-04 실기기: 2m 떨어져 있을 때 −47~−60 dBFS로 들어와 세기
// 게이트(−42.0)가 다 걸렀다. 마주 앉으면 그 문턱을 넘는다.
//
// 🚫 **마이크를 닫아서 막지 않는다.** 상대 마이크를 닫으면 그동안 상대가
//   실제로 한 말이 잘리고, 알림이 유실되면 마이크가 닫힌 채 남는다. 대신
//   소리 낼 문장을 미리 건네 두고 **들어온 뒤에 골라낸다** — 거리와
//   무관하고, 알림이 못 가면 세기 게이트만 남아 지금 동작 그대로다.

import 'dart:math' as math;

/// 상대가 "지금 이 문장을 소리 낸다"고 알려 온 뒤 이만큼만 그 문장을 쓴다.
///
/// 알림은 상대의 **재생 시작** 시점에 온다. 그 소리가 내 마이크로 들어와
/// 전사문이 되기까지 `재생 길이 + 서버 VAD 무음(0.6초) + 전사`가 걸린다.
/// 한 턴이 보통 2~6초이므로 8초면 덮는다.
///
/// 더 늘리지 않는 이유가 있다 — 창이 길수록 **상대가 낸 소리와 비슷한 진짜
/// 발화**를 지울 위험이 커진다. 창이 좁은 것이 이 방어선의 안전장치다.
const Duration kPartnerEchoWindow = Duration(seconds: 8);

/// 얼마나 닮아야 상대 폰이 낸 소리로 보는가.
///
/// 완전 일치를 요구하면 안 된다 — 스피커 소리를 STT가 다시 들으면 구두점과
/// 조사, 짧은 낱말 하나쯤은 달라진다. 그렇다고 넓히면 진짜 발화를 지운다.
///
/// 0.75로 둘 수 있는 근거는 **언어가 갈린다**는 것이다. 상대 폰이 내는 소리는
/// 내 대화 언어이고, 그 언어로 말하는 사람은 나뿐이다 — 상대는 자기 언어로
/// 말한다. 그래서 이 비교에 상대의 진짜 발화가 걸릴 일이 구조적으로 없다.
/// (두 사람의 대화 언어가 같으면 번역을 건너뛰므로 재생 자체가 없다.)
const double kPartnerEchoSimilarity = 0.75;

/// 들고 있을 문장의 최대 개수. 창 안에 여러 턴이 겹칠 수 있다.
const int kPartnerEchoMaxItems = 5;

/// 이보다 짧은 전사문은 대조하지 않는다.
///
/// "네"·"그럼" 같은 짧은 말은 누가 해도 비슷해서, 포함 관계로 보면 긴 문장
/// 아무 데나 걸린다. 짧은 말을 지키는 것이 [[duo-history-cleanup-principle]]
/// 이고, 그 판정은 소리(세기·길이)가 한다.
const int kPartnerEchoMinLength = 4;

/// 글자가 아닌 것은 다 지운다. 구두점·띄어쓰기 차이를 없애기 위한 것이다.
///
/// `\p{L}`을 쓴다 — 한글만 따로 적으면 일본어·중국어·태국어에서 통째로
/// 빈 문자열이 되어 이 방어선이 조용히 꺼진다.
///
/// `\p{M}`(결합 부호)도 남긴다. 태국어의 성조·모음 부호와 베트남어·힌디어의
/// 부호가 여기 든다. 지워도 양쪽에 똑같이 적용되어 대조 자체는 되지만,
/// 서로 다른 낱말이 같은 뼈대로 뭉쳐 **엉뚱한 발화를 지울** 위험이 커진다.
final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}\p{M}]', unicode: true);

/// 대조용으로 문장을 납작하게 만든다.
String partnerEchoNormalize(String s) =>
    s.toLowerCase().replaceAll(_nonWord, '');

/// 낱말 자카드 유사도(0~1).
///
/// 띄어쓰기가 없는 언어에서는 낱말이 하나로 뭉쳐 이 값이 쓸모없어진다.
/// 그쪽은 아래 포함 관계가 잡는다 — 두 자를 같이 쓰는 이유가 이것이다.
double partnerEchoJaccard(String a, String b) {
  final Set<String> sa = _tokens(a);
  final Set<String> sb = _tokens(b);
  if (sa.isEmpty || sb.isEmpty) return 0;
  final int inter = sa.intersection(sb).length;
  final int union = sa.union(sb).length;
  if (union == 0) return 0;
  return inter / union;
}

Set<String> _tokens(String s) => s
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .map((t) => t.replaceAll(_nonWord, ''))
    .where((t) => t.isNotEmpty)
    .toSet();

/// 상대 폰이 방금 소리 낸 문장 하나.
class PartnerSpokenLine {
  PartnerSpokenLine(this.text, this.at);

  /// 상대 폰이 실제로 읽은 문장. **내 대화 언어**다.
  final String text;

  /// 알림이 도착한 시각. 상대의 재생 시작에 맞춰 온다.
  final DateTime at;
}

/// 📢 최근 몇 초 안에 상대 폰이 낸 문장들.
///
/// 통화 한 번짜리다. [clear]를 부르는 곳은 마이크를 접는 자리 하나뿐이고,
/// 앞 통화의 문장이 다음 통화로 넘어가면 엉뚱한 발화를 지운다.
class PartnerEchoMemory {
  final List<PartnerSpokenLine> _lines = <PartnerSpokenLine>[];

  int get length => _lines.length;
  bool get isEmpty => _lines.isEmpty;

  /// 상대가 알려 온 문장을 담는다.
  void note(String text, {DateTime? at}) {
    final String t = text.trim();
    if (t.isEmpty) return;
    final DateTime now = at ?? DateTime.now();
    _lines.add(PartnerSpokenLine(t, now));
    prune(now: now);
  }

  /// 창을 넘긴 것과 넘치는 것을 버린다.
  void prune({DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    _lines.removeWhere((e) => at.difference(e.at) > kPartnerEchoWindow);
    while (_lines.length > kPartnerEchoMaxItems) {
      _lines.removeAt(0);
    }
  }

  void clear() => _lines.clear();

  /// 이 전사문이 상대 폰 스피커가 낸 소리인가.
  ///
  /// **마이크는 이 판정과 무관하게 계속 열려 있다.** 여기서 하는 일은 이미
  /// 들어와 전사된 글자가 사람이 한 말인지 폰이 낸 소리인지 가르는 것뿐이다.
  bool matches(String transcript, {DateTime? now}) {
    final String t = transcript.trim();
    if (t.length < kPartnerEchoMinLength) return false;
    final DateTime at = now ?? DateTime.now();
    prune(now: at);
    if (_lines.isEmpty) return false;
    final String tn = partnerEchoNormalize(t);
    if (tn.isEmpty) return false;
    for (final PartnerSpokenLine e in _lines) {
      final String gn = partnerEchoNormalize(e.text);
      if (gn.isEmpty) continue;
      // ① 납작하게 만든 뒤의 포함 관계. 마이크가 문장의 일부만 주웠거나
      //   꼬리가 잘린 경우, 그리고 띄어쓰기 없는 언어를 여기서 잡는다.
      //   짧은 쪽이 너무 짧으면 아무 데나 걸리므로 길이를 함께 본다.
      final int shorter = math.min(gn.length, tn.length);
      if (shorter >= kPartnerEchoMinLength &&
          (gn == tn || gn.contains(tn) || tn.contains(gn))) {
        return true;
      }
      // ② 낱말 자카드. 조사 한둘이 어긋난 경우를 잡는다.
      if (partnerEchoJaccard(e.text, t) >= kPartnerEchoSimilarity) return true;
    }
    return false;
  }
}
