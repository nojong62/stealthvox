// ====================================================================
// 🎙️ [SOCKET-PCM] 소켓 전사 갈래에서도 발화 소리를 남긴다
// --------------------------------------------------------------------
// 만능 통역의 기본 전사 갈래는 OpenAI 스트리밍 소켓이다
// (`kDuoInterpUseSocketStt`, 기본 켜짐). 그 갈래는 PCM을 소켓으로 흘려보내고
// **앱에 한 조각도 남기지 않는다** — 발화를 자르는 것이 서버라서 "이 발화의
// 소리"라는 덩이가 앱 손에 없었다.
//
// 그래서 이 갈래에서는 세 가지가 동시에 막혀 있었다.
//
//   · 로비 언어가 맞는지 **되들어 볼** 소리가 없다(origin probe)
//   · 통화가 끝난 뒤 **전체 소리로 History 원문을 다시 만들** 수 없다
//   · 잘못 들린 낱말을 소리로 재확인할 수 없다
//
// 이 클래스가 그 덩이를 만든다. 새 판정기를 만드는 것이 아니다 —
// **경계는 여전히 서버가 준다.** 서버가 "말이 시작됐다"고 하면 담기 시작하고,
// "발화가 확정됐다"고 하면 그 순간까지를 한 덩이로 내준다.
//
//   소켓 speech_started  → [beginSpeech]
//   소켓 committed(id)   → [commitSpeech] → 그 id를 단 PCM 한 덩이
//
// 🚪 **문(gate)이 이 클래스를 막지 않는다.** 문이 정하는 것은 "소켓으로 보낼
//   것인가"이고, 소리를 보존할 것인가는 문이 정하지 않는다. 문이 닫힌 동안에도
//   [addPcm]은 계속 받아 고리에 쌓는다.
//
// 🎧 **앞 여유가 핵심이다.** 서버의 `speech_started`는 왕복을 거쳐 오므로
//   언제나 소리보다 늦다. 그 사이의 첫 음절은 이미 지나갔고, 고리에 담아 둔
//   것이 그것을 되살린다. 담는 일도 상한도 전부 [DuoUtteranceCapture]가 이미
//   하던 것이라 여기서 다시 만들지 않는다.
// ====================================================================

import 'dart:typed_data';

import 'duo_utterance_capture.dart';
import 'pcm_audio_utils.dart';

/// 통화 한 통 = 이 객체 한 개.
class DuoSocketPcmCapture {
  DuoSocketPcmCapture({
    this.idPrefix = 'duo_interp',
    this.sampleRate = kStealthVoxSttSampleRate,
    this.onLog,
  }) : _capture = DuoUtteranceCapture(
          idPrefix: idPrefix,
          sampleRate: sampleRate,
        );

  final String idPrefix;
  final int sampleRate;
  final void Function(String tag, String msg)? onLog;

  final DuoUtteranceCapture _capture;

  int _committed = 0;
  int _dropped = 0;

  /// 지금 담는 중인가. 서버가 발화를 열어 둔 동안 참이다.
  bool get isCapturing => _capture.isCapturing;

  /// 고리에 들고 있는 앞소리 길이. 로그가 "앞을 얼마나 지켰나"를 말한다.
  int get preRollBufferedMs => _capture.preRollBufferedMs;

  int get committedCount => _committed;
  int get droppedCount => _dropped;

  /// 마이크 조각 하나. **문과 무관하게 언제나 받는다.**
  void addPcm(Uint8List pcm) => _capture.addPcm(pcm);

  /// 🚪 문이 닫혔다. 고리를 늘려 그 구간의 소리도 들고 있는다.
  void onGateClosed() => _capture.onGateClosed();

  /// 🚪 문이 열렸다. 고리를 평소 길이로 되돌린다.
  void onGateOpened() => _capture.onGateOpened();

  /// 서버가 말이 시작됐다고 했다. 고리를 발화 앞에 붙이고 담기 시작한다.
  void beginSpeech() {
    final String id = _capture.begin();
    onLog?.call('🎙️ [SOCKET-PCM]',
        'begin local=$id preRollMs=${_capture.preRollBufferedMs}');
  }

  /// 서버가 발화를 확정했다. 그때까지 담은 것을 한 덩이로 내준다.
  ///
  /// **돌려주는 덩이에는 서버가 준 [serverItemId]가 붙는다.** 히스토리의
  /// `pcm_key`와 창고의 열쇠가 그 값이라, 우리가 매긴 번호를 쓰면 나중에
  /// 그 소리를 찾을 수 없다.
  ///
  /// 담고 있지 않았거나 담긴 것이 없으면 **null이다** — 빈 덩이를 내보내면
  /// 전사기가 무음에서 문장을 지어낸다.
  DuoCapturedUtterance? commitSpeech(String serverItemId) {
    final DuoCapturedUtterance? raw = _capture.commit();
    if (raw == null || raw.isEmpty) {
      _dropped++;
      onLog?.call('🎙️ [SOCKET-PCM]',
          'commit_empty item=$serverItemId dropped=$_dropped');
      return null;
    }
    final String id = serverItemId.trim().isEmpty ? raw.utteranceId : serverItemId.trim();
    final out = DuoCapturedUtterance(
      utteranceId: id,
      pcm: raw.pcm,
      sampleRate: raw.sampleRate,
      preRollBytes: raw.preRollBytes,
      frames: raw.frames,
      maxFrameGapMs: raw.maxFrameGapMs,
    );
    _committed++;
    onLog?.call(
        '🎙️ [SOCKET-PCM]',
        'commit item=$id preRollMs=${out.preRollMs} bodyMs=${out.bodyMs} '
            'totalMs=${out.durationMs} frames=${out.frames} '
            'maxGapMs=${out.maxFrameGapMs} committed=$_committed');
    return out;
  }

  /// 담던 것을 버린다. **고리는 그대로 둔다** — 다음 발화의 앞 여유다.
  void abortSpeech(String reason) {
    if (!_capture.isCapturing) return;
    onLog?.call('🎙️ [SOCKET-PCM]', 'abort reason=$reason');
    _capture.abort();
  }

  /// 통화가 끝났다. 고리까지 비운다.
  void reset() {
    _capture.reset();
    onLog?.call('🎙️ [SOCKET-PCM]',
        'reset committed=$_committed dropped=$_dropped');
  }
}
