// 🔬 [P2-VOICE-LAB] P2 음성 Pattern 후보의 재료 정의.
//
//   여기 있는 건 **상수뿐이다.** 로직도 상태도 없다. 관리자 Voice Lab이
//   지금 이걸 읽고, 나중에 확정될 공식 P2 Pattern preset도 여기서 나온다.
//
//   위젯 파일이 아니라 services/에 둔 이유: 2차 작업에서 실사용 P2 화면
//   (`chat_history_master.dart`)이 확정 Pattern을 읽어야 하는데, 그때
//   실사용 화면이 관리자 도구 위젯을 import하게 되면 안 된다.
//
//   ⚠️ **이 파일은 현재 실사용 P2 음성에 아무 영향이 없다.** 실사용 P2는
//   `chat_history_master.dart`의 `_meaningUnitTtsInstructions`를 쓰고,
//   그 파일은 이번 작업에서 한 줄도 바뀌지 않았다.

/// P2 낭독 스타일 한 벌.
class P2VoiceStyle {
  const P2VoiceStyle({
    required this.id,
    required this.label,
    required this.instruction,
    required this.goal,
  });

  /// 캐시·preset identity. **표시 이름이 바뀌어도 이건 절대 바꾸지 않는다.**
  /// 바꾸는 순간 그 스타일로 만들어 둔 캐시가 전부 미아가 된다.
  final String id;

  /// 화면에 보이는 이름. 자유롭게 바꿔도 안전하다.
  final String label;

  /// OpenAI `/v1/audio/speech`의 `instructions`에 **그대로** 실려 가는 본문.
  final String instruction;

  /// 이 스타일로 무엇을 노리는지(한국어). API로는 가지 않는다 —
  /// Lab 화면에서 관리자가 의도를 확인하는 용도다.
  final String goal;
}

/// 🔖 instruction 문구를 고치면 **반드시 이 값을 올린다.**
///
/// 안 올리면 캐시 키가 그대로라 예전 지시로 만든 소리가 그대로 나오고,
/// 화면에서는 새 지시가 먹은 것처럼 보인다. 그 상태는 귀로 구분되지 않는다.
const String kP2StyleInstructionVersion = 'v1';

/// Lab이 쓰는 TTS 모델. 실사용 P2(`_historyPracticeTtsModel`)와 같은 값이다.
/// `instructions`가 실제로 먹는 모델이어야 하므로 tts-1로 내리면 안 된다.
const String kP2LabTtsModel = 'gpt-4o-mini-tts';

/// 모든 조합이 공유하는 단 하나의 비교용 문장.
///
/// **조합마다 다른 문장을 쓰면 비교 자체가 무의미해진다.** 문장을 바꾸고
/// 싶으면 여기만 고치면 되고, 캐시 키에 텍스트가 이미 들어가므로 예전 문장의
/// 음성이 섞여 나올 일은 없다.
const String kP2LabSampleSentence =
    'I was honestly a little surprised at first, but after thinking about it '
    'for a while, I realized it might actually be a much better idea than I '
    'expected.';

/// GPT TTS Voice 13종. **전부 화면에 띄운다.**
///
/// 이 앱에서 실제로 검증된 건 marin·cedar·verse·coral·nova 다섯뿐이다.
/// 나머지가 API에서 오류를 내더라도 **여기서 빼거나 다른 voice로 바꾸지
/// 않는다** — 어느 voice가 안 되는지가 Lab이 알아내야 할 사실이다.
const List<String> kP2LabVoices = <String>[
  'alloy',
  'ash',
  'ballad',
  'coral',
  'echo',
  'fable',
  'nova',
  'onyx',
  'sage',
  'shimmer',
  'verse',
  'marin',
  'cedar',
];

/// 🌬️ Breath Echoing Phase 1의 고정 Style.
///
/// 호흡 비교는 **instruction을 고정한 채 Voice만 바꿔야** 성립한다. Style이
/// 섞이면 pause 차이가 Voice 때문인지 지시문 때문인지 알 수 없다.
const String kP2BreathTestStyleId = 'style_smooth_jazz';

/// 🌬️ Breath Echoing Phase 1의 우선 비교 Voice 4종.
///
/// [kP2LabVoices] 13종을 줄이는 것이 아니다 — dropdown은 그대로 13개다.
/// 이 목록은 "먼저 이 넷을 같은 조건으로 들어본다"는 **순서**일 뿐이다.
const List<String> kP2BreathTestVoices = <String>[
  'marin',
  'echo',
  'cedar',
  'verse',
];

/// 🎵 P3(에코잉·쉐도잉)가 쓰는 낭독 패턴 — Sing-Song Flow.
///
/// Lab 조합표([kP2VoiceStyles])에 넣지 않는다. 조합표는 6 × 13을 비교하는
/// 실험대이고, 이건 실사용 P3가 **고정으로** 쓰는 한 벌이다. id가 다르므로
/// 캐시 칸도 따로 서서, P2 Breath(Smooth Jazz)로 만들어 둔 소리는 그대로다.
///
/// 문구를 고치면 [kP2StyleInstructionVersion]이 아니라 이 id 뒤에 세대를
/// 붙여 올린다 — 버전을 올리면 P2 캐시까지 통째로 미아가 된다.
const P2VoiceStyle kP3SpeakingStyle = P2VoiceStyle(
  id: 'style_sing_song_flow_p3',
  label: 'Sing-Song Flow',
  instruction: '''
Speak in a clear General American accent with a strongly melodic, almost sing-song flow.

Use noticeable pitch rises and falls, with lively, rhythmic phrasing, but keep the delivery easy to follow for a non-native English learner.

Speak at a medium-slow pace, slightly slower than natural conversation. Give each phrase enough space to be heard and repeated clearly, without sounding unnaturally stretched.

Keep the rhythm strong and musical. Gently emphasize important words, and let unstressed words flow lightly between them.

Use a playful, bright, energetic tone with expressive pitch variation. Make the sentence feel almost like a simple melody, while keeping every word crisp and intelligible.

Avoid rushing, slurring, or compressing words. Prioritize clear rhythm, clear stress, and easy shadowing.''',
  goal: '영어 억양을 노래처럼 몸에 새기는 훈련용. 호흡마다 따라 말할 자리가 '
      '남도록 대화보다 조금 느리게 읽고, 강약과 pitch는 확실히 살린다.',
);

/// TTS 스타일 6종. Voice 13종과 **서로 독립적으로** 조합된다(6 × 13 = 78).
const List<P2VoiceStyle> kP2VoiceStyles = <P2VoiceStyle>[
  P2VoiceStyle(
    id: 'style_musical_natural',
    label: 'Musical Natural',
    instruction: '''
Accent: General American

Intonation: Highly melodic and flowing, with clear rises and falls across each phrase

Speed: Medium, with a smooth rhythmic pace

Tone: Warm, lively, conversational

Emotional range: Expressive and dynamic, but still natural''',
    goal: '말인데 멜로디가 잘 들리는 영어. 너무 과장되지 않으면서 확실히 '
        '리드미컬하고 쉐도잉용으로 균형이 좋은 스타일.',
  ),
  P2VoiceStyle(
    id: 'style_sing_song_flow',
    label: 'Sing-Song Flow',
    instruction: '''
Accent: General American

Intonation: Strongly melodic, almost sing-song, with noticeable pitch movement and rhythmic phrasing

Speed: Medium-slow with clear rhythmic timing

Tone: Playful, bright, energetic

Emotional range: High and expressive, with lively pitch variation''',
    goal: '영어 억양을 몸으로 익히게 하는 훈련용 스타일. 실제 대화용 최종 '
        '발음보다는 리듬 연습 단계에 더 적합한 느낌.',
  ),
  P2VoiceStyle(
    id: 'style_groove_english',
    label: 'Groove English',
    instruction: '''
Accent: General American

Intonation: Rhythmic and punchy, with strong contrast between stressed and unstressed words

Speed: Medium, maintaining a steady conversational groove

Tone: Confident, relaxed, energetic

Emotional range: Moderately high, with expressive stress and pitch movement''',
    goal: "예: I REALLY didn't think / you'd COME this EARLY.\n"
        '처럼 강세 단어가 박자처럼 들리는 영어. 단어 하나하나의 발음보다 '
        '영어 특유의 강약과 리듬을 확실히 느끼게 하는 쉐도잉용 스타일.',
  ),
  P2VoiceStyle(
    id: 'style_story_melody',
    label: 'Story Melody',
    instruction: '''
Accent: General American

Intonation: Storytelling-style melodic intonation, with smooth pitch arcs and expressive phrase endings

Speed: Medium-slow

Tone: Warm, engaging, slightly dramatic

Emotional range: Rich but controlled''',
    goal: '이야기를 들려주듯 자연스럽게 음높이가 움직이는 스타일. 조금 긴 '
        '문장이나 Scenario Talk의 상황 영어에 잘 맞고, 과도한 연기 없이 문장 '
        '전체 흐름과 의미 단위가 자연스럽게 들려야 한다.',
  ),
  P2VoiceStyle(
    id: 'style_bounce_flow',
    label: 'Bounce & Flow',
    instruction: '''
Accent: General American

Intonation: Bouncy and highly rhythmic, with clear pitch movement and strong sentence stress

Speed: Medium-fast but easy to follow

Tone: Friendly, upbeat, confident

Emotional range: Energetic and expressive''',
    goal: '예: YOU know what? ↗ / I ACTually kinda LIKE it. ↘\n'
        '처럼 문장이 튕기듯 진행되는 느낌. 영어 초중급자가 따라 했을 때 단어 '
        '단위 발음보다 영어 특유의 강약, 리듬, sentence stress, pitch movement를 '
        '익힐 수 있는 스타일.',
  ),
  P2VoiceStyle(
    id: 'style_smooth_jazz',
    label: 'Smooth Jazz',
    instruction: '''
Accent: General American

Intonation: Smooth, melodic, and gently undulating

Speed: Medium

Tone: Relaxed, soft, conversational

Emotional range: Moderate, subtle, expressive''',
    goal: '노래처럼 과장하지 않고 매우 부드럽게 연결되는 스타일. 연음과 '
        '자연스러운 호흡을 연습하기 좋고, pitch 변화는 존재하지만 과장되지 '
        '않게 한다.',
  ),
];

/// Lab 전용 캐시 네임스페이스.
///
/// `TtsCache`의 두 번째 인자는 이름이 `voice`지만 실제로는 **네임스페이스
/// 문자열**로 쓰인다(실사용 P2도 `gpt-4o-mini-tts_unit_style_v6_$voice`처럼
/// 쓴다). 여기서는 `p2lab_` 접두어로 시작해, 실사용 P2 캐시 키와 문자열이
/// 절대 겹치지 않는다.
///
/// 샘플 문장은 `TtsCache._key`가 text를 해시에 이미 넣으므로 여기 넣지 않는다.
///
/// 예) `p2lab_gpt-4o-mini-tts_style_musical_natural_v1_nova`
String p2LabCacheNamespace(P2VoiceStyle style, String voice) =>
    'p2lab_${kP2LabTtsModel}_${style.id}_${kP2StyleInstructionVersion}_$voice';

/// Breath Analyzer 전용 네임스페이스. 위 mp3 캐시와 **완전히 다른 키**다.
///
/// `p2lab_wav_` 접두어로 시작하므로 mp3 쪽 키와 문자열이 겹칠 수 없다.
/// 기존 6×13 mp3 테스트 결과는 이 기능을 켜도 그대로 살아 있다.
///
/// ⚠️ 여기 저장되는 내용은 **WAV**인데 `TtsCache`가 파일 확장자를 `.mp3`로
/// 고정한다. 즉 `tts_cache/`를 직접 열어보면 `.mp3` 이름의 WAV가 보인다.
/// `TtsCache`는 확장자를 해석하지 않고 바이트만 다루므로 동작에는 문제가
/// 없다. 이 이유만으로 실사용이 의존하는 `TtsCache`를 뜯지 않는다.
String p2LabWavCacheNamespace(P2VoiceStyle style, String voice) =>
    'p2lab_wav_${kP2LabTtsModel}_${style.id}_${kP2StyleInstructionVersion}_$voice';
