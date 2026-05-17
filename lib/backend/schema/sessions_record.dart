import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class SessionsRecord extends FirestoreRecord {
  SessionsRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "session_no" field.
  int? _sessionNo;

  /// 대화 번호 (예: 7)
  int get sessionNo => _sessionNo ?? 0;
  bool hasSessionNo() => _sessionNo != null;

  // "created_at" field.
  DateTime? _createdAt;

  /// 저장 날짜
  DateTime? get createdAt => _createdAt;
  bool hasCreatedAt() => _createdAt != null;

  // "transcript" field.
  List<ChatLineStruct>? _transcript;
  List<ChatLineStruct> get transcript => _transcript ?? const [];
  bool hasTranscript() => _transcript != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _sessionNo = castToType<int>(snapshotData['session_no']);
    _createdAt = snapshotData['created_at'] as DateTime?;
    _transcript = getStructList(
      snapshotData['transcript'],
      ChatLineStruct.fromMap,
    );
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('sessions')
          : FirebaseFirestore.instance.collectionGroup('sessions');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('sessions').doc(id);

  static Stream<SessionsRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => SessionsRecord.fromSnapshot(s));

  static Future<SessionsRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => SessionsRecord.fromSnapshot(s));

  static SessionsRecord fromSnapshot(DocumentSnapshot snapshot) =>
      SessionsRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static SessionsRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      SessionsRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'SessionsRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is SessionsRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createSessionsRecordData({
  int? sessionNo,
  DateTime? createdAt,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'session_no': sessionNo,
      'created_at': createdAt,
    }.withoutNulls,
  );

  return firestoreData;
}

class SessionsRecordDocumentEquality implements Equality<SessionsRecord> {
  const SessionsRecordDocumentEquality();

  @override
  bool equals(SessionsRecord? e1, SessionsRecord? e2) {
    const listEquality = ListEquality();
    return e1?.sessionNo == e2?.sessionNo &&
        e1?.createdAt == e2?.createdAt &&
        listEquality.equals(e1?.transcript, e2?.transcript);
  }

  @override
  int hash(SessionsRecord? e) =>
      const ListEquality().hash([e?.sessionNo, e?.createdAt, e?.transcript]);

  @override
  bool isValidKey(Object? o) => o is SessionsRecord;
}
