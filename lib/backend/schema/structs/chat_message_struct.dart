// ignore_for_file: unnecessary_getters_setters

import 'package:cloud_firestore/cloud_firestore.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class ChatMessageStruct extends FFFirebaseStruct {
  ChatMessageStruct({
    String? korText,
    String? engText,
    bool? isMe,
    String? audioUrl,
    FirestoreUtilData firestoreUtilData = const FirestoreUtilData(),
  })  : _korText = korText,
        _engText = engText,
        _isMe = isMe,
        _audioUrl = audioUrl,
        super(firestoreUtilData);

  // "korText" field.
  String? _korText;
  String get korText => _korText ?? '';
  set korText(String? val) => _korText = val;

  bool hasKorText() => _korText != null;

  // "engText" field.
  String? _engText;
  String get engText => _engText ?? '';
  set engText(String? val) => _engText = val;

  bool hasEngText() => _engText != null;

  // "isMe" field.
  bool? _isMe;
  bool get isMe => _isMe ?? false;
  set isMe(bool? val) => _isMe = val;

  bool hasIsMe() => _isMe != null;

  // "audio_url" field.
  String? _audioUrl;
  String get audioUrl => _audioUrl ?? '';
  set audioUrl(String? val) => _audioUrl = val;

  bool hasAudioUrl() => _audioUrl != null;

  static ChatMessageStruct fromMap(Map<String, dynamic> data) =>
      ChatMessageStruct(
        korText: data['korText'] as String?,
        engText: data['engText'] as String?,
        isMe: data['isMe'] as bool?,
        audioUrl: data['audio_url'] as String?,
      );

  static ChatMessageStruct? maybeFromMap(dynamic data) => data is Map
      ? ChatMessageStruct.fromMap(data.cast<String, dynamic>())
      : null;

  Map<String, dynamic> toMap() => {
        'korText': _korText,
        'engText': _engText,
        'isMe': _isMe,
        'audio_url': _audioUrl,
      }.withoutNulls;

  @override
  Map<String, dynamic> toSerializableMap() => {
        'korText': serializeParam(
          _korText,
          ParamType.String,
        ),
        'engText': serializeParam(
          _engText,
          ParamType.String,
        ),
        'isMe': serializeParam(
          _isMe,
          ParamType.bool,
        ),
        'audio_url': serializeParam(
          _audioUrl,
          ParamType.String,
        ),
      }.withoutNulls;

  static ChatMessageStruct fromSerializableMap(Map<String, dynamic> data) =>
      ChatMessageStruct(
        korText: deserializeParam(
          data['korText'],
          ParamType.String,
          false,
        ),
        engText: deserializeParam(
          data['engText'],
          ParamType.String,
          false,
        ),
        isMe: deserializeParam(
          data['isMe'],
          ParamType.bool,
          false,
        ),
        audioUrl: deserializeParam(
          data['audio_url'],
          ParamType.String,
          false,
        ),
      );

  @override
  String toString() => 'ChatMessageStruct(${toMap()})';

  @override
  bool operator ==(Object other) {
    return other is ChatMessageStruct &&
        korText == other.korText &&
        engText == other.engText &&
        isMe == other.isMe &&
        audioUrl == other.audioUrl;
  }

  @override
  int get hashCode =>
      const ListEquality().hash([korText, engText, isMe, audioUrl]);
}

ChatMessageStruct createChatMessageStruct({
  String? korText,
  String? engText,
  bool? isMe,
  String? audioUrl,
  Map<String, dynamic> fieldValues = const {},
  bool clearUnsetFields = true,
  bool create = false,
  bool delete = false,
}) =>
    ChatMessageStruct(
      korText: korText,
      engText: engText,
      isMe: isMe,
      audioUrl: audioUrl,
      firestoreUtilData: FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
        delete: delete,
        fieldValues: fieldValues,
      ),
    );

ChatMessageStruct? updateChatMessageStruct(
  ChatMessageStruct? chatMessage, {
  bool clearUnsetFields = true,
  bool create = false,
}) =>
    chatMessage
      ?..firestoreUtilData = FirestoreUtilData(
        clearUnsetFields: clearUnsetFields,
        create: create,
      );

void addChatMessageStructData(
  Map<String, dynamic> firestoreData,
  ChatMessageStruct? chatMessage,
  String fieldName, [
  bool forFieldValue = false,
]) {
  firestoreData.remove(fieldName);
  if (chatMessage == null) {
    return;
  }
  if (chatMessage.firestoreUtilData.delete) {
    firestoreData[fieldName] = FieldValue.delete();
    return;
  }
  final clearFields =
      !forFieldValue && chatMessage.firestoreUtilData.clearUnsetFields;
  if (clearFields) {
    firestoreData[fieldName] = <String, dynamic>{};
  }
  final chatMessageData =
      getChatMessageFirestoreData(chatMessage, forFieldValue);
  final nestedData =
      chatMessageData.map((k, v) => MapEntry('$fieldName.$k', v));

  final mergeFields = chatMessage.firestoreUtilData.create || clearFields;
  firestoreData
      .addAll(mergeFields ? mergeNestedFields(nestedData) : nestedData);
}

Map<String, dynamic> getChatMessageFirestoreData(
  ChatMessageStruct? chatMessage, [
  bool forFieldValue = false,
]) {
  if (chatMessage == null) {
    return {};
  }
  final firestoreData = mapToFirestore(chatMessage.toMap());

  // Add any Firestore field values
  mapToFirestore(chatMessage.firestoreUtilData.fieldValues)
      .forEach((k, v) => firestoreData[k] = v);

  return forFieldValue ? mergeNestedFields(firestoreData) : firestoreData;
}

List<Map<String, dynamic>> getChatMessageListFirestoreData(
  List<ChatMessageStruct>? chatMessages,
) =>
    chatMessages?.map((e) => getChatMessageFirestoreData(e, true)).toList() ??
    [];
