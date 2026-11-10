// ====================================================================
// 🌍 [OTHER-LANG] 대화 언어 "기타 언어" — 2026-11-10 실장님 결정
// --------------------------------------------------------------------
// 로비 대화 언어 14개 밖의 사람을 위한 자리다. 배울 언어는 14개 안에서만.
//
//   · 로비 저장값은 `'Other'` 하나다(FFAppState.chatLangRaw).
//   · 실제로 쓰는 언어 이름은 첫 마디에서 AI가 판정해 저장해 둔다
//     (FFAppState.otherChatLang / otherChatLangCode). 판정 전에는 폰 시스템
//     언어로 짐작하고, 그것도 모르면 English다.
//   · FFAppState.chatLang은 그 "실제 이름"을 돌려준다 — 프롬프트·히스토리·
//     음성은 'Thai' 같은 진짜 이름을 받는다. 'Other'를 보는 곳은 로비 목록과
//     아래 [isOtherChatLanguageSelected]뿐이다.
//   · 전사는 언제나 자동 감지(언어를 박지 않는다).
//   · 통화 통역: 한쪽이라도 기타면 직접통화로 넘어가지 않고, 기타 쪽은 상대
//     말을 자기 **배울 언어**로 듣는다.
// ====================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import '/app_state.dart';
import 'openai_connection_pool.dart';
import 'secure_ai_gateway.dart';
import 'history_text_model.dart';

const String kOtherChatLanguage = 'Other';

/// 로비에서 "기타 언어"를 골랐는가.
bool get isOtherChatLanguageSelected =>
    FFAppState().chatLangRaw == kOtherChatLanguage;

/// 흔한 언어 코드 → 영문 이름. 폰 시스템 언어로 첫 짐작을 할 때만 쓴다.
const Map<String, String> kOtherLanguageNames = <String, String>{
  'ar': 'Arabic',
  'bg': 'Bulgarian',
  'bn': 'Bengali',
  'cs': 'Czech',
  'da': 'Danish',
  'el': 'Greek',
  'et': 'Estonian',
  'fa': 'Persian',
  'fi': 'Finnish',
  'fil': 'Filipino',
  'gu': 'Gujarati',
  'he': 'Hebrew',
  'hr': 'Croatian',
  'hu': 'Hungarian',
  'kn': 'Kannada',
  'lt': 'Lithuanian',
  'lv': 'Latvian',
  'ml': 'Malayalam',
  'mr': 'Marathi',
  'ms': 'Malay',
  'nb': 'Norwegian',
  'no': 'Norwegian',
  'pa': 'Punjabi',
  'pl': 'Polish',
  'ro': 'Romanian',
  'sk': 'Slovak',
  'sl': 'Slovenian',
  'sr': 'Serbian',
  'sv': 'Swedish',
  'sw': 'Swahili',
  'ta': 'Tamil',
  'te': 'Telugu',
  'th': 'Thai',
  'tl': 'Filipino',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'ur': 'Urdu',
};

/// 판정 전 첫 짐작. 폰 시스템 언어가 표에 있으면 그 언어, 아니면 English.
({String name, String code}) otherLanguageDeviceGuess() {
  final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
  final name = kOtherLanguageNames[code];
  return name == null
      ? (name: 'English', code: 'en')
      : (name: name, code: code == 'tl' ? 'fil' : code);
}

/// 첫 마디가 무슨 언어인지 묻는다(언어 목록 제한 없음). 실패하면 null.
Future<({String name, String code})?> detectSpokenLanguage({
  required String apiKey,
  required String transcript,
  void Function(String tag, String msg)? onLog,
}) async {
  final text = transcript.trim();
  if (apiKey.isEmpty || text.isEmpty) return null;
  try {
    final response = await OpenAiConnectionPool.instance.client
        .post(
          SecureAiGateway.openAiUri('/v1/chat/completions'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, dynamic>{
            'model': kPostProcessModel,
            'reasoning_effort': kLiveTextReasoningEffort,
            'max_completion_tokens': 40,
            'response_format': <String, String>{'type': 'json_object'},
            'messages': <Map<String, String>>[
              <String, String>{
                'role': 'system',
                'content': '''Identify the language of the user's transcript.
Reply as JSON: {"name": "<English name of the language, e.g. Thai>", "code": "<ISO 639-1 code, or ISO 639-3 if there is no 639-1 code>"}.
If you cannot tell, reply {"name": "", "code": ""}.''',
              },
              <String, String>{'role': 'user', 'content': text},
            ],
          }),
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      onLog?.call('🌍 [OTHER-LANG]', 'detect status=${response.statusCode}');
      return null;
    }
    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content = (((decoded['choices'] as List<dynamic>?)?.first
            as Map<String, dynamic>?)?['message']
        as Map<String, dynamic>?)?['content'] as String?;
    if (content == null) return null;
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    final name = (parsed['name'] as String?)?.trim() ?? '';
    final code = (parsed['code'] as String?)?.trim().toLowerCase() ?? '';
    if (name.isEmpty || !RegExp(r'^[a-z]{2,3}$').hasMatch(code)) return null;
    return (name: name, code: code);
  } on TimeoutException {
    onLog?.call('🌍 [OTHER-LANG]', 'detect timeout');
    return null;
  } catch (e) {
    onLog?.call('🌍 [OTHER-LANG]', 'detect failed ${e.runtimeType}');
    return null;
  }
}

/// 판정 결과를 저장한다. 다음 대화도 이 언어로 시작한다.
void rememberOtherChatLanguage(({String name, String code}) detected) {
  FFAppState().otherChatLang = detected.name;
  FFAppState().otherChatLangCode = detected.code;
}
