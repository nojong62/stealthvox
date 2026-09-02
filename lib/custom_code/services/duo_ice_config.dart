// ====================================================================
// 🧊 [DUO-ICE] 직접 대화 WebRTC의 ICE 서버 설정
// --------------------------------------------------------------------
// 여기가 정하는 것은 **"어느 길로 붙을 것인가"** 하나뿐이다.
//
//   STUN  — 서로의 공인 주소를 알아내 P2P로 직접 붙는다. 무료·무제한.
//   TURN  — P2P가 끝내 안 될 때만 쓰는 WebRTC 자체의 중계. 유료(대역폭).
//
// ⚠️ **TURN은 옛 Cloud Run `duo-relay`와 다른 물건이다.** TURN으로 넘어가도
//   연결은 여전히 WebRTC이고, 우리 앱 코드는 PCM을 한 조각도 만지지 않는다.
//   릴레이로 되돌아가는 것이 아니다.
//
// 🔒 **TURN 비밀키는 이 파일에 없다. 앱 어디에도 없다.**
//   TURN 자격증명은 대역폭 과금이 붙으므로 APK에서 뽑히면 곧바로 요금 사고가
//   된다. 그래서 Cloud Function이 짧은 만료로 발급한 것만 받아 쓴다.
//   (같은 패턴의 선례: `createRealtimeClientSecret`)
// ====================================================================

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

/// TURN 자격증명을 발급하는 Cloud Function 이름.
///
/// ⚠️ **아직 서버에 배포돼 있지 않을 수 있다.** 없으면 이 파일은 STUN만으로
/// 설정을 만들고 그 사실을 로그로 남긴다 — 임의의 TURN 주소나 비밀번호를
/// 지어내지 않는다.
const String kDuoTurnCredentialFunction = 'createTurnCredential';

/// Cloud Function 리전. 기존 `createRealtimeClientSecret`과 같은 자리에 둔다.
const String kDuoTurnCredentialRegion = 'us-central1';

/// 자격증명 발급 상한. 통화 시작을 여기서 오래 붙잡으면 안 된다 —
/// 실패하면 STUN만으로라도 붙여 본다.
const Duration kDuoTurnFetchTimeout = Duration(seconds: 6);

/// 공개 STUN 서버. 주소를 알아내는 데만 쓰고 미디어는 지나가지 않으므로
/// 앱에 박혀 있어도 문제가 없다(비밀도 과금도 없다).
const List<String> kDuoDefaultStunUrls = <String>[
  'stun:stun.l.google.com:19302',
  'stun:stun1.l.google.com:19302',
];

/// 한 통화가 쓸 ICE 설정 한 벌.
class DuoIceConfig {
  const DuoIceConfig({
    required this.iceServers,
    required this.hasTurn,
    this.turnSource = 'none',
  });

  /// `createPeerConnection`에 그대로 넘어가는 모양.
  final List<Map<String, dynamic>> iceServers;

  /// TURN이 실제로 들어 있는가. false면 **대칭 NAT 환경에서 통화가 무음으로
  /// 실패한다** — 호출부가 이 사실을 로그로 남길 수 있게 노출한다.
  final bool hasTurn;

  /// TURN이 어디서 왔는지(진단용). 'function' | 'none'
  final String turnSource;

  /// P2P만 가능한 설정. TURN 발급이 실패했거나 아직 서버가 없을 때 쓴다.
  factory DuoIceConfig.stunOnly() => const DuoIceConfig(
        iceServers: <Map<String, dynamic>>[
          <String, dynamic>{'urls': kDuoDefaultStunUrls},
        ],
        hasTurn: false,
      );

  Map<String, dynamic> toPeerConnectionConfig() => <String, dynamic>{
        'iceServers': iceServers,
        // 통화는 오디오 한 줄기뿐이다. Unified Plan이 지금의 표준이고,
        // flutter_webrtc 1.5의 기본값이기도 하다.
        'sdpSemantics': 'unified-plan',
        // 후보를 계속 모은다. 통화 중 Wi-Fi ↔ LTE가 바뀌어도 새 후보를
        // 찾아 붙을 수 있어야 한다.
        'continualGatheringPolicy': 'gather_continually',
      };

  String describe() => 'turn=$hasTurn source=$turnSource '
      'servers=${iceServers.length}';
}

/// ICE 설정을 만든다. **TURN을 못 받아도 통화를 막지 않는다** —
/// 대부분의 망에서는 STUN만으로 붙고, 못 붙는 경우는 호출부가 로그로 안다.
///
/// [onLog]는 위젯의 `_lgDuo`를 그대로 받는다.
Future<DuoIceConfig> loadDuoIceConfig({
  void Function(String tag, String msg)? onLog,
}) async {
  void lg(String tag, String msg) => onLog?.call(tag, msg);

  try {
    final callable = FirebaseFunctions.instanceFor(
      region: kDuoTurnCredentialRegion,
    ).httpsCallable(
      kDuoTurnCredentialFunction,
      options: HttpsCallableOptions(timeout: kDuoTurnFetchTimeout),
    );
    final result = await callable.call<Map<String, dynamic>>();
    final parsed = _parseTurnResponse(result.data);
    if (parsed == null) {
      lg('⚠️ [DUO-ICE]', 'turn_response_unusable — STUN만으로 붙는다');
      return DuoIceConfig.stunOnly();
    }
    lg('🧊 [DUO-ICE]', 'turn_ready ${parsed.describe()}');
    return parsed;
  } on FirebaseFunctionsException catch (e) {
    // 함수가 아직 배포 전이면 'not-found'가 온다. 이건 사고가 아니라
    // "아직 없음"이므로 통화를 막지 않는다.
    lg('⚠️ [DUO-ICE]',
        'turn_unavailable code=${e.code} — STUN만으로 붙는다 '
        '(대칭 NAT에서는 무음 실패할 수 있다)');
    return DuoIceConfig.stunOnly();
  } catch (e) {
    lg('⚠️ [DUO-ICE]',
        'turn_fetch_failed(${e.runtimeType}) — STUN만으로 붙는다');
    return DuoIceConfig.stunOnly();
  }
}

/// Cloud Function 응답을 ICE 설정으로 옮긴다.
///
/// 기대하는 모양:
/// ```json
/// { "iceServers": [
///     {"urls": ["stun:..."]},
///     {"urls": ["turn:...:3478?transport=udp"],
///      "username": "<expiry>:<uid>", "credential": "<hmac>"}
///   ] }
/// ```
/// 모양이 어긋나면 null을 돌려준다 — **넘겨짚어 채우지 않는다.**
DuoIceConfig? _parseTurnResponse(Object? raw) {
  if (raw is! Map) return null;
  final servers = raw['iceServers'];
  if (servers is! List || servers.isEmpty) return null;

  final parsed = <Map<String, dynamic>>[];
  bool sawTurn = false;
  for (final entry in servers) {
    if (entry is! Map) continue;
    final urls = entry['urls'] ?? entry['url'];
    final List<String> urlList;
    if (urls is String) {
      urlList = <String>[urls];
    } else if (urls is List) {
      urlList = urls.whereType<String>().toList();
    } else {
      continue;
    }
    if (urlList.isEmpty) continue;
    if (urlList.any((u) => u.startsWith('turn:') || u.startsWith('turns:'))) {
      sawTurn = true;
    }
    parsed.add(<String, dynamic>{
      'urls': urlList,
      if (entry['username'] is String) 'username': entry['username'],
      if (entry['credential'] is String) 'credential': entry['credential'],
    });
  }
  if (parsed.isEmpty) return null;

  // 서버가 STUN을 안 실어 보냈으면 우리 기본값을 얹는다. STUN은 비밀이
  // 아니므로 앱이 갖고 있어도 된다.
  if (!parsed.any((s) => (s['urls'] as List)
      .any((u) => u is String && u.startsWith('stun:')))) {
    parsed.insert(0, <String, dynamic>{'urls': kDuoDefaultStunUrls});
  }

  return DuoIceConfig(
    iceServers: parsed,
    hasTurn: sawTurn,
    turnSource: sawTurn ? 'function' : 'none',
  );
}
