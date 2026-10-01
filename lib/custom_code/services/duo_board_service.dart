import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

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

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchPosts() =>
      FirebaseFirestore.instance
          .collection('duo_board_posts')
          .where('active', isEqualTo: true)
          .orderBy('updatedAt', descending: true)
          .limit(50)
          .snapshots();

  static Future<User> ensureParticipantIdentity() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) return current;
    return (await FirebaseAuth.instance.signInAnonymously()).user!;
  }

  static Future<String> publishPost(
      {required String roomId,
      required String historyPath,
      required String topic,
      required String mode,
      required String directLanguage,
      required String availability}) async {
    final result = await _functions.httpsCallable('publishDuoBoardPost').call({
      'roomId': roomId,
      'historyPath': historyPath,
      'topic': topic,
      'mode': mode,
      'directLanguage': directLanguage,
      'availability': availability,
    });
    return Map<String, dynamic>.from(result.data as Map)['postId'].toString();
  }

  static Future<void> withdrawPost(String postId) async {
    await _functions
        .httpsCallable('withdrawDuoBoardPost')
        .call({'postId': postId});
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

  static Future<String> requestPost(String postId) async {
    await ensureParticipantIdentity();
    final result = await _functions
        .httpsCallable('requestDuoBoardPost')
        .call({'postId': postId});
    return Map<String, dynamic>.from(result.data as Map)['requestId']
        .toString();
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
    final ref = FirebaseDatabase.instance
        .ref('duo_board_waiting/$requestId/${user.uid}');
    await ref.onDisconnect().remove();
    await ref.set({
      'online': true,
      'updatedAt': ServerValue.timestamp,
    });
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

  static Future<void> cancelRequest(String requestId) async {
    await _functions
        .httpsCallable('cancelDuoBoardRequest')
        .call({'requestId': requestId});
  }
}
