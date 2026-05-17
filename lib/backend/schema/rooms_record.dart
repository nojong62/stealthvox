import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class RoomsRecord extends FirestoreRecord {
  RoomsRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "host_ref" field.
  DocumentReference? _hostRef;

  /// 방장
  DocumentReference? get hostRef => _hostRef;
  bool hasHostRef() => _hostRef != null;

  // "target_lang" field.
  String? _targetLang;

  /// 언어
  String get targetLang => _targetLang ?? '';
  bool hasTargetLang() => _targetLang != null;

  // "tone" field.
  String? _tone;

  /// 말투
  String get tone => _tone ?? '';
  bool hasTone() => _tone != null;

  // "created_at" field.
  DateTime? _createdAt;

  /// 만든시간
  DateTime? get createdAt => _createdAt;
  bool hasCreatedAt() => _createdAt != null;

  // "invite_code" field.
  String? _inviteCode;
  String get inviteCode => _inviteCode ?? '';
  bool hasInviteCode() => _inviteCode != null;

  // "is_active" field.
  bool? _isActive;
  bool get isActive => _isActive ?? false;
  bool hasIsActive() => _isActive != null;

  void _initializeFields() {
    _hostRef = snapshotData['host_ref'] as DocumentReference?;
    _targetLang = snapshotData['target_lang'] as String?;
    _tone = snapshotData['tone'] as String?;
    _createdAt = snapshotData['created_at'] as DateTime?;
    _inviteCode = snapshotData['invite_code'] as String?;
    _isActive = snapshotData['is_active'] as bool?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('rooms');

  static Stream<RoomsRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => RoomsRecord.fromSnapshot(s));

  static Future<RoomsRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => RoomsRecord.fromSnapshot(s));

  static RoomsRecord fromSnapshot(DocumentSnapshot snapshot) => RoomsRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static RoomsRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      RoomsRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'RoomsRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is RoomsRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createRoomsRecordData({
  DocumentReference? hostRef,
  String? targetLang,
  String? tone,
  DateTime? createdAt,
  String? inviteCode,
  bool? isActive,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'host_ref': hostRef,
      'target_lang': targetLang,
      'tone': tone,
      'created_at': createdAt,
      'invite_code': inviteCode,
      'is_active': isActive,
    }.withoutNulls,
  );

  return firestoreData;
}

class RoomsRecordDocumentEquality implements Equality<RoomsRecord> {
  const RoomsRecordDocumentEquality();

  @override
  bool equals(RoomsRecord? e1, RoomsRecord? e2) {
    return e1?.hostRef == e2?.hostRef &&
        e1?.targetLang == e2?.targetLang &&
        e1?.tone == e2?.tone &&
        e1?.createdAt == e2?.createdAt &&
        e1?.inviteCode == e2?.inviteCode &&
        e1?.isActive == e2?.isActive;
  }

  @override
  int hash(RoomsRecord? e) => const ListEquality().hash([
        e?.hostRef,
        e?.targetLang,
        e?.tone,
        e?.createdAt,
        e?.inviteCode,
        e?.isActive
      ]);

  @override
  bool isValidKey(Object? o) => o is RoomsRecord;
}
