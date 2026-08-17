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
      _aiStyle = prefs.getString('ff_aiStyle') ?? _aiStyle;
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
      _hasLinkedAccount =
          prefs.getBool('ff_hasLinkedAccount') ?? _hasLinkedAccount;
    });
    _safeInit(() {
      _duoRoomId = prefs.getString('ff_duoRoomId') ?? _duoRoomId;
    });
    _safeInit(() {
      _pendingInviteType =
          prefs.getString('ff_pendingInviteType') ?? _pendingInviteType;
    });
    _safeInit(() {
      _trialStep = prefs.getInt('ff_trialStep') ?? _trialStep;
    });
    _safeInit(() {
      _trialHistoryPath =
          prefs.getString('ff_trialHistoryPath') ?? _trialHistoryPath;
    });
    _safeInit(() {
      _trialCompleted = prefs.getBool('ff_trialCompleted') ?? _trialCompleted;
    });
    _safeInit(() {
      _lastAuthProvider =
          prefs.getString('ff_lastAuthProvider') ?? _lastAuthProvider;
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

  /// AI response style selected in the lobby.
  String _aiStyle = 'Standard';
  String get aiStyle => _aiStyle;
  set aiStyle(String value) {
    _aiStyle = value;
    prefs.setString('ff_aiStyle', value);
  }

  /// 남은 시간 (초)
  int _remainingTime = 0;
  int get remainingTime => _remainingTime;
  set remainingTime(int value) {
    _remainingTime = value;
  }

  /// remainingTime을 Firestore에서 최초 로드했는지 여부.
  /// false인 동안 UI는 숫자 대신 로딩 표시를 해야 한다.
  bool _remainingTimeLoaded = false;
  bool get remainingTimeLoaded => _remainingTimeLoaded;
  set remainingTimeLoaded(bool value) {
    _remainingTimeLoaded = value;
  }

  /// Firestore fetch가 완료되고 실제로 0(또는 그 이하)임이 확정된 경우에만 true.
  /// 로딩 중에는 이 값이 true가 되지 않아야 한다.
  bool get hasConfirmedZeroTime => remainingTimeLoaded && remainingTime <= 0;

  /// 로딩 완료 후 실제로 사용할 시간이 있는 경우에만 true.
  bool get hasConfirmedPositiveTime => remainingTimeLoaded && remainingTime > 0;

  String _secureApiKey = '';
  String get secureApiKey => _secureApiKey;
  set secureApiKey(String value) {
    _secureApiKey = value;
  }

  String _aiVoice = 'echo';
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

  /// ⚠️ **이름과 의미가 다르다. "모국어"로 읽지 말 것.**
  ///
  /// 제품 의미는 **ORIGIN = Chat Language** — 사용자가 실제로 말하고 듣는
  /// 언어다. 배우는 언어는 [targetLang]이다. 로비 화면도 이 값을
  /// `ORIGIN (Chat Lang)`으로 표시한다.
  ///
  /// `nativeLang`과 저장 키 `ff_nativeLang`은 FlutterFlow 시절부터 내려온
  /// **레거시 이름**이다(이 저장소의 첫 커밋에 이미 이 형태로 존재한다).
  /// 이름을 바꾸면 기존 사용자의 저장값이 통째로 사라지므로 그대로 둔다.
  /// 앱 코드는 `_myNative()` · `_nativeLangName()` 같은 래퍼를 통해 쓴다.
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

  bool _hasLinkedAccount = false;
  bool get hasLinkedAccount => _hasLinkedAccount;
  set hasLinkedAccount(bool value) {
    _hasLinkedAccount = value;
    prefs.setBool('ff_hasLinkedAccount', value);
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

  int _trialStep = 0;
  int get trialStep => _trialStep;
  set trialStep(int value) {
    _trialStep = value;
    prefs.setInt('ff_trialStep', value);
  }

  String _trialHistoryPath = '';
  String get trialHistoryPath => _trialHistoryPath;
  set trialHistoryPath(String value) {
    _trialHistoryPath = value;
    prefs.setString('ff_trialHistoryPath', value);
  }

  bool _trialCompleted = false;
  bool get trialCompleted => _trialCompleted;
  set trialCompleted(bool value) {
    _trialCompleted = value;
    prefs.setBool('ff_trialCompleted', value);
  }

  String _lastAuthProvider = '';
  String get lastAuthProvider => _lastAuthProvider;
  set lastAuthProvider(String value) {
    _lastAuthProvider = value;
    prefs.setString('ff_lastAuthProvider', value);
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
