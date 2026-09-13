// ====================================================================
// 🩺 [DUO-ORIGIN-CORRECT] 통화가 끝난 뒤, 잘못 들린 낱말 하나를 문맥으로 되살린다
// --------------------------------------------------------------------
// gpt-transcribe는 발화 하나를 그 자리에서 옮긴다. 그때는 앞뒤에 무슨 말이
// 오갔는지 아직 없다. 통화가 끝나면 전부 있다 — 그래서 여기서 한 번 본다.
//
//   "아까 뒷지표를 예매했어."   ← 앞 세 마디가 기차·서울행·표 이야기라면
//   "아까 기차표를 예매했어."      '뒷지표'는 성립하지 않는다
//
// ⚠️ **작문기가 아니다. STT 오류 검수기다.**
//    말투·어미·조사·어순·존댓말은 손대지 않는다. 없던 말을 채우지 않는다.
//    확신이 없으면 원 전사를 그대로 둔다 — 못 고친 낱말이 남는 편이,
//    하지 않은 말이 학습 자료로 남는 것보다 낫다.
//
// 🚫 **숫자·시간·날짜·금액·사람 이름·지명·상호는 고치지 않는다.**
//    그 항목은 소리로 확인해야 하는 것이라 PCM 재검증(`origin_restoration`)의
//    몫으로 남긴다. 문맥만으로 "3시"를 "4시"로 바꾸는 길은 만들지 않는다.
//
// 🧭 **여기는 확정이 아니라 후보다.** PCM이 있는 줄은 뒤이어 원문 복원이
//    같은 소리를 다시 듣고 뒤집을 수 있다. 그 관계를 기록으로 남기는 것이
//    [kOriginCorrectionStageField]다.
//
// **판정은 전부 이 파일의 순수 함수에 있다.** 모델 호출은 주입받으므로
// ([resolveDuoOriginCorrections]), 테스트가 네트워크 없이 모든 갈래를 태운다.
// ====================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'origin_restoration.dart' show isSuspectOverflow;

/// 이 줄을 고친 모델. **고친 줄에만 찍는다.**
const String kOriginCorrectionModelField = 'origin_correction_model';

/// 그 교정이 소리로 확인될 수 있는 자리인가.
///
/// Duo는 내 마이크 소리만 내 창고에 있다. 그래서 같은 교정이라도 이 폰에서
/// 다시 들어 볼 수 있는 줄과 그렇지 못한 줄이 갈린다 — 그 사실을 나중에
/// 데이터만 보고 알 수 있어야 한다.
const String kOriginCorrectionStageField = 'origin_correction_stage';

/// 이 폰에 그 발화의 PCM이 있다. 원문 복원이 다시 듣고 뒤집을 수 있는 **후보**다.
const String kOriginCorrectionVerifiable = 'context_verified_candidate';

/// 이 폰에 소리가 없다. 문맥만으로 선 교정이고, 여기서는 되짚을 길이 없다.
const String kOriginCorrectionUnverified = 'context_unverified';

/// GPT 한 번의 상한. canonical 전체가 이 뒤에 서 있으므로 길게 잡지 않는다.
const Duration kDuoOriginCorrectTimeout = Duration(seconds: 40);

// ══════════════════════════════════════════════════════════════════════
// 자료
// ══════════════════════════════════════════════════════════════════════

/// 교정기가 보는 발화 하나.
@immutable
class DuoOriginLine {
  const DuoOriginLine({
    required this.id,
    required this.speaker,
    required this.text,
  });

  final String id;

  /// 모델에게 주는 화자 표시. **`A` / `B`만 쓴다.**
  ///
  /// HOST/GUEST를 그대로 주면 모델이 주인·손님 관계를 추론해 존댓말 방향까지
  /// 손보려 든다. 여기서 필요한 것은 "두 사람이 번갈아 말한다"뿐이다.
  final String speaker;
  final String text;
}

/// 모델이 내놓은 교정 하나.
@immutable
class DuoOriginProposal {
  const DuoOriginProposal({
    required this.id,
    required this.raw,
    required this.corrected,
    this.reason = '',
  });

  final String id;
  final String raw;
  final String corrected;
  final String reason;
}

/// 한 통화의 교정 결과.
@immutable
class DuoOriginCorrectionResult {
  const DuoOriginCorrectionResult({
    required this.corrections,
    required this.proposed,
    required this.overflow,
    this.rejected = const <String>[],
  });

  const DuoOriginCorrectionResult.none()
      : corrections = const <String, String>{},
        proposed = 0,
        overflow = false,
        rejected = const <String>[];

  /// 채택된 것만. id → 고쳐진 글.
  final Map<String, String> corrections;

  /// 모델이 내놓은 것 중 **구조적으로 성립한** 개수(모르는 id·빈 글·같은 글 제외).
  final int proposed;

  /// 폭주해서 통째로 버렸는가.
  final bool overflow;

  /// 가드에 걸린 까닭들. 로그·테스트용이고 저장하지 않는다.
  final List<String> rejected;

  int get accepted => corrections.length;
}

// ══════════════════════════════════════════════════════════════════════
// 판정 — 전부 순수 함수다
// ══════════════════════════════════════════════════════════════════════

final RegExp _kWhitespace = RegExp(r'\s+');
final RegExp _kDigits = RegExp(r'\d+');
final RegExp _kLatin = RegExp(r'[A-Za-z]');

/// 바뀐 자리가 이만큼을 넘으면 교정이 아니라 다시 쓴 문장이다.
const int _kMaxChangedChars = 8;

/// 짧은 줄에서도 낱말 하나는 고칠 수 있어야 한다.
const int _kMinChangedAllowance = 2;

/// 전체 길이 대비 바꿔도 되는 비율.
const double _kMaxChangedRatio = 0.34;

/// 문장이 통째로 길어지거나 짧아지면 낱말을 되살린 것이 아니다.
const int _kMaxLengthDelta = 6;

/// 조사·어미로 흔히 쓰이는 음절. **이것만 바뀌면 교정이 아니다.**
///
/// 발음 오인식을 되살리는 일과 "말을 다듬는" 일을 가르는 기계적 경계다.
/// 프롬프트로 "조사를 바꾸지 말라"고 적어도 모델은 종종 바꾼다.
const Set<String> _kParticleSyllables = <String>{
  '은', '는', '이', '가', '을', '를', '에', '의', '도', '만', '과', '와', //
  '로', '으', '께', '서', '부', '터', '까', '지', '야', '요', '죠', '네', //
  '다', '어', '아', '고', '며', '면', '나', '든', '습', '니', //
  '자', '군', '걸', '텐', '데', '였', '했', '겠', '더', '라', //
};

/// 이 글자 앞의 낱말은 사람·자리를 가리킨다. **그 자리는 고치지 않는다.**
///
/// 이름·지명을 문맥만으로 바꾸는 것은 다른 사람 이야기로 만드는 일이다.
/// 표식이 없는 맨 이름까지 잡지는 못한다 — 그건 프롬프트와 PCM이 맡는다.
const Set<String> _kProperNounMarkers = <String>{
  '씨', '님', '군', '양', '역', '동', '구', '읍', '면', '리', '로', //
  '길', '점', '사', '팀', '부', '과', '실', '관', //
};

/// 이 글자 앞의 낱말은 수량·시각이다. 한글 숫자까지 여기서 걸린다("세시"→"네시").
const Set<String> _kQuantityMarkers = <String>{
  '시', '분', '초', '년', '월', '일', '주', '개', '명', '번', '원', '살', //
  '층', '호', 'км', '킬', '미', '센', '퍼', //
};

String _stripSpace(String v) => v.replaceAll(_kWhitespace, '');

/// 두 글에서 **다른 자리 한 곳**을 뽑는다. 공백은 미리 지운다.
///
/// 앞뒤로 같은 부분을 걷어 내면 남는 것이 실제로 바뀐 자리다. 한국어 전사는
/// 띄어쓰기가 흔들리므로("뒷 지표를" ↔ "기차표를") 어절 수로 세면 정상 교정도
/// 버리게 된다. 그래서 글자로 본다.
@immutable
class OriginChangedSpan {
  const OriginChangedSpan({
    required this.from,
    required this.to,
    required this.start,
    required this.tail,
  });

  /// 원문 쪽에서 바뀐 조각.
  final String from;

  /// 교정문 쪽에서 바뀐 조각.
  final String to;

  /// 바뀐 자리가 시작되는 위치(공백 제거 기준).
  final int start;

  /// 바뀐 자리 **바로 뒤**에 오는 글(공백 제거 기준). 단위·호칭을 여기서 본다.
  final String tail;

  bool get isEmpty => from.isEmpty && to.isEmpty;
}

/// 공백을 지운 두 글에서 바뀐 한 자리를 뽑는다.
OriginChangedSpan changedSpanOf(String raw, String corrected) {
  final String a = _stripSpace(raw);
  final String b = _stripSpace(corrected);
  var head = 0;
  while (head < a.length && head < b.length && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < a.length - head &&
      tail < b.length - head &&
      a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
    tail++;
  }
  return OriginChangedSpan(
    from: a.substring(head, a.length - tail),
    to: b.substring(head, b.length - tail),
    start: head,
    tail: a.substring(a.length - tail),
  );
}

/// 조사·어미만 바뀌었는가. 그것은 교정이 아니라 말 다듬기다.
bool isParticleOnlyChange(OriginChangedSpan span) {
  if (span.isEmpty) return false;
  bool allParticles(String v) =>
      v.isNotEmpty && v.split('').every(_kParticleSyllables.contains);
  // 한쪽이 비어 있으면 조사를 넣거나 뺀 것이다 — 그것도 다듬기다.
  if (span.from.isEmpty) return allParticles(span.to);
  if (span.to.isEmpty) return allParticles(span.from);
  return allParticles(span.from) && allParticles(span.to);
}

/// 숫자가 달라졌는가. **자릿수 하나라도 다르면 거절이다.**
bool changesNumbers(String raw, String corrected, OriginChangedSpan span) {
  final from = _kDigits.allMatches(raw).map((m) => m.group(0)).toList();
  final to = _kDigits.allMatches(corrected).map((m) => m.group(0)).toList();
  if (from.length != to.length) return true;
  for (var i = 0; i < from.length; i++) {
    if (from[i] != to[i]) return true;
  }
  // 바뀐 자리 자체에 숫자가 끼어 있으면 그 줄은 손대지 않는다.
  if (_kDigits.hasMatch(span.from) || _kDigits.hasMatch(span.to)) return true;
  // 한글 수사는 글자만으로 못 가린다("세"·"네"). 뒤에 오는 단위로 가린다.
  final String next = span.tail.isEmpty ? '' : span.tail[0];
  return _kQuantityMarkers.contains(next);
}

/// 고유명사를 건드렸는가.
///
/// 맨 이름은 못 잡는다 — 잡을 수 있는 것은 **표식이 붙은 자리**와 라틴 문자다.
/// 나머지는 프롬프트와 PCM 재검증이 맡는다.
bool changesProperNouns(OriginChangedSpan span) {
  if (_kLatin.hasMatch(span.from) || _kLatin.hasMatch(span.to)) return true;
  final String next = span.tail.isEmpty ? '' : span.tail[0];
  return _kProperNounMarkers.contains(next);
}

/// 🩺 [LUNA-GUARD] 문맥 교정기 전용 최소 수정 판정.
///
/// **[isMinimalTranscriptRepair]를 대신하지 않는다.** 그쪽은 어절 수가 같아야
/// 통과하는데, 한국어 전사는 띄어쓰기 자체가 흔들려서("뒷 지표를" → "기차표를")
/// 정상 교정까지 버린다. 여기서는 공백을 지우고 글자로 본다.
///
/// 통과 조건:
///   · 바뀐 자리가 **한 곳**이고, 그 길이가 여덟 글자와 전체의 34% 안쪽
///   · 전체 길이 변화가 여섯 글자 안쪽 — 문장을 보태거나 지운 것이 아니다
///   · 조사·어미만 바뀐 것이 아니다
///   · 숫자·단위가 그대로다
///   · 고유명사 표식 자리가 아니고 라틴 문자가 끼지 않았다
bool isMinimalOriginCorrection(String raw, String corrected) {
  final String a = raw.trim();
  final String b = corrected.trim();
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return false;
  final String sa = _stripSpace(a);
  final String sb = _stripSpace(b);
  // 띄어쓰기만 달라진 것은 교정이 아니다. 되살린 낱말이 없다.
  if (sa == sb) return false;
  if ((sa.length - sb.length).abs() > _kMaxLengthDelta) return false;

  final span = changedSpanOf(a, b);
  if (span.isEmpty) return false;
  final int changed =
      span.from.length > span.to.length ? span.from.length : span.to.length;
  if (changed > _kMaxChangedChars) return false;
  final int allowance = (sa.length * _kMaxChangedRatio).floor();
  if (changed > (allowance < _kMinChangedAllowance ? _kMinChangedAllowance : allowance)) {
    return false;
  }
  if (isParticleOnlyChange(span)) return false;
  if (changesNumbers(a, b, span)) return false;
  if (changesProperNouns(span)) return false;
  return true;
}

/// 교정이 비정상적으로 많은가.
///
/// **원문 복원의 폭주 가드와 같은 자를 쓴다**([isSuspectOverflow]) — 15%,
/// 최소 3건. 두 층이 다른 기준으로 폭주를 판단하면, 같은 통화에서 한쪽만
/// 살아남아 무엇이 정상인지 알 수 없게 된다.
bool isOriginCorrectionOverflow(int proposed, int turns) =>
    isSuspectOverflow(proposed, turns);

/// 모델 응답에서 교정을 읽는다. **모르는 줄은 버린다.**
List<DuoOriginProposal> parseDuoOriginCorrections(
  String content, {
  required Map<String, String> textById,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return const <DuoOriginProposal>[];
  }
  final list = decoded is Map ? decoded['corrections'] : decoded;
  if (list is! List) return const <DuoOriginProposal>[];

  final out = <DuoOriginProposal>[];
  final seen = <String>{};
  for (final raw in list) {
    if (raw is! Map) continue;
    final String id = (raw['id'] ?? raw['turn_id'] ?? '').toString().trim();
    if (id.isEmpty) continue;
    final String source = textById[id] ?? '';
    // 모르는 id는 모델이 지어낸 자리다. 지어낸 자리를 고치면 엉뚱한 줄이 바뀐다.
    if (source.isEmpty) continue;
    // 같은 줄을 두 번 고치라고 하면 첫 번째만 본다.
    if (!seen.add(id)) continue;
    final String corrected =
        (raw['text'] ?? raw['corrected'] ?? '').toString().trim();
    if (corrected.isEmpty) continue;
    if (corrected == source.trim()) continue;
    out.add(DuoOriginProposal(
      id: id,
      raw: source,
      corrected: corrected,
      reason: (raw['reason'] ?? '').toString().trim(),
    ));
  }
  return out;
}

/// 읽어 낸 교정을 가드에 태운다. **폭주면 통째로 버린다.**
DuoOriginCorrectionResult screenDuoOriginCorrections(
  List<DuoOriginProposal> proposals, {
  required int turns,
}) {
  if (proposals.isEmpty) {
    return const DuoOriginCorrectionResult.none();
  }
  // 🚧 폭주는 "그만큼 틀렸다"가 아니라 응답이 무너졌다는 뜻이다. 일부만
  //   골라 쓰지 않는다 — 무너진 응답에서 고른 몇 개도 근거가 없다.
  if (isOriginCorrectionOverflow(proposals.length, turns)) {
    return DuoOriginCorrectionResult(
      corrections: const <String, String>{},
      proposed: proposals.length,
      overflow: true,
      rejected: <String>[for (final p in proposals) '${p.id}:overflow'],
    );
  }
  final accepted = <String, String>{};
  final rejected = <String>[];
  for (final p in proposals) {
    if (!isMinimalOriginCorrection(p.raw, p.corrected)) {
      rejected.add('${p.id}:not_minimal');
      continue;
    }
    accepted[p.id] = p.corrected.trim();
  }
  return DuoOriginCorrectionResult(
    corrections: accepted,
    proposed: proposals.length,
    overflow: false,
    rejected: rejected,
  );
}

// ══════════════════════════════════════════════════════════════════════
// 지시문
// ══════════════════════════════════════════════════════════════════════

/// 모델에게 주는 규칙. **작문 금지가 규칙의 대부분이다.**
String buildDuoOriginCorrectorPrompt(String sourceName) {
  // 한 통화에서 두 사람이 서로 다른 언어로 말할 수 있다(직접 대화). 그래서
  // "이 대화는 X다"로 못 박지 않고, **고치는 줄과 같은 언어로** 두라고 적는다.
  final String lang = sourceName.trim().isEmpty
      ? 'the language the speakers are already using'
      : sourceName.trim();
  return '''You are auditing a speech-recognition transcript of one phone call between two people (A and B).

Speech recognition wrote each line the moment it was spoken, with no knowledge of what came before or after. You can see the whole call, so you can catch a word it heard wrong.

YOUR ONLY JOB
Return the lines where recognition clearly wrote the wrong word, with that word replaced. Nothing else.

WHAT TO FIX
- A word that sounds like another word, where only the other one makes sense in this conversation.
- A common noun that the surrounding turns make near-certain.
That is all. One or two words in a line, never more.

NEVER DO ANY OF THIS
- Do not rewrite, polish, shorten, expand, or smooth a line.
- Do not change a particle, an ending, the word order, or the speech level. Casual stays casual.
- Do not fix grammar. Real speech is ungrammatical, and that is not an error.
- Do not add a word that was not said, and do not fill in something left out.
- Do not infer new facts and do not resolve who someone is.

NEVER TOUCH THESE, EVEN WHEN THEY LOOK WRONG
Numbers, times, dates, amounts of money, phone numbers, people's names, place names,
company names, shop names, product names. Something else re-listens to the audio for
those. Leave them exactly as written.

WHEN YOU ARE NOT SURE
Leave the line out. A line that keeps a misheard word is far better than a line the
speaker never said. Most calls need no correction at all, and returning nothing is a
normal, correct answer.

Most of this call is in $lang. Keep every corrected line in the same language as the line you are correcting, and never translate.

Return strict JSON only, and include ONLY the lines you are correcting:
{"corrections":[{"id":"<line id>","text":"<the line with only the misheard word replaced>","reason":"<the word you replaced>"}]}''';
}

/// 모델에게 주는 대화. 시간순 전체이고, 화자는 A/B뿐이다.
String formatDuoOriginPayload(List<DuoOriginLine> lines) => jsonEncode(
      <String, dynamic>{
        'lines': <Map<String, String>>[
          for (final l in lines)
            <String, String>{
              'id': l.id,
              'speaker': l.speaker,
              'text': l.text,
            }
        ]
      },
    );

// ══════════════════════════════════════════════════════════════════════
// 실행
// ══════════════════════════════════════════════════════════════════════

/// 모델 한 번. 응답 본문을 그대로 돌려주고, 실패면 null이다.
typedef DuoOriginModelCall = Future<String?> Function(String payload);

/// 대화 하나를 교정한다. **실패는 전부 "원 전사 유지"로 떨어진다.**
///
/// 호출을 주입받으므로 테스트가 네트워크 없이 모든 갈래를 태운다.
Future<DuoOriginCorrectionResult> resolveDuoOriginCorrections({
  required List<DuoOriginLine> lines,
  required DuoOriginModelCall call,
}) async {
  if (lines.isEmpty) return const DuoOriginCorrectionResult.none();
  final textById = <String, String>{for (final l in lines) l.id: l.text};
  String? content;
  try {
    content = await call(formatDuoOriginPayload(lines));
  } catch (e) {
    debugPrint('[DUO-ORIGIN-CORRECT] call_failed=${e.runtimeType}');
    return const DuoOriginCorrectionResult.none();
  }
  if (content == null || content.trim().isEmpty) {
    return const DuoOriginCorrectionResult.none();
  }
  final proposals = parseDuoOriginCorrections(content, textById: textById);
  final result = screenDuoOriginCorrections(proposals, turns: lines.length);
  // 🔇 발화 내용은 남기지 않는다. 세는 것만 센다.
  debugPrint('[DUO-ORIGIN-CORRECT] proposed=${result.proposed} '
      'accepted=${result.accepted} overflow=${result.overflow} '
      'turns=${lines.length}');
  return result;
}

/// 실제 호출. HTTP 하나를 [resolveDuoOriginCorrections]에 물려 준다.
Future<DuoOriginCorrectionResult> correctDuoOriginTexts({
  required String apiKey,
  required String model,
  required String sourceName,
  required List<DuoOriginLine> lines,
  http.Client? client,
}) async {
  if (apiKey.isEmpty || lines.isEmpty) {
    return const DuoOriginCorrectionResult.none();
  }
  final http.Client http_ = client ?? http.Client();
  return resolveDuoOriginCorrections(
    lines: lines,
    call: (payload) async {
      final response = await http_
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'model': model,
              // 판정이라 흔들리면 안 된다. 같은 대화는 같은 교정을 낸다.
              'temperature': 0.0,
              'max_tokens': 1200,
              'response_format': <String, String>{'type': 'json_object'},
              'messages': <Map<String, String>>[
                <String, String>{
                  'role': 'system',
                  'content': buildDuoOriginCorrectorPrompt(sourceName),
                },
                <String, String>{'role': 'user', 'content': payload},
              ],
            }),
          )
          .timeout(kDuoOriginCorrectTimeout);
      if (response.statusCode != 200) {
        debugPrint('[DUO-ORIGIN-CORRECT] status=${response.statusCode}');
        return null;
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body['choices']?[0]?['message']?['content']?.toString();
    },
  );
}
