import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class DuoBoardClaim {
  const DuoBoardClaim({required this.roomId, required this.ownerUid})
      : startGuestHost = false;

  /// 게시판에서 "비회원으로 초대 올리기"를 고른 결과. 들어갈 방은 아직 없다.
  const DuoBoardClaim.startGuestHost()
      : roomId = '',
        ownerUid = '',
        startGuestHost = true;

  final String roomId;
  final String ownerUid;
  final bool startGuestHost;
}

/// 홍보 기간 비회원 초대 설정. 서버의 `app_config/duo_board_promo`와 같은 값.
class DuoBoardPromo {
  const DuoBoardPromo({
    required this.guestPostsEnabled,
    required this.guestCallSeconds,
  });

  static const DuoBoardPromo closed =
      DuoBoardPromo(guestPostsEnabled: false, guestCallSeconds: 180);

  final bool guestPostsEnabled;
  final int guestCallSeconds;

  factory DuoBoardPromo.fromData(Map<String, dynamic>? data) {
    final seconds = (data?['guestCallSeconds'] as num?)?.toInt() ?? 0;
    return DuoBoardPromo(
      guestPostsEnabled: data?['guestPostsEnabled'] == true,
      guestCallSeconds: seconds > 0 ? seconds : 180,
    );
  }
}

/// Intro에서 비회원 초대를 고른 뒤 StealthRoom → Duo 방까지 건네는 일회용 표.
/// 라우트 인자를 늘리지 않으려고 둔다. 읽는 쪽이 [consume]으로 지운다.
class DuoGuestHostLaunch {
  DuoGuestHostLaunch._();
  static bool _pending = false;
  static bool get pending => _pending;
  static void request() => _pending = true;
  static bool consume() {
    final value = _pending;
    _pending = false;
    return value;
  }

  /// 글을 올린 비회원은 Duo 방에 남지 않고 Intro의 게시판으로 돌아간다.
  /// 요청이 오면 그때 방으로 다시 들어온다(`hostRoomId`).
  static bool _boardReturn = false;
  static void requestBoardReturn() => _boardReturn = true;
  static bool consumeBoardReturn() {
    final value = _boardReturn;
    _boardReturn = false;
    return value;
  }
}

class DuoBoardHostMatch {
  const DuoBoardHostMatch({
    required this.roomId,
    required this.requestId,
    required this.historyPath,
  });

  final String roomId;
  final String requestId;
  final String historyPath;
}

/// 보낸 요청 한 건. 초대자 앱이 꺼져 있으면 알림으로 불러서 더 오래 기다린다.
class DuoBoardRequestTicket {
  const DuoBoardRequestTicket({
    required this.requestId,
    required this.viaPush,
    required this.expiresAtMillis,
  });

  final String requestId;
  final bool viaPush;
  final int expiresAtMillis;
}

/// 내 Duo 버디(서버 이름 talk host) 상태. 문서는 서버만 쓴다.
class DuoBuddyStatus {
  const DuoBuddyStatus({
    required this.active,
    required this.adminDisabled,
    required this.dailyHours,
  });

  static const none =
      DuoBuddyStatus(active: false, adminDisabled: false, dailyHours: 0);

  final bool active;
  final bool adminDisabled;
  final int dailyHours;

  factory DuoBuddyStatus.fromData(Map<String, dynamic>? data) => DuoBuddyStatus(
        active: data?['active'] == true && data?['adminDisabled'] != true,
        adminDisabled: data?['adminDisabled'] == true,
        dailyHours: (data?['dailyHours'] as num?)?.toInt() ?? 0,
      );
}

class DuoBoardService {
  DuoBoardService._();

  /// 푸시 받기 시간(시간 단위). 0은 끄기. 서버 PUSH_HOURS와 같다.
  static const List<int> pushHourChoices = [0, 1, 2, 4, 8];
  static const int defaultPushHours = 2;

  /// Duo 버디가 하루 평균 대화할 수 있는 시간. 서버 TALK_HOST_DAILY_HOURS와 같다.
  static const List<int> buddyHourChoices = [2, 3, 4, 6, 8];

  /// 내가 남의 글에 요청을 보내고 기다리는 중인가. 이때 내 글로 들어온 요청은
  /// 창을 띄우지 않고 "다른 대화 중"으로 돌려보낸다. 두 창이 겹치면 기다림 창이
  /// 수락 결과로 위의 창을 닫아 버려 입장이 막혔다(10-30 실기기).
  static bool awaitingOwnRequest = false;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static const String _databaseUrl =
      'https://stealth-vox-3p3rq3-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// The project database lives in asia-southeast1, while the URL inferred by
  /// older Android Firebase configuration points at the US endpoint.
  static FirebaseDatabase get database => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      );

  static Stream<DuoBoardPromo> watchPromo() => FirebaseFirestore.instance
      .collection('app_config')
      .doc('duo_board_promo')
      .snapshots()
      .map((snap) => DuoBoardPromo.fromData(snap.data()))
      .handleError((Object error) {
        debugPrint('[DuoBoard] promo config unavailable: $error');
      });

  /// 한 번 읽기. 로그인 전(Intro 안내 창)에도 읽힌다. 못 읽으면 닫힘으로 본다.
  static Future<DuoBoardPromo> fetchPromo() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('duo_board_promo')
          .get()
          .timeout(const Duration(seconds: 4));
      return DuoBoardPromo.fromData(snap.data());
    } catch (error) {
      debugPrint('[DuoBoard] promo config read failed: $error');
      return DuoBoardPromo.closed;
    }
  }

  /// 통화 상대를 신고한다. 서버가 같은 방 참가자인지 확인한다.
  static Future<void> reportPartner(String roomId) async {
    await _functions
        .httpsCallable('reportDuoPartner')
        .call({'roomId': roomId}).timeout(const Duration(seconds: 10));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchPosts() =>
      FirebaseFirestore.instance
          .collection('duo_board_posts')
          .where('active', isEqualTo: true)
          .snapshots();

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      findOwnActivePosts() async {
    // 홍보 기간에는 비회원(익명)도 자기 초대글을 가진다.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];
    final result = await FirebaseFirestore.instance
        .collection('duo_board_posts')
        .where('ownerUid', isEqualTo: user.uid)
        .where('active', isEqualTo: true)
        .limit(20)
        .get();
    final posts =
        result.docs.where((doc) => doc.data()['active'] == true).toList();
    posts.sort((left, right) {
      final leftUpdatedAt = left.data()['updatedAt'];
      final rightUpdatedAt = right.data()['updatedAt'];
      final leftMillis =
          leftUpdatedAt is Timestamp ? leftUpdatedAt.millisecondsSinceEpoch : 0;
      final rightMillis = rightUpdatedAt is Timestamp
          ? rightUpdatedAt.millisecondsSinceEpoch
          : 0;
      return rightMillis.compareTo(leftMillis);
    });
    return posts;
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
      findOwnActivePost() async {
    final posts = await findOwnActivePosts();
    return posts.isEmpty ? null : posts.first;
  }

  static Future<User> ensureParticipantIdentity() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) return current;
    return (await FirebaseAuth.instance.signInAnonymously()).user!;
  }

  static Future<String> publishPost(
      {required String roomId,
      required String historyPath,
      required String topic,
      required String topicLanguage,
      required String mode,
      required String directLanguage,
      required String availability,
      int pushHours = 0}) async {
    final result = await _functions.httpsCallable('publishDuoBoardPost').call({
      'roomId': roomId,
      'historyPath': historyPath,
      'topic': topic,
      'topicLanguage': topicLanguage,
      'mode': mode,
      'directLanguage': directLanguage,
      'availability': availability,
      'pushHours': pushHours,
    }).timeout(const Duration(seconds: 15));
    return Map<String, dynamic>.from(result.data as Map)['postId'].toString();
  }

  /// 올린 글의 푸시 받기 시간을 바꾼다. 0보다 크면 글도 활성으로 켜진다.
  static Future<void> setPushWindow(String postId, int hours) async {
    await _functions
        .httpsCallable('setDuoBoardPushWindow')
        .call({'postId': postId, 'hours': hours}).timeout(
            const Duration(seconds: 12));
  }

  static Stream<DuoBuddyStatus> watchBuddyStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return Stream<DuoBuddyStatus>.value(DuoBuddyStatus.none);
    }
    return FirebaseFirestore.instance
        .collection('duo_talk_hosts')
        .doc(user.uid)
        .snapshots()
        .map((snap) => DuoBuddyStatus.fromData(snap.data()));
  }

  static Future<DuoBuddyStatus> fetchBuddyStatus() =>
      watchBuddyStatus().first.timeout(const Duration(seconds: 6),
          onTimeout: () => DuoBuddyStatus.none);

  /// Duo 버디 신청·그만두기. 신청은 시간과 서약 동의가 필요하다.
  static Future<void> setBuddy({
    required bool enabled,
    int dailyHours = 0,
    bool pledge = false,
  }) async {
    await _functions.httpsCallable('setDuoTalkHost').call({
      'enabled': enabled,
      'dailyHours': dailyHours,
      'pledge': pledge,
    }).timeout(const Duration(seconds: 12));
  }

  static Future<void> withdrawPost(String postId) async {
    await _functions
        .httpsCallable('withdrawDuoBoardPost')
        .call({'postId': postId});
  }

  static Future<bool> resumePost(String postId) async {
    final result = await _functions
        .httpsCallable('resumeDuoBoardPost')
        .call({'postId': postId})
        // A failed restore must return control to the host-presence recovery
        // path. Without a bound here, a stalled callable leaves the post
        // paused for the rest of the login session.
        .timeout(const Duration(seconds: 12));
    return Map<String, dynamic>.from(result.data as Map)['resumed'] == true;
  }

  static Future<bool> setPostVisibility(
    String postId, {
    required bool enabled,
  }) async {
    final result = await _functions
        .httpsCallable('setDuoBoardPostVisibility')
        .call({'postId': postId, 'enabled': enabled}).timeout(
            const Duration(seconds: 12));
    return Map<String, dynamic>.from(result.data as Map)['discoverable'] ==
        true;
  }

  static Future<bool> isPostDiscoverable(String postId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final post = await FirebaseFirestore.instance
        .collection('duo_board_posts')
        .doc(postId)
        .get(const GetOptions(source: Source.server));
    final data = post.data();
    return post.exists &&
        data?['ownerUid'] == user.uid &&
        data?['active'] == true &&
        data?['state'] != 'reserved' &&
        data?['ownerPaused'] != true &&
        data?['discoverable'] == true;
  }

  static Future<DuoBoardClaim> claimNow(String postId) async {
    await ensureParticipantIdentity();
    final result = await _functions
        .httpsCallable('claimDuoBoardPost')
        .call({'postId': postId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return DuoBoardClaim(
        roomId: data['roomId'].toString(),
        ownerUid: data['ownerUid'].toString());
  }

  static String createRequestAttemptId() => FirebaseFirestore.instance
      .collection('duo_board_request_attempts')
      .doc()
      .id;

  static Future<DuoBoardRequestTicket> requestPost(
      String postId, String attemptId) async {
    await ensureParticipantIdentity();
    final result = await _functions
        .httpsCallable('requestDuoBoardPost')
        .call({'postId': postId, 'attemptId': attemptId}).timeout(
            const Duration(seconds: 15));
    final data = Map<String, dynamic>.from(result.data as Map);
    return DuoBoardRequestTicket(
      requestId: data['requestId'].toString(),
      viaPush: data['viaPush'] == true,
      expiresAtMillis: (data['expiresAtMillis'] as num?)?.toInt() ?? 0,
    );
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchRequest(
          String requestId) =>
      FirebaseFirestore.instance
          .collection('duo_board_requests')
          .doc(requestId)
          .snapshots();

  static Future<DatabaseReference> startWaitingPresence(
      String requestId) async {
    final user = await ensureParticipantIdentity();
    final ref = database.ref('duo_board_waiting/$requestId/${user.uid}');
    await ref.set({
      'online': true,
      'updatedAt': ServerValue.timestamp,
    }).timeout(const Duration(seconds: 8));
    // The Firestore request expires independently after 30 seconds, so a slow
    // onDisconnect registration must not prevent the request from being sent.
    unawaited(
      ref
          .onDisconnect()
          .remove()
          .timeout(const Duration(seconds: 3))
          .catchError((Object error) {
        debugPrint('[DuoBoard] waiting onDisconnect unavailable: $error');
      }),
    );
    return ref;
  }

  static Future<DuoBoardHostMatch> openRequest(String requestId) async {
    final result = await _functions
        .httpsCallable('openDuoBoardRequest')
        .call({'requestId': requestId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return DuoBoardHostMatch(
      roomId: data['roomId'].toString(),
      requestId: requestId,
      historyPath: data['historyPath']?.toString() ?? '',
    );
  }

  static Future<void> cancelRequest(String requestId, String attemptId) async {
    await _functions
        .httpsCallable('cancelDuoBoardRequest')
        .call({'requestId': requestId, 'attemptId': attemptId});
  }

  static Future<void> declineRequest(String requestId,
      {required String reason}) async {
    await _functions.httpsCallable('declineDuoBoardRequest').call({
      'requestId': requestId,
      'reason': reason,
    });
  }
}
