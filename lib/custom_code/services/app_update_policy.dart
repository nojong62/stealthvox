const String kDefaultAndroidUpdateMessage = '새 버전이 있습니다. 업데이트해 주세요.';
const String kStealthVoxPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.aienglishpractice.stealthvox';

enum AppUpdateRequirement { none, recommended, required }

class AppUpdateDecision {
  const AppUpdateDecision({
    required this.requirement,
    this.message = kDefaultAndroidUpdateMessage,
    this.storeUrl = kStealthVoxPlayStoreUrl,
  });

  const AppUpdateDecision.none()
      : requirement = AppUpdateRequirement.none,
        message = kDefaultAndroidUpdateMessage,
        storeUrl = kStealthVoxPlayStoreUrl;

  final AppUpdateRequirement requirement;
  final String message;
  final String storeUrl;
}

/// Firebase와 UI에 의존하지 않는 Android 업데이트 정책 판정 함수.
///
/// 입력값 하나라도 신뢰할 수 없으면 앱을 막지 않고 [AppUpdateRequirement.none]
/// 으로 처리한다.
AppUpdateDecision evaluateAndroidAppUpdate({
  required bool isAndroid,
  required bool remoteConfigFetchSucceeded,
  required int? currentVersionCode,
  required Object? minVersion,
  required Object? latestVersion,
  Object? updateMessage,
  Object? storeUrl,
}) {
  if (!isAndroid ||
      !remoteConfigFetchSucceeded ||
      currentVersionCode == null ||
      currentVersionCode <= 0) {
    return const AppUpdateDecision.none();
  }

  final min = _parseNonNegativeInt(minVersion);
  final latest = _parseNonNegativeInt(latestVersion);
  if (min == null || latest == null || min > latest) {
    return const AppUpdateDecision.none();
  }

  final message = _validMessageOrDefault(updateMessage);
  final resolvedStoreUrl = validPlayStoreUrlOrDefault(storeUrl);
  if (currentVersionCode < min) {
    return AppUpdateDecision(
      requirement: AppUpdateRequirement.required,
      message: message,
      storeUrl: resolvedStoreUrl,
    );
  }
  if (currentVersionCode < latest) {
    return AppUpdateDecision(
      requirement: AppUpdateRequirement.recommended,
      message: message,
      storeUrl: resolvedStoreUrl,
    );
  }
  return const AppUpdateDecision.none();
}

int? _parseNonNegativeInt(Object? value) {
  final int? parsed;
  if (value is int) {
    parsed = value;
  } else if (value is String && value.trim().isNotEmpty) {
    parsed = int.tryParse(value.trim());
  } else {
    parsed = null;
  }
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

String _validMessageOrDefault(Object? value) {
  if (value is! String) return kDefaultAndroidUpdateMessage;
  final message = value.trim();
  return message.isEmpty ? kDefaultAndroidUpdateMessage : message;
}

String validPlayStoreUrlOrDefault(Object? value) {
  if (value is! String) return kStealthVoxPlayStoreUrl;
  final candidate = value.trim();
  final uri = Uri.tryParse(candidate);
  final isValid = uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'play.google.com' &&
      uri.path == '/store/apps/details' &&
      uri.queryParameters['id'] == 'com.aienglishpractice.stealthvox';
  return isValid ? candidate : kStealthVoxPlayStoreUrl;
}
