import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class ChatHistoryRecord extends FirestoreRecord {
  ChatHistoryRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "custom_title" field.
  String? _customTitle;
  String get customTitle => _customTitle ?? '';
  bool hasCustomTitle() => _customTitle != null;

  // "is_pinned" field.
  bool? _isPinned;
  bool get isPinned => _isPinned ?? false;
  bool hasIsPinned() => _isPinned != null;

  // "created_at" field.
  DateTime? _createdAt;
  DateTime? get createdAt => _createdAt;
  bool hasCreatedAt() => _createdAt != null;

  // "expanded_sentence" field.
  String? _expandedSentence;
  String get expandedSentence => _expandedSentence ?? '';
  bool hasExpandedSentence() => _expandedSentence != null;

  // "polished_sentence" field.
  String? _polishedSentence;
  String get polishedSentence => _polishedSentence ?? '';
  bool hasPolishedSentence() => _polishedSentence != null;

  // "has_practice" field.
  bool? _hasPractice;
  bool get hasPractice => _hasPractice ?? false;
  bool hasHasPractice() => _hasPractice != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _customTitle = snapshotData['custom_title'] as String?;
    _isPinned = snapshotData['is_pinned'] as bool?;
    _createdAt = snapshotData['created_at'] as DateTime?;
    _expandedSentence = snapshotData['expanded_sentence'] as String?;
    _polishedSentence = snapshotData['polished_sentence'] as String?;
    _hasPractice = snapshotData['has_practice'] as bool?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('chat_history')
          : FirebaseFirestore.instance.collectionGroup('chat_history');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('chat_history').doc(id);

  static Stream<ChatHistoryRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => ChatHistoryRecord.fromSnapshot(s));

  static Future<ChatHistoryRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => ChatHistoryRecord.fromSnapshot(s));

  static ChatHistoryRecord fromSnapshot(DocumentSnapshot snapshot) =>
      ChatHistoryRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static ChatHistoryRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      ChatHistoryRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'ChatHistoryRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is ChatHistoryRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createChatHistoryRecordData({
  String? customTitle,
  bool? isPinned,
  DateTime? createdAt,
  String? expandedSentence,
  String? polishedSentence,
  bool? hasPractice,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'custom_title': customTitle,
      'is_pinned': isPinned,
      'created_at': createdAt,
      'expanded_sentence': expandedSentence,
      'polished_sentence': polishedSentence,
      'has_practice': hasPractice,
    }.withoutNulls,
  );

  return firestoreData;
}

class ChatHistoryRecordDocumentEquality implements Equality<ChatHistoryRecord> {
  const ChatHistoryRecordDocumentEquality();

  @override
  bool equals(ChatHistoryRecord? e1, ChatHistoryRecord? e2) {
    return e1?.customTitle == e2?.customTitle &&
        e1?.isPinned == e2?.isPinned &&
        e1?.createdAt == e2?.createdAt &&
        e1?.expandedSentence == e2?.expandedSentence &&
        e1?.polishedSentence == e2?.polishedSentence &&
        e1?.hasPractice == e2?.hasPractice;
  }

  @override
  int hash(ChatHistoryRecord? e) => const ListEquality().hash([
        e?.customTitle,
        e?.isPinned,
        e?.createdAt,
        e?.expandedSentence,
        e?.polishedSentence,
        e?.hasPractice
      ]);

  @override
  bool isValidKey(Object? o) => o is ChatHistoryRecord;
}
