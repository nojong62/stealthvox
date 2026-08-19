// 🪜 [PRACTICE-REPLAY] 계단 하나의 유저 호흡들을 이어 한 벌로 만든다.
//
//   **이건 순수한 유저 녹음이 아니다.** 유저가 말하지 않았거나 너무 짧게
//   말한 호흡 자리에는 AI 호흡이 들어간다. 그래서 제품에서 `My Voice`라고
//   부르면 안 된다 — `Practice Replay`다.
//
//   유저 PCM과 AI PCM이 **같은 규격(24kHz·16bit·mono)** 이라 디코더도
//   인코더도 없이 바이트로 이어 붙인다.

import 'dart:typed_data';

import 'breath_segment.dart';
import 'pcm_audio_utils.dart';

/// 호흡 한 칸을 무엇으로 채웠는지. 화면 표시·로그용.
enum ReplaySource { user, aiNoSpeech, aiTooShort, aiMissing }

class PracticeReplay {
  const PracticeReplay({required this.pcm, required this.sources});

  final Uint8List pcm;

  /// 길이는 호흡 수와 같다. 어느 칸이 AI로 대체됐는지 그대로 남는다.
  final List<ReplaySource> sources;

  int get userCount =>
      sources.where((s) => s == ReplaySource.user).length;
  int get replacedCount => sources.length - userCount;
}

/// 🚧 유저 호흡을 살릴 최소 비율. **최종 정책값이 아니다.**
///
/// 유저가 낸 발성 길이가 그 호흡의 AI 길이에 비해 이 비율보다 짧으면
/// "말하다 만 것"으로 보고 AI 호흡으로 갈아 끼운다. 실기기에서 조정한다.
/// STT도 문장 일치 검사도 하지 않는다 — 목적은 채점이 아니라
/// **명백히 말하지 않은 칸을 빈칸으로 두지 않는 것**뿐이다.
const double kPracticeReplayMinUserRatio = 0.45;

/// 계단 하나의 Practice Replay를 조립한다.
///
/// [userPcm]과 [userVoicedMs]는 호흡 수와 길이가 같아야 하고, 유저 음성을
/// 못 받은 칸은 `null`/`0`이다.
PracticeReplay buildPracticeReplay({
  required Uint8List aiPcm,
  required List<BreathSegment> segments,
  required List<Uint8List?> userPcm,
  required List<int> userVoicedMs,
  double minUserRatio = kPracticeReplayMinUserRatio,
  int sampleRate = kStealthVoxSttSampleRate,
}) {
  final int bytesPerMs = sampleRate * 2 ~/ 1000;
  final chunks = <Uint8List>[];
  final sources = <ReplaySource>[];

  for (int i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final Uint8List? user = i < userPcm.length ? userPcm[i] : null;
    final int voicedMs = i < userVoicedMs.length ? userVoicedMs[i] : 0;

    ReplaySource source;
    if (user == null || user.isEmpty) {
      source = ReplaySource.aiMissing;
    } else if (voicedMs <= 0) {
      source = ReplaySource.aiNoSpeech;
    } else if (segment.durationMs > 0 &&
        voicedMs / segment.durationMs < minUserRatio) {
      source = ReplaySource.aiTooShort;
    } else {
      source = ReplaySource.user;
    }

    if (source == ReplaySource.user) {
      chunks.add(user!);
    } else {
      chunks.add(_sliceAi(aiPcm, segment, bytesPerMs));
    }
    sources.add(source);
  }

  int total = 0;
  for (final c in chunks) {
    total += c.length;
  }
  final out = Uint8List(total);
  int offset = 0;
  for (final c in chunks) {
    out.setRange(offset, offset + c.length, c);
    offset += c.length;
  }
  return PracticeReplay(pcm: out, sources: sources);
}

Uint8List _sliceAi(Uint8List pcm, BreathSegment segment, int bytesPerMs) {
  int start = (segment.startMs * bytesPerMs).clamp(0, pcm.length);
  int end = (segment.endMs * bytesPerMs).clamp(start, pcm.length);
  start -= start % 2;
  end -= end % 2;
  if (end <= start) return Uint8List(0);
  return Uint8List.sublistView(pcm, start, end);
}

/// 조립 결과를 재생 가능한 WAV로. 기존 `user_record_path`(DeviceFileSource)에
/// 그대로 물릴 수 있다.
Uint8List practiceReplayToWav(
  PracticeReplay replay, {
  int sampleRate = kStealthVoxSttSampleRate,
}) =>
    pcm16ToWav(replay.pcm, sampleRate: sampleRate);
