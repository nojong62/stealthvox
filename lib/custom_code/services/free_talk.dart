// ====================================================================
// 🗣️ [FREE TALK] 처음부터 배우는 언어로 대화하는 방.
// --------------------------------------------------------------------
// 고르는 곳은 서클톡·시나리오톡에 들어가기 직전이다(`stealth_room_master`).
// 로비 Origin/Target은 **언제나 모국어/배울 언어**다 — 로비 값을 같이 읽는
// Duo는 이 설정과 무관하다(실장님, 2026-10-24).
//
// Free Talk 방은 언어 짝을 맞바꿔 저장한다.
//
//   native_lang  로비 Target  대화한 언어. History 위 줄, 공부방 연습 언어
//   target_lang  로비 Origin  뜻을 확인할 언어. History 아래 줄
//   free_talk    true
//
// 📌 **들어갈 때마다 묻는다.** 기억하지 않는다 — 시작 화면의 시작 버튼을
//   누르면 Free Talk / 기본 중 하나를 고르고, 고른 값은 모드 위젯 인자로
//   넘어가 그 방에 끝까지 고정된다. 한 방 안에 두 언어 짝이 섞이면 History가
//   깨진다(실장님, 2026-10-25). 필드가 없는 방은 평소 방이다.
//
// History 화면은 평소 방과 똑같이 보인다 — 위에 로비 Target(내가 한 말),
// 아래 작게 로비 Origin(뜻). 원문 칸에는 실제로 한 말이 그대로 남아야
// 확정·문맥 교정이 그 말을 지키므로, 저장은 위 표처럼 맞바꾸고 화면만
// 순서를 바꾼다(`chat_history_master._sessionFreeTalk`).
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

/// 서클톡·시나리오톡에 **들어갈 때마다** 묻는 창의 글. 로그인 전 화면과 같이
/// 폰 언어를 따른다. `{lang}`에는 그 언어 이름이 들어간다.
class FreeTalkChoiceCopy {
  const FreeTalkChoiceCopy._(
      this.title, this.freeTalkDesc, this.standard, this.standardDesc);

  final String title;
  final String freeTalkDesc;
  final String standard;
  final String standardDesc;

  static FreeTalkChoiceCopy forSystemLocale() {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return _copies[code] ?? _copies['en']!;
  }

  static const Map<String, FreeTalkChoiceCopy> _copies = {
    'en': FreeTalkChoiceCopy._(
        'Talk in Free Talk?', 'Talk in {lang}', 'Standard', 'Talk in {lang}'),
    'ko': FreeTalkChoiceCopy._(
        'Free Talk으로 대화할까요?', '{lang}로 대화합니다', '기본', '{lang}로 대화합니다'),
    'ja': FreeTalkChoiceCopy._(
        'Free Talk で話しますか?', '{lang}で話します', '標準', '{lang}で話します'),
    'zh': FreeTalkChoiceCopy._(
        '要用 Free Talk 对话吗?', '用{lang}对话', '标准', '用{lang}对话'),
    'es': FreeTalkChoiceCopy._(
        '¿Hablar en Free Talk?', 'Hablas en {lang}', 'Estándar', 'Hablas en {lang}'),
    'fr': FreeTalkChoiceCopy._('Parler en Free Talk ?', 'Vous parlez en {lang}',
        'Standard', 'Vous parlez en {lang}'),
    'de': FreeTalkChoiceCopy._(
        'Im Free Talk sprechen?', 'Du sprichst {lang}', 'Standard', 'Du sprichst {lang}'),
    'hi': FreeTalkChoiceCopy._('Free Talk में बात करें?', '{lang} में बात करें',
        'सामान्य', '{lang} में बात करें'),
    'ru': FreeTalkChoiceCopy._('Говорить в режиме Free Talk?',
        'Разговор на языке: {lang}', 'Обычный', 'Разговор на языке: {lang}'),
    'pt': FreeTalkChoiceCopy._('Conversar em Free Talk?', 'Você fala em {lang}',
        'Padrão', 'Você fala em {lang}'),
    'it': FreeTalkChoiceCopy._(
        'Parlare in Free Talk?', 'Parli in {lang}', 'Standard', 'Parli in {lang}'),
    'nl': FreeTalkChoiceCopy._(
        'Praten in Free Talk?', 'Je praat in {lang}', 'Standaard', 'Je praat in {lang}'),
  };
}
