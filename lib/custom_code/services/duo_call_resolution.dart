// Room-scoped execution-mode resolution for Duo calls.
//
// `duo_sessions.mode` is the invitation mode and remains immutable. An
// Interpreter invitation may resolve to Direct only after both participants
// have joined, published their Chat Lang, and advertised support for this
// negotiation version.

const String kDuoResolvedModeField = 'resolvedMode';
const String kDuoResolvedModeLockedAtField = 'resolvedModeLockedAt';
const String kDuoResolutionReasonField = 'resolutionReason';
const String kDuoHostSameOriginDirectV1Field = 'hostSameOriginDirectV1';
const String kDuoPartnerSameOriginDirectV1Field = 'partnerSameOriginDirectV1';

const String kDuoResolutionSameOrigin = 'same_origin';
const String kDuoResolutionTranslationRequired = 'translation_required';
const String kDuoResolutionCompatibilityFallback = 'compatibility_fallback';
const String kDuoResolutionLanguageUnavailable = 'language_unavailable';

/// Release gate for advertising support to the other phone.
///
/// Old clients omit the capability fields. A new client must never infer that
/// an omitted field means support, because that could put the two phones on
/// different audio paths.
const bool kDuoSameOriginDirectV1Enabled = true;

const Set<String> kDuoResolvableOriginLanguages = <String>{
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
};

const Map<String, String> _duoOriginLanguageAbbreviations = <String, String>{
  'English': 'En',
  'Korean': 'Ko',
  'Japanese': 'Ja',
  'Chinese': 'Zh',
  'Spanish': 'Es',
  'French': 'Fr',
  'German': 'De',
  'Hindi': 'Hi',
  'Russian': 'Ru',
  'Portuguese': 'Pt',
  'Italian': 'It',
  'Dutch': 'Nl',
};

/// Duo 게시판에서 Origin(Chat Lang)을 짧게 표시하는 영문 2자 약자.
String duoOriginLanguageAbbreviation(Object? language) =>
    _duoOriginLanguageAbbreviations[canonicalDuoOriginLanguage(language)] ??
    '--';

bool duoSameOriginDirectCapability({
  bool enabled = kDuoSameOriginDirectV1Enabled,
}) =>
    enabled;

/// Returns the canonical stored Chat Lang or null.
///
/// This is intentionally exact and fail-closed. Firestore Rules enforce the
/// same fixed values, so accepting aliases or case differences only on the
/// client would make the host transaction fail after it selected Direct.
String? canonicalDuoOriginLanguage(Object? value) {
  final language = value?.toString();
  return kDuoResolvableOriginLanguages.contains(language) ? language : null;
}

class DuoCallResolution {
  const DuoCallResolution({required this.mode, required this.reason});

  final String mode;
  final String reason;

  bool get isDirect => mode == 'direct';
}

class DuoLockedCallResolution {
  const DuoLockedCallResolution({
    required this.mode,
    required this.reason,
    this.interpreterProtocol,
  });

  final String mode;
  final String reason;
  final String? interpreterProtocol;

  bool get isDirect => mode == 'direct';
}

DuoCallResolution chooseDuoCallResolution({
  required Object? hostLanguage,
  required Object? partnerLanguage,
  required bool hostSameOriginDirectV1,
  required bool partnerSameOriginDirectV1,
}) {
  if (!hostSameOriginDirectV1 || !partnerSameOriginDirectV1) {
    return const DuoCallResolution(
      mode: 'interpreter',
      reason: kDuoResolutionCompatibilityFallback,
    );
  }

  final host = canonicalDuoOriginLanguage(hostLanguage);
  final partner = canonicalDuoOriginLanguage(partnerLanguage);
  if (host == null || partner == null) {
    return const DuoCallResolution(
      mode: 'interpreter',
      reason: kDuoResolutionLanguageUnavailable,
    );
  }
  if (host == partner) {
    return const DuoCallResolution(
      mode: 'direct',
      reason: kDuoResolutionSameOrigin,
    );
  }
  return const DuoCallResolution(
    mode: 'interpreter',
    reason: kDuoResolutionTranslationRequired,
  );
}

bool isKnownDuoResolvedMode(Object? value) =>
    value == 'direct' || value == 'interpreter';

bool isKnownDuoResolutionReason(Object? value) =>
    value == kDuoResolutionSameOrigin ||
    value == kDuoResolutionTranslationRequired ||
    value == kDuoResolutionCompatibilityFallback ||
    value == kDuoResolutionLanguageUnavailable;
