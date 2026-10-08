import 'package:shared_preferences/shared_preferences.dart';

/// Device-local duplicate guard for generated Circle and Scenario suggestions.
class RecentRecommendationHistory {
  RecentRecommendationHistory._();

  static const int _maxEntries = 200;

  /// Records [result] when it is new and returns whether it may be shown.
  static Future<bool> rememberIfNew(String mode, String result) async {
    final normalized = _normalize(result);
    if (normalized.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    final entries =
        List<String>.from(prefs.getStringList(_key(mode)) ?? const []);
    if (entries.contains(normalized)) return false;
    entries.add(normalized);
    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }
    await prefs.setStringList(_key(mode), entries);
    return true;
  }

  static String scenarioResult({
    required String situation,
    required String aiRole,
    required String userRole,
  }) =>
      '$situation\u001f$aiRole\u001f$userRole';

  static String _key(String mode) => 'recent_recommendations_v1_$mode';

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
