import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// 쇼츠 링크 → 시나리오톡 세 칸 + 핵심 표현 (서버 `extractShortsScenario`,
/// firebase/functions/shorts_scenario.js).
///
/// 상황·역할은 로비 Origin, 표현 문장은 로비 Target, 표현 뜻은 Origin으로
/// 받는다. 대사 전문은 서버가 돌려주지 않는다.
class ShortsExpression {
  const ShortsExpression({required this.text, required this.meaning});

  /// Target 언어 문장 — 화면 위, 큰 글씨.
  final String text;

  /// Origin 언어 뜻 — 화면 아래, 작은 글씨.
  final String meaning;

  static ShortsExpression? fromMap(Object? value) {
    if (value is! Map) return null;
    final text = (value['text'] ?? '').toString().trim();
    if (text.isEmpty) return null;
    return ShortsExpression(
      text: text,
      meaning: (value['meaning'] ?? '').toString().trim(),
    );
  }
}

class ShortsScenarioResult {
  const ShortsScenarioResult({
    required this.situation,
    required this.aiRole,
    required this.userRole,
    required this.expressions,
    this.sourceUrl = '',
  });

  final String situation;
  final String aiRole;
  final String userRole;
  final List<ShortsExpression> expressions;

  /// 출처 표시용 원본 링크(서버가 검증한 ID로 만든 것).
  final String sourceUrl;
}

/// 실패 이유. 화면 문구는 [code]로 고른다.
///   notYoutube · unavailable(비공개·삭제) · unusable(대화 없는 영상)
///   limit(하루 상한) · noTime(시간 없음) · adultOnly(만 18세 미만) · failed(그 밖)
class ShortsScenarioException implements Exception {
  const ShortsScenarioException(this.code);
  final String code;
  @override
  String toString() => 'ShortsScenarioException($code)';
}

/// 서버 결과 맵 → 결과. 쓸 수 없는 영상이면 unusable 예외.
@visibleForTesting
ShortsScenarioResult parseShortsScenarioResult(Object? data) {
  if (data is! Map) throw const ShortsScenarioException('failed');
  if (data['usable'] != true) throw const ShortsScenarioException('unusable');
  String field(String key) => (data[key] ?? '').toString().trim();
  final situation = field('situation');
  final aiRole = field('aiRole');
  final userRole = field('userRole');
  if (situation.isEmpty || aiRole.isEmpty || userRole.isEmpty) {
    throw const ShortsScenarioException('unusable');
  }
  final raw = data['expressions'];
  final expressions = raw is List
      ? raw.map(ShortsExpression.fromMap).whereType<ShortsExpression>().toList()
      : <ShortsExpression>[];
  return ShortsScenarioResult(
    situation: situation,
    aiRole: aiRole,
    userRole: userRole,
    expressions: expressions,
    sourceUrl: field('sourceUrl'),
  );
}

@visibleForTesting
String shortsErrorCodeFor(String functionsCode) {
  switch (functionsCode) {
    case 'invalid-argument':
      return 'notYoutube';
    case 'not-found':
      return 'unavailable';
    case 'resource-exhausted':
      return 'limit';
    case 'permission-denied':
      return 'noTime';
    case 'out-of-range':
      return 'adultOnly';
    default:
      return 'failed';
  }
}

/// 링크처럼 보이는지 앱에서 먼저 거른다(서버도 다시 본다).
bool looksLikeYoutubeLink(String value) {
  final v = value.trim().toLowerCase();
  return v.contains('youtube.com/') || v.contains('youtu.be/');
}

/// AI 프롬프트에 붙는 표현 블록. 표현이 없으면 빈 문자열이라 기존 프롬프트가
/// 글자 하나 바뀌지 않는다.
String shortsExpressionsPromptBlock(List<ShortsExpression> expressions) {
  if (expressions.isEmpty) return '';
  final lines = expressions.map((e) =>
      e.meaning.isEmpty ? '- ${e.text}' : '- ${e.text} (= ${e.meaning})');
  return '\nKey expressions from the video this scene came from. Let the '
      'conversation naturally give the user chances to use them, and when a '
      'line means the same thing, prefer these exact wordings:\n'
      '${lines.join('\n')}';
}

class ShortsScenarioService {
  ShortsScenarioService._();

  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static Future<ShortsScenarioResult> extract({
    required String url,
    required String originLanguage,
    required String targetLanguage,
  }) async {
    if (!looksLikeYoutubeLink(url)) {
      throw const ShortsScenarioException('notYoutube');
    }
    final sw = Stopwatch()..start();
    try {
      final response = await _functions
          .httpsCallable(
            'extractShortsScenario',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
          )
          .call(<String, dynamic>{
        'url': url.trim(),
        'originLanguage': originLanguage,
        'targetLanguage': targetLanguage,
      });
      final result = parseShortsScenarioResult(response.data);
      debugPrint('[SHORTS-SCENARIO] ok ms=${sw.elapsedMilliseconds} '
          'expressions=${result.expressions.length} '
          'cached=${(response.data as Map)['cached'] == true}');
      return result;
    } on FirebaseFunctionsException catch (error) {
      debugPrint('[SHORTS-SCENARIO] failed code=${error.code} '
          'ms=${sw.elapsedMilliseconds}');
      throw ShortsScenarioException(shortsErrorCodeFor(error.code));
    } on ShortsScenarioException catch (error) {
      debugPrint('[SHORTS-SCENARIO] failed code=${error.code} '
          'ms=${sw.elapsedMilliseconds}');
      rethrow;
    } catch (error) {
      debugPrint('[SHORTS-SCENARIO] failed code=failed '
          'reason=${error.runtimeType} ms=${sw.elapsedMilliseconds}');
      throw const ShortsScenarioException('failed');
    }
  }
}
