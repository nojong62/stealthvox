import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class ClonesRecord extends FirestoreRecord {
  ClonesRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "name" field.
  String? _name;
  String get name => _name ?? '';
  bool hasName() => _name != null;

  // "personality" field.
  String? _personality;
  String get personality => _personality ?? '';
  bool hasPersonality() => _personality != null;

  // "summary" field.
  String? _summary;
  String get summary => _summary ?? '';
  bool hasSummary() => _summary != null;

  // "turn_count" field.
  int? _turnCount;
  int get turnCount => _turnCount ?? 0;
  bool hasTurnCount() => _turnCount != null;

  // "created_at" field.
  DateTime? _createdAt;
  DateTime? get createdAt => _createdAt;
  bool hasCreatedAt() => _createdAt != null;

  // "recent_history" field.
  List<String>? _recentHistory;
  List<String> get recentHistory => _recentHistory ?? const [];
  bool hasRecentHistory() => _recentHistory != null;

  // "original_text" field.
  String? _originalText;
  String get originalText => _originalText ?? '';
  bool hasOriginalText() => _originalText != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _name = snapshotData['name'] as String?;
    _personality = snapshotData['personality'] as String?;
    _summary = snapshotData['summary'] as String?;
    _turnCount = castToType<int>(snapshotData['turn_count']);
    _createdAt = snapshotData['created_at'] as DateTime?;
    _recentHistory = getDataList(snapshotData['recent_history']);
    _originalText = snapshotData['original_text'] as String?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('clones')
          : FirebaseFirestore.instance.collectionGroup('clones');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('clones').doc(id);

  static Stream<ClonesRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => ClonesRecord.fromSnapshot(s));

  static Future<ClonesRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => ClonesRecord.fromSnapshot(s));

  static ClonesRecord fromSnapshot(DocumentSnapshot snapshot) => ClonesRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static ClonesRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      ClonesRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'ClonesRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is ClonesRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createClonesRecordData({
  String? name,
  String? personality,
  String? summary,
  int? turnCount,
  DateTime? createdAt,
  String? originalText,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'name': name,
      'personality': personality,
      'summary': summary,
      'turn_count': turnCount,
      'created_at': createdAt,
      'original_text': originalText,
    }.withoutNulls,
  );

  return firestoreData;
}

class ClonesRecordDocumentEquality implements Equality<ClonesRecord> {
  const ClonesRecordDocumentEquality();

  @override
  bool equals(ClonesRecord? e1, ClonesRecord? e2) {
    const listEquality = ListEquality();
    return e1?.name == e2?.name &&
        e1?.personality == e2?.personality &&
        e1?.summary == e2?.summary &&
        e1?.turnCount == e2?.turnCount &&
        e1?.createdAt == e2?.createdAt &&
        listEquality.equals(e1?.recentHistory, e2?.recentHistory) &&
        e1?.originalText == e2?.originalText;
  }

  @override
  int hash(ClonesRecord? e) => const ListEquality().hash([
        e?.name,
        e?.personality,
        e?.summary,
        e?.turnCount,
        e?.createdAt,
        e?.recentHistory,
        e?.originalText
      ]);

  @override
  bool isValidKey(Object? o) => o is ClonesRecord;
}
