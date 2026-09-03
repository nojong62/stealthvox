// ====================================================================
// ⏱️ [INTERP-LATENCY] 상대 한 마디가 내 귀에 닿기까지를 구간별로 잰다
// --------------------------------------------------------------------
// 만능 통역의 병목은 **번역이 다 끝나야 TTS가 시작되는 직렬 구조**였다.
// 그걸 겹치게 바꾸는 작업이라, "정말 겹쳤는가"를 숫자로 봐야 한다.
//
//   incomingMessageReceived   Firestore에서 상대 원문을 받았다
//   translationRequestStart   번역을 물어보기 시작했다
//   firstTranslationDelta     번역 첫 글자가 왔다
//   firstTtsChunkCommitted    읽어도 되는 첫 구절이 확정됐다
//   firstTtsRequestStart      그 구절의 TTS를 요청했다
//   firstTtsAudioReady        TTS 첫 오디오가 도착했다
//   playbackStart             스피커에서 소리가 나기 시작했다   ← KPI
//   translationComplete       번역이 끝났다
//   lastPlaybackComplete      마지막 조각까지 다 나왔다
//
// **가장 중요한 값은 `incomingMessageReceived → playbackStart`다.**
// 나머지는 그 값이 나빠졌을 때 어디를 봐야 하는지 알려 주는 재료다.
//
// 겹침이 실제로 일어났는지는 `translationComplete`와 `playbackStart`의
// 앞뒤로 안다 — 재생이 번역보다 **먼저** 시작됐으면 겹친 것이다.
// ====================================================================

/// 한 턴(상대 발화 하나)의 시각표. 턴마다 새로 만든다.
class DuoInterpLatency {
  DuoInterpLatency({required this.turnId, required this.path})
      : incomingMessageReceived = DateTime.now();

  /// 로그에서 턴을 이어 보기 위한 값. TTS `turnId`와 같은 것을 쓴다.
  final String turnId;

  /// 'stream'(새 경로) 또는 'blocking'(기존 경로). A/B 비교의 기준이다.
  final String path;

  final DateTime incomingMessageReceived;

  DateTime? translationRequestStart;
  DateTime? firstTranslationDelta;
  DateTime? firstTtsChunkCommitted;
  DateTime? firstTtsRequestStart;
  DateTime? firstTtsAudioReady;
  DateTime? playbackStart;
  DateTime? translationComplete;
  DateTime? lastPlaybackComplete;

  /// 이 턴에 보낸 TTS 요청 수. 조각이 몇 개로 나뉘었는지가 곧 이 값이다.
  int ttsChunks = 0;

  /// 번역을 건너뛴 턴인가(상대가 이미 내 언어로 말함).
  bool sameLangSkip = false;

  /// 한 번만 찍는다. 두 번째 조각이 첫 조각의 값을 덮으면 안 된다.
  void markOnce(void Function() set, DateTime? current) {
    if (current != null) return;
    set();
  }

  int? _ms(DateTime? from, DateTime? to) =>
      (from == null || to == null) ? null : to.difference(from).inMilliseconds;

  /// 🎯 KPI — 상대 말이 도착하고 내 귀에 소리가 나기까지.
  int? get toPlaybackMs => _ms(incomingMessageReceived, playbackStart);

  int? get translateTtfbMs =>
      _ms(translationRequestStart, firstTranslationDelta);
  int? get deltaToChunkMs =>
      _ms(firstTranslationDelta, firstTtsChunkCommitted);
  int? get ttsTtfbMs => _ms(firstTtsRequestStart, firstTtsAudioReady);
  int? get translateTotalMs =>
      _ms(translationRequestStart, translationComplete);
  int? get totalMs => _ms(incomingMessageReceived, lastPlaybackComplete);

  /// 번역과 재생이 실제로 시간상 겹쳤는가.
  ///
  /// 재생이 번역 완료보다 **먼저** 시작했으면 겹친 것이다. 기존 경로에서는
  /// 정의상 항상 거짓이다(번역이 끝나야 TTS를 부르므로).
  bool get overlapped {
    final p = playbackStart;
    final t = translationComplete;
    if (p == null || t == null) return false;
    return p.isBefore(t);
  }

  /// 겹쳐서 아낀 시간(ms). 겹치지 않았으면 0.
  int get overlapMs {
    if (!overlapped) return 0;
    return translationComplete!.difference(playbackStart!).inMilliseconds;
  }

  /// 실기기 로그 한 줄. 오디오 내용도 전사문도 싣지 않는다 — 숫자뿐이다.
  String summary() => 'turn=$turnId path=$path '
      'toPlaybackMs=${toPlaybackMs ?? -1} '
      'translateTtfbMs=${translateTtfbMs ?? -1} '
      'deltaToChunkMs=${deltaToChunkMs ?? -1} '
      'ttsTtfbMs=${ttsTtfbMs ?? -1} '
      'translateTotalMs=${translateTotalMs ?? -1} '
      'totalMs=${totalMs ?? -1} '
      'ttsChunks=$ttsChunks overlapped=$overlapped overlapMs=$overlapMs '
      'sameLangSkip=$sameLangSkip';
}
