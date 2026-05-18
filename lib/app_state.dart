import 'package:flutter/material.dart';
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/backend/api_requests/api_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'flutter_flow/flutter_flow_util.dart';

class FFAppState extends ChangeNotifier {
  static FFAppState _instance = FFAppState._internal();

  factory FFAppState() {
    return _instance;
  }

  FFAppState._internal();

  static void reset() {
    _instance = FFAppState._internal();
  }

  Future initializePersistedState() async {
    prefs = await SharedPreferences.getInstance();
    _safeInit(() {
      _targetLang = prefs.getString('ff_targetLang') ?? _targetLang;
    });
    _safeInit(() {
      _tone = prefs.getString('ff_tone') ?? _tone;
    });
    _safeInit(() {
      _aiVoice = prefs.getString('ff_aiVoice') ?? _aiVoice;
    });
    _safeInit(() {
      _aiRole = prefs.getString('ff_aiRole') ?? _aiRole;
    });
    _safeInit(() {
      _nativeLang = prefs.getString('ff_nativeLang') ?? _nativeLang;
    });
    _safeInit(() {
      _aiLevel = prefs.getString('ff_aiLevel') ?? _aiLevel;
    });
    _safeInit(() {
      _inviterUid = prefs.getString('ff_inviterUid') ?? _inviterUid;
    });
    _safeInit(() {
      _isGuestSession = prefs.getBool('ff_isGuestSession') ?? _isGuestSession;
    });
    _safeInit(() {
      _duoRoomId = prefs.getString('ff_duoRoomId') ?? _duoRoomId;
    });
    _safeInit(() {
      _pendingInviteType = prefs.getString('ff_pendingInviteType') ?? _pendingInviteType;
    });
  }

  void update(VoidCallback callback) {
    callback();
    notifyListeners();
  }

  late SharedPreferences prefs;

  bool _isRecording = false;
  bool get isRecording => _isRecording;
  set isRecording(bool value) {
    _isRecording = value;
  }

  List<ChatMessageStruct> _chatHistory = [];
  List<ChatMessageStruct> get chatHistory => _chatHistory;
  set chatHistory(List<ChatMessageStruct> value) {
    _chatHistory = value;
  }

  void addToChatHistory(ChatMessageStruct value) {
    chatHistory.add(value);
  }

  void removeFromChatHistory(ChatMessageStruct value) {
    chatHistory.remove(value);
  }

  void removeAtIndexFromChatHistory(int index) {
    chatHistory.removeAt(index);
  }

  void updateChatHistoryAtIndex(
    int index,
    ChatMessageStruct Function(ChatMessageStruct) updateFn,
  ) {
    chatHistory[index] = updateFn(_chatHistory[index]);
  }

  void insertAtIndexInChatHistory(int index, ChatMessageStruct value) {
    chatHistory.insert(index, value);
  }

  String _selectedRole = '';
  String get selectedRole => _selectedRole;
  set selectedRole(String value) {
    _selectedRole = value;
  }

  int _selectedEpisode = 0;
  int get selectedEpisode => _selectedEpisode;
  set selectedEpisode(int value) {
    _selectedEpisode = value;
  }

  String _targetLang = '';
  String get targetLang => _targetLang;
  set targetLang(String value) {
    _targetLang = value;
    prefs.setString('ff_targetLang', value);
  }

  /// Formal
  String _tone = '';
  String get tone => _tone;
  set tone(String value) {
    _tone = value;
    prefs.setString('ff_tone', value);
  }

  /// 남은 시간 (초)
  int _remainingTime = 10000;
  int get remainingTime => _remainingTime;
  set remainingTime(int value) {
    _remainingTime = value;
  }

  String _secureApiKey = '';
  String get secureApiKey => _secureApiKey;
  set secureApiKey(String value) {
    _secureApiKey = value;
  }

  String _aiVoice = 'nova';
  String get aiVoice => _aiVoice;
  set aiVoice(String value) {
    _aiVoice = value;
    prefs.setString('ff_aiVoice', value);
  }

  String _aiRole = '';
  String get aiRole => _aiRole;
  set aiRole(String value) {
    _aiRole = value;
    prefs.setString('ff_aiRole', value);
  }

  String _nativeLang = 'Korean';
  String get nativeLang => _nativeLang;
  set nativeLang(String value) {
    _nativeLang = value;
    prefs.setString('ff_nativeLang', value);
  }

  String _aiLevel = 'Ⅰ';
  String get aiLevel => _aiLevel;
  set aiLevel(String value) {
    _aiLevel = value;
    prefs.setString('ff_aiLevel', value);
  }

  int _currentMode = 0;
  int get currentMode => _currentMode;
  set currentMode(int value) {
    _currentMode = value;
  }

  bool _isGuestSession = false;
  bool get isGuestSession => _isGuestSession;
  set isGuestSession(bool value) {
    _isGuestSession = value;
    prefs.setBool('ff_isGuestSession', value);
  }

  String _inviterUid = '';
  String get inviterUid => _inviterUid;
  set inviterUid(String value) {
    _inviterUid = value;
    prefs.setString('ff_inviterUid', value);
  }

  String _duoRoomId = '';
  String get duoRoomId => _duoRoomId;
  set duoRoomId(String value) {
    _duoRoomId = value;
    prefs.setString('ff_duoRoomId', value);
  }

  String _pendingInviteType = '';
  String get pendingInviteType => _pendingInviteType;
  set pendingInviteType(String value) {
    _pendingInviteType = value;
    prefs.setString('ff_pendingInviteType', value);
  }

}

void _safeInit(Function() initializeField) {
  try {
    initializeField();
  } catch (_) {}
}

Future _safeInitAsync(Function() initializeField) async {
  try {
    await initializeField();
  } catch (_) {}
}
