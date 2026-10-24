// ====================================================================
// 🗣️ [FREE TALK] 처음부터 배우는 언어로 대화하는 방.
// --------------------------------------------------------------------
// 고르는 곳은 서클톡·시나리오톡의 시작 화면이다(`stealth_room_master`).
// 로비 Origin/Target은 **언제나 모국어/배울 언어**다 — 로비 값을 같이 읽는
// Duo는 이 설정과 무관하다(실장님, 2026-10-24).
//
// Free Talk 방은 언어 짝을 맞바꿔 저장한다.
//
//   native_lang  로비 Target  대화한 언어. History 위 줄, 공부방 연습 언어
//   target_lang  로비 Origin  뜻을 확인할 언어. History 아래 줄
//   free_talk    true
//
// 📌 방마다 고정이다. 모드 위젯이 처음 뜰 때 한 번 읽고 끝까지 바꾸지 않는다
//   — 한 방 안에 두 언어 짝이 섞이면 History가 깨진다. 시작 화면의 체크는
//   마지막 선택으로 기억한다(`FFAppState.freeTalk`).
//   필드가 없는 방은 평소 방이다.
// ====================================================================

import 'dart:ui' show PlatformDispatcher;

/// 방 문서에 적는 표시. Free Talk 방에만 붙는다.
const String kHistoryFreeTalkField = 'free_talk';

/// 새 방 문서에 펼쳐 넣는다. 평소 방에는 아무것도 더하지 않는다.
Map<String, dynamic> freeTalkRoomFields(bool freeTalk) =>
    freeTalk ? const {kHistoryFreeTalkField: true} : const {};

/// 방 문서가 Free Talk 방인지.
bool isFreeTalkRoom(Map<String, dynamic>? data) =>
    data?[kHistoryFreeTalkField] == true;

/// 이 방에서 **말하는** 로비 언어. Free Talk이면 로비 Target이다.
String freeTalkSpokenLobbyLang({
  required bool freeTalk,
  required String chatLang,
  required String targetLang,
}) =>
    freeTalk ? targetLang : chatLang;

/// 이 방의 **둘째 줄** 로비 언어. Free Talk이면 뜻을 볼 로비 Origin이다.
String freeTalkSecondLobbyLang({
  required bool freeTalk,
  required String chatLang,
  required String targetLang,
}) =>
    freeTalk ? chatLang : targetLang;

/// 시작 화면 체크 칸 이름 옆의 작은 표시. 설명은 인트로 FAQ가 한다.
/// 로그인 전 화면과 같이 폰 언어를 따른다.
String freeTalkOptionLabelForSystemLocale() {
  final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
  return _kFreeTalkOptionLabels[code] ?? _kFreeTalkOptionLabels['en']!;
}

const Map<String, String> _kFreeTalkOptionLabels = {
  'en': 'Optional',
  'ko': '옵션',
  'ja': 'オプション',
  'zh': '可选',
  'es': 'Opcional',
  'fr': 'Option',
  'de': 'Optional',
  'hi': 'वैकल्पिक',
  'ru': 'Опция',
  'pt': 'Opcional',
  'it': 'Opzionale',
  'nl': 'Optioneel',
};
