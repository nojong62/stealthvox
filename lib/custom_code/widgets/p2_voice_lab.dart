// 🔬 [P2-VOICE-LAB] 관리자 전용 P2 음성 실험실.
//
//   Style 6종 × Voice 13종 = 78조합을 **같은 한 문장**으로 만들어 듣고
//   비교한다. 여기서 고른 조합이 나중에 공식 P2 Pattern이 된다.
//
//   ⚠️ **이 파일은 실사용 P2에 아무것도 하지 않는다.** TTS 호출도 캐시도
//   전부 이 파일 안에서 끝나고, `chat_history_master.dart`의 상태나 캐시
//   네임스페이스를 공유하지 않는다.
//
//   ⚠️ **일반 route가 아니다.** `nav.dart`/`index.dart`에 등록하지 않는다.
//   여는 길은 Lobby 'StealthVox' 3초 롱프레스 하나뿐이고, 딥링크·URL·
//   `pushNamed`로는 닿을 수 없다.
//
//   과금: [BillingIdleMixin]을 **일부러 쓰지 않는다.** 관리자 실험 시간은
//   차감 대상이 아니다.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '/custom_code/services/admin_gate.dart';
import '/custom_code/services/audio_silence_analyzer.dart';
import '/custom_code/services/breath_segment.dart';
import '/custom_code/services/p2_voice_styles.dart';
import '/custom_code/services/pcm_audio_utils.dart'
    show kStealthVoxSttSampleRate, pcm16ToWav;
import 'routine_mode_roleplay.dart' show TtsCache;

// ── 색 ────────────────────────────────────────────────────────────────
const Color _kLabBg = Color(0xFF121212);
const Color _kLabSurface = Color(0xFF1C1C1C);
const Color _kLabDropdownBg = Color(0xFF232323);
const Color _kLabBorder = Color(0x22FFFFFF);
const Color _kLabAccent = Colors.amber;
const Color _kLabDanger = Color(0xFFFF6B6B);
const Color _kLabBreath = Color(0xFF7DD3FC);

/// TTS 한 번의 결과. 성공이면 [audio], 실패면 [error]에 원인이 그대로 담긴다.
class _LabTtsResult {
  const _LabTtsResult({this.audio, this.error, required this.fromCache});

  final Uint8List? audio;

  /// 관리자에게 **가공 없이** 보여줄 실패 원문(status code + response body 등).
  final String? error;

  /// 캐시에서 꺼냈는가(= API를 부르지 않았는가).
  final bool fromCache;

  bool get ok => audio != null;
}

/// 최근 테스트 조합 한 줄.
class _LabCombo {
  const _LabCombo(this.styleId, this.voice);

  final String styleId;
  final String voice;

  String get key => '$styleId|$voice';

  @override
  bool operator ==(Object other) => other is _LabCombo && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

enum _LabStatus {
  idle,
  generating,
  playing,
  ready,
  error,
  recording,
  recordReady,
}

class P2VoiceLabPage extends StatefulWidget {
  const P2VoiceLabPage({super.key});

  @override
  State<P2VoiceLabPage> createState() => _P2VoiceLabPageState();
}

class _P2VoiceLabPageState extends State<P2VoiceLabPage> {
  // ── 선택 상태 ──────────────────────────────────────────────────────
  P2VoiceStyle _style = kP2VoiceStyles.first;
  String _voice = kP2LabVoices.first;
  bool _instructionExpanded = true;

  // ── 실행 상태 ──────────────────────────────────────────────────────
  _LabStatus _status = _LabStatus.idle;
  String? _error;
  String? _lastNote; // 'cache hit' 같은 짧은 안내

  // ── 오디오 ────────────────────────────────────────────────────────
  AudioPlayer? _player;
  StreamSubscription<void>? _completeSub;

  // ── 중복 요청 방지 ─────────────────────────────────────────────────
  //   같은 조합이 이미 날아가 있으면 **그 Future를 그대로 돌려준다.**
  //   실사용 P2의 `_meaningUnitTtsInFlight`와 같은 패턴이되, 상태는
  //   공유하지 않는 이 화면만의 것이다.
  final Map<String, Future<_LabTtsResult>> _inFlight =
      <String, Future<_LabTtsResult>>{};

  /// 조합별 캐시 보유 여부(확인된 것만). 화면의 `cached` 표시에 쓴다.
  final Map<String, bool> _cacheProbe = <String, bool>{};

  /// 최근 테스트 조합. 최신이 앞, 최대 8개. **화면에 있는 동안만 유지한다.**
  final List<_LabCombo> _recent = <_LabCombo>[];
  static const int _kRecentMax = 8;

  String _apiKey = '';
  bool _apiKeyLoaded = false;

  // ── Breath Analyzer ───────────────────────────────────────────────
  /// 분석에 쓰는 WAV 원본. Full Play가 이걸 그대로 재생한다.
  Uint8List? _analysisWav;

  /// 위 WAV의 본문(raw PCM). slice와 분석이 이 오프셋을 쓴다.
  Uint8List? _analysisPcm;

  BreathAnalysis? _analysis;
  bool _analyzing = false;
  int? _playingSegmentIndex;

  /// 🔒 **화면의 분석 결과가 어느 조합에서 나왔는지.**
  ///
  /// 패널은 현재 dropdown 값이 아니라 **이 값을 표시한다.** marin 결과가
  /// 남은 채 echo를 고르면 marin 숫자가 echo 것처럼 보이는 사고가 이번
  /// 비교에서 가장 위험한데, 표시원을 분석 시점 값으로 못박으면 라벨이
  /// 거짓말을 할 수 없다. 여기에 더해 Style/Voice가 바뀌면 결과를 통째로
  /// 버린다([_invalidateAnalysis]).
  String? _analyzedStyleId;
  String? _analyzedVoice;

  /// 현재 선택과 화면의 분석 결과가 어긋났는가. 정상 흐름에서는 늘 false다.
  bool get _analysisStale =>
      _analysis != null &&
      (_analyzedStyleId != _style.id || _analyzedVoice != _voice);

  /// 🚧 Phase 1 tuning defaults — **최종 Breath 정책이 아니다.**
  /// 실제 Smooth Jazz PCM을 듣고 정한다.
  BreathAnalysisConfig _cfg = const BreathAnalysisConfig();

  /// player complete → recorder.start() 실측(ms).
  int? _micLatencyMs;
  bool _probing = false;

  // ── Echo / Shadow ─────────────────────────────────────────────────
  /// 🚧 Lab 실험값. 최종 제품 정책이 아니다.
  /// 후보는 +300 / +500 / +700 / +900. 실기기에서 말해보고 정한다.
  int _gapMs = 500;

  /// Lab 전용 recorder. **`appAudioRecorder`(chat_history_master 소유)를
  /// 건드리지 않는다.** 이 화면이 만들고 이 화면이 닫는다.
  AudioRecorder? _labRecorder;

  /// 녹음은 어느 시점에도 하나만. 중복 start를 막는다.
  bool _recording = false;

  /// Echo와 Shadow를 **따로 보관한다.** 한 파일을 덮어쓰면 둘을 같은 조건에서
  /// 비교할 수 없다(한쪽을 들으려면 다른 쪽을 다시 녹음해야 한다).
  String? _echoRecordPath;
  String? _shadowRecordPath;

  /// 진행 중인 Echo/Shadow 회차. STOP·Voice 변경이 이 값을 올려 취소한다.
  int _echoShadowGeneration = 0;

  Timer? _silenceTimer;
  bool _hasSpoken = false;
  int _silenceTicks = 0;

  /// 🚧 Lab 테스트용. 앱이 이미 쓰는 값을 그대로 가져왔다
  /// (`_startAutoVADRecording`: 100ms 폴링 · -25dBFS · 무음 15틱).
  /// **P3 실사용 final recording 값으로 확정된 것이 아니다** — 긴 문장 중간에
  /// 생각하느라 쉬는 사용자가 있어서, Phase 4에서 따로 잡아야 한다.
  static const double _kSpeechDbfs = -25.0;
  static const int _kSilenceTicksToStop = 15; // 1,500ms
  static const int _kNoSpeechTicksToGiveUp = 100; // 10s (Lab 안전장치)

  // ── Auth 감시 ─────────────────────────────────────────────────────
  /// 🔐 로그아웃·계정 전환을 **기다리지 않고 곧바로** 받기 위한 구독.
  ///
  /// `AdminGate.isAdmin`은 그냥 getter라서, [build]의 재검사만으로는
  /// 이 화면이 스스로 setState를 부를 때까지 아무 일도 일어나지 않는다.
  /// 즉 로그아웃한 뒤 화면을 건드리지 않으면 내용이 그대로 남는다.
  /// 그래서 Auth 변화를 직접 듣는다.
  ///
  /// 기존 Auth 구조는 건드리지 않는다 — `authenticatedUserStream`
  /// (auth_util.dart)은 Firestore 문서까지 딸려 오는 스트림이라 여기에는
  /// 과하다. 우리가 알아야 할 건 uid 하나뿐이다.
  ///
  /// ⚠️ **경계.** 이 스트림이 알려주는 건 *이 클라이언트*의 로그인/로그아웃과
  /// 계정 전환뿐이다. 서버에서 refresh token을 revoke해도 그 순간 이벤트가
  /// 오지 않는다(토큰 재발급·검증 시점에야 드러난다). 즉시 차단이 필요한
  /// 것은 앱 안에서 일어나는 logout·account switch이고, 이 가드는 거기까지다.
  StreamSubscription<User?>? _authSub;

  /// 이미 닫는 중인가. Auth 변화와 뒤로가기가 겹쳐 두 번 pop 되면 로비까지
  /// 함께 닫힌다. 닫기는 한 번뿐이어야 한다.
  bool _closing = false;

  // ══════════════════════════════════════════════════════════════════
  // 권한 가드
  // ══════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    // 🔐 페이지 자체 가드. 롱프레스를 거치지 않고 이 위젯이 직접 만들어져도
    //   여기서 되돌아간다. 메시지는 남기지 않는다 — 기능의 존재 자체를
    //   알리지 않는 것이 요건이다.
    if (!AdminGate.isAdmin) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    // 관리자로 들어왔을 때만 구독한다. 위에서 돌아간 경우는 이미 닫히는
    // 중이라 들을 것이 없다.
    _authSub = FirebaseAuth.instance.authStateChanges().listen(
          _onAuthChanged,
          onError: (_) => _onAuthChanged(null),
        );
    unawaited(_loadApiKey());
    unawaited(_probeCache(_style, _voice));
  }

  /// 로그아웃·계정 전환이 오면 **소리부터 끊고 화면을 닫는다.**
  ///
  /// 구독 직후 현재 사용자가 한 번 흘러나오는데, 그때는 아직 관리자이므로
  /// 아무 일도 일어나지 않는다.
  void _onAuthChanged(User? _) {
    if (!mounted || _closing) return;
    if (AdminGate.isAdmin) return;
    _closing = true;
    unawaited(_stopPlayback());
    // build()가 곧바로 빈 화면을 그리게 한 뒤 닫는다. pop이 한 프레임
    // 늦더라도 그사이에 내용이 보이지 않는다.
    setState(() {});
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    // ⚠️ 구독을 여기서 반드시 끊는다. 안 끊으면 화면이 사라진 뒤에도
    //   콜백이 살아 남아 죽은 State를 건드린다.
    _authSub?.cancel();
    _authSub = null;
    _completeSub?.cancel();
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final player = _player;
    _player = null;
    if (player != null) {
      unawaited(player.stop().catchError((_) {}));
      unawaited(player.dispose().catchError((_) {}));
    }
    // Lab이 만든 recorder는 Lab이 닫는다. 임시 녹음도 남기지 않는다.
    final recorder = _labRecorder;
    _labRecorder = null;
    _recording = false;
    if (recorder != null) {
      unawaited(recorder.stop().then((_) {}).catchError((_) {}));
      unawaited(recorder.dispose().then((_) {}).catchError((_) {}));
    }
    _deleteRecordings();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════
  // API 키
  // ══════════════════════════════════════════════════════════════════

  Future<void> _loadApiKey() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.fetchAndActivate();
      if (!mounted) return;
      setState(() {
        _apiKey = rc.getString('OpenAIAPIKey');
        _apiKeyLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _apiKeyLoaded = true;
        _error = 'Remote Config 실패: $e';
        _status = _LabStatus.error;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // TTS — 캐시 → API → 캐시 저장
  // ══════════════════════════════════════════════════════════════════

  /// 캐시에 있는지만 본다. 화면의 `cached` 배지용.
  Future<void> _probeCache(P2VoiceStyle style, String voice) async {
    final ns = p2LabCacheNamespace(style, voice);
    if (_cacheProbe.containsKey(ns)) return;
    final hit = await TtsCache.get(kP2LabSampleSentence, ns);
    if (!mounted) return;
    setState(() => _cacheProbe[ns] = hit != null && hit.isNotEmpty);
  }

  /// 조합 하나를 확보한다. **캐시 히트면 API를 부르지 않는다.**
  ///
  /// 같은 조합이 이미 진행 중이면 그 Future를 그대로 돌려줘, Generate를
  /// 연타해도 요청이 하나만 나간다.
  Future<_LabTtsResult> _obtain(P2VoiceStyle style, String voice) {
    final ns = p2LabCacheNamespace(style, voice);
    final existing = _inFlight[ns];
    if (existing != null) return existing;

    final future = () async {
      final cached = await TtsCache.get(kP2LabSampleSentence, ns);
      if (cached != null && cached.isNotEmpty) {
        return _LabTtsResult(audio: cached, fromCache: true);
      }
      final fresh = await _postTts(style, voice);
      if (fresh.ok) {
        await TtsCache.put(kP2LabSampleSentence, ns, fresh.audio!);
      }
      return fresh;
    }();

    _inFlight[ns] = future;
    future.whenComplete(() => _inFlight.remove(ns));
    return future;
  }

  /// Breath 분석용 **WAV**를 확보한다. mp3 경로와 캐시가 완전히 갈린다.
  ///
  /// OpenAI가 주는 건 헤더 없는 raw PCM16(24kHz·mono)이라, 그대로 두면
  /// 재생할 수 없다. `pcm16ToWav`로 한 번 감싸 캐시에 넣으면 Full Play는
  /// 바이트를 그대로 쓰고, 분석·slice는 헤더 44바이트만 건너뛰면 된다.
  Future<_LabTtsResult> _obtainWav(P2VoiceStyle style, String voice) {
    final ns = p2LabWavCacheNamespace(style, voice);
    final existing = _inFlight[ns];
    if (existing != null) return existing;

    final future = () async {
      final cached = await TtsCache.get(kP2LabSampleSentence, ns);
      if (cached != null && cached.isNotEmpty) {
        return _LabTtsResult(audio: cached, fromCache: true);
      }
      final fresh = await _postTts(style, voice, responseFormat: 'pcm');
      if (!fresh.ok) return fresh;
      final wav = pcm16ToWav(
        fresh.audio!,
        sampleRate: kStealthVoxSttSampleRate,
      );
      await TtsCache.put(kP2LabSampleSentence, ns, wav);
      return _LabTtsResult(audio: wav, fromCache: false);
    }();

    _inFlight[ns] = future;
    future.whenComplete(() => _inFlight.remove(ns));
    return future;
  }

  /// OpenAI `/v1/audio/speech` 직접 호출.
  ///
  /// body는 실사용 P2(`_fetchOpenAITTSInternal`)와 같은 모양이다. 다른 점은
  /// **둘뿐이고, 둘 다 Lab이라서 그렇다**:
  ///   · timeout 10초 → 30초 (긴 문장 + 무거운 지시는 10초를 넘길 수 있다)
  ///   · 실패를 null로 삼키지 않고 status/body를 그대로 올려보낸다
  /// [responseFormat]만 다르면 mp3 경로와 PCM 경로가 같은 함수를 쓴다.
  /// 기본값이 `'mp3'`라 기존 GENERATE & PLAY의 동작은 그대로다.
  Future<_LabTtsResult> _postTts(
    P2VoiceStyle style,
    String voice, {
    String responseFormat = 'mp3',
  }) async {
    if (_apiKey.trim().isEmpty) {
      return const _LabTtsResult(
        error: 'OpenAI API key 없음 (Remote Config `OpenAIAPIKey`가 비어 있다)',
        fromCache: false,
      );
    }
    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/audio/speech'),
            headers: <String, String>{
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'model': kP2LabTtsModel,
              'input': kP2LabSampleSentence,
              'voice': voice,
              'response_format': responseFormat,
              // 선택한 Style의 **전체 지시문**이 여기로 그대로 간다.
              'instructions': style.instruction,
              // speed는 넣지 않는다 — gpt-4o-mini-tts는 무시한다.
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('[P2-LAB] style=${style.id} voice=$voice '
          'model=$kP2LabTtsModel fmt=$responseFormat '
          'status=${response.statusCode} bytes=${response.bodyBytes.length}');

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return _LabTtsResult(audio: response.bodyBytes, fromCache: false);
      }
      // 200이 아니면 body에 이유가 들어 있다. 잘라내지 않고 그대로 보여준다.
      //
      // ⚠️ PCM이 400을 내더라도 **다른 모델이나 mp3로 몰래 바꾸지 않는다.**
      //   tts-1은 instructions를 무시하므로 Smooth Jazz가 성립하지 않는다.
      //   실패는 실패대로 관리자에게 보이고 거기서 멈춘다.
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      return _LabTtsResult(
        error: 'TTS ${response.statusCode} — voice="$voice" fmt=$responseFormat'
            '\n$body',
        fromCache: false,
      );
    } on TimeoutException {
      return const _LabTtsResult(
        error: 'TTS timeout (30초 초과)',
        fromCache: false,
      );
    } catch (e) {
      return _LabTtsResult(error: 'TTS 호출 실패: $e', fromCache: false);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 재생 — 한 번에 하나만
  // ══════════════════════════════════════════════════════════════════

  /// 돌고 있는 소리를 **반드시 먼저 끊는다.** 겹쳐 들리면 비교가 무의미하다.
  Future<void> _stopPlayback() async {
    await _completeSub?.cancel();
    _completeSub = null;
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  Future<void> _play(Uint8List audio) async {
    await _stopPlayback();
    final player = AudioPlayer();
    _player = player;
    _completeSub = player.onPlayerComplete.listen((_) {
      if (!mounted || _player != player) return;
      unawaited(_stopPlayback());
      setState(() => _status = _LabStatus.ready);
    });
    try {
      await player.play(BytesSource(audio));
      if (!mounted) return;
      setState(() => _status = _LabStatus.playing);
    } catch (e) {
      await _stopPlayback();
      if (!mounted) return;
      setState(() {
        _status = _LabStatus.error;
        _error = 'playback 실패: $e';
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 동작
  // ══════════════════════════════════════════════════════════════════

  Future<void> _generateAndPlay(P2VoiceStyle style, String voice) async {
    await _stopPlayback();
    if (!mounted) return;
    setState(() {
      _status = _LabStatus.generating;
      _error = null;
      _lastNote = null;
    });

    final result = await _obtain(style, voice);
    if (!mounted) return;

    final ns = p2LabCacheNamespace(style, voice);
    if (!result.ok) {
      setState(() {
        _status = _LabStatus.error;
        _error = result.error;
      });
      return;
    }

    setState(() {
      _cacheProbe[ns] = true;
      _lastNote = result.fromCache ? 'cache hit — API 호출 안 함' : 'API 생성 완료';
      _pushRecent(_LabCombo(style.id, voice));
    });
    await _play(result.audio!);
  }

  // ══════════════════════════════════════════════════════════════════
  // Breath Analyzer
  // ══════════════════════════════════════════════════════════════════

  /// PCM 확보 → 무음 분석. **API는 여기서만 호출될 수 있다.**
  Future<void> _analyzeBreath(P2VoiceStyle style, String voice) async {
    await _stopPlayback();
    if (!mounted) return;
    setState(() {
      _analyzing = true;
      _error = null;
      _lastNote = null;
      _playingSegmentIndex = null;
    });

    final result = await _obtainWav(style, voice);
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _analyzing = false;
        _status = _LabStatus.error;
        _error = result.error;
      });
      return;
    }

    final wav = result.audio!;
    final pcm = pcmFromWav(wav);
    setState(() {
      _analysisWav = wav;
      _analysisPcm = pcm;
      // 🔒 분석 시점의 조합을 함께 못박는다. 패널은 이 값을 표시한다.
      _analyzedStyleId = style.id;
      _analyzedVoice = voice;
      _analysis = analyzeBreaths(pcm, _cfg);
      _analyzing = false;
      _status = _LabStatus.ready;
      _cacheProbe[p2LabWavCacheNamespace(style, voice)] = true;
      _lastNote = result.fromCache
          ? 'PCM cache hit — API 호출 안 함'
          : 'PCM ${(wav.length / 1024).round()}KB 생성';
    });
  }

  /// Breath 테스트 기본 조합으로 한 번에 맞춘다.
  ///
  /// Style은 **Smooth Jazz 고정**이고 Voice만 갈아 끼운다 — Phase 1의 목적이
  /// "같은 instruction에서 Voice가 만드는 호흡 차이"를 보는 것이라, Style이
  /// 섞이면 비교가 성립하지 않는다. 13 Voice dropdown과 6 Style dropdown은
  /// 그대로 살아 있다.
  void _selectBreathTestVoice(String voice) {
    final style = kP2VoiceStyles.firstWhere(
      (s) => s.id == kP2BreathTestStyleId,
      orElse: () => _style,
    );
    setState(() {
      _style = style;
      _voice = voice;
      _status = _LabStatus.idle;
      _error = null;
      _lastNote = null;
      _invalidateAnalysis();
    });
    unawaited(_stopPlayback());
    unawaited(_probeCache(style, voice));
    unawaited(_probeWavCache(style, voice));
  }

  /// 이 조합의 PCM이 이미 캐시에 있는지. 눌러보기 전에 API 비용이 드는지
  /// 알 수 있게 한다.
  Future<void> _probeWavCache(P2VoiceStyle style, String voice) async {
    final ns = p2LabWavCacheNamespace(style, voice);
    if (_cacheProbe.containsKey(ns)) return;
    final hit = await TtsCache.get(kP2LabSampleSentence, ns);
    if (!mounted) return;
    setState(() => _cacheProbe[ns] = hit != null && hit.isNotEmpty);
  }

  /// threshold를 바꿨을 때. **이미 받아 둔 PCM만 다시 분석한다 — API 없음.**
  ///
  /// 이 함수 안에 네트워크 호출이 없다는 것이 그 근거다. `_obtainWav`도
  /// `_postTts`도 부르지 않는다.
  void _reanalyze(BreathAnalysisConfig next) {
    final pcm = _analysisPcm;
    setState(() {
      _cfg = next;
      if (pcm != null) _analysis = analyzeBreaths(pcm, next);
    });
  }

  /// 재생이 끝날 때까지 기다린다.
  ///
  /// ⚠️ **`onPlayerComplete.first`를 쓰면 안 된다.** 플레이어를 dispose하면
  /// 그 스트림이 *아무것도 내보내지 않고* 닫히는데, 그때 `first`는
  /// `Bad state: No element`를 던진다. 그 예외가 try 밖으로 새어 나가면
  /// 대기 사슬이 통째로 무너진다 — 9.15초짜리 FULL SHADOW가 1초 만에
  /// 끝나던 원인이 이것이었다(2026-08-20 실기기 로그로 확인).
  ///
  /// 구독을 직접 들고 `finally`에서 취소하면, 중간에 STOP을 눌러 dispose가
  /// 나도 `onDone`으로 조용히 풀린다.
  Future<void> _awaitPlayback(AudioPlayer player, Duration limit) async {
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    final sub = player.onPlayerComplete.listen(
      (_) => finish(),
      onDone: finish,
      onError: (Object _) => finish(),
      cancelOnError: false,
    );
    try {
      await completer.future.timeout(limit, onTimeout: finish);
    } finally {
      await sub.cancel();
    }
  }

  /// 바이트를 재생하고 **끝날 때까지 기다린다.** 순차 재생·probe가 쓴다.
  Future<void> _playBytesAwait(Uint8List bytes, {int expectedMs = 0}) async {
    await _stopPlayback();
    final player = AudioPlayer();
    _player = player;
    try {
      await player.play(BytesSource(bytes));
      await _awaitPlayback(
          player, Duration(milliseconds: expectedMs + 5000));
    } catch (e) {
      debugPrint('[P2-LAB] segment play $e');
    }
    if (identical(_player, player)) _player = null;
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }

  Future<void> _playSegment(int index) async {
    final pcm = _analysisPcm;
    final analysis = _analysis;
    if (pcm == null || analysis == null) return;
    if (index < 0 || index >= analysis.segments.length) return;
    final segment = analysis.segments[index];
    setState(() => _playingSegmentIndex = index);
    await _playBytesAwait(
      sliceToWav(pcm, segment, sampleRate: kStealthVoxSttSampleRate),
      expectedMs: segment.durationMs,
    );
    if (!mounted) return;
    setState(() => _playingSegmentIndex = null);
  }

  Future<void> _playFull() async {
    final wav = _analysisWav;
    final analysis = _analysis;
    if (wav == null) return;
    setState(() => _playingSegmentIndex = -1);
    await _playBytesAwait(wav, expectedMs: analysis?.totalMs ?? 0);
    if (!mounted) return;
    setState(() => _playingSegmentIndex = null);
  }

  /// 관리자 검증용 순차 재생. **실제 P2/P3 UX가 아니다** — 경계가 자연스러운지
  /// 귀로 확인하는 도구다.
  Future<void> _playAllSequential() async {
    final analysis = _analysis;
    if (analysis == null) return;
    for (int i = 0; i < analysis.segments.length; i++) {
      if (!mounted) return;
      await _playSegment(i);
      if (!mounted) return;
    }
  }

  /// 🎤 player complete → recorder.start() 실측.
  ///
  /// **Echo 엔진이 아니다.** 유저 음성을 쓰지도 남기지도 않는다. 권한과 임시
  /// 디렉터리를 미리 잡아 두고, 순수한 player→recorder 전환 시간만 잰다.
  /// 측정이 끝나면 recorder를 즉시 닫고 파일도 지운다.
  Future<void> _runMicLatencyProbe() async {
    final pcm = _analysisPcm;
    final analysis = _analysis;
    if (pcm == null || analysis == null || analysis.segments.isEmpty) return;

    setState(() {
      _probing = true;
      _micLatencyMs = null;
      _error = null;
    });

    final recorder = AudioRecorder();
    String? path;
    try {
      // 전환 시간에 권한·디렉터리 조회가 섞이지 않게 **미리** 끝내 둔다.
      if (!await recorder.hasPermission()) {
        if (!mounted) return;
        setState(() {
          _probing = false;
          _status = _LabStatus.error;
          _error = '마이크 권한 없음 — probe를 실행할 수 없다';
        });
        return;
      }
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/p2lab_probe_'
          '${DateTime.now().millisecondsSinceEpoch}.m4a';

      final segment = analysis.segments.first;
      await _playBytesAwait(
        sliceToWav(pcm, segment, sampleRate: kStealthVoxSttSampleRate),
        expectedMs: segment.durationMs,
      );

      // ── 여기부터가 측정 구간이다 ──
      final watch = Stopwatch()..start();
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      watch.stop();
      // ── 측정 끝 ──

      final elapsed = watch.elapsedMilliseconds;
      debugPrint('[P2-LAB] mic start latency = ${elapsed}ms');
      if (mounted) setState(() => _micLatencyMs = elapsed);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _LabStatus.error;
          _error = 'probe 실패: $e';
        });
      }
    } finally {
      try {
        await recorder.stop();
      } catch (_) {}
      try {
        await recorder.dispose();
      } catch (_) {}
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _probing = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // Echo / Shadow
  // ══════════════════════════════════════════════════════════════════

  /// Lab 전용 recorder를 확보한다. 권한이 없으면 null.
  Future<AudioRecorder?> _ensureRecorder() async {
    final existing = _labRecorder;
    if (existing != null) return existing;
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        await recorder.dispose();
        if (mounted) {
          setState(() {
            _status = _LabStatus.error;
            _error = '마이크 권한 없음 — Echo/Shadow 녹음을 할 수 없다';
          });
        }
        return null;
      }
    } catch (e) {
      try {
        await recorder.dispose();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _status = _LabStatus.error;
          _error = 'recorder 초기화 실패: $e';
        });
      }
      return null;
    }
    _labRecorder = recorder;
    return recorder;
  }

  Future<String?> _startLabRecording(String tag) async {
    if (_recording) return null;
    final recorder = await _ensureRecorder();
    if (recorder == null) return null;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/p2lab_${tag}_'
          '${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _recording = true;
      return path;
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _LabStatus.error;
          _error = '녹음 시작 실패: $e';
        });
      }
      return null;
    }
  }

  /// 녹음을 닫고 실제 파일 경로를 돌려준다.
  Future<String?> _stopLabRecording() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    if (!_recording) return null;
    _recording = false;
    try {
      return await _labRecorder?.stop();
    } catch (_) {
      return null;
    }
  }

  /// 유저 발화 종료 감시. 앱의 기존 VAD와 같은 판정식이다.
  ///
  /// [onDone]의 `spoke`가 false면 **한 번도 발화가 감지되지 않은 것**이다.
  /// 그 결과물은 무음(또는 스피커 잔향)뿐이라 녹음으로 취급하면 안 된다.
  void _watchUserSilence(
    int generation,
    void Function(String? path, bool spoke) onDone,
  ) {
    _hasSpoken = false;
    _silenceTicks = 0;
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(const Duration(milliseconds: 100),
        (timer) async {
      if (!mounted || generation != _echoShadowGeneration || !_recording) {
        timer.cancel();
        return;
      }
      final recorder = _labRecorder;
      if (recorder == null) {
        timer.cancel();
        return;
      }
      try {
        if (!await recorder.isRecording()) {
          timer.cancel();
          return;
        }
        final amp = await recorder.getAmplitude();
        if (amp.current > _kSpeechDbfs) {
          _hasSpoken = true;
          _silenceTicks = 0;
          return;
        }
        _silenceTicks++;
        final bool done = _hasSpoken
            ? _silenceTicks >= _kSilenceTicksToStop
            : _silenceTicks >= _kNoSpeechTicksToGiveUp;
        if (done) {
          timer.cancel();
          final spoke = _hasSpoken;
          final path = await _stopLabRecording();
          if (!mounted || generation != _echoShadowGeneration) return;
          onDone(path, spoke);
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }

  /// ② FULL ECHO — AI가 **전부 끝난 뒤** 유저가 혼자 말한다.
  ///
  /// 여백은 원본 그대로다(gap 조작 없음). AI 재생 완료와 recorder.start()
  /// 사이에 **고정 대기를 두지 않는다** — mic start latency가 32ms라
  /// "듣고 바로 말하기"를 지연시킬 이유가 없다. 실기기 녹음에 스피커 잔향이
  /// 섞이는 것이 확인되면 그때 guard delay를 넣고 측정값을 보고한다.
  Future<void> _runFullEcho() async {
    final wav = _analysisWav;
    final analysis = _analysis;
    if (wav == null || analysis == null) return;

    final generation = ++_echoShadowGeneration;
    await _stopPlayback();
    await _stopLabRecording();
    if (!mounted || generation != _echoShadowGeneration) return;
    setState(() {
      _status = _LabStatus.playing;
      _error = null;
      _lastNote = 'FULL ECHO · AI 재생 중';
    });

    await _playBytesAwait(wav, expectedMs: analysis.totalMs);
    if (!mounted || generation != _echoShadowGeneration) return;

    // ★ 지연 없이 곧바로 녹음을 연다.
    final path = await _startLabRecording('echo');
    if (!mounted || generation != _echoShadowGeneration || path == null) {
      await _stopLabRecording();
      return;
    }
    setState(() {
      _status = _LabStatus.recording;
      _lastNote = 'FULL ECHO · 지금 전체 문장을 말하세요';
    });

    _watchUserSilence(generation, (recorded, spoke) {
      // 말하지 않았으면 녹음이 아니다. 파일을 버리고 버튼도 켜지 않는다 —
      // 남겨 두면 무음 파일이 "녹음 성공"처럼 보인다.
      if (!spoke) {
        _deleteFile(recorded ?? path);
        setState(() {
          _status = _LabStatus.error;
          _error = '발화가 감지되지 않았다 — 녹음을 버렸다';
          _lastNote = null;
        });
        return;
      }
      setState(() {
        _echoRecordPath = recorded ?? path;
        _status = _LabStatus.recordReady;
        _lastNote = 'ECHO 녹음 완료';
      });
    });
  }

  /// ③ FULL SHADOW — AI와 **동시에** 겹쳐 말한다.
  ///
  /// 호흡 사이 여백만 [_gapMs]만큼 벌린 PCM을 로컬에서 조립해 쓴다.
  /// **recorder를 먼저 열고 재생을 시작한다** — 반대로 하면 첫 음절이 녹음에서
  /// 잘린다.
  Future<void> _runFullShadow() async {
    final pcm = _analysisPcm;
    final analysis = _analysis;
    if (pcm == null || analysis == null || analysis.segments.isEmpty) return;

    final generation = ++_echoShadowGeneration;
    await _stopPlayback();
    await _stopLabRecording();
    if (!mounted || generation != _echoShadowGeneration) return;

    // 로컬 조립. TTS 재호출도 재인코딩도 없다.
    final gapped = buildGappedPcm(
      pcm,
      analysis.segments,
      extraGapMs: _gapMs,
      sampleRate: kStealthVoxSttSampleRate,
    );
    final wav = pcm16ToWav(gapped, sampleRate: kStealthVoxSttSampleRate);
    final totalMs = _shadowTotalMs;

    // ★ 녹음 먼저.
    final path = await _startLabRecording('shadow');
    if (!mounted || generation != _echoShadowGeneration || path == null) {
      await _stopLabRecording();
      return;
    }
    setState(() {
      _status = _LabStatus.recording;
      _error = null;
      _lastNote = 'FULL SHADOW · AI와 함께 말하세요';
    });

    await _playBytesAwait(wav, expectedMs: totalMs);
    if (!mounted || generation != _echoShadowGeneration) {
      await _stopLabRecording();
      return;
    }
    // 🚧 Lab 실험값. 기존 P3 코드가 쓰는 700ms를 가져왔다. 최종 정책 아님.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || generation != _echoShadowGeneration) {
      await _stopLabRecording();
      return;
    }
    final recorded = await _stopLabRecording();
    if (!mounted || generation != _echoShadowGeneration) return;
    setState(() {
      _shadowRecordPath = recorded ?? path;
      _status = _LabStatus.recordReady;
      _lastNote = 'SHADOW 녹음 완료 (gap +${_gapMs}ms)';
    });
  }

  /// gap을 반영한 전체 길이. 재생 전에 몇 초짜리인지 보여준다.
  int get _shadowTotalMs {
    final analysis = _analysis;
    if (analysis == null) return 0;
    final inserts = analysis.segments.length - 1;
    return analysis.totalMs + (inserts > 0 ? inserts * _gapMs : 0);
  }

  Future<void> _stopEchoShadow() async {
    _echoShadowGeneration++;
    await _stopPlayback();
    await _stopLabRecording();
    if (!mounted) return;
    setState(() {
      _status = _LabStatus.ready;
      _lastNote = null;
    });
  }

  Future<void> _playRecordFile(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    await _stopPlayback();
    final player = AudioPlayer();
    _player = player;
    try {
      await player.play(DeviceFileSource(path));
      setState(() => _status = _LabStatus.playing);
      await _awaitPlayback(player, const Duration(seconds: 60));
    } catch (e) {
      debugPrint('[P2-LAB] record playback $e');
    }
    if (identical(_player, player)) _player = null;
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _status = _LabStatus.recordReady);
  }

  void _deleteFile(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// 녹음 임시 파일을 지운다. 조합이 바뀌거나 화면을 나갈 때 부른다.
  void _deleteRecordings() {
    _deleteFile(_echoRecordPath);
    _deleteFile(_shadowRecordPath);
    _echoRecordPath = null;
    _shadowRecordPath = null;
  }

  /// Style/Voice가 바뀌면 화면의 분석 결과는 더 이상 그 조합의 것이 아니다.
  void _invalidateAnalysis() {
    _analysisWav = null;
    _analysisPcm = null;
    _analysis = null;
    _analyzedStyleId = null;
    _analyzedVoice = null;
    _playingSegmentIndex = null;
    _micLatencyMs = null;
    // 🔒 녹음도 그 조합에 딸린 것이다. marin에 대고 말한 것이 cedar 결과처럼
    //   보이면 안 되는 건 분석 결과와 같은 문제다.
    _echoShadowGeneration++;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    if (_recording) {
      _recording = false;
      unawaited(_labRecorder?.stop().then((_) {}).catchError((_) {}));
    }
    _deleteRecordings();
  }

  void _pushRecent(_LabCombo combo) {
    _recent.remove(combo);
    _recent.insert(0, combo);
    if (_recent.length > _kRecentMax) {
      _recent.removeRange(_kRecentMax, _recent.length);
    }
  }

  Future<void> _selectRecent(_LabCombo combo) async {
    final style = kP2VoiceStyles.firstWhere(
      (s) => s.id == combo.styleId,
      orElse: () => kP2VoiceStyles.first,
    );
    setState(() {
      _style = style;
      _voice = combo.voice;
    });
    await _generateAndPlay(style, combo.voice);
  }

  // ══════════════════════════════════════════════════════════════════
  // 화면
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // 🔐 build에서도 다시 본다. Lab에 머무는 동안 로그아웃·계정 전환이
    //   일어나면 그 즉시 내용이 사라져야 한다.
    if (!AdminGate.isAdmin) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: _kLabBg,
      body: SafeArea(
        // 라벨만 있는 실험 화면이라 큰 배율에서 레이아웃이 먼저 무너진다.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildStyleSection(),
                      const SizedBox(height: 18),
                      _buildVoiceSection(),
                      const SizedBox(height: 18),
                      _buildSampleSection(),
                      const SizedBox(height: 18),
                      _buildActionSection(),
                      const SizedBox(height: 18),
                      _buildBreathSection(),
                      if (_analysis != null) const SizedBox(height: 18),
                      _buildRecentSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 20),
            tooltip: '뒤로',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Text(
            '🔬 P2 VOICE LAB',
            style: TextStyle(
              color: _kLabAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            '${kP2VoiceStyles.length}×${kP2LabVoices.length}'
            '=${kP2VoiceStyles.length * kP2LabVoices.length}',
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      );

  BoxDecoration get _surfaceDecoration => BoxDecoration(
        color: _kLabSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kLabBorder),
      );

  // ── STYLE ─────────────────────────────────────────────────────────
  Widget _buildStyleSection() {
    final bool busy = _status == _LabStatus.generating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildLabel('STYLE'),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: _surfaceDecoration,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _style.id,
              dropdownColor: _kLabDropdownBg,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: busy ? Colors.white24 : _kLabAccent, size: 20),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              items: kP2VoiceStyles
                  .map((s) => DropdownMenuItem<String>(
                        value: s.id,
                        child: Text(s.label),
                      ))
                  .toList(),
              onChanged: busy
                  ? null
                  : (id) {
                      if (id == null || id == _style.id) return;
                      final next =
                          kP2VoiceStyles.firstWhere((s) => s.id == id);
                      setState(() {
                        _style = next;
                        _status = _LabStatus.idle;
                        _error = null;
                        _lastNote = null;
                        _invalidateAnalysis();
                      });
                      unawaited(_stopPlayback());
                      unawaited(_probeCache(next, _voice));
                    },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_style.id} / $kP2StyleInstructionVersion',
          style: const TextStyle(
              color: Colors.white24, fontSize: 10, fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        _buildInstructionBox(),
      ],
    );
  }

  Widget _buildInstructionBox() {
    return Container(
      decoration: _surfaceDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () =>
                setState(() => _instructionExpanded = !_instructionExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'TTS instruction (실제 전송 본문)',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  Icon(
                    _instructionExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white38,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_instructionExpanded) ...<Widget>[
            const Divider(height: 1, color: _kLabBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(
                    _style.instruction,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '목표 느낌',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _style.goal,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── VOICE ─────────────────────────────────────────────────────────
  Widget _buildVoiceSection() {
    final bool busy = _status == _LabStatus.generating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildLabel('VOICE'),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: _surfaceDecoration,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _voice,
              dropdownColor: _kLabDropdownBg,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: busy ? Colors.white24 : _kLabAccent, size: 20),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              // 13종 전부 띄운다. 오류가 나는 voice도 숨기거나 갈아 끼우지
              // 않는다 — 어느 게 안 되는지가 이 화면이 알아낼 사실이다.
              items: kP2LabVoices
                  .map((v) => DropdownMenuItem<String>(
                        value: v,
                        child: Text(v),
                      ))
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) {
                      if (v == null || v == _voice) return;
                      setState(() {
                        _voice = v;
                        _status = _LabStatus.idle;
                        _error = null;
                        _lastNote = null;
                        _invalidateAnalysis();
                      });
                      unawaited(_stopPlayback());
                      unawaited(_probeCache(_style, v));
                    },
            ),
          ),
        ),
      ],
    );
  }

  // ── SAMPLE ────────────────────────────────────────────────────────
  Widget _buildSampleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildLabel('SAMPLE SENTENCE (모든 조합 공통)'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _surfaceDecoration,
          child: const SelectableText(
            kP2LabSampleSentence,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  // ── ACTION ────────────────────────────────────────────────────────
  Widget _buildActionSection() {
    final bool generating = _status == _LabStatus.generating;
    final bool playing = _status == _LabStatus.playing;
    final String ns = p2LabCacheNamespace(_style, _voice);
    final bool cached = _cacheProbe[ns] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _surfaceDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${_style.label}  +  $_voice',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (cached)
                const Text('● cached',
                    style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 10)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kLabAccent,
                disabledBackgroundColor: Colors.white12,
                foregroundColor: Colors.black,
                disabledForegroundColor: Colors.white38,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white38),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 22),
              label: Text(
                generating ? 'GENERATING…' : 'GENERATE & PLAY',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              // 생성 중에는 버튼을 잠근다. 그래도 다른 경로로 같은 조합이
              // 들어오면 in-flight guard가 두 번째 요청을 막는다.
              onPressed: generating || !_apiKeyLoaded
                  ? null
                  : () => unawaited(_generateAndPlay(_style, _voice)),
            ),
          ),
          if (playing) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: _kLabBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('STOP'),
                onPressed: () async {
                  await _stopPlayback();
                  if (!mounted) return;
                  setState(() => _status = _LabStatus.ready);
                },
              ),
            ),
          ],
          const Divider(height: 22, color: _kLabBorder),
          _buildBreathTestPicker(generating || _analyzing),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _kLabBreath,
                side: BorderSide(color: _kLabBreath.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _analyzing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kLabBreath),
                    )
                  : const Icon(Icons.air_rounded, size: 18),
              label: Text(
                _analyzing
                    ? 'ANALYZING…'
                    : (_cacheProbe[p2LabWavCacheNamespace(_style, _voice)] ==
                            true
                        ? 'ANALYZE BREATH  ● cached'
                        : 'ANALYZE BREATH'),
              ),
              onPressed: generating || _analyzing || !_apiKeyLoaded
                  ? null
                  : () => unawaited(_analyzeBreath(_style, _voice)),
            ),
          ),
          const SizedBox(height: 12),
          _buildStatusLine(),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kLabDanger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kLabDanger.withValues(alpha: 0.35)),
              ),
              child: SelectableText(
                _error!,
                style: const TextStyle(
                  color: _kLabDanger,
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusLine() {
    final String text;
    final Color color;
    switch (_status) {
      case _LabStatus.idle:
        text = _apiKeyLoaded ? 'idle' : 'API key 불러오는 중…';
        color = Colors.white38;
        break;
      case _LabStatus.generating:
        text = 'generating…';
        color = _kLabAccent;
        break;
      case _LabStatus.playing:
        text = 'playing';
        color = const Color(0xFF6EE7B7);
        break;
      case _LabStatus.ready:
        text = 'ready';
        color = Colors.white54;
        break;
      case _LabStatus.error:
        text = 'error';
        color = _kLabDanger;
        break;
      case _LabStatus.recording:
        text = '● recording';
        color = _kLabDanger;
        break;
      case _LabStatus.recordReady:
        text = 'record ready';
        color = _kLabBreath;
        break;
    }
    return Row(
      children: <Widget>[
        Text('상태: $text',
            style: TextStyle(color: color, fontSize: 11, height: 1.4)),
        if (_lastNote != null) ...<Widget>[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '· ${_lastNote!}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }

  /// 🌬️ Phase 1 비교용 빠른 선택. Smooth Jazz를 고정하고 Voice만 바꾼다.
  /// 위의 Style 6종·Voice 13종 dropdown은 그대로 살아 있다.
  Widget _buildBreathTestPicker(bool busy) {
    final onSmoothJazz = _style.id == kP2BreathTestStyleId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'BREATH TEST · Smooth Jazz 고정${onSmoothJazz ? '' : ' (현재 다른 Style)'}',
          style: TextStyle(
            color: onSmoothJazz ? Colors.white38 : _kLabAccent,
            fontSize: 10,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final voice in kP2BreathTestVoices) ...<Widget>[
              Expanded(
                child: _buildBreathVoiceChip(voice, busy),
              ),
              if (voice != kP2BreathTestVoices.last) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildBreathVoiceChip(String voice, bool busy) {
    final selected = _voice == voice && _style.id == kP2BreathTestStyleId;
    final style = kP2VoiceStyles.firstWhere(
      (s) => s.id == kP2BreathTestStyleId,
      orElse: () => _style,
    );
    final cached = _cacheProbe[p2LabWavCacheNamespace(style, voice)] == true;
    return InkWell(
      onTap: busy ? null : () => _selectBreathTestVoice(voice),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? _kLabBreath.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kLabBreath : _kLabBorder,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              voice,
              style: TextStyle(
                color: busy
                    ? Colors.white24
                    : (selected ? _kLabBreath : Colors.white60),
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (cached) ...<Widget>[
              const SizedBox(width: 4),
              const Text('●',
                  style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 8)),
            ],
          ],
        ),
      ),
    );
  }

  // ── BREATH ANALYSIS ───────────────────────────────────────────────
  String _sec(int ms) => (ms / 1000).toStringAsFixed(2);

  String _analyzedStyleLabel() {
    final id = _analyzedStyleId;
    if (id == null) return '—';
    for (final s in kP2VoiceStyles) {
      if (s.id == id) return s.label;
    }
    return id;
  }

  Widget _buildBreathSection() {
    final analysis = _analysis;
    if (analysis == null) return const SizedBox.shrink();
    final busy = _analyzing || _probing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildLabel('BREATH ANALYSIS'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _surfaceDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 🔒 현재 dropdown이 아니라 **분석 시점에 못박은 조합**을 쓴다.
              //   이 라벨은 구조적으로 거짓말을 할 수 없다.
              Text(
                '${_analyzedStyleLabel()}  +  ${_analyzedVoice ?? '—'}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              if (_analysisStale) ...<Widget>[
                const SizedBox(height: 4),
                const Text(
                  '⚠ 현재 선택과 다른 조합의 결과다. ANALYZE BREATH를 다시 눌러라.',
                  style: TextStyle(color: _kLabDanger, fontSize: 10),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Full ${_sec(analysis.totalMs)}s · '
                'Breaths ${analysis.segments.length} · '
                'WAV ${((_analysisWav?.length ?? 0) / 1024).round()}KB',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 12),
              if (analysis.segments.isEmpty)
                const Text(
                  '발성 구간을 찾지 못했다. 임계값 또는 PCM을 확인할 것.',
                  style: TextStyle(color: _kLabDanger, fontSize: 12),
                )
              else
                for (int i = 0; i < analysis.segments.length; i++) ...<Widget>[
                  _buildBreathRow(i, analysis.segments[i], busy),
                  if (i < analysis.gaps.length)
                    Padding(
                      padding: const EdgeInsets.only(left: 26, bottom: 2),
                      child: Text(
                        '↓ pause ${analysis.gaps[i].durationMs}ms',
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 10),
                      ),
                    ),
                ],
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      style: _breathButtonStyle,
                      onPressed:
                          busy ? null : () => unawaited(_playFull()),
                      child: const Text('▶ PLAY FULL',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: _breathButtonStyle,
                      onPressed: busy || analysis.segments.isEmpty
                          ? null
                          : () => unawaited(_playAllSequential()),
                      child: const Text('▶ PLAY ALL SEQ',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
              const Divider(height: 26, color: _kLabBorder),
              _buildEchoShadowSection(),
              const Divider(height: 26, color: _kLabBorder),
              _buildThresholdSteppers(busy),
              const Divider(height: 26, color: _kLabBorder),
              _buildMicProbe(busy, analysis),
            ],
          ),
        ),
      ],
    );
  }

  ButtonStyle get _breathButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: _kLabBreath,
        side: BorderSide(color: _kLabBreath.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      );

  Widget _buildBreathRow(int index, BreathSegment s, bool busy) {
    final playing = _playingSegmentIndex == index;
    return InkWell(
      onTap: busy ? null : () => unawaited(_playSegment(index)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 22,
              child: Text(
                '${index + 1}.',
                style: TextStyle(
                  color: playing ? _kLabBreath : Colors.white38,
                  fontSize: 12,
                  fontWeight: playing ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '${_sec(s.startMs)} – ${_sec(s.endMs)}   '
                '${_sec(s.durationMs)}s',
                style: TextStyle(
                  color: playing ? _kLabBreath : Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: playing ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Icon(
              playing ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
              size: 18,
              color: busy
                  ? Colors.white12
                  : (playing ? _kLabBreath : Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  /// ②③ 실험 구역. Echo와 Shadow를 각각 말해보고 세 소리를 비교한다.
  Widget _buildEchoShadowSection() {
    final analysis = _analysis;
    final busy = _analyzing || _probing;
    final running =
        _status == _LabStatus.recording || _status == _LabStatus.playing;
    final canRun = !busy && !running && analysis != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'ECHO / SHADOW',
          style: TextStyle(
              color: Colors.white38, fontSize: 10, letterSpacing: 1.1),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: OutlinedButton(
            style: _breathButtonStyle,
            onPressed: canRun ? () => unawaited(_runFullEcho()) : null,
            child: const Text('▶ FULL ECHO  (AI 전체 → 내가 혼자)',
                style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: OutlinedButton(
            style: _breathButtonStyle,
            onPressed: canRun ? () => unawaited(_runFullShadow()) : null,
            child: const Text('▶ FULL SHADOW  (AI와 동시에)',
                style: TextStyle(fontSize: 12)),
          ),
        ),
        _buildStepperRow(
          'shadow gap',
          '+${_gapMs}ms',
          busy || running,
          () => setState(() => _gapMs = (_gapMs - 100).clamp(0, 2000)),
          () => setState(() => _gapMs = (_gapMs + 100).clamp(0, 2000)),
        ),
        if (analysis != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'shadow 길이 ${_sec(analysis.totalMs)}s → ${_sec(_shadowTotalMs)}s'
              '  ·  gap 변경은 로컬 재조립만 (API 없음)',
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ),
        if (running) ...<Widget>[
          const SizedBox(height: 4),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _kLabDanger,
                side: BorderSide(color: _kLabDanger.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => unawaited(_stopEchoShadow()),
              child: const Text('■ STOP', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _buildComparePlayButton(
                'AI ORIGINAL',
                canRun && _analysisWav != null,
                () => unawaited(_playFull()),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildComparePlayButton(
                'ECHO',
                canRun && _echoRecordPath != null,
                () => unawaited(_playRecordFile(_echoRecordPath)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildComparePlayButton(
                'SHADOW',
                canRun && _shadowRecordPath != null,
                () => unawaited(_playRecordFile(_shadowRecordPath)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildComparePlayButton(
      String label, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.06 : 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled ? _kLabBorder : Colors.white10,
          ),
        ),
        child: Text(
          '▶ $label',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: enabled ? Colors.white70 : Colors.white24,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 🚧 Phase 1 tuning defaults를 실기기에서 바로 굴리기 위한 조절기.
  /// **여기서 값을 바꿔도 API는 호출되지 않는다** — [_reanalyze] 참조.
  Widget _buildThresholdSteppers(bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'THRESHOLDS (재분석만 · API 호출 없음)',
          style: TextStyle(
              color: Colors.white38, fontSize: 10, letterSpacing: 1.1),
        ),
        const SizedBox(height: 8),
        _buildStepperRow(
          'minSilence',
          '${_cfg.minSilenceMs}ms',
          busy,
          () => _reanalyze(
              _cfg.copyWith(minSilenceMs: (_cfg.minSilenceMs - 20).clamp(20, 2000))),
          () => _reanalyze(
              _cfg.copyWith(minSilenceMs: (_cfg.minSilenceMs + 20).clamp(20, 2000))),
        ),
        _buildStepperRow(
          'minBreath',
          '${_cfg.minBreathMs}ms',
          busy,
          () => _reanalyze(
              _cfg.copyWith(minBreathMs: (_cfg.minBreathMs - 100).clamp(100, 6000))),
          () => _reanalyze(
              _cfg.copyWith(minBreathMs: (_cfg.minBreathMs + 100).clamp(100, 6000))),
        ),
        _buildStepperRow(
          'pad',
          '${_cfg.padMs}ms',
          busy,
          () => _reanalyze(_cfg.copyWith(padMs: (_cfg.padMs - 20).clamp(0, 500))),
          () => _reanalyze(_cfg.copyWith(padMs: (_cfg.padMs + 20).clamp(0, 500))),
        ),
      ],
    );
  }

  Widget _buildStepperRow(
    String label,
    String value,
    bool busy,
    VoidCallback onMinus,
    VoidCallback onPlus,
  ) {
    Widget button(IconData icon, VoidCallback action) => InkWell(
          onTap: busy ? null : action,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon,
                size: 18, color: busy ? Colors.white12 : _kLabBreath),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          button(Icons.remove_rounded, onMinus),
          SizedBox(
            width: 62,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          button(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }

  Widget _buildMicProbe(bool busy, BreathAnalysis analysis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'MIC START LATENCY (측정만 · 녹음 남기지 않음)',
          style: TextStyle(
              color: Colors.white38, fontSize: 10, letterSpacing: 1.1),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                style: _breathButtonStyle,
                onPressed: busy || analysis.segments.isEmpty
                    ? null
                    : () => unawaited(_runMicLatencyProbe()),
                child: Text(_probing ? 'PROBING…' : 'RUN PROBE',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _micLatencyMs == null ? '— ms' : '$_micLatencyMs ms',
              style: TextStyle(
                color: _micLatencyMs == null ? Colors.white24 : _kLabBreath,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── RECENT ────────────────────────────────────────────────────────
  Widget _buildRecentSection() {
    if (_recent.isEmpty) return const SizedBox.shrink();
    final bool busy = _status == _LabStatus.generating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildLabel('RECENT (최대 $_kRecentMax · 화면을 나가면 사라진다)'),
        Container(
          decoration: _surfaceDecoration,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < _recent.length; i++) ...<Widget>[
                if (i > 0) const Divider(height: 1, color: _kLabBorder),
                _buildRecentRow(_recent[i], busy),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentRow(_LabCombo combo, bool busy) {
    final style = kP2VoiceStyles.firstWhere(
      (s) => s.id == combo.styleId,
      orElse: () => kP2VoiceStyles.first,
    );
    final bool current = style.id == _style.id && combo.voice == _voice;
    return InkWell(
      onTap: busy ? null : () => unawaited(_selectRecent(combo)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${style.label} + ${combo.voice}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: current ? _kLabAccent : Colors.white70,
                  fontSize: 13,
                  fontWeight: current ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.play_arrow_rounded,
              size: 20,
              color: busy ? Colors.white12 : Colors.white38,
            ),
          ],
        ),
      ),
    );
  }
}
