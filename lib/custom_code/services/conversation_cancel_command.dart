import 'package:cloud_firestore/cloud_firestore.dart';

/// 음성 전사의 공백·문장부호 차이를 무시하되, 다른 문장에 포함된 표현은
/// 취소 명령으로 보지 않는다.
bool isConversationCancelCommand(String transcript) {
  final normalized = transcript
      .trim()
      .replaceAll(RegExp(r'''[\s.!?~…。！？,，'"“”‘’·:;()\[\]{}]'''), '');
  return normalized == '취소합니다';
}

/// 화면 대화에서 가장 최근 HOST부터 뒤쪽의 임시/AI 메시지를 함께 걷어낸다.
/// 반환값은 실제로 이전 사용자 턴을 찾았는지 여부다.
bool removeFromLastUserTurn(List<Map<String, dynamic>> messages) {
  final hostIndex =
      messages.lastIndexWhere((message) => message['role'] == 'HOST');
  if (hostIndex < 0) {
    messages.removeWhere((message) => message['role'] == 'HOST_TEMP');
    return false;
  }
  messages.removeRange(hostIndex, messages.length);
  return true;
}

/// sessions/transcript와 chat_history/messages에서 가장 최근 HOST부터
/// 그 뒤의 SYSTEM까지 같은 범위로 삭제한다.
Future<int> rollbackLastPersistedUserTurn({
  required FirebaseFirestore firestore,
  required String uid,
  String? sessionDocId,
  DocumentReference? historyRef,
}) async {
  var removedMessages = 0;

  if (sessionDocId != null) {
    final sessionRef = firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionDocId);
    final snapshot = await sessionRef.get();
    final transcript = List<Map<String, dynamic>>.from(
      (snapshot.data()?['transcript'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)),
    );
    final hostIndex =
        transcript.lastIndexWhere((message) => message['role'] == 'HOST');
    if (hostIndex >= 0) {
      transcript.removeRange(hostIndex, transcript.length);
      await sessionRef.update(<String, dynamic>{'transcript': transcript});
    }
  }

  if (historyRef != null) {
    final snapshot =
        await historyRef.collection('messages').orderBy('created_at').get();
    final docs = snapshot.docs;
    final hostIndex = docs.lastIndexWhere((doc) {
      final data = doc.data();
      return data['role'] == 'HOST';
    });
    if (hostIndex >= 0) {
      removedMessages = docs.length - hostIndex;
      final batch = firestore.batch();
      for (var index = hostIndex; index < docs.length; index++) {
        batch.delete(docs[index].reference);
      }
      final remainingLastMessage = hostIndex > 0
          ? ((docs[hostIndex - 1].data()['original_text'] ?? ''))
              .toString()
              .trim()
          : '';
      batch.update(historyRef, <String, dynamic>{
        'msg_count': FieldValue.increment(-removedMessages),
        'last_message': remainingLastMessage.isEmpty
            ? FieldValue.delete()
            : remainingLastMessage,
        'last_active': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    }
  }

  return removedMessages;
}
