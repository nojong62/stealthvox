// ====================================================================
// 📮 [DUO-SIGNAL] 직접 대화 WebRTC의 신호 교환 — Firestore만 쓴다
// --------------------------------------------------------------------
// WebRTC는 붙기 전에 서로 SDP와 ICE 후보를 주고받아야 한다. 그 통로를
// **새로 만들지 않는다.** 두 사람은 이미 `duo_sessions/{roomId}` 문서를
// 양쪽에서 구독하고 있고, 규칙에 참가자 판정(`hostUid`/`partnerUid`)이
// 이미 서 있다. 그 위에 하위 컬렉션 하나만 얹는다.
//
//   duo_sessions/{roomId}/webrtc/current
//       { sessionId, offer{sdp,type}, answer{sdp,type}, offerUid, answerUid }
//   duo_sessions/{roomId}/webrtc/current/candidates/{autoId}
//       { sessionId, role, candidate, sdpMid, sdpMLineIndex }
//
// 🚫 **상시 WebSocket signaling 서버를 두지 않는다.** 릴레이를 걷어내는 것이
//   목적인데 신호 때문에 Cloud Run 인스턴스를 살려 두면 아무것도 못 지운다.
//
// ============================================================================
// 🆔 세션 id의 **주인은 호스트(offerer) 하나다**
// ----------------------------------------------------------------------------
// 예전에는 두 폰이 각자 `_directGeneration`으로 id를 만들었다. 그 값은 폰마다
// 따로 도는 숫자라 통화를 한 번 끊었다 걸면 곧바로 어긋난다 — 게스트가
// 호스트의 offer를 "남의 세대"로 보고 조용히 버리고, 아무 일도 일어나지 않는다.
//
// 그래서 지금은:
//   호스트  자기 id를 문서에 쓴다              (진실값의 주인)
//   게스트  문서에 적힌 id를 **그대로 채택**한다 (answer·후보에도 같은 값)
//
// stale 차단은 그대로다. 호스트가 통화를 열 때 문서를 새 id로 덮으므로
// (`reset`), 이전 통화의 offer/answer는 그 순간 사라진다.
// ============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// 신호가 사는 자리. canonical·replay와 같은 층에 나란히 둔다 —
/// 새 최상위 컬렉션을 만들지 않는다.
const String kDuoWebrtcCollection = 'webrtc';
const String kDuoWebrtcDoc = 'current';
const String kDuoWebrtcCandidateCollection = 'candidates';

/// 이 신호가 어느 통화의 것인가. **호스트가 정하고 게스트가 따른다.**
const String kDuoWebrtcSessionField = 'sessionId';

DocumentReference<Map<String, dynamic>> duoWebrtcRef(String roomId) =>
    FirebaseFirestore.instance
        .collection('duo_sessions')
        .doc(roomId)
        .collection(kDuoWebrtcCollection)
        .doc(kDuoWebrtcDoc);

CollectionReference<Map<String, dynamic>> duoWebrtcCandidatesRef(
        String roomId) =>
    duoWebrtcRef(roomId).collection(kDuoWebrtcCandidateCollection);

/// 원격 서술 하나를 가리키는 열쇠. **이 값이 같으면 같은 신호다.**
///
/// 세션·종류·SDP를 **함께** 본다. 셋 중 하나라도 달라지면 새 신호이므로
/// ICE restart나 정상 재협상은 막히지 않는다.
String duoRemoteSdpKey({
  required String sessionId,
  required String type,
  required String sdp,
}) =>
    '$sessionId|$type|$sdp';

/// 신호 한 벌 = 통화 한 번. 방을 나가면 버리고 새로 만든다.
class DuoWebrtcSignaling {
  DuoWebrtcSignaling({
    required this.roomId,
    required this.isOfferer,
    String? offerSessionId,
    this.onLog,
  }) : _sessionId = isOfferer ? offerSessionId : null {
    assert(!isOfferer || (offerSessionId != null && offerSessionId.isNotEmpty),
        '호스트는 세션 id를 갖고 시작해야 한다');
  }

  final String roomId;

  /// 호스트가 offerer다. 역할이 이미 방 문서로 정해져 있으므로
  /// 누가 먼저 offer를 만들지 다툴 일이 없다.
  final bool isOfferer;

  final void Function(String tag, String msg)? onLog;

  /// 호스트는 생성 시점에 갖고, 게스트는 문서에서 **채택**한다.
  /// 채택 전에는 null이고, 그동안 게스트는 후보를 보내지 않는다
  /// (어느 통화의 것인지 적을 수 없기 때문이다).
  String? _sessionId;
  String? get sessionId => _sessionId;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candSub;

  final Set<String> _seenCandidateIds = <String>{};

  /// 아직 세션 id를 몰라 못 보낸 내 후보. 채택되는 순간 한꺼번에 나간다.
  final List<Map<String, dynamic>> _pendingOutboundCandidates =
      <Map<String, dynamic>>[];

  bool _disposed = false;

  void _lg(String tag, String msg) => onLog?.call(tag, msg);

  /// 이번 통화의 신호 자리를 비운다. **호스트만 부른다.**
  ///
  /// 이전 통화의 offer/answer가 남아 있으면 새 통화가 그것을 읽고 엉뚱한
  /// 세대에 붙는다. `set`(merge 아님)으로 문서를 통째로 갈아 끼운다.
  ///
  /// 후보는 지우지 않고 남겨 둔다 — 세션 id로 이미 걸러지고, 통화 시작을
  /// 삭제 왕복으로 늦추지 않기 위해서다.
  Future<void> reset() async {
    if (_disposed || !isOfferer) return;
    try {
      await duoWebrtcRef(roomId).set(<String, dynamic>{
        kDuoWebrtcSessionField: _sessionId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _lg('⚠️ [DUO-SIGNAL]', 'reset_failed(${e.runtimeType})');
    }
  }

  Future<void> sendOffer(String sdp, String type, String uid) =>
      _writeDescription('offer', sdp, type, uid);

  Future<void> sendAnswer(String sdp, String type, String uid) =>
      _writeDescription('answer', sdp, type, uid);

  Future<void> _writeDescription(
      String field, String sdp, String type, String uid) async {
    if (_disposed) return;
    final session = _sessionId;
    if (session == null) {
      _lg('⚠️ [DUO-SIGNAL]', 'send_${field}_skipped reason=no_session_yet');
      return;
    }
    try {
      await duoWebrtcRef(roomId).set(<String, dynamic>{
        kDuoWebrtcSessionField: session,
        field: <String, dynamic>{'sdp': sdp, 'type': type},
        '${field}Uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _lg('📮 [DUO-SIGNAL]', 'sent=$field len=${sdp.length}');
    } catch (e) {
      _lg('❌ [DUO-SIGNAL]', 'send_${field}_failed(${e.runtimeType})');
    }
  }

  /// 내 ICE 후보 하나. 후보는 수십 개가 빠르게 나오므로 문서를 나눠 쓴다
  /// (배열에 누적하면 매번 문서 전체를 다시 쓰게 되고 경합이 난다).
  ///
  /// 세션 id를 아직 채택하지 못했으면 **버리지 않고 담아 둔다** — 게스트는
  /// offer가 오기 전에도 후보를 만들 수 있는데, 그걸 버리면 연결이 느려진다.
  Future<void> sendCandidate({
    required String role,
    required String? candidate,
    required String? sdpMid,
    required int? sdpMLineIndex,
  }) async {
    if (_disposed || candidate == null || candidate.isEmpty) return;
    final payload = <String, dynamic>{
      'role': role,
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
    };
    if (_sessionId == null) {
      _pendingOutboundCandidates.add(payload);
      return;
    }
    await _writeCandidate(payload);
  }

  Future<void> _writeCandidate(Map<String, dynamic> payload) async {
    final session = _sessionId;
    if (_disposed || session == null) return;
    try {
      await duoWebrtcCandidatesRef(roomId).add(<String, dynamic>{
        ...payload,
        kDuoWebrtcSessionField: session,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _lg('⚠️ [DUO-SIGNAL]', 'send_candidate_failed(${e.runtimeType})');
    }
  }

  /// 세션 id를 채택한다(게스트 전용). 채택되는 순간 담아 둔 후보가 나간다.
  void _adoptSession(String session) {
    if (_sessionId == session) return;
    _sessionId = session;
    _lg('🆔 [DUO-SIGNAL]', 'adopted_session=$session');
    // 세션이 바뀌면 이전 세션의 후보 장부는 의미가 없다.
    _seenCandidateIds.clear();
    final pending = List<Map<String, dynamic>>.of(_pendingOutboundCandidates);
    _pendingOutboundCandidates.clear();
    for (final payload in pending) {
      unawaited(_writeCandidate(payload));
    }
  }

  /// 상대의 SDP를 기다린다. offerer면 answer를, answerer면 offer를 받는다.
  ///
  /// **게스트는 문서의 세션 id를 채택한다.** 호스트는 자기 id와 다른 신호를
  /// 버린다(늦게 도착한 옛 세션의 answer가 새 통화에 섞이지 않게).
  ///
  /// ⚠️ 이 리스너는 **같은 신호를 여러 번 준다.** 내가 answer를 같은 문서에
  ///   쓰면 스냅샷이 다시 떨어지고 거기에 offer가 그대로 들어 있기 때문이다.
  ///   그래서 중복 판단은 호출부가 [duoRemoteSdpKey]로 한다 — 여기서 걸러
  ///   버리면 ICE restart로 정말 바뀐 SDP까지 막힌다.
  void listenForDescription(
      void Function(String sdp, String type, String sessionId)
          onRemoteDescription) {
    _docSub?.cancel();
    _docSub = duoWebrtcRef(roomId).snapshots().listen((snap) {
      if (_disposed || !snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      final docSession = data[kDuoWebrtcSessionField]?.toString();
      if (docSession == null || docSession.isEmpty) return;

      if (isOfferer) {
        // 호스트는 자기 id가 진실값이다. 다른 id는 남의 세대다.
        if (docSession != _sessionId) return;
      } else {
        // 게스트는 문서를 따른다. 호스트가 통화를 다시 열면 id가 바뀌고,
        // 그때 이 자리에서 새 세션을 채택한다.
        _adoptSession(docSession);
      }

      final wanted = isOfferer ? 'answer' : 'offer';
      final desc = data[wanted];
      if (desc is! Map) return;
      final sdp = desc['sdp']?.toString();
      final type = desc['type']?.toString();
      if (sdp == null || sdp.isEmpty || type == null || type.isEmpty) return;
      onRemoteDescription(sdp, type, docSession);
    }, onError: (Object e) {
      _lg('⚠️ [DUO-SIGNAL]', 'doc_listen_error(${e.runtimeType})');
    });
  }

  /// 상대의 ICE 후보를 받는다. **내가 올린 것은 건너뛴다** —
  /// 같은 컬렉션을 둘이 함께 쓰므로 role로 가른다.
  ///
  /// 세션 id를 채택한 뒤에 불러야 한다(질의 조건에 그 값이 들어간다).
  void listenForCandidates({
    required String myRole,
    required void Function(String candidate, String? sdpMid, int? sdpMLineIndex)
        onRemoteCandidate,
  }) {
    final session = _sessionId;
    if (_disposed || session == null) return;
    _candSub?.cancel();
    _candSub = duoWebrtcCandidatesRef(roomId)
        .where(kDuoWebrtcSessionField, isEqualTo: session)
        .snapshots()
        .listen((snap) {
      if (_disposed) return;
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final doc = change.doc;
        if (!_seenCandidateIds.add(doc.id)) continue;
        final data = doc.data();
        if (data == null) continue;
        if (data['role']?.toString() == myRole) continue; // 내 것
        final candidate = data['candidate']?.toString();
        if (candidate == null || candidate.isEmpty) continue;
        onRemoteCandidate(
          candidate,
          data['sdpMid']?.toString(),
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
      }
    }, onError: (Object e) {
      _lg('⚠️ [DUO-SIGNAL]', 'candidate_listen_error(${e.runtimeType})');
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final docSub = _docSub;
    _docSub = null;
    await docSub?.cancel();
    final candSub = _candSub;
    _candSub = null;
    await candSub?.cancel();
    _seenCandidateIds.clear();
    _pendingOutboundCandidates.clear();
  }
}
