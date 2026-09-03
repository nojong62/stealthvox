// ====================================================================
// ✂️ [DUO-CHUNK] 번역이 흘러나오는 동안 "지금 읽어도 되는 만큼"을 떼는 자리
// --------------------------------------------------------------------
// 만능 통역의 병목은 **번역이 다 끝나야 TTS가 시작되는 직렬 구조**다.
// 번역을 스트리밍으로 받으면서 자연스러운 구절이 완성되는 즉시 읽기
// 시작하면 그 둘이 시간상 겹친다.
//
//   기존:  번역 100% ────────────→ TTS ──────→ 재생
//   신규:  번역 일부 ──→ TTS ──→ 재생
//               └ 번역 나머지 계속 ──→ TTS ──→ 재생
//
// ⚠️ **토큰 하나마다 자르면 안 된다.** "If you're" / "free this" 처럼
//   끊어 읽으면 억양이 무너지고 TTS 호출 수와 비용만 늘어난다. 사람이 한
//   호흡으로 말할 수 있는 구절이 될 때까지 모은다.
//
// ⚠️ 반대로 첫 조각을 너무 오래 기다리면 이 작업의 목적 자체가 사라진다.
//   그래서 경계마다 요구하는 최소 길이를 다르게 둔다.
//
// 📏 문턱의 근거 (2026-09-03 실기기 로그, 표본 3건이라 작다):
//     "이번 테스트에서"                8자
//     "지금은 144번째 테스트입니다."   17자
//     "좋은 결과가 나오기를 기대합니다." 17자
//   한국어 8~17자 → 영어 번역은 대략 25~60자다. **대부분 한 문장이다.**
//   즉 보통의 Duo 발화는 조각 하나로 끝나야 정상이고, 쪼개지는 것은
//   쉼표가 들어간 중간 길이 이상 문장뿐이다. 실기기 값이 더 쌓이면 다시 잡는다.
// ====================================================================

/// 문장이 끝났다고 볼 글자. 여기서 끊으면 억양이 상하지 않는다.
const String kDuoSentenceEnders = '.?!。？！…';

/// 구절이 끊긴다고 볼 글자. 문장 끝보다 약하므로 더 긴 길이를 요구한다.
const String kDuoClauseEnders = ',;:，；：·—';

/// 🔑 **첫 조각은 이만큼은 되어야 떼어 낸다.**
///
/// 나눌지 말지를 가르는 것은 "지금까지 몇 자가 왔는가"가 아니라
/// **"지금 떼어 낼 구절이 혼자 말이 되는가"**다.
///
/// 누적 길이로 재면 조기 재생이 늦어진다. 예를 들어
///   `If you're free this afternoon, do you want to grab a coffee?`
/// 는 쉼표가 **30자에서 이미 완성**되는데, 누적 60자를 기다리면 그 30자만큼
/// 늦게 읽기 시작한다. 자를 위치는 어차피 같은 쉼표다 — 늦춘 만큼 손해다.
///
/// 반대로 문턱이 없으면 `Sounds good. Thanks a lot.`(26자)이 두 조각으로
/// 갈라진다. 얻는 것 없이 TTS 호출만 두 배가 되고 억양이 끊긴다.
///
/// 그래서 **첫 조각의 길이**로 가른다. 첫 조각이 이 길이를 넘으면 뒤에 무엇이
/// 오든 그것만으로 한 호흡이 되므로 먼저 읽어도 자연스럽다.
///
/// 📊 값의 근거 — `dart run tool/duo_chunk_sim.dart` (말뭉치 19건)
///
///   문턱  쪼개짐  평균조각  첫조각  자연경계  짧은말  중간문장
///    12    32%    1.47    24.9자   100%    0/11    —
///    16    26%    1.42    25.7자   100%    0/11    2/5
///    20    26%    1.42    25.7자   100%    0/11    2/5
///   →24    26%    1.42    25.7자   100%    0/11    2/5
///    28    21%    1.37    26.7자   100%    0/11    1/5
///    40    16%    1.26    30.2자   100%    0/11    0/5
///    60    16%    1.16    34.2자   100%    0/11    0/5
///
/// 읽는 법:
///   · **짧은 말은 어느 값에서도 안 쪼개진다**(0/11). 16 이상이면 안전하다.
///   · 40 이상에서는 **중간 문장이 하나도 안 쪼개진다**(0/5). 조기 재생을
///     넣어 놓고 안 쓰는 셈이 된다 — 60은 그래서 버렸다.
///   · 16~24는 결과가 같다. [kDuoMinClauseChunkChars]가 24라 그 아래에서는
///     이 값이 무의미하기 때문이다. **평탄 구간의 위쪽 끝을 고른다** —
///     같은 효과를 내면서 가장 보수적인 값이다.
///   · 어느 값에서도 자연 경계 100%, 1~2단어 꼬리 0건이었다.
///
/// ⚠️ 말뭉치 19건 중 **실측은 3건뿐이다.** 나머지는 지어낸 문장이라 경향만
///   본 것이다. 실기기 번역문이 쌓이면 그 값을 도구에 넣고 다시 돌릴 것.
const int kDuoMinFirstChunkChars = 24;

/// 첫 조각을 뗀 **뒤**로는 누적 길이를 보지 않는다. 이미 앞을 읽고 있으므로
/// 뒤를 모아 둘 이유가 없다 — 모으는 만큼 조각 사이가 벌어진다.
///
/// 0이면 끄는 것이고 그것이 기본이다. 비교 실험용으로만 남겨 둔다.
const int kDuoChunkingMinTotalChars = 0;

/// 문장 끝에서 조각을 떼기 위한 최소 길이.
///
/// 문장 부호에서 끊는 것은 억양이 상하지 않으므로 문턱이 낮아도 된다.
/// (위 [kDuoChunkingMinTotalChars]를 이미 넘긴 뒤에만 여기까지 온다)
const int kDuoMinSentenceChunkChars = 10;

/// 쉼표 등에서 조각을 떼기 위한 최소 길이.
///
/// 문장 끝이 아니므로 더 긴 맥락을 요구한다. "If you're free this afternoon,"
/// (30자)은 통과하고 "If you're,"(10자)는 통과하지 않는다.
const int kDuoMinClauseChunkChars = 24;

/// 경계가 한 번도 안 나올 때 강제로 떼는 길이. 이게 없으면 마침표 없는 긴
/// 번역에서 첫 소리가 끝까지 안 난다.
const int kDuoMaxChunkChars = 120;

/// 번역 델타를 받아 **읽어도 되는 구절**만 내보내는 절단기.
///
/// 한 발화(turn)에 하나씩 만든다. 상태를 들고 있으므로 재사용하지 않는다.
class DuoSpeechChunker {
  DuoSpeechChunker({
    this.minFirstChunkChars = kDuoMinFirstChunkChars,
    this.minTotalChars = kDuoChunkingMinTotalChars,
    this.minSentenceChars = kDuoMinSentenceChunkChars,
    this.minClauseChars = kDuoMinClauseChunkChars,
    this.maxChars = kDuoMaxChunkChars,
  });

  /// 🔑 첫 조각이 이만큼은 되어야 뗀다. 짧은 발화를 통짜로 두는 자리다.
  final int minFirstChunkChars;

  /// 누적 길이 문턱(비교 실험용, 기본 0=끔).
  final int minTotalChars;
  final int minSentenceChars;
  final int minClauseChars;
  final int maxChars;

  /// 경계에서 조각을 한 번이라도 떼었는가(내부용).
  ///
  /// 한 번 떼기 시작하면 그 뒤로는 문턱을 낮춘다 — 앞을 이미 읽고 있으므로
  /// 뒤를 모아 둘 이유가 없다.
  ///
  /// ⚠️ 이것이 참이라고 발화가 **나뉜** 것은 아니다. 문장 끝이 마지막 글자면
  ///   통짜 하나가 이 경로로 나간다. 나뉨의 판정은 [didSplit]이 한다.
  bool _splitStarted = false;

  /// 지금까지 내보낸 조각 수([flush] 포함).
  int _emittedCount = 0;
  int get emittedCount => _emittedCount;

  /// 이 발화가 **둘 이상으로** 나뉘었는가. 거짓이면 기존 경로와 동작이 같다.
  bool get didSplit => _emittedCount > 1;

  final StringBuffer _pending = StringBuffer();

  /// 지금까지 내보낸 조각을 다시 합친 것. History에 쓰지 않는다 —
  /// 저장용 전체 번역문은 호출부가 스트림 원문으로 따로 들고 있어야 한다.
  final StringBuffer _emitted = StringBuffer();

  int get pendingLength => _pending.length;
  String get emittedText => _emitted.toString();

  /// 델타 한 조각을 넣고, 떼어 낼 구절이 생겼으면 돌려준다.
  ///
  /// 한 번의 델타로 조각이 여럿 완성될 수도 있으므로 목록으로 돌려준다
  /// (예: "네. 알겠습니다." 가 한꺼번에 올 때).
  List<String> add(String delta) {
    if (delta.isEmpty) return const <String>[];
    _pending.write(delta);
    final out = <String>[];
    while (true) {
      final chunk = _takeChunk();
      if (chunk == null) break;
      out.add(chunk);
    }
    return out;
  }

  /// 스트림이 끝났다. 남은 것을 마지막 조각으로 내보낸다.
  ///
  /// 길이 문턱을 보지 않는다 — 더 올 것이 없으므로 짧아도 읽어야 한다.
  String? flush() {
    final rest = _pending.toString().trim();
    _pending.clear();
    if (rest.isEmpty) return null;
    _emittedCount++;
    _emitted.write(_emitted.isEmpty ? rest : ' $rest');
    return rest;
  }

  /// 지금 버퍼에서 떼어 낼 구절이 있으면 잘라 돌려준다.
  String? _takeChunk() {
    final String buf = _pending.toString();
    if (buf.trim().isEmpty) return null;

    final int cut = _findCut(buf);
    if (cut < 0) return null;

    final String chunk = buf.substring(0, cut).trim();
    final String rest = buf.substring(cut);
    _pending
      ..clear()
      ..write(rest);
    if (chunk.isEmpty) return null;
    _splitStarted = true;
    _emittedCount++;
    _emitted.write(_emitted.isEmpty ? chunk : ' $chunk');
    return chunk;
  }

  /// 자를 위치(자른 뒤 남는 첫 글자의 인덱스). 없으면 -1.
  ///
  /// 문장 끝을 먼저 찾고, 없으면 구절 끝, 그것도 없으면 길이 상한을 본다.
  /// **경계 글자는 조각에 포함시킨다** — 물음표가 잘려 나가면 억양이 바뀐다.
  int _findCut(String buf) {
    // ⓪ 비교 실험용 누적 문턱. 기본은 0이라 아무 일도 하지 않는다.
    if (!_splitStarted && minTotalChars > 0 && buf.trim().length < minTotalChars) {
      return -1;
    }

    // 🔑 **첫 조각만 더 길게 요구한다.**
    //   나눌지 말지를 가르는 것은 첫 결정 하나다. 첫 조각이 혼자 말이 될
    //   만큼 길면 먼저 읽어도 자연스럽고, 짧으면 나눠서 얻을 것이 없다.
    //   두 번째부터는 이미 앞을 읽는 중이라 낮은 문턱으로 곧바로 뗀다.
    final int sentenceFloor =
        _splitStarted ? minSentenceChars : _maxOf(minSentenceChars, minFirstChunkChars);
    final int clauseFloor =
        _splitStarted ? minClauseChars : _maxOf(minClauseChars, minFirstChunkChars);

    // ① 문장 끝. 가장 이른 것에서 끊어 첫 소리를 빨리 낸다.
    for (int i = 0; i < buf.length; i++) {
      if (!kDuoSentenceEnders.contains(buf[i])) continue;
      // 소수점·약어(3.5, Mr.)에서 끊지 않는다.
      if (_isMidNumber(buf, i)) continue;
      final int end = _consumeTrailing(buf, i);
      if (end >= sentenceFloor) return end;
    }

    // ② 구절 끝. 문장 끝보다 긴 맥락을 요구한다.
    for (int i = 0; i < buf.length; i++) {
      if (!kDuoClauseEnders.contains(buf[i])) continue;
      if (_isMidNumber(buf, i)) continue;
      final int end = _consumeTrailing(buf, i);
      if (end >= clauseFloor) return end;
    }

    // ③ 경계가 없다. 너무 길어지면 공백에서라도 끊는다.
    if (buf.length >= maxChars) {
      final int space = buf.lastIndexOf(' ', maxChars);
      if (space > minClauseChars) return space;
      return maxChars;
    }
    return -1;
  }

  /// 경계 글자 뒤에 붙는 닫는 따옴표·괄호까지 조각에 포함시킨다.
  int _consumeTrailing(String buf, int i) {
    int end = i + 1;
    while (end < buf.length && '”"\')]』」'.contains(buf[end])) {
      end++;
    }
    return end;
  }

  int _maxOf(int a, int b) => a > b ? a : b;

  /// 숫자 사이의 마침표·쉼표인가(3.5, 1,000). 거기서 끊으면 안 된다.
  bool _isMidNumber(String buf, int i) {
    if (i == 0 || i + 1 >= buf.length) return false;
    final prev = buf.codeUnitAt(i - 1);
    final next = buf.codeUnitAt(i + 1);
    bool isDigit(int c) => c >= 0x30 && c <= 0x39;
    return isDigit(prev) && isDigit(next);
  }
}
