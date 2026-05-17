// ignore_for_file: unnecessary_getters_setters

import 'package:cloud_firestore/cloud_firestore.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class ChatLineStruct extends FFFirebaseStruct {
  ChatLineStruct({
    /// "HOST" or "SYSTEM"
    String? role,
    String? originalText,
    String? translatedText,
    FirestoreUtilData firestoreUtilData = const FirestoreUtilData(),
  })  : _role = role,
        _originalText = originalText,
        _translatedText = translatedText,
        super(firestoreUtilData);

  // "role" field.
  String? _role;
  String get role => _role ?? '';
  set role(String? val) => _role = val;

  bool hasRole() => _role != null;

  // "original_text" field.
  String? _originalText;
  String get originalText => _originalText ?? '';
  set originalText(String? val) => _originalText = val;

  bool hasOriginalText() => _originalText != null;

  // "translated_text" field.
  String? _translatedText;
  String get translatedText => _translatedText ?? '';
  set translatedText(String? val) => _translatedText = val;

  bool hasTranslatedText() => _translatedText != null;

  static ChatLineStruct fromMap(Map<String, dynamic> data) => ChatLineStruct(
        role: data['role'] as String?,
        originalText: data['original_text'] as String?,
        translatedText: data['translated_text'] as String?,
      );

  static ChatLineStruct? maybeFromMap(dynamic data) =>
      data is Map ? ChatLineStruct.fromMap(data.cast<String, dynamic>()) : null;

  Map<String, dynamic> toMap() => {
        'role': _role,
        'original_text': _originalText,
        'translated_text': _translatedText,
      }.withoutNulls;

  @override
  Map<String, dynamic> toSerializableMap() => {
        'role': serializeParam(
          _role,
          ParamType.String,
        ),
        'original_text': serializeParam(
          _originalText,
          ParamType.String,
        ),
        'translated_text': serializeParam(
          _translatedText,
          ParamType.String,
        ),
      }.withoutNulls;

  static ChatLineStruct fromSerializableMap(Map<String, dynamic> data) =>
      ChatLineStruct(
        role: deserializeParam(
          data['role'],
          ParamType.String,
          false,
        ),
        originalText: deserializeParam(
          data['original_text'],
          ParamType.String,
          false,
        ),
        translatedText: deserializeParam(
          data['translated_text'],
          ParamType.String,
          false,
        ),
      );

  @override
  String toString() => 'ChatLineStruct(${toMap()})';

  @override
  bool operator ==(Object other) {
    return other is ChatLineStruct &&
        role == other.role &&
        originalText == other.originalText &&
        translatedText == other.translatedText;
  }

  @override
  int get hashCode =>
      const ListEquality().hash([role, originalText, translatedText]);
}

ChatLineStruct createChatLineStruct({
  String? role,
  String? originalText,
  String? translatedText,
  Map<String, dynamic> fieldValues = const {},
  bool clearUnsetFields = true,
  bool create = false,
  bool delete = false,
}) =>
    ChatLineStruct(
      role: role,
      originalText: originalText,
      translatedText: translatedText,
      firestoreUtilData: FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
        delete: delete,
        fieldValues: fieldValues,
      ),
    );

ChatLineStruct? updateChatLineStruct(
  ChatLineStruct? chatLine, {
  bool clearUnsetFields = true,
  bool create = false,
}) =>
    chatLine
      ?..firestoreUtilData = FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
      );

void addChatLineStructData(
  Map<String, dynamic> firestoreData,
  ChatLineStruct? chatLine,
  String fieldName, [
  bool forFieldValue = false,
]) {
  firestoreData.remove(fieldName);
  if (chatLine == null) {
    return;
  }
  if (chatLine.firestoreUtilData.delete) {
    firestoreData[fieldName] = FieldValue.delete();
    return;
  }
  final clearFields =
      !forFieldValue && chatLine.firestoreUtilData.clearUnsetFields;
  if (clearFields) {
    firestoreData[fieldName] = <String, dynamic>{};
  }
  final chatLineData = getChatLineFirestoreData(chatLine, forFieldValue);
  final nestedData = chatLineData.map((k, v) => MapEntry('$fieldName.$k', v));

  final mergeFields = chatLine.firestoreUtilData.create || clearFields;
  firestoreData
      .addAll(mergeFields ? mergeNestedFields(nestedData) : nestedData);
}

Map<String, dynamic> getChatLineFirestoreData(
  ChatLineStruct? chatLine, [
  bool forFieldValue = false,
]) {
  if (chatLine == null) {
    return {};
  }
  final firestoreData = mapToFirestore(chatLine.toMap());

  // Add any Firestore field values
  mapToFirestore(chatLine.firestoreUtilData.fieldValues)
      .forEach((k, v) => firestoreData[k] = v);

  return forFieldValue ? mergeNestedFields(firestoreData) : firestoreData;
}

List<Map<String, dynamic>> getChatLineListFirestoreData(
  List<ChatLineStruct>? chatLines,
) =>
    chatLines?.map((e) => getChatLineFirestoreData(e, true)).toList() ?? [];
