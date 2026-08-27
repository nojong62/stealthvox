// ====================================================================
// 📝 [ORIGIN-REPAIR-GUARD] 전사 교정은 **낱말 하나를 되살리는 일**이지
//    문장을 다시 쓰는 일이 아니다.
// --------------------------------------------------------------------
// 히스토리는 배울글(타겟)을 만들면서 같은 요청으로 원문 교정도 받는다.
// 프롬프트가 "잘못 들은 낱말만 고쳐라"라고 못 박아도 모델은 종종 문장을
// 통째로 다시 쓴다. 그러면 유저가 하지 않은 말이 학습 자료로 남는다.
//
//   말한 것: "이번 주 토요일에 연구회 모임이 한강공원에서 있다더라!"
//   저장된 것: "이번 주 토요일에 연구회가 한강공원으로 옮겨진다더라!"
//
// 모임이 열리는 자리가 연구회가 옮겨 가는 이야기로 바뀌었다. 그 위에서
// 번역까지 만들어지므로 두 줄이 나란히 틀린다.
//
// 그래서 **받은 교정문을 그대로 믿지 않는다.** 낱말 몇 개를 바꾼 정도만
// 교정으로 인정하고, 그보다 크면 전사 원문을 지킨다. 못 고친 낱말이
// 남는 편이, 하지 않은 말이 남는 것보다 낫다.
// ====================================================================

/// 낱말 수 대비 바꿔도 되는 낱말의 비율.
const double _kMaxChangedWordRatio = 0.2;

/// 짧은 줄에서도 낱말 하나는 고칠 수 있어야 한다("우리 병 중에서" → "우리 반 중에서").
const int _kMinChangedWordAllowance = 1;

final RegExp _kWhitespace = RegExp(r'\s+');

/// [repaired]가 [raw]의 **교정**인가, 아니면 다시 쓴 문장인가.
///
/// 인정하는 것:
///   · 손대지 않은 문장(같은 글자)
///   · 낱말 수가 그대로이고, 바뀐 낱말이 전체의 20% 이내(최소 1개)
///
/// 낱말이 늘거나 줄면 무조건 거절한다 — 낱말을 지우거나 보태는 것은
/// 잘못 들은 소리를 되살리는 일이 아니다.
bool isMinimalTranscriptRepair(String raw, String repaired) {
  final String a = raw.trim();
  final String b = repaired.trim();
  if (b.isEmpty) return false;
  if (a == b) return true;

  final List<String> from = a.split(_kWhitespace);
  final List<String> to = b.split(_kWhitespace);
  if (from.length != to.length) return false;

  var changed = 0;
  for (var i = 0; i < from.length; i++) {
    if (from[i] != to[i]) changed++;
  }
  final int allowance = (from.length * _kMaxChangedWordRatio).ceil();
  return changed <=
      (allowance < _kMinChangedWordAllowance
          ? _kMinChangedWordAllowance
          : allowance);
}
