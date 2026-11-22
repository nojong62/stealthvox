// 🎵 P3(에코잉·쉐도잉) 낭독 스타일 정의.
//
//   여기 있는 건 **상수뿐이다.** 로직도 상태도 없다.
//   P2 Voice Lab(관리자 실험실)은 2026-11-22에 삭제했다. Lab 전용 상수
//   (샘플 문장·Voice 13종·6종 조합표·Lab 캐시 이름)도 함께 지웠다.
//   지금 남은 것은 P3가 캐시 이름을 만들 때 쓰는 스타일 id와 지시문 한 벌씩이다.

/// 낭독 스타일 한 벌.
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

  /// 낭독 지시 본문. 지금 P3는 이 지시문을 소리 요청에 싣지 않고, 캐시 이름을
  /// 만드는 `id`만 쓴다(Chirp·Gemini 경로는 `instructions`를 받지 않는다).
  final String instruction;

  /// 이 스타일로 무엇을 노리는지(한국어). API로는 가지 않는다.
  final String goal;
}

/// 🔖 instruction 문구를 고치면 **반드시 이 값을 올린다.**
///
/// 안 올리면 캐시 키가 그대로라 예전 지시로 만든 소리가 그대로 나오고,
/// 화면에서는 새 지시가 먹은 것처럼 보인다. 그 상태는 귀로 구분되지 않는다.
const String kP2StyleInstructionVersion = 'v1';

/// 🎵 P3 에코잉이 쓰는 낭독 패턴 — Sing-Song Flow.
///
/// 실사용 P3가 **고정으로** 쓰는 한 벌이다. id가 쉐도잉 스타일과 달라
/// 캐시 칸도 따로 선다.
///
/// 문구를 고치면 [kP2StyleInstructionVersion]이 아니라 이 id 뒤에 세대를
/// 붙여 올린다 — 버전을 올리면 다른 스타일의 캐시까지 통째로 미아가 된다.
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

/// 🎭 P3 쉐도잉이 쓰는 낭독 패턴 — Story Melody.
///
/// 에코잉([kP3SpeakingStyle])과 다른 한 벌이다. 끊어 따라 하는 연습과 겹쳐
/// 말하는 연습은 필요한 읽기가 다르다 — 쉐도잉은 구절 사이를 벌리지 않고
/// 이어서 읽어야 얹어 말할 수 있다.
const P2VoiceStyle kP3ShadowingStyle = P2VoiceStyle(
  id: 'style_story_melody_p3',
  label: 'Story Melody',
  instruction: '''
Speak in a warm, clear General American accent, like a friendly teacher helping a teenage English learner practice by saying, "Listen to me, then say it the same way."

Use natural storytelling-style intonation with smooth rises and falls in pitch. Let each phrase have a gentle melodic shape, with expressive but controlled endings.

Speak slightly slower than normal conversation, at an easy shadowing pace. Leave enough space inside each phrase for the learner to clearly hear the rhythm, stress, and pronunciation, but do not add long pauses between phrases.

Gently emphasize the important words and let the smaller words flow naturally around them. Keep the rhythm smooth and connected, so the learner can imitate the whole phrase rather than pronounce each word separately.

Use a warm, encouraging, engaging tone, with a little dramatic expression as if telling an interesting story. Keep the emotion rich but controlled.

Make the pronunciation very clear and natural. Do not rush, mumble, exaggerate individual sounds, or sound childish. The goal is to make a teenage learner want to immediately copy the speaker's rhythm, melody, and phrasing.''',
  goal: '이야기하듯 이어 읽어 통째로 얹어 말하게 하는 쉐도잉용. 구절 안에는 '
      '들을 자리를 주되 구절 사이는 벌리지 않는다.',
);
