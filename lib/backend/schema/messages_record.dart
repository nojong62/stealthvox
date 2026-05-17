import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class MessagesRecord extends FirestoreRecord {
  MessagesRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "sender_type" field.
  String? _senderType;

  /// 'host'인지 'guest'인지 구분 (중요!)
  String get senderType => _senderType ?? '';
  bool hasSenderType() => _senderType != null;

  // "timestamp" field.
  DateTime? _timestamp;

  /// 대화 순서 정렬용
  DateTime? get timestamp => _timestamp;
  bool hasTimestamp() => _timestamp != null;

  // "sender_ref" field.
  DocumentReference? _senderRef;
  DocumentReference? get senderRef => _senderRef;
  bool hasSenderRef() => _senderRef != null;

  // "user" field.
  DocumentReference? _user;
  DocumentReference? get user => _user;
  bool hasUser() => _user != null;

  // "translated_text" field.
  String? _translatedText;
  String get translatedText => _translatedText ?? '';
  bool hasTranslatedText() => _translatedText != null;

  // "original_text" field.
  String? _originalText;
  String get originalText => _originalText ?? '';
  bool hasOriginalText() => _originalText != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _senderType = snapshotData['sender_type'] as String?;
    _timestamp = snapshotData['timestamp'] as DateTime?;
    _senderRef = snapshotData['sender_ref'] as DocumentReference?;
    _user = snapshotData['user'] as DocumentReference?;
    _translatedText = snapshotData['translated_text'] as String?;
    _originalText = snapshotData['original_text'] as String?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('messages')
          : FirebaseFirestore.instance.collectionGroup('messages');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('messages').doc(id);

  static Stream<MessagesRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => MessagesRecord.fromSnapshot(s));

  static Future<MessagesRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => MessagesRecord.fromSnapshot(s));

  static MessagesRecord fromSnapshot(DocumentSnapshot snapshot) =>
      MessagesRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static MessagesRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      MessagesRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'MessagesRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is MessagesRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createMessagesRecordData({
  String? senderType,
  DateTime? timestamp,
  DocumentReference? senderRef,
  DocumentReference? user,
  String? translatedText,
  String? originalText,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'sender_type': senderType,
      'timestamp': timestamp,
      'sender_ref': senderRef,
      'user': user,
      'translated_text': translatedText,
      'original_text': originalText,
    }.withoutNulls,
  );

  return firestoreData;
}

class MessagesRecordDocumentEquality implements Equality<MessagesRecord> {
  const MessagesRecordDocumentEquality();

  @override
  bool equals(MessagesRecord? e1, MessagesRecord? e2) {
    return e1?.senderType == e2?.senderType &&
        e1?.timestamp == e2?.timestamp &&
        e1?.senderRef == e2?.senderRef &&
        e1?.user == e2?.user &&
        e1?.translatedText == e2?.translatedText &&
        e1?.originalText == e2?.originalText;
  }

  @override
  int hash(MessagesRecord? e) => const ListEquality().hash([
        e?.senderType,
        e?.timestamp,
        e?.senderRef,
        e?.user,
        e?.translatedText,
        e?.originalText
      ]);

  @override
  bool isValidKey(Object? o) => o is MessagesRecord;
}
