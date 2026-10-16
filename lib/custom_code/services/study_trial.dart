// ====================================================================
// 🎟️ [STUDY-TRIAL] 공부방 체험 — 인트로에서 회원이 아닌 사람이 10분간 써 보는
// 이미 만들어 둔 대화.
// --------------------------------------------------------------------
// 체험 대화는 관리자 계정의 서클톡으로 만든다(실장님 지시, 2026-10-15).
// AI가 먼저 말하고, 관리자가 유저 대신 **글자로** 답한다. 그렇게 만든 방에
// 유저 눈에 안 보이는 `study_trial` 속성이 붙고, 체험 버튼은 그 방들 중에서
// Chat Lang이 폰 시스템 언어와 맞는 하나를 불러온다.
//
// 언어 짝은 고정이다(실장님, 2026-10-16).
//   Chat Lang 한국어·중국어   → Learn Lang 영어
//   Chat Lang 나머지 10개     → Learn Lang 한국어
// 폰 언어가 12개 밖이면 영어 대화(→ 한국어)를 연다(`systemUiLanguageName`의 대체와 같다).
// ====================================================================

import 'package:firebase_auth/firebase_auth.dart';

/// 방 문서에 붙는 숨은 표시. 화면 어디에도 그리지 않는다.
const String kStudyTrialField = 'study_trial';

/// 체험이 이 방을 고를 때 맞춰 보는 Chat Lang. `native_lang`과 같은 값이지만,
/// 표시를 켠 순간의 값으로 따로 박아 둔다 — 찾는 쪽이 한 필드만 보게 한다.
const String kStudyTrialChatLangField = 'study_trial_chat_lang';

/// 체험 대화를 만들 수 있는 Chat Lang. 앱 화면 언어 목록과 같다.
const List<String> kStudyTrialChatLanguages = <String>[
  'English',
  'Korean',
  'Japanese',
  'Chinese',
  'Spanish',
  'French',
  'German',
  'Hindi',
  'Russian',
  'Portuguese',
  'Italian',
  'Dutch',
];

/// 이 Chat Lang의 체험 대화가 써야 하는 Learn Lang.
String studyTrialLearnLangFor(String chatLang) {
  final chat = chatLang.trim();
  return chat == 'Korean' || chat == 'Chinese' ? 'English' : 'Korean';
}

/// 폰 언어로 체험 대화의 Chat Lang을 고른다. 목록 밖이면 영어다.
String studyTrialChatLangForSystem(String systemLanguage) =>
    kStudyTrialChatLanguages.contains(systemLanguage.trim())
        ? systemLanguage.trim()
        : 'English';

/// 이 언어 짝으로 체험 대화를 만들 수 없다면 그 이유. 만들 수 있으면 null.
String? studyTrialPairProblem({
  required String chatLang,
  required String learnLang,
}) {
  final chat = chatLang.trim();
  if (!kStudyTrialChatLanguages.contains(chat)) {
    return 'Chat Lang "$chat"은 체험 대화 언어가 아닙니다';
  }
  final expected = studyTrialLearnLangFor(chat);
  if (learnLang.trim() != expected) {
    return 'Chat Lang $chat의 체험은 Learn Lang $expected여야 합니다';
  }
  return null;
}

/// 원본 준비(🪄)가 끝까지 성공한 시각. ESSAY·다른 표현 전 줄·연습 소리 3벌이
/// 모두 갖춰졌을 때만 적는다. 이 값이 있으면 운영자 화면에서도 🪄을 그리지 않는다.
const String kStudyTrialPreparedField = 'study_trial_prepared_at';

/// 원본 준비가 끝난 방인가.
bool studyTrialRoomPrepared(Map<String, dynamic>? room) =>
    room?[kStudyTrialPreparedField] != null;

/// 서버가 체험자 계정에 복사한 사본에 붙이는 표시(`study_trial.js`).
const String kStudyTrialCopyField = 'study_trial_copy';

/// 체험 원본이거나 그 사본인가. 연습 소리를 Storage에서 함께 쓰는 방이다.
bool isStudyTrialRoom(Map<String, dynamic>? room) =>
    room?[kStudyTrialField] == true || room?[kStudyTrialCopyField] == true;

/// 체험의 연습 설정. 서버 사본(`FIXED_PRACTICE_SETTINGS`)과 같은 값이다.
/// **원본에도 처음부터 묶는다** — 관리자가 원본에서 다른 목소리로 연습하면
/// 그 소리는 체험자가 찾는 칸과 달라 공유되지 않는다.
const Map<String, dynamic> kStudyTrialPracticeSettings = <String, dynamic>{
  'echoing': <String, dynamic>{'voice': 'google-female', 'repeat': 2},
  'shadowing': <String, dynamic>{'voice': 'google-male', 'speed': 0.87},
};

/// 방을 만들 때 함께 적는 체험 표시.
Map<String, dynamic> studyTrialRoomFields(String chatLang) => <String, dynamic>{
      kStudyTrialField: true,
      kStudyTrialChatLangField: chatLang.trim(),
      'practice_settings': kStudyTrialPracticeSettings,
    };

/// 체험 대화를 만들 수 있는 사람인가. 관리자 웹과 같은 `admin` 클레임 하나로
/// 판별한다 — 앱 안의 옛 AdminGate UID 목록은 쓰지 않는다.
Future<bool> isStudyTrialAuthor() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.isAnonymous) return false;
  try {
    final token = await user.getIdTokenResult();
    return token.claims?['admin'] == true;
  } catch (_) {
    return false;
  }
}
