// ====================================================================
// 🗣️ [FREE TALK] 배울 언어로 바로 대화하는 설정.
// --------------------------------------------------------------------
// 저장 위치는 그대로다. 로비 두 칸의 **이름만** 바뀐다.
//
//   평소       Origin (Chat Lang)  → chatLang   내가 말하는 언어(모국어)
//              Target (Learn Lang) → targetLang 배우는 언어
//   Free Talk  Free Talk Lang      → chatLang   내가 말하는 언어(배우는 언어)
//              Base Lang           → targetLang 뜻을 확인할 언어(모국어)
//
// 대화는 지금처럼 chatLang으로 돌고, History의 두 번째 줄이 Base Lang으로
// 나온다. 그래서 History에서는 위아래를 바꿔 내가 한 말(Free Talk Lang)을
// 위에 크게, 뜻(Base Lang)을 아래에 작게 둔다.
//
// 📌 방 문서에 남긴다. 나중에 로비 설정을 바꿔도 지난 방의 줄 순서는 그대로다.
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

/// 로비 체크 칸 이름 옆의 작은 표시. 설명은 인트로 FAQ가 한다.
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
