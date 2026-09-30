import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DuoBoardClaim {
  const DuoBoardClaim({required this.roomId, required this.ownerUid});
  final String roomId;
  final String ownerUid;
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
      required String topic,
      required String mode,
      required String directLanguage,
      required String availability}) async {
    final result = await _functions.httpsCallable('publishDuoBoardPost').call({
      'roomId': roomId,
      'topic': topic,
      'mode': mode,
      'directLanguage': directLanguage,
      'availability': availability,
    });
    return Map<String, dynamic>.from(result.data as Map)['postId'].toString();
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
}
