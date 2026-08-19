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
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '/custom_code/services/admin_gate.dart';
import '/custom_code/services/p2_voice_styles.dart';
import 'routine_mode_roleplay.dart' show TtsCache;

// ── 색 ────────────────────────────────────────────────────────────────
const Color _kLabBg = Color(0xFF121212);
const Color _kLabSurface = Color(0xFF1C1C1C);
const Color _kLabDropdownBg = Color(0xFF232323);
const Color _kLabBorder = Color(0x22FFFFFF);
const Color _kLabAccent = Colors.amber;
const Color _kLabDanger = Color(0xFFFF6B6B);

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

enum _LabStatus { idle, generating, playing, ready, error }

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
    final player = _player;
    _player = null;
    if (player != null) {
      unawaited(player.stop().catchError((_) {}));
      unawaited(player.dispose().catchError((_) {}));
    }
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

  /// OpenAI `/v1/audio/speech` 직접 호출.
  ///
  /// body는 실사용 P2(`_fetchOpenAITTSInternal`)와 같은 모양이다. 다른 점은
  /// **둘뿐이고, 둘 다 Lab이라서 그렇다**:
  ///   · timeout 10초 → 30초 (긴 문장 + 무거운 지시는 10초를 넘길 수 있다)
  ///   · 실패를 null로 삼키지 않고 status/body를 그대로 올려보낸다
  Future<_LabTtsResult> _postTts(P2VoiceStyle style, String voice) async {
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
              // 선택한 Style의 **전체 지시문**이 여기로 그대로 간다.
              'instructions': style.instruction,
              // speed는 넣지 않는다 — gpt-4o-mini-tts는 무시한다.
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('[P2-LAB] style=${style.id} voice=$voice '
          'model=$kP2LabTtsModel status=${response.statusCode} '
          'bytes=${response.bodyBytes.length}');

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return _LabTtsResult(audio: response.bodyBytes, fromCache: false);
      }
      // 200이 아니면 body에 이유가 들어 있다. 잘라내지 않고 그대로 보여준다.
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      return _LabTtsResult(
        error: 'TTS ${response.statusCode} — voice="$voice"\n$body',
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
