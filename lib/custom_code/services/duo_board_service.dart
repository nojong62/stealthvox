import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class DuoBoardClaim {
  const DuoBoardClaim({required this.roomId, required this.ownerUid});
  final String roomId;
  final String ownerUid;
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

class DuoBoardService {
  DuoBoardService._();
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static const String _databaseUrl =
      'https://stealth-vox-3p3rq3-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// The project database lives in asia-southeast1, while the URL inferred by
  /// older Android Firebase configuration points at the US endpoint.
  static FirebaseDatabase get database => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      );

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchPosts() =>
      FirebaseFirestore.instance
          .collection('duo_board_posts')
          .where('active', isEqualTo: true)
          .orderBy('updatedAt', descending: true)
          .limit(50)
          .snapshots();

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
      findOwnActivePost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    final result = await FirebaseFirestore.instance
        .collection('duo_board_posts')
        .where('ownerUid', isEqualTo: user.uid)
        .limit(10)
        .get();
    for (final doc in result.docs) {
      if (doc.data()['active'] == true) return doc;
    }
    return null;
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
      required String availability}) async {
    final result = await _functions.httpsCallable('publishDuoBoardPost').call({
      'roomId': roomId,
      'historyPath': historyPath,
      'topic': topic,
      'topicLanguage': topicLanguage,
      'mode': mode,
      'directLanguage': directLanguage,
      'availability': availability,
    }).timeout(const Duration(seconds: 15));
    return Map<String, dynamic>.from(result.data as Map)['postId'].toString();
  }

  static Future<void> withdrawPost(String postId) async {
    await _functions
        .httpsCallable('withdrawDuoBoardPost')
        .call({'postId': postId});
  }

  static Future<bool> resumePost(String postId) async {
    final result = await _functions
        .httpsCallable('resumeDuoBoardPost')
        .call({'postId': postId});
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

  static Future<String> requestPost(String postId, String attemptId) async {
    await ensureParticipantIdentity();
    final result = await _functions
        .httpsCallable('requestDuoBoardPost')
        .call({'postId': postId, 'attemptId': attemptId}).timeout(
            const Duration(seconds: 15));
    return Map<String, dynamic>.from(result.data as Map)['requestId']
        .toString();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchRequest(
          String requestId) =>
      FirebaseFirestore.instance
          .collection('duo_board_requests')
          .doc(requestId)
          .snapshots();

  static Future<DatabaseReference> startWaitingPresence(String requestId) async {
    final user = await ensureParticipantIdentity();
    final ref = database.ref('duo_board_waiting/$requestId/${user.uid}');
    await ref.set({
      'online': true,
      'updatedAt': ServerValue.timestamp,
    }).timeout(const Duration(seconds: 8));
    // The Firestore request expires independently after 30 seconds, so a slow
    // onDisconnect registration must not prevent the request from being sent.
    try {
      await ref.onDisconnect().remove().timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('[DuoBoard] waiting onDisconnect unavailable: $error');
    }
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
