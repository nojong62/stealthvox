import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class PurchasesRecord extends FirestoreRecord {
  PurchasesRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "product_id" field.
  String? _productId;
  String get productId => _productId ?? '';
  bool hasProductId() => _productId != null;

  // "product_title" field.
  String? _productTitle;
  String get productTitle => _productTitle ?? '';
  bool hasProductTitle() => _productTitle != null;

  // "seconds_added" field.
  int? _secondsAdded;
  int get secondsAdded => _secondsAdded ?? 0;
  bool hasSecondsAdded() => _secondsAdded != null;

  // "purchased_at" field.
  DateTime? _purchasedAt;
  DateTime? get purchasedAt => _purchasedAt;
  bool hasPurchasedAt() => _purchasedAt != null;

  DocumentReference get parentReference => reference.parent.parent!;

  void _initializeFields() {
    _productId = snapshotData['product_id'] as String?;
    _productTitle = snapshotData['product_title'] as String?;
    _secondsAdded = castToType<int>(snapshotData['seconds_added']);
    _purchasedAt = snapshotData['purchased_at'] as DateTime?;
  }

  static Query<Map<String, dynamic>> collection([DocumentReference? parent]) =>
      parent != null
          ? parent.collection('purchases')
          : FirebaseFirestore.instance.collectionGroup('purchases');

  static DocumentReference createDoc(DocumentReference parent, {String? id}) =>
      parent.collection('purchases').doc(id);

  static Stream<PurchasesRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => PurchasesRecord.fromSnapshot(s));

  static Future<PurchasesRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => PurchasesRecord.fromSnapshot(s));

  static PurchasesRecord fromSnapshot(DocumentSnapshot snapshot) =>
      PurchasesRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static PurchasesRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      PurchasesRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'PurchasesRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is PurchasesRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createPurchasesRecordData({
  String? productId,
  String? productTitle,
  int? secondsAdded,
  DateTime? purchasedAt,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'product_id': productId,
      'product_title': productTitle,
      'seconds_added': secondsAdded,
      'purchased_at': purchasedAt,
    }.withoutNulls,
  );

  return firestoreData;
}

class PurchasesRecordDocumentEquality implements Equality<PurchasesRecord> {
  const PurchasesRecordDocumentEquality();

  @override
  bool equals(PurchasesRecord? e1, PurchasesRecord? e2) {
    return e1?.productId == e2?.productId &&
        e1?.productTitle == e2?.productTitle &&
        e1?.secondsAdded == e2?.secondsAdded &&
        e1?.purchasedAt == e2?.purchasedAt;
  }

  @override
  int hash(PurchasesRecord? e) => const ListEquality()
      .hash([e?.productId, e?.productTitle, e?.secondsAdded, e?.purchasedAt]);

  @override
  bool isValidKey(Object? o) => o is PurchasesRecord;
}
