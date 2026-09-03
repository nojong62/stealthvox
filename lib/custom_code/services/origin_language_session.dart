// ====================================================================
// 🌐 [ORIGIN-RESOLVE] 첫 발화가 로비 ORIGIN과 다른 언어인지 **알아만 둔다**
// --------------------------------------------------------------------
// 로비 ORIGIN 기본값은 'Korean'이다(app_state.dart). 설정을 모르는 유저가
// 그대로 두고 자기 언어로 말하면, 전사기에 language=ko가 박혀 있어서 일본어
// 발화가 한글로 음차되어 나온다. 그 깨진 문장이 원문으로 저장되고 학습
// 자료의 출발점이 된다.
//
// 그래서 **첫 발화만 언어를 박지 않고 자동 감지로 전사**한 뒤, 그 전사문에서
// 실제 언어를 판정한다.
//
// 🚫 **판정 결과로 ORIGIN을 갈아 끼우지 않는다.**
//
//   예전에는 갈아 끼웠다(2026-09-04 이전). 유저가 로비 설정과 다른 말로
//   시작하면 이 세션 동안만 그 언어를 ORIGIN으로 삼고, "이번 대화는 한국어로
//   진행할게요"라고 통보했다. 그러면 **유저가 고르지도 않은 언어가 히스토리
//   메타데이터(`native_lang`)에 남는다.** 로비에서 분명히 골라 둔 값이 있는데
//   말 한마디로 조용히 뒤집히는 것이라, 유저는 자기 설정이 왜 안 먹는지 알 수
//   없었다.
//
//   기준은 언제나 **유저가 확정한 ORIGIN**이다. 판정값은 [detected]에 적어
//   두고, 확인 창(`origin_language_recheck_dialog.dart`)을 띄우는 데에만 쓴다.
//   유저가 그 창에서 확정해야 비로소 [override]로 값이 바뀐다.
//
// **저장하지 않는다.** `FFAppState().nativeLang`의 setter는 prefs에 즉시
// 쓰므로 여기서는 건드리지 않는다. 확정은 호출부가 두 곳에 함께 적는다.
//
// 판정은 **세션당 딱 한 번**이다. 대화 중간에 유저가 한 마디 외국어를 섞어도
// 다시 묻지 않는다.
// ====================================================================

import 'dart:async';
import 'dart:convert';

import 'openai_connection_pool.dart';

/// 로비가 제공하는 ORIGIN 12종. 판정 결과는 반드시 이 안에서 나온다.
///
/// 여기 없는 언어로 갈아 끼우면 `originRetryLine`·`localizedSeedGuidanceLine`
/// 같은 고정 문구표가 전부 영어로 떨어져, 되묻기만 영어로 나오는 잡탕이 된다.
/// 표와 목록을 같은 12개로 묶어 둔다.
const List<String> kOriginLanguageOptions = <String>[
  'English',
  'Japanese',
  'Chinese',
  'Spanish',
  'French',
  'German',
  'Korean',
  'Hindi',
  'Russian',
  'Portuguese',
  'Italian',
  'Dutch',
];

/// 🏷️ [LANG-LABEL] 저장값(영문 언어명) → 화면에 적을 한국어 이름.
///
/// 저장값과 표시명은 **다른 층이다.** 저장값은 `'Japanese'`처럼 영문으로만
/// 남고(프롬프트·API가 그 이름을 쓴다), 화면 문구는 한국어로 적는다.
///
/// 표는 여기 하나뿐이다. 화면마다 따로 만들면 반드시 어긋난다 —
/// 히스토리 언어 토글은 예전에 '영어만 보기' / '한글만 보기'로 박혀 있어서,
/// 일본어↔스페인어로 쓰는 사람에게 없는 언어를 말하고 있었다.
///
/// 로비가 주는 12개 밖의 값은 **그대로 돌려준다.** 영문 이름이라도 보이는 편이
/// 엉뚱한 언어로 적히는 것보다 낫다.
String koreanLanguageDisplayName(String language) {
  switch (language.trim().toLowerCase()) {
    case 'korean':
      return '한국어';
    case 'english':
      return '영어';
    case 'japanese':
      return '일본어';
    case 'chinese':
      return '중국어';
    case 'spanish':
      return '스페인어';
    case 'french':
      return '프랑스어';
    case 'german':
      return '독일어';
    case 'hindi':
      return '힌디어';
    case 'russian':
      return '러시아어';
    case 'portuguese':
      return '포르투갈어';
    case 'italian':
      return '이탈리아어';
    case 'dutch':
      return '네덜란드어';
    default:
      return language.trim();
  }
}

/// 라틴 문자를 쓰는 ORIGIN. 문자만으로는 서로 구분되지 않아 모델 판정이 필요하다.
const Set<String> _kLatinScriptOrigins = <String>{
  'English',
  'Spanish',
  'French',
  'German',
  'Portuguese',
  'Italian',
  'Dutch',
};

/// 문자 판정을 시도할 최소 길이(문자·라틴 제외).
/// "네", "응" 같은 한두 글자로 언어를 뒤집으면 안 된다.
const int _kMinNonLatinChars = 4;

/// 라틴 문자일 때 모델 판정을 걸 최소 단어 수.
/// "OK", "yes" 한 마디로 ORIGIN을 갈아 끼우지 않는다.
const int _kMinLatinWords = 3;

/// 비라틴 문자끼리 비교할 때 우세 문자로 인정할 최소 비율.
const double _kDominantScriptRatio = 0.6;

/// 라틴 문자를 제치고 비라틴 문자로 판정하기 위한 최소 존재 비율.
///
/// 낮게 잡는 이유: 어느 언어든 외래어·상표·약어를 라틴 문자로 적는다.
/// "오늘 meeting 끝나고 집에 갔어요"는 한글이 절반을 겨우 넘는데, 이걸
/// 판정 보류로 떨어뜨리면 정작 걸러야 할 불일치까지 같이 새어 나간다.
/// 거꾸로 "hello world 안녕"처럼 한두 글자만 섞인 경우는 이 문턱에 걸려
/// 라틴 판정으로 넘어간다.
const double _kNonLatinPresenceRatio = 0.3;

/// 모델 판정 제한 시간. 넘기면 로비값을 그대로 쓴다 — 첫 턴을 늦추지 않는다.
const Duration _kJudgeTimeout = Duration(milliseconds: 1500);

/// 문자만으로 내린 판정.
class OriginScriptVerdict {
  const OriginScriptVerdict({
    required this.language,
    required this.decisive,
    required this.reason,
  });

  /// 판정된 언어 이름. 확정하지 못했으면 null.
  final String? language;

  /// 문자만으로 확정됐는가. false면 모델 판정이 필요하다.
  final bool decisive;

  final String reason;
}

/// 전사문의 문자 구성만 보고 언어를 가른다. 네트워크를 쓰지 않는다(0ms, 무료).
///
/// 한글·가나·키릴 같은 고유 문자는 여기서 끝난다. 라틴 문자는 여러 언어가
/// 나눠 쓰므로 [decisive]가 false로 나오고, 호출부가 모델 판정으로 넘긴다.
OriginScriptVerdict detectOriginScript(String text) {
  var hangul = 0;
  var kana = 0;
  var han = 0;
  var cyrillic = 0;
  var devanagari = 0;
  var latin = 0;
  var counted = 0;

  for (final rune in text.runes) {
    // 공백·문장부호·숫자는 언어 근거가 못 된다.
    if (rune <= 0x40) continue;
    var matched = true;
    if ((rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x3130 && rune <= 0x318F)) {
      hangul++;
    } else if ((rune >= 0x3040 && rune <= 0x309F) ||
        (rune >= 0x30A0 && rune <= 0x30FF)) {
      kana++;
    } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
      han++;
    } else if (rune >= 0x0400 && rune <= 0x04FF) {
      cyrillic++;
    } else if (rune >= 0x0900 && rune <= 0x097F) {
      devanagari++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0xC0 && rune <= 0x24F)) {
      latin++;
    } else {
      matched = false;
    }
    if (matched) counted++;
  }

  if (counted == 0) {
    return const OriginScriptVerdict(
      language: null,
      decisive: false,
      reason: 'no_countable_chars',
    );
  }

  final nonLatin = hangul + kana + han + cyrillic + devanagari;

  // 비라틴 문자가 충분히 있으면 **비라틴끼리만** 비교해 고른다. 라틴 문자는
  // 외래어·상표·약어로 어느 언어에나 섞여 들어오므로, 전체 대비 비율로
  // 재면 멀쩡한 한국어 문장이 판정 보류로 떨어진다.
  if (nonLatin >= _kMinNonLatinChars &&
      nonLatin >= counted * _kNonLatinPresenceRatio) {
    bool dominant(int n) => n >= nonLatin * _kDominantScriptRatio;
    // 가나가 하나라도 있으면 일본어다. 한자를 함께 써도 마찬가지다 —
    // 중국어에는 가나가 없다.
    if (kana > 0 && dominant(kana + han)) {
      return const OriginScriptVerdict(
          language: 'Japanese', decisive: true, reason: 'kana');
    }
    if (dominant(hangul)) {
      return const OriginScriptVerdict(
          language: 'Korean', decisive: true, reason: 'hangul');
    }
    // 가나 없이 한자만 = 중국어.
    if (dominant(han)) {
      return const OriginScriptVerdict(
          language: 'Chinese', decisive: true, reason: 'han_only');
    }
    if (dominant(cyrillic)) {
      return const OriginScriptVerdict(
          language: 'Russian', decisive: true, reason: 'cyrillic');
    }
    if (dominant(devanagari)) {
      return const OriginScriptVerdict(
          language: 'Hindi', decisive: true, reason: 'devanagari');
    }
    // 비라틴 문자끼리 섞여 우열이 없다. 근거가 없으니 로비값을 지킨다.
    return const OriginScriptVerdict(
        language: null, decisive: false, reason: 'mixed_script');
  }

  if (latin >= counted * _kDominantScriptRatio) {
    // 라틴 문자를 쓰는 ORIGIN이 일곱이다. 여기서는 못 가른다.
    return const OriginScriptVerdict(
      language: null,
      decisive: false,
      reason: 'latin_needs_judge',
    );
  }
  if (nonLatin > 0) {
    // 고유 문자가 보이긴 하는데 언어를 뒤집을 만큼은 아니다("네", "はい").
    return const OriginScriptVerdict(
        language: null, decisive: false, reason: 'too_short');
  }
  return const OriginScriptVerdict(
    language: null,
    decisive: false,
    reason: 'mixed_script',
  );
}

// ────────────────────────────────────────────────────────────────────
// 🔤 [SCRIPT-CHECK] 선언된 언어가 아니라 **실제 글자**로 확인한다.
//
//   로비의 ORIGIN/TARGET은 유저가 적어 둔 선언일 뿐이다. 그 선언이 실제
//   발화와 어긋나면(영어로 적어 두고 한국어로 말한다) "이 줄은 이미 배울
//   언어다"라는 지름길이 잘못 열려, 원문이 배울글 자리에 그대로 복사된다.
//   2026-08-28 실기기 로그가 그 자리를 찍었다:
//     [HISTORY-TARGET] generated model=copy src=English tgt=English
//     → 본문은 한국어("책 얘기도 하고")였다.
//
//   라틴 문자를 쓰는 일곱 언어끼리는 글자로 가릴 수 없다. 그때는 둘 다
//   false다 — **근거 없이 선언을 뒤집지 않는다.**
// ────────────────────────────────────────────────────────────────────

/// 글자로 보아 [text]가 확실히 [language]인가.
bool textIsLanguage(String text, String language) {
  final lang = language.trim();
  if (lang.isEmpty) return false;
  final verdict = detectOriginScript(text);
  final decided = verdict.language;
  if (!verdict.decisive || decided == null) return false;
  return decided.toLowerCase() == lang.toLowerCase();
}

/// 글자로 보아 [text]가 [language]가 **아님이 분명한가.**
bool textContradictsLanguage(String text, String language) {
  final lang = language.trim();
  if (lang.isEmpty) return false;
  final verdict = detectOriginScript(text);
  final decided = verdict.language;
  if (!verdict.decisive || decided == null) return false;
  return decided.toLowerCase() != lang.toLowerCase();
}

/// 라틴 문자 전사문이 어느 ORIGIN인지 모델에게 묻는다.
/// 실패·타임아웃·목록 밖 응답은 전부 null — 그러면 로비값을 그대로 쓴다.
Future<String?> _judgeLatinOrigin({
  required String apiKey,
  required String transcript,
  void Function(String tag, String msg)? onLog,
}) async {
  if (apiKey.isEmpty) return null;
  final options = _kLatinScriptOrigins.toList()..sort();
  try {
    final response = await OpenAiConnectionPool.instance.client
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, dynamic>{
            'model': 'gpt-4o-mini',
            'temperature': 0,
            'max_tokens': 20,
            'response_format': <String, String>{'type': 'json_object'},
            'messages': <Map<String, String>>[
              <String, String>{
                'role': 'system',
                'content': '''Identify the language of the user's transcript.

Answer with exactly one of: ${options.join(', ')}.
If the transcript is too short, ambiguous, or not clearly one of those, answer "Unknown".
Judge the language only — never the meaning, topic, or quality.

Reply as JSON: {"language": "<one of the names above, or Unknown>"}''',
              },
              <String, String>{'role': 'user', 'content': transcript},
            ],
          }),
        )
        .timeout(_kJudgeTimeout);
    if (response.statusCode != 200) {
      onLog?.call('🌐 [ORIGIN-JUDGE]', 'status=${response.statusCode}');
      return null;
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content = (((decoded['choices'] as List<dynamic>?)?.first
            as Map<String, dynamic>?)?['message'] as Map<String, dynamic>?)?['content']
        as String?;
    if (content == null) return null;
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final name = (parsed['language'] as String?)?.trim() ?? '';
    // 목록 밖 응답(Unknown 포함)은 근거가 없는 것으로 본다.
    return _kLatinScriptOrigins.contains(name) ? name : null;
  } on TimeoutException {
    onLog?.call('🌐 [ORIGIN-JUDGE]', 'timeout → keep lobby origin');
    return null;
  } catch (e) {
    onLog?.call('🌐 [ORIGIN-JUDGE]', 'failed reason=${e.runtimeType}');
    return null;
  }
}

/// 첫 발화의 전사문에서 이 세션의 ORIGIN을 정한다.
///
/// 로비값과 같거나 근거가 약하면 null을 돌려준다 — 호출부는 아무것도 바꾸지
/// 않는다. **애매하면 로비값이 이긴다**가 이 함수의 기본 태도다.
Future<String?> resolveOriginFromFirstUtterance({
  required String apiKey,
  required String transcript,
  required String lobbyOrigin,
  void Function(String tag, String msg)? onLog,
}) async {
  final text = transcript.trim();
  if (text.isEmpty) return null;

  final verdict = detectOriginScript(text);
  if (verdict.decisive) {
    final detected = verdict.language!;
    if (detected == lobbyOrigin) {
      onLog?.call('🌐 [ORIGIN-RESOLVE]',
          'script=${verdict.reason} matches lobby=$lobbyOrigin → keep');
      return null;
    }
    onLog?.call('🌐 [ORIGIN-RESOLVE]',
        'script=${verdict.reason} lobby=$lobbyOrigin → $detected');
    return detected;
  }

  if (verdict.reason != 'latin_needs_judge') {
    onLog?.call(
        '🌐 [ORIGIN-RESOLVE]', 'undecided(${verdict.reason}) → keep lobby');
    return null;
  }

  // 라틴 문자다. 로비값이 비라틴이면 이미 불일치가 확정이지만, 어느
  // 라틴 언어인지는 모델만 안다. 로비값이 라틴이어도 물어봐야 한다 —
  // 기본값 그대로 둔 영어권 밖 유저가 여기로 들어온다.
  final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (wordCount < _kMinLatinWords) {
    onLog?.call(
        '🌐 [ORIGIN-RESOLVE]', 'latin too short words=$wordCount → keep lobby');
    return null;
  }

  final judged =
      await _judgeLatinOrigin(apiKey: apiKey, transcript: text, onLog: onLog);
  if (judged == null || judged == lobbyOrigin) {
    onLog?.call('🌐 [ORIGIN-RESOLVE]',
        'judge=${judged ?? 'none'} lobby=$lobbyOrigin → keep');
    return null;
  }
  onLog?.call(
      '🌐 [ORIGIN-RESOLVE]', 'judge lobby=$lobbyOrigin → $judged');
  return judged;
}

/// 이 세션의 ORIGIN 상태. **유저가 확정한 값만 로비값을 이긴다.**
///
/// 방에 들어올 때 [begin]으로 비우고, 첫 발화에서 [adopt]로 판정만 적어 둔다.
/// 판정은 [resolve]에 영향을 주지 않는다 — 확인 창을 띄울지 정할 뿐이다.
/// prefs에는 한 글자도 쓰지 않는다.
class OriginLanguageSession {
  OriginLanguageSession._();

  static final OriginLanguageSession instance = OriginLanguageSession._();

  /// 유저가 확인 창에서 확정한 ORIGIN. 확정 전에는 null이다.
  String? _override;

  /// 첫 발화에서 판정된 언어. **ORIGIN이 아니다** — 물어볼 근거일 뿐이다.
  String? _detected;

  bool _settled = false;
  bool _noticeShown = false;

  /// 판정이 끝났는가. 세션당 한 번만 판정하기 위한 빗장이다.
  bool get settled => _settled;

  /// 첫 발화가 로비값과 다른 언어로 판정됐는가. 그 언어가 담긴다.
  ///
  /// ⚠️ 이 값을 ORIGIN으로 쓰지 말 것. 전사기·히스토리·번역 방향은 전부
  ///   [resolve]를 본다.
  String? get detected => _detected;

  /// 물어볼 것이 있는가 — 판정이 로비값과 달랐는가.
  bool get mismatched => _detected != null;

  /// 유저가 확인 창에서 ORIGIN을 실제로 바꿨는가.
  bool get switched => _override != null;

  /// 유저가 확정한 언어. 확정이 없었으면 null.
  String? get adopted => _override;

  /// 확인 창을 아직 안 띄웠으면 true를 한 번만 돌려준다.
  ///
  /// [switched]가 아니라 [mismatched]를 본다. 확정은 유저가 창에서 하는
  /// 것이므로, 창을 띄우기 전에는 아직 아무것도 바뀌어 있지 않다.
  bool takeNoticeSlot() {
    if (!mismatched || _noticeShown) return false;
    _noticeShown = true;
    return true;
  }

  /// 방 입장·퇴장 시 호출. 세션 한정을 보장하는 자리다.
  void begin() {
    _override = null;
    _detected = null;
    _settled = false;
    _noticeShown = false;
  }

  /// 첫 발화 판정 결과를 **적어만 둔다.** [languageName]이 null이면 로비값과
  /// 같거나 근거가 약했다는 뜻이라, 물을 것도 없이 확정만 한다.
  ///
  /// 🚫 [resolve]가 내는 값은 여기서 바뀌지 않는다. 기준은 유저가 확정한
  ///   ORIGIN이고, 판정은 확인 창을 띄우는 근거일 뿐이다.
  void adopt(String? languageName) {
    _settled = true;
    if (languageName == null) return;
    if (!kOriginLanguageOptions.contains(languageName)) return;
    _detected = languageName;
  }

  /// 🌐 [ORIGIN-RECHECK] **유저가 확인 창에서 확정한 값**으로 ORIGIN을 잡는다.
  ///
  /// [adopt]와 하는 일이 다르다. 그쪽은 기계가 내린 판정을 적어 두는 것이고,
  /// 이쪽은 유저가 손으로 고른 값이라 **이것만이 ORIGIN을 바꾼다.**
  /// 판정과 다른 언어를 골랐을 수도 있으므로(일부러 다른 언어를 연습하는
  /// 경우) 고른 값을 그대로 따른다.
  ///
  /// 호출부는 같은 값을 `FFAppState().nativeLang`과 히스토리 방 문서에도
  /// 함께 적는다 — 세 곳이 어긋나면 히스토리가 엉뚱한 언어로 배울글을 만든다.
  ///
  /// 목록(12개) 밖의 값은 무시한다 — 고정 문구표가 그 12개에만 있어서
  /// 벗어나면 되묻기만 영어로 나오는 잡탕이 된다.
  void override(String languageName) {
    _settled = true;
    if (!kOriginLanguageOptions.contains(languageName)) return;
    _override = languageName;
  }

  /// 이 세션에서 실제로 쓸 ORIGIN.
  ///
  /// **유저가 확정하지 않았으면 로비값 그대로다.** 첫 발화가 다른 언어였어도
  /// 여기서는 아무 일도 일어나지 않는다.
  String resolve(String lobbyOrigin) => _override ?? lobbyOrigin;
}
