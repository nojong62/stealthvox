import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class UsersRecord extends FirestoreRecord {
  UsersRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "email" field.
  String? _email;
  String get email => _email ?? '';
  bool hasEmail() => _email != null;

  // "display_name" field.
  String? _displayName;
  String get displayName => _displayName ?? '';
  bool hasDisplayName() => _displayName != null;

  // "photo_url" field.
  String? _photoUrl;
  String get photoUrl => _photoUrl ?? '';
  bool hasPhotoUrl() => _photoUrl != null;

  // "uid" field.
  String? _uid;
  String get uid => _uid ?? '';
  bool hasUid() => _uid != null;

  // "created_time" field.
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  // "phone_number" field.
  String? _phoneNumber;
  String get phoneNumber => _phoneNumber ?? '';
  bool hasPhoneNumber() => _phoneNumber != null;

  // "remaining_seconds" field.
  int? _remainingSeconds;

  /// 남은 시간 (초)
  int get remainingSeconds => _remainingSeconds ?? 0;
  bool hasRemainingSeconds() => _remainingSeconds != null;

  // "total_sessions" field.
  int? _totalSessions;

  /// 지금까지 연습한 총 횟수
  int get totalSessions => _totalSessions ?? 0;
  bool hasTotalSessions() => _totalSessions != null;

  // "target_lang" field.
  String? _targetLang;

  /// 학습 언어 (기본값: en)
  String get targetLang => _targetLang ?? '';
  bool hasTargetLang() => _targetLang != null;

  // "tone" field.
  String? _tone;

  /// 말투 (Formal/Casual)
  String get tone => _tone ?? '';
  bool hasTone() => _tone != null;

  // "credits" field.
  int? _credits;
  int get credits => _credits ?? 0;
  bool hasCredits() => _credits != null;

  // "remainingTime" field.
  int? _remainingTime;
  int get remainingTime => _remainingTime ?? 0;
  bool hasRemainingTime() => _remainingTime != null;

  void _initializeFields() {
    _email = snapshotData['email'] as String?;
    _displayName = snapshotData['display_name'] as String?;
    _photoUrl = snapshotData['photo_url'] as String?;
    _uid = snapshotData['uid'] as String?;
    _createdTime = snapshotData['created_time'] as DateTime?;
    _phoneNumber = snapshotData['phone_number'] as String?;
    _remainingSeconds = castToType<int>(snapshotData['remaining_seconds']);
    _totalSessions = castToType<int>(snapshotData['total_sessions']);
    _targetLang = snapshotData['target_lang'] as String?;
    _tone = snapshotData['tone'] as String?;
    _credits = castToType<int>(snapshotData['credits']);
    _remainingTime = castToType<int>(snapshotData['remainingTime']);
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('users');

  static Stream<UsersRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => UsersRecord.fromSnapshot(s));

  static Future<UsersRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => UsersRecord.fromSnapshot(s));

  static UsersRecord fromSnapshot(DocumentSnapshot snapshot) => UsersRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static UsersRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      UsersRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'UsersRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is UsersRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createUsersRecordData({
  String? email,
  String? displayName,
  String? photoUrl,
  String? uid,
  DateTime? createdTime,
  String? phoneNumber,
  int? remainingSeconds,
  int? totalSessions,
  String? targetLang,
  String? tone,
  int? credits,
  int? remainingTime,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'email': email,
      'display_name': displayName,
      'photo_url': photoUrl,
      'uid': uid,
      'created_time': createdTime,
      'phone_number': phoneNumber,
      'remaining_seconds': remainingSeconds,
      'total_sessions': totalSessions,
      'target_lang': targetLang,
      'tone': tone,
      'credits': credits,
      'remainingTime': remainingTime,
    }.withoutNulls,
  );

  return firestoreData;
}

class UsersRecordDocumentEquality implements Equality<UsersRecord> {
  const UsersRecordDocumentEquality();

  @override
  bool equals(UsersRecord? e1, UsersRecord? e2) {
    return e1?.email == e2?.email &&
        e1?.displayName == e2?.displayName &&
        e1?.photoUrl == e2?.photoUrl &&
        e1?.uid == e2?.uid &&
        e1?.createdTime == e2?.createdTime &&
        e1?.phoneNumber == e2?.phoneNumber &&
        e1?.remainingSeconds == e2?.remainingSeconds &&
        e1?.totalSessions == e2?.totalSessions &&
        e1?.targetLang == e2?.targetLang &&
        e1?.tone == e2?.tone &&
        e1?.credits == e2?.credits &&
        e1?.remainingTime == e2?.remainingTime;
  }

  @override
  int hash(UsersRecord? e) => const ListEquality().hash([
        e?.email,
        e?.displayName,
        e?.photoUrl,
        e?.uid,
        e?.createdTime,
        e?.phoneNumber,
        e?.remainingSeconds,
        e?.totalSessions,
        e?.targetLang,
        e?.tone,
        e?.credits,
        e?.remainingTime
      ]);

  @override
  bool isValidKey(Object? o) => o is UsersRecord;
}
