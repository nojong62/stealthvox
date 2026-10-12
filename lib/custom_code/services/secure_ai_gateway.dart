import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';

/// Server-owned AI credentials.
///
/// The device receives only short-lived, App-Check-attested session tokens.
/// Provider API keys never enter Remote Config, app state, or the APK.
class SecureAiGateway {
  SecureAiGateway._();

  static const String region = 'asia-northeast3';
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: region);

  static String? _gatewayToken;
  static String _gatewayScope = '';
  static DateTime _gatewayExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  static String? _deepgramToken;
  static String _deepgramScope = '';
  static DateTime _deepgramExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  static String openAiUrl(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final projectId = Firebase.app().options.projectId;
    return 'https://$region-$projectId.cloudfunctions.net/openAiProxy$normalized';
  }

  static Uri openAiUri(String path) => Uri.parse(openAiUrl(path));

  static Map<String, dynamic> _accessData(String? duoRoomId) {
    final roomId = duoRoomId?.trim() ?? '';
    return roomId.isEmpty ? <String, dynamic>{} : {'roomId': roomId};
  }

  static String _cacheScope(String? duoRoomId) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return '$uid|${duoRoomId?.trim() ?? ''}';
  }

  static Future<void> claimTrialAccess() async {
    final installationId = await FirebaseInstallations.instance.getId();
    final result = await _functions
        .httpsCallable('claimAiTrial')
        .call(<String, dynamic>{'installationId': installationId});
    final data = Map<String, dynamic>.from(result.data as Map);
    if (data['granted'] != true) {
      throw StateError('AI trial access was not granted.');
    }
    clearCachedTokens();
  }

  static Future<String> gatewayToken({
    bool forceRefresh = false,
    String? duoRoomId,
  }) async {
    final now = DateTime.now();
    final scope = _cacheScope(duoRoomId);
    if (!forceRefresh &&
        _gatewayToken != null &&
        _gatewayScope == scope &&
        now.isBefore(_gatewayExpiresAt.subtract(const Duration(minutes: 5)))) {
      return _gatewayToken!;
    }
    final result = await _functions
        .httpsCallable('mintAiGatewaySession')
        .call(_accessData(duoRoomId));
    final data = Map<String, dynamic>.from(result.data as Map);
    final token = data['token']?.toString() ?? '';
    final expiresAt = (data['expiresAt'] as num?)?.toInt() ?? 0;
    if (token.isEmpty || expiresAt <= 0) {
      throw StateError('AI gateway returned an invalid session token.');
    }
    _gatewayToken = token;
    _gatewayScope = scope;
    _gatewayExpiresAt =
        DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true);
    return token;
  }

  static Future<String> deepgramToken({
    bool forceRefresh = false,
    String? duoRoomId,
  }) async {
    final now = DateTime.now();
    final scope = _cacheScope(duoRoomId);
    if (!forceRefresh &&
        _deepgramToken != null &&
        _deepgramScope == scope &&
        now.isBefore(_deepgramExpiresAt.subtract(const Duration(minutes: 2)))) {
      return _deepgramToken!;
    }
    final result = await _functions
        .httpsCallable('mintDeepgramToken')
        .call(_accessData(duoRoomId));
    final data = Map<String, dynamic>.from(result.data as Map);
    final token = data['token']?.toString() ?? '';
    final expiresIn = (data['expiresIn'] as num?)?.toInt() ?? 0;
    if (token.isEmpty || expiresIn <= 0) {
      throw StateError('Deepgram token broker returned an invalid token.');
    }
    _deepgramToken = token;
    _deepgramScope = scope;
    _deepgramExpiresAt = now.add(Duration(seconds: expiresIn));
    return token;
  }

  static Future<String> openAiRealtimeToken({String? duoRoomId}) async {
    final result = await _functions
        .httpsCallable('mintOpenAiRealtimeToken')
        .call(_accessData(duoRoomId));
    final data = Map<String, dynamic>.from(result.data as Map);
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw StateError('OpenAI realtime broker returned an invalid token.');
    }
    return token;
  }

  static void clearCachedTokens() {
    _gatewayToken = null;
    _gatewayScope = '';
    _gatewayExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);
    _deepgramToken = null;
    _deepgramScope = '';
    _deepgramExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
