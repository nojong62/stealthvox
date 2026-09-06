// ====================================================================
// 🧭 [DUO-CONTEXT] 전사기에게 주는 **낱말 힌트**
// --------------------------------------------------------------------
// 소리만으로는 갈리지 않는 낱말이 있다. 사람 이름, 지명, 제품명, 그 통화에서
// 반복해서 나온 고유명사가 그렇다. 같은 소리를 놓고 전사기는 매번 다르게
// 적을 수 있고, 그러면 한 통화 안에서 같은 사람 이름이 세 가지로 남는다.
//
// 그래서 **직전 몇 마디를 힌트로 함께 넘긴다.** 전사기가 그 낱말을 이미 본
// 적이 있으면 같은 철자로 적는다.
//
// ⚠️ **맥락은 문장을 지어내라는 뜻이 아니다.**
//   "대화 흐름상 이 말이 나왔을 것"이라고 추측해서 소리에 없는 내용을
//   전사문에 넣으면 안 된다. 힌트는 **애매하게 들린 낱말을 가려내는 데만**
//   쓴다. 이 경계가 무너지면 사용자가 하지 않은 말이 자기 기록에 남는다.
//
// 📌 **Firestore를 다시 읽지 않는다.** 발화마다 방 문서를 읽으면 그 왕복이
//   전사 지연에 그대로 붙는다. 수용된 전사문이 생길 때 여기 넣어 두고,
//   다음 발화가 그것을 쓴다.
//
// 🧠 메모리는 몇 줄뿐이다. 통화가 길어져도 늘지 않는다.
// ====================================================================

/// 힌트로 들고 있을 최근 발화 수. 길게 줄수록 전사기가 그 문장에 끌려간다.
const int kDuoContextMaxTurns = 4;

/// 힌트 전체 길이 상한. 넘으면 **오래된 것부터** 버린다.
const int kDuoContextMaxChars = 400;

/// 통화 한 통 = 이 객체 한 개.
class DuoTranscriptContext {
  DuoTranscriptContext({
    this.maxTurns = kDuoContextMaxTurns,
    this.maxChars = kDuoContextMaxChars,
  });

  final int maxTurns;
  final int maxChars;

  final List<String> _turns = <String>[];

  int get length => _turns.length;
  bool get isEmpty => _turns.isEmpty;

  /// 수용된 전사문 하나. **버려진 전사문은 넣지 않는다** — 잡음이나 환청으로
  /// 판정된 글자를 힌트로 주면 다음 발화가 그쪽으로 끌려간다.
  void add(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _turns.add(trimmed);
    while (_turns.length > maxTurns) {
      _turns.removeAt(0);
    }
    while (_turns.length > 1 && _totalChars > maxChars) {
      _turns.removeAt(0);
    }
  }

  int get _totalChars => _turns.fold<int>(0, (sum, t) => sum + t.length + 1);

  /// 전사기에게 넘길 힌트. 담긴 것이 없으면 빈 문자열이고, 그때는
  /// **아예 넘기지 않는다**(빈 prompt를 보내면 요청만 커진다).
  ///
  /// 모양은 앞선 말들을 그대로 이어 붙인 것이다. 지시문을 섞지 않는다 —
  /// 전사 API의 prompt는 "이런 낱말이 나온다"는 표본으로 읽히고, 명령문을
  /// 넣으면 그 명령문이 전사문에 섞여 나오는 일이 있다.
  String buildPrompt() {
    if (_turns.isEmpty) return '';
    var text = _turns.join(' ');
    if (text.length > maxChars) {
      text = text.substring(text.length - maxChars);
    }
    return text;
  }

  /// 통화가 끝났다. 다음 통화의 힌트로 새지 않게 비운다.
  void clear() => _turns.clear();
}
