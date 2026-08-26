// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '/auth/firebase_auth/auth_util.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:record/record.dart';
import 'routine_mode_scenario_talk.dart' show TtsCache;
import '/custom_code/actions/billing_ticker.dart';
import '/custom_code/actions/billing_idle_mixin.dart';

const String _historyListTtsModel = 'tts-1';
const String _historyListTtsVoice = 'nova';

// ── Keepers 소리듣기 전용 ─────────────────────────────────────────────
// 의미단위 리듬을 말로 지시하려면 instructions를 받는 모델이어야 한다.
// tts-1은 instructions 자리가 없고, gpt-4o-mini-tts는 대신 speed를 무시한다.
// 캐시 키에 모델명을 박아 tts-1 시절 음성이 섞여 나오지 않게 한다.
const String _keeperPlayTtsModel = 'gpt-4o-mini-tts';
const String _keeperPlayTtsCacheVoice = 'keeper-4omini-nova';
const String _keeperPlayInstruction = '''
Read the line in natural meaning units — breath groups of roughly five to seven words.
Leave a brief pause at each unit boundary and hold a steady, rhythmic cadence throughout.
Speak clearly and slightly slower than conversational pace, as a model for a learner shadowing along.
Do not add, drop, or reword anything in the text.''';

class ChatHistoryListMaster extends StatefulWidget {
  const ChatHistoryListMaster({
    Key? key,
    this.width,
    this.height,
  }) : super(key: key);

  final double? width;
  final double? height;

  @override
  _ChatHistoryListMasterState createState() => _ChatHistoryListMasterState();
}

class _ChatHistoryListMasterState extends State<ChatHistoryListMaster>
    with BillingIdleMixin<ChatHistoryListMaster> {
  String _selectedFilter = 'All';
  Set<String> _selectedDocIds = {};

  // ── Idle Timeout (무반응 과금 정지, History List: 자동 이동 없음) ──────────
  // 🔧 틱 방식: 1초마다 활동 여부 확인. 키퍼 재생/튜터링/녹음 중엔 카운터 0 유지.

  // 유저나 AI가 작동 중인지 판단 (활동 중이면 idle 누적 안 함)
  @override
  String get billingModeName => 'history_list';

  /// 🆓 전체 목록은 **유일한 무과금 화면**이다. Keepers 필터로 들어가는
  /// 순간부터만 차감한다 — 거기서부터는 실제 학습 기능이 돌기 때문이다.
  @override
  bool get isBillingEnabled => _selectedFilter == 'Keepers';

  @override
  bool get isBillingBusy {
    return _keeperTutoringLoading ||
        _keeperIsRecording ||
        _isPlayingKeeper ||
        _keeperIsPlayingCorrected;
  }

  Widget _buildIdleOverlay() => const SizedBox.shrink();
  // ─────────────────────────────────────────────────────────────────────────

  // ── 필터 전환 + Keepers 과금 경계 제어 ──
  void _switchFilter(String newFilter) {
    // Keepers는 과금 구간이다. 전체 목록(무과금)에 머무는 것은 막지 않는다.
    if (newFilter == 'Keepers' && BillingTicker.instance.isBillingBlocked) {
      showBillingBlockedNotice(context);
      return;
    }
    final wasKeepers = _selectedFilter == 'Keepers';
    setState(() {
      _selectedFilter = newFilter;
      _selectedDocIds.clear();
    });

    final isKeepers = newFilter == 'Keepers';
    if (isKeepers && !wasKeepers) {
      // 💰 [BILLING-IDLE] Keepers로 들어가는 순간부터 과금 + 유휴 감시.
      startBillingRoom();
    } else if (!isKeepers && wasKeepers) {
      // 전체 목록으로 돌아왔다 = 무과금 화면. 감시도 과금도 멈춘다.
      clearBillingIdle();
      BillingTicker.instance.pause();
    }
  }

  // ── Keepers 전용 상태 ──
  String _apiKey = '';
  AudioPlayer? _keeperAudioPlayer;
  bool _isPlayingKeeper = false;
  String? _playingKeeperId;

  // ── Keepers 튜터링 상태 ──
  bool _keeperTutoringLoading = false;
  String _keeperTutoringKo = '';
  String _keeperTutoringAnswerEn = '';
  String _keeperTutoringCorrected = '';
  String _keeperTutoringCorrection = '';
  String _keeperTutoringUsageTip = ''; // 🆕 활용가치 있는 구문/관용구 팁 (있을 때만)
  String _keeperTutoringTranscript = '';
  // 🆕 Another Sentence 중복 회피: 최근 생성한 한국어 문장(최대 6개) 기억
  final List<String> _keeperRecentKoSentences = [];
  bool _keeperIsRecording = false;
  AudioRecorder? _keeperRecorder;
  Uint8List? _keeperCorrectedAudio;
  bool _keeperIsPlayingCorrected = false;
  AudioPlayer? _keeperCorrectionPlayer;
  StateSetter? _keeperDialogSetState;

  // Keepers 색상 상수
  static const Color _keepersColor = Color(0xFFD97706); // 앰버/골드

  bool _keepersMigrateOnce = false;
  final ScrollController _keepersScrollController = ScrollController();

  // build 안에서 snapshots()를 부르면 재빌드마다 새 스트림이 생겨 목록이
  // waiting으로 되돌아가며 깜빡인다. 한 번 만들어 계속 쓴다.
  Stream<QuerySnapshot>? _keepersStream;

  @override
  void initState() {
    super.initState();
    _fetchApiKey();
    // 과금은 Keepers 필터 진입 시에만 시작한다.
    BillingTicker.instance.balanceExhausted.addListener(_onBalanceExhausted);
  }

  /// Keepers를 보는 중에 잔여시간이 0이 됐을 때.
  ///
  /// 다른 과금 화면과 달리 스토어로 밀어내지 않는다 — 이 페이지는 목록만
  /// 보는 동안 무과금이라, 무료 화면에 있던 사람을 갑자기 내보내는 셈이 된다.
  /// 과금 구간인 Keepers만 접고 전체 목록으로 되돌린다.
  void _onBalanceExhausted() {
    if (!BillingTicker.instance.balanceExhausted.value) return;
    if (!mounted || _selectedFilter != 'Keepers') return;
    dismissRoutesAbove(context); // 열려 있는 튜터링 시트부터 닫는다
    _switchFilter('All');
    showBillingBlockedNotice(context);
  }

  @override
  void dispose() {
    BillingTicker.instance.balanceExhausted.removeListener(_onBalanceExhausted);
    clearBillingIdle();
    BillingTicker.instance.pause();
    _keepersScrollController.dispose();
    _keeperAudioPlayer?.dispose();
    _keeperCorrectionPlayer?.dispose();
    if (_keeperIsRecording) {
      _keeperRecorder?.stop().catchError((_) => null);
    }
    _keeperRecorder?.dispose();
    super.dispose();
  }

  Future<void> _fetchApiKey() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.fetchAndActivate();
      if (mounted) {
        setState(() => _apiKey = rc.getString('OpenAIAPIKey'));
      }
    } catch (e) {
      debugPrint('[Keepers] fetchApiKey error: $e');
    }
  }

  // 🏷️ [필터칩 표시명] 화면에 보이는 이름만 바꾼다.
  //   filterKey는 room_name 매칭에 그대로 쓰이므로(_selectedFilter로
  //   rn.contains 비교) 절대 바꾸면 안 된다. 키를 'Scenario'로 바꾸면
  //   저장된 "Roleplay Mode" 방들이 필터에서 통째로 사라진다.
  //     Anyone   → Circle   (Circle Talk)
  //     Roleplay → Scenario (Scenario Talk)
  String _filterLabel(String filterKey) {
    switch (filterKey) {
      case 'Anyone':
        return 'Circle';
      case 'Roleplay':
        return 'Scenario';
      default:
        return filterKey;
    }
  }

  bool _isCircleTalkRoom(String roomName) =>
      roomName.contains("Anyone") ||
      roomName.contains("Free Talk") ||
      roomName.contains("Circle Talk");

  IconData _getIconForRoom(String roomName) {
    if (roomName.contains("Duo")) return Icons.people;
    if (roomName.contains("Clone")) return Icons.face;
    if (roomName.contains("Roleplay")) return Icons.smart_toy;
    if (roomName.contains("Shadowing")) return Icons.smart_toy;
    if (roomName.contains("NativeSync")) return Icons.mic_external_on;
    if (_isCircleTalkRoom(roomName)) return Icons.forum;
    return Icons.chat_bubble_outline;
  }

  Color _getColorForRoom(String roomName) {
    if (roomName.contains("Duo")) return const Color(0xFF2563EB);
    if (roomName.contains("Clone")) return const Color(0xFF9333EA);
    if (roomName.contains("Roleplay")) return const Color(0xFF16A34A);
    if (roomName.contains("Shadowing")) return Colors.greenAccent;
    if (roomName.contains("NativeSync")) return Colors.orangeAccent;
    if (_isCircleTalkRoom(roomName)) return const Color(0xFF9333EA);
    return Colors.white54;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  BUILD
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  @override
  Widget build(BuildContext context) {
    if (currentUserReference == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: Text("로그인이 필요합니다.", style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        // 🔖 스토어는 스텔스룸 상단 줄로 옮겼다. 이 자리는 이 화면에서 자주
        //   쓰는 것에 내준다 — 스텔스룸(대화하러 가기)과 Keepers(모아 둔 문장).
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              tooltip: '스텔스룸',
              icon: const Icon(Icons.security, color: Colors.white70),
              onPressed: () {
                if (!guardBillingEntry(context)) return;
                context.pushNamed('StealthRoom');
              },
            ),
            IconButton(
              padding: EdgeInsets.zero,
              tooltip: _selectedFilter == 'Keepers' ? '전체 대화 보기' : 'Keepers',
              icon: Icon(
                Icons.bookmark_rounded,
                // 켜져 있을 때는 아래 필터칩과 같은 색으로 물든다. 지금 무엇을
                // 보고 있는지가 두 자리에서 같은 신호로 읽혀야 한다.
                color: _selectedFilter == 'Keepers'
                    ? _keepersColor
                    : Colors.white70,
              ),
              onPressed: () => _switchFilter(
                  _selectedFilter == 'Keepers' ? 'All' : 'Keepers'),
            ),
          ],
        ),
        // 🏠 모드 필터를 푸는 방법이 "방금 누른 그 아이콘을 다시 누르기"뿐이라
        //   유저가 전체 목록으로 돌아오지 못하는 일이 있었다. 제목 칩을 눌러도
        //   전체로 돌아오게 하고, 필터가 걸린 동안은 되돌리기 아이콘을 붙여
        //   누를 수 있다는 걸 알린다.
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _selectedFilter == 'All' ? null : () => _switchFilter('All'),
          child: Tooltip(
            message: _selectedFilter == 'All' ? '전체 대화' : '전체 대화 보기',
            // 📏 AppBar title 슬롯은 leading(96)과 actions를 뺀 나머지로 폭이
            //   고정된다. 폰 글꼴을 키워 둔 기기에서는 이 칩이 그 폭을 넘어
            //   노란 줄무늬(overflow)가 떴다. 글자를 자르는 대신 슬롯에 맞게
            //   줄여, 어떤 글꼴 배율에서도 "Study Room"이 온전히 보이게 한다.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6)
                      .withValues(alpha: _selectedFilter == 'All' ? 0.15 : 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF3B82F6).withValues(
                          alpha: _selectedFilter == 'All' ? 0.5 : 0.9),
                      width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedFilter != 'All') ...[
                      const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                    ],
                    const Text(
                      "Study Room",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: BillingTicker.instance.billingState,
            builder: (_, s, __) => GestureDetector(
              onTap: s == 0 && _selectedFilter == 'Keepers'
                  ? resetBillingIdle
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CustomPaint(
                  size: const Size(16, 16),
                  painter: BillingDotPainter(s),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.help_outline_rounded,
                color: Colors.amber.withValues(alpha: 0.75), size: 20),
            tooltip: "사용설명서",
            padding: const EdgeInsets.symmetric(horizontal: 8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _showStudyRoomManual,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: Stack(children: [
              _selectedFilter == 'Keepers'
                  ? _buildKeepersBody()
                  : _buildHistoryBody(),
              _buildIdleOverlay(),
            ]),
          ),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  기존 히스토리 바디 (변경 없음)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildHistoryBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: currentUserReference!
          .collection('chat_history')
          .orderBy('is_pinned', descending: true)
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.amber));
        }

        final allDocs = snapshot.data!.docs;

        final filteredDocs = allDocs.where((doc) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          if (data['last_message'] == null) return false;
          if (_selectedFilter == 'All') return true;
          if (data['room_name'] == null) return false;
          final rn = data['room_name'].toString();
          if (_selectedFilter == 'Anyone') return _isCircleTalkRoom(rn);
          return rn.contains(_selectedFilter);
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history_toggle_off,
                    size: 60, color: Colors.white24),
                const SizedBox(height: 20),
                Text("해당 모드의 기록이 없습니다.",
                    style: GoogleFonts.notoSans(color: Colors.white54)),
              ],
            ),
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            return _buildHistoryTile(filteredDocs[index]);
          },
        );
      },
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Keepers 바디
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildKeepersBody() {
    if (!_keepersMigrateOnce) {
      _keepersMigrateOnce = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _migrateKeeperMissingIsDeleted());
    }
    _keepersStream ??= currentUserReference!.collection('keepers').snapshots();
    return StreamBuilder<QuerySnapshot>(
      // 인덱스/필드 누락 오류를 피하기 위해 필터·정렬 없이 전체 조회 후 Dart에서 처리
      stream: _keepersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[Keepers] stream error: ${snapshot.error}');
          debugPrint('[Keepers] stream stackTrace: ${snapshot.stackTrace}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text("Keepers를 불러오지 못했습니다.",
                    style: GoogleFonts.notoSans(color: Colors.white70)),
                const SizedBox(height: 8),
                Text(
                  "오류: ${snapshot.error}",
                  style: GoogleFonts.notoSans(
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      fontSize: 11),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text("잠시 후 다시 시도해 주세요.",
                    style: GoogleFonts.notoSans(
                        color: Colors.white30, fontSize: 12)),
              ],
            ),
          );
        }
        // 이미 받아둔 데이터가 있으면 스피너로 갈아끼우지 않는다.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: _keepersColor));
        }
        final allDocs = snapshot.data?.docs ?? [];

        // is_deleted == true 제외 (Dart 필터)
        final rawDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['is_deleted'] != true;
        }).toList();

        if (rawDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bookmark_border_rounded,
                    size: 60, color: Colors.white24),
                const SizedBox(height: 20),
                Text("저장된 표현이 없습니다.",
                    style: GoogleFonts.notoSans(color: Colors.white54)),
                const SizedBox(height: 8),
                Text("대화 기록에서 대사를 길게 누르면 여기에 저장됩니다.",
                    style: GoogleFonts.notoSans(
                        color: Colors.white30, fontSize: 12)),
              ],
            ),
          );
        }
        // pinned_at 있는 항목 먼저, 없으면 created_at 최신순 (Dart 정렬)
        final docs = List<QueryDocumentSnapshot>.from(rawDocs);
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aPinned = aData['pinned_at'] as Timestamp?;
          final bPinned = bData['pinned_at'] as Timestamp?;
          if (aPinned != null && bPinned != null) {
            return bPinned.compareTo(aPinned);
          }
          if (aPinned != null) return -1;
          if (bPinned != null) return 1;
          final aCreated = aData['created_at'] as Timestamp?;
          final bCreated = bData['created_at'] as Timestamp?;
          if (aCreated == null && bCreated == null) return 0;
          if (aCreated == null) return 1;
          if (bCreated == null) return -1;
          return bCreated.compareTo(aCreated);
        });
        return _buildKeepersList(docs);
      },
    );
  }

  Widget _buildKeepersList(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bookmark_border_rounded,
                size: 60, color: Colors.white24),
            const SizedBox(height: 20),
            Text("저장된 표현이 없습니다.",
                style: GoogleFonts.notoSans(color: Colors.white54)),
            const SizedBox(height: 8),
            Text("대화 기록에서 대사를 탭하면 여기에 저장됩니다.",
                style:
                    GoogleFonts.notoSans(color: Colors.white30, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _keepersScrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) => _buildKeeperTile(docs[index]),
    );
  }

  // is_deleted 필드 누락 문서 보정 (1회 실행)
  Future<void> _migrateKeeperMissingIsDeleted() async {
    try {
      final snap = await currentUserReference!.collection('keepers').get();
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (!data.containsKey('is_deleted')) {
          await doc.reference.update({
            'is_deleted': false,
            'updated_at': FieldValue.serverTimestamp(),
          });
          debugPrint('[Keepers] migrated ${doc.id}: is_deleted 필드 추가');
        }
      }
    } catch (e) {
      debugPrint('[Keepers] migrate error: $e');
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  필터 바 (Keepers 버튼 추가)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildFilterBar() {
    // 📏 칩은 글자 폭만큼 커진다. 폰 글꼴을 크게 써 두면 Duo/Circle 두 개로
    //   화면이 차서 뒤쪽 모드가 있는 줄도 모르게 된다. 가로 스크롤은 그대로
    //   두되 배율에 천장을 씌워, 큰 글꼴에서도 모드가 몇 개인지는 보이게 한다.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF1A1A1A),
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: _selectedFilter == 'All' || _selectedFilter == 'Keepers'
                ? [
                    _buildFilterChip('Duo', _filterLabel('Duo'), Icons.people),
                    _buildFilterChip(
                        'Anyone', _filterLabel('Anyone'), Icons.forum),
                    _buildFilterChip(
                        'Roleplay', _filterLabel('Roleplay'), Icons.smart_toy),
                    _buildKeepersChip(),
                  ]
                : [
                    _buildDeleteActionChip(),
                    _buildFilterChip(
                        _selectedFilter,
                        _filterLabel(_selectedFilter),
                        _getIconForRoom(_selectedFilter)),
                  ],
          ),
        ),
      ),
    );
  }

  // ── Keepers 전용 필터 칩 ──
  Widget _buildKeepersChip() {
    final bool isSelected = _selectedFilter == 'Keepers';
    return GestureDetector(
      onTap: () {
        _switchFilter(isSelected ? 'All' : 'Keepers');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? _keepersColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _keepersColor : Colors.white24,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_rounded,
                size: 16, color: isSelected ? _keepersColor : Colors.white54),
            const SizedBox(width: 6),
            Text(
              'Keepers',
              style: TextStyle(
                color: isSelected ? _keepersColor : Colors.white54,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteActionChip() {
    return GestureDetector(
      onTap: _showBatchDeleteDialog,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _selectedDocIds.isNotEmpty
              ? const Color(0xFF4A4A4A)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: _selectedDocIds.isNotEmpty
                  ? const Color(0xFF9E9E9E)
                  : Colors.white24,
              width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_sweep,
                size: 16,
                color: _selectedDocIds.isNotEmpty
                    ? const Color(0xFF9E9E9E)
                    : Colors.white54),
            const SizedBox(width: 6),
            Text("선택삭제",
                style: TextStyle(
                    color: _selectedDocIds.isNotEmpty
                        ? const Color(0xFF9E9E9E)
                        : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            if (_selectedDocIds.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                    color: Color(0xFF9E9E9E), shape: BoxShape.circle),
                child: Text('${_selectedDocIds.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label, IconData icon) {
    bool isSelected = _selectedFilter == filterKey;
    Color baseColor =
        filterKey == 'All' ? Colors.grey : _getColorForRoom(filterKey);

    return GestureDetector(
      onTap: () {
        final newFilter = (_selectedFilter == filterKey && filterKey != 'All')
            ? 'All'
            : filterKey;
        _switchFilter(newFilter);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? baseColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? baseColor : Colors.white24,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16, color: isSelected ? baseColor : Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? baseColor : Colors.white54,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  기존 히스토리 타일 (변경 없음)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildHistoryTile(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    String title = "";
    bool isPinned = data['is_pinned'] ?? false;
    String roomName = data['room_name'] ?? 'Stealth Mode';

    if (data['custom_title'] != null &&
        data['custom_title'].toString().isNotEmpty) {
      title = data['custom_title'];
    } else {
      Timestamp? ts = data['created_at'];
      if (ts != null) {
        title =
            DateFormat('yyyy.MM.dd (E) a h:mm', 'ko_KR').format(ts.toDate());
      } else {
        title = "날짜 정보 없음";
      }
    }

    String previewText = data['last_message'] ?? "(대화 내용 없음)";
    bool isChecked = _selectedDocIds.contains(doc.id);
    bool showCheckbox = _selectedFilter != 'All';

    return GestureDetector(
      onTap: () {
        // 목록 첫 페이지만 무과금이다. 여기서 안으로 들어가면 과금이 시작된다.
        if (!guardBillingEntry(context)) return;
        context.pushNamed(
          'ChatDetail',
          queryParameters: {
            'historyRef':
                serializeParam(doc.reference, ParamType.DocumentReference)
          }.withoutNulls,
        );
      },
      onLongPress: () => _showOptionMenu(doc),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: isPinned
              ? Border.all(
                  color: Colors.amber.withValues(alpha: 0.6), width: 1.5)
              : Border.all(
                  color: isChecked ? const Color(0xFF9E9E9E) : Colors.white10,
                  width: isChecked ? 1.5 : 1.0),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            if (showCheckbox)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Checkbox(
                  value: isChecked,
                  activeColor: const Color(0xFF757575),
                  checkColor: Colors.white,
                  side: const BorderSide(color: Colors.white54, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedDocIds.add(doc.id);
                      } else {
                        _selectedDocIds.remove(doc.id);
                      }
                    });
                  },
                ),
              ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getColorForRoom(roomName).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_getIconForRoom(roomName),
                  color: _getColorForRoom(roomName), size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isPinned ? Colors.amber : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(previewText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            if (!showCheckbox)
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Keeper 타일 카드
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildKeeperTile(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final translated = (data['translated_text'] ?? '').toString();
    final original = (data['original_text'] ?? '').toString();
    final role = (data['speaker_role'] ?? '').toString();
    final isPinned = data['pinned_at'] != null;
    final sourceRoom = (data['source_room_name'] ?? '').toString();
    final bool isCurrentlyPlaying =
        _playingKeeperId == doc.id && _isPlayingKeeper;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: isPinned
            ? Border.all(
                color: _keepersColor.withValues(alpha: 0.6), width: 1.5)
            : Border.all(color: Colors.white10, width: 1.0),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단: 출처 + 핀 아이콘 ──
          if (sourceRoom.isNotEmpty || isPinned)
            Row(
              children: [
                if (sourceRoom.isNotEmpty)
                  Text(sourceRoom,
                      style:
                          const TextStyle(color: Colors.white24, fontSize: 10)),
                const Spacer(),
                if (isPinned)
                  const Icon(Icons.push_pin_rounded,
                      color: _keepersColor, size: 12),
              ],
            ),
          const SizedBox(height: 10),
          // ── 영어 텍스트 (메인) ──
          Text(
            translated,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.4),
          ),
          if (original.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              original,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          // ── 하단: 액션 아이콘들 ──
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 1) 소리듣기
              _buildKeeperAction(
                icon: isCurrentlyPlaying
                    ? Icons.stop_circle_rounded
                    : Icons.play_circle_rounded,
                color: Colors.amberAccent,
                tooltip: '소리 듣기',
                onTap: () => _playKeeperAudio(doc.id, translated),
              ),
              const SizedBox(width: 4),
              // 2) 튜터링
              _buildKeeperAction(
                icon: Icons.school_rounded,
                color: Colors.deepPurpleAccent,
                tooltip: '실전 튜터링',
                onTap: () => _showKeeperTutoringPopup(doc.id, translated),
              ),
              const SizedBox(width: 4),
              // 3) 맨 위로 올리기
              _buildKeeperAction(
                icon: Icons.keyboard_double_arrow_up_rounded,
                color: _keepersColor,
                tooltip: '맨 위로 올리기',
                onTap: () => _togglePinKeeper(doc),
              ),
              const SizedBox(width: 4),
              // 4) 삭제
              _buildKeeperAction(
                icon: Icons.delete_outline_rounded,
                color: Colors.redAccent.withValues(alpha: 0.7),
                tooltip: '삭제',
                onTap: () => _showDeleteKeeperDialog(doc),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeeperAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    // 손가락으로 정확히 짚기 어려워 탭 영역을 권장치(48dp)까지 넓힌다.
    return IconButton(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      splashRadius: 24,
      icon: Icon(icon, color: color, size: 22),
      onPressed: onTap,
      tooltip: tooltip,
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Keepers 소리듣기
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Future<void> _playKeeperAudio(String keeperId, String text) async {
    resetBillingIdle();
    if (text.isEmpty || _apiKey.isEmpty) return;

    // 이미 재생 중이면 정지
    if (_isPlayingKeeper && _playingKeeperId == keeperId) {
      await _keeperAudioPlayer?.stop();
      if (mounted)
        setState(() {
          _isPlayingKeeper = false;
          _playingKeeperId = null;
        });
      return;
    }

    try {
      // TtsCache 우선 조회
      Uint8List? audio = await TtsCache.get(text, _keeperPlayTtsCacheVoice);
      final bool fromCache = audio != null;
      if (audio == null) {
        audio = await _fetchTts(
          text,
          _historyListTtsVoice,
          model: _keeperPlayTtsModel,
          instructions: _keeperPlayInstruction,
        );
        if (audio != null) {
          TtsCache.put(text, _keeperPlayTtsCacheVoice, audio);
        }
      }
      if (audio == null || !mounted) return;

      _keeperAudioPlayer?.dispose();
      final player = AudioPlayer();
      _keeperAudioPlayer = player;

      if (mounted)
        setState(() {
          _isPlayingKeeper = true;
          _playingKeeperId = keeperId;
        });

      player.onPlayerComplete.listen((_) {
        if (mounted)
          setState(() {
            _isPlayingKeeper = false;
            _playingKeeperId = null;
          });
      });

      try {
        await player.play(BytesSource(audio));
      } on PlatformException {
        // 예전에 잘린 채 저장된 캐시는 원자적 쓰기로도 풀리지 않는다.
        // 버리고 한 번만 다시 받아, 기존 기기도 탭 한 번으로 복구되게 한다.
        if (!fromCache) rethrow;
        debugPrint('[Keepers] cached audio unplayable — refetching');
        await TtsCache.invalidate(text, _keeperPlayTtsCacheVoice);
        final fresh = await _fetchTts(
          text,
          _historyListTtsVoice,
          model: _keeperPlayTtsModel,
          instructions: _keeperPlayInstruction,
        );
        if (fresh == null || !mounted) rethrow;
        TtsCache.put(text, _keeperPlayTtsCacheVoice, fresh);
        await player.play(BytesSource(fresh));
      }
    } catch (e) {
      debugPrint('[Keepers] playAudio error: $e');
      if (mounted)
        setState(() {
          _isPlayingKeeper = false;
          _playingKeeperId = null;
        });
    }
  }

  /// [model]/[instructions]를 주지 않으면 기존 tts-1 경로 그대로다(튜터링용).
  /// instructions는 gpt-4o-mini-tts에서만 동작하고, 그 모델은 speed를 무시하므로
  /// 둘을 같이 보내지 않는다.
  Future<Uint8List?> _fetchTts(String text, String voice,
      {double speed = 1.0, String? model, String? instructions}) async {
    if (_apiKey.isEmpty || text.trim().isEmpty) return null;
    try {
      final payload = <String, dynamic>{
        'model': model ?? _historyListTtsModel,
        'input': text,
        'voice': voice,
      };
      if (instructions != null && instructions.trim().isNotEmpty) {
        payload['instructions'] = instructions.trim();
      } else {
        payload['speed'] = speed;
      }
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode != 200) {
        debugPrint('[Keepers] fetchTts http ${response.statusCode}: '
            '${response.body}');
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('[Keepers] fetchTts error: $e');
      return null;
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Keepers 맨 위로 올리기 (단방향)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Future<void> _togglePinKeeper(DocumentSnapshot doc) async {
    try {
      await doc.reference.update({'pinned_at': FieldValue.serverTimestamp()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("맨 위로 올렸습니다.",
                style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: _keepersColor,
            duration: Duration(seconds: 1)));
      }
    } catch (e) {
      debugPrint('[Keepers] moveToTop error: $e');
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Keepers 삭제 (소프트 삭제)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  void _showDeleteKeeperDialog(DocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Keepers 삭제",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("이 표현을 Keepers에서 삭제할까요?",
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await doc.reference.update({
                    'is_deleted': true,
                    'deleted_at': FieldValue.serverTimestamp()
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("삭제되었습니다.",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.redAccent,
                        duration: Duration(seconds: 1)));
                  }
                } catch (e) {
                  debugPrint('[Keepers] delete error: $e');
                }
              },
              child: const Text("삭제",
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  Keepers 튜터링 팝업 (chat_history_master의 패턴 재사용)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  void _showKeeperTutoringPopup(String keeperId, String baseText) {
    if (baseText.trim().isEmpty || _apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("튜터링을 시작할 수 없습니다.",
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orangeAccent));
      return;
    }

    // 상태 초기화
    _keeperTutoringKo = '';
    _keeperTutoringAnswerEn = '';
    _keeperTutoringCorrected = '';
    _keeperTutoringCorrection = '';
    _keeperTutoringUsageTip = '';
    _keeperTutoringTranscript = '';
    _keeperIsRecording = false;
    _keeperCorrectedAudio = null;
    _keeperIsPlayingCorrected = false;
    _keeperTutoringLoading = true;
    _keeperDialogSetState = null;

    // STEP 1: 응용 문장 생성
    _generateKeeperAppText(baseText);

    BillingTicker.instance.setRate(BillingRate.full);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (_, ss) {
          _keeperDialogSetState = ss;
          return DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => SingleChildScrollView(
              controller: scrollController,
              child: _buildKeeperTutoringBody(
                baseText,
                onClose: () => Navigator.of(ctx).pop(),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      BillingTicker.instance.setRate(BillingRate.full);
      _keeperDialogSetState = null;
      if (_keeperIsRecording) {
        _keeperRecorder?.stop().catchError((_) => null);
      }
      _keeperIsRecording = false;
      _keeperCorrectedAudio = null;
    });
  }

  Future<void> _generateKeeperAppText(String baseText) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'temperature': 1.0,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content':
                  r"""You are a grammar application tutor. Keep ONLY the core grammar pattern (tense / structure / word order) of the input English sentence. Then create ONE completely NEW Korean sentence that uses the SAME structure but an ENTIRELY DIFFERENT topic, vocabulary, and situation from the input — it must not be a paraphrase of the input. Also provide one natural English answer for that new Korean sentence. reply ONLY in JSON: {"ko": "새 한국어 문장", "en": "영어 정답"}""",
            },
            {
              'role': 'user',
              'content': _keeperRecentKoSentences.isEmpty
                  ? 'Input English sentence: "$baseText"'
                  : 'Input English sentence: "$baseText"\n\nDo NOT repeat the topic or wording of these recently used Korean sentences — pick a clearly different subject:\n- ${_keeperRecentKoSentences.join("\n- ")}',
            },
          ],
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final jsonResult = jsonDecode(data['choices'][0]['message']['content']);
        _keeperTutoringKo = (jsonResult['ko'] as String? ?? '').trim();
        _keeperTutoringAnswerEn = (jsonResult['en'] as String? ?? '').trim();
        // 🆕 최근 문장 기록(중복 회피용, 최대 6개 유지)
        if (_keeperTutoringKo.isNotEmpty) {
          _keeperRecentKoSentences.add(_keeperTutoringKo);
          if (_keeperRecentKoSentences.length > 6) {
            _keeperRecentKoSentences.removeAt(0);
          }
        }
      }
    } catch (e) {
      debugPrint('[Keepers] generateAppText error: $e');
    } finally {
      _keeperTutoringLoading = false;
      _keeperDialogSetState?.call(() {});
    }
  }

  Widget _buildKeeperTutoringBody(String baseText, {VoidCallback? onClose}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _keepersColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              const Icon(Icons.school_rounded, color: _keepersColor, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("Keepers 실전 튜터링",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 원본 문장
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(baseText,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.4)),
          ),
          const Divider(color: Colors.white12, height: 24),

          // ── STEP 1: 응용 ──
          _buildStepHeader('STEP 1', '응용', Colors.cyanAccent),
          const SizedBox(height: 8),
          if (_keeperTutoringLoading)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                  color: _keepersColor, strokeWidth: 2),
            ))
          else if (_keeperTutoringKo.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
              ),
              child: Text(_keeperTutoringKo,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, height: 1.5)),
            )
          else
            const Text("생성 실패 — 다시 시도해주세요.",
                style: TextStyle(color: Colors.redAccent, fontSize: 13)),
          const SizedBox(height: 16),

          // ── STEP 2: 도전 (녹음) ──
          _buildStepHeader('STEP 2', '도전', Colors.orangeAccent),
          const SizedBox(height: 8),
          if (_keeperTutoringKo.isNotEmpty)
            Center(
              child: GestureDetector(
                onTap: _keeperIsRecording
                    ? _stopKeeperRecording
                    : _startKeeperRecording,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: _keeperIsRecording
                        ? Colors.redAccent.withValues(alpha: 0.2)
                        : Colors.orangeAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: _keeperIsRecording
                            ? Colors.redAccent
                            : Colors.orangeAccent,
                        width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _keeperIsRecording ? Icons.stop : Icons.mic,
                        color: _keeperIsRecording
                            ? Colors.redAccent
                            : Colors.orangeAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _keeperIsRecording ? "녹음 중지" : "내 입으로 말하기",
                        style: TextStyle(
                          color: _keeperIsRecording
                              ? Colors.redAccent
                              : Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_keeperTutoringTranscript.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text("내 답변: $_keeperTutoringTranscript",
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 16),

          // ── STEP 3: 교정 ──
          if (_keeperTutoringCorrected.isNotEmpty) ...[
            _buildStepHeader('STEP 3', '교정', Colors.greenAccent),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_keeperTutoringCorrected,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.4)),
                  if (_keeperTutoringCorrection.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_keeperTutoringCorrection,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12, height: 1.4)),
                  ],
                ],
              ),
            ),
            // 🆕 활용 구문 팁 (있을 때만)
            if (_keeperTutoringUsageTip.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.lightbulb_outline,
                          color: Colors.amber, size: 14),
                      SizedBox(width: 6),
                      Text("더 자연스러운 표현",
                          style: TextStyle(
                              color: Colors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 8),
                    Text(_keeperTutoringUsageTip,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.5)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],

          // ── STEP 4: 체득 (교정 문장 TTS 듣기) ──
          if (_keeperCorrectedAudio != null) ...[
            _buildStepHeader('STEP 4', '체득', Colors.amberAccent),
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: _playKeeperCorrectedAudio,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.amberAccent, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _keeperIsPlayingCorrected
                            ? Icons.stop
                            : Icons.headphones_rounded,
                        color: Colors.amberAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _keeperIsPlayingCorrected ? "재생 중지" : "교정 문장 듣기",
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ── 다시 하기 버튼 ──
          if (!_keeperTutoringLoading && _keeperTutoringKo.isNotEmpty)
            Center(
              child: TextButton.icon(
                onPressed: () {
                  _keeperTutoringLoading = true;
                  _keeperTutoringKo = '';
                  _keeperTutoringAnswerEn = '';
                  _keeperTutoringCorrected = '';
                  _keeperTutoringCorrection = '';
                  _keeperTutoringUsageTip = '';
                  _keeperTutoringTranscript = '';
                  _keeperCorrectedAudio = null;
                  _keeperDialogSetState?.call(() {});
                  _generateKeeperAppText(baseText);
                },
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white38, size: 18),
                label: const Text("다시 하기",
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepHeader(String step, String label, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(step,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── 녹음 시작/중지 + Whisper STT + 교정 ──
  Future<void> _startKeeperRecording() async {
    _keeperRecorder ??= AudioRecorder();
    final hasPermission = await _keeperRecorder!.hasPermission();
    if (!hasPermission) return;
    try {
      final dir = await Directory.systemTemp.createTemp('keeper_rec');
      final path =
          '${dir.path}/keeper_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _keeperRecorder!.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      BillingTicker.instance.resumeFromActivity('history_keeper_mic_start');
      _keeperIsRecording = true;
      _keeperDialogSetState?.call(() {});
    } catch (e) {
      debugPrint('[Keepers] startRecording error: $e');
    }
  }

  Future<void> _stopKeeperRecording() async {
    try {
      final path = await _keeperRecorder?.stop();
      BillingTicker.instance.resumeFromActivity('history_keeper_mic_stop');
      _keeperIsRecording = false;
      _keeperDialogSetState?.call(() {});

      if (path == null || path.isEmpty) return;
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();

      // Whisper STT
      final transcript = await _whisperTranscribe(bytes);
      if (transcript.isEmpty) return;
      BillingTicker.instance.resumeFromActivity('history_keeper_stt_result');
      _keeperTutoringTranscript = transcript;
      _keeperDialogSetState?.call(() {});

      // 교정 요청
      await _correctKeeperAnswer(transcript);
    } catch (e) {
      debugPrint('[Keepers] stopRecording error: $e');
      _keeperIsRecording = false;
      _keeperDialogSetState?.call(() {});
    }
  }

  Future<String> _whisperTranscribe(Uint8List audioBytes) async {
    if (_apiKey.isEmpty) return '';
    try {
      var request = http.MultipartRequest(
          'POST', Uri.parse('https://api.openai.com/v1/audio/transcriptions'));
      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.fields['model'] = 'gpt-4o-mini-transcribe';
      request.fields['language'] = 'en';
      request.files.add(http.MultipartFile.fromBytes('file', audioBytes,
          filename: 'audio.m4a'));
      final response = await request.send();
      if (response.statusCode == 200) {
        final body = await response.stream.bytesToString();
        final json = jsonDecode(body);
        return (json['text'] as String? ?? '').trim();
      }
    } catch (e) {
      debugPrint('[Keepers] whisper error: $e');
    }
    return '';
  }

  Future<void> _correctKeeperAnswer(String userAnswer) async {
    if (_apiKey.isEmpty || _keeperTutoringAnswerEn.isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'temperature': 0.2,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'user',
              'content':
                  '''You are a strict but fair English tutor for a Korean learner.

[KOREAN_PROMPT] (the meaning the user MUST express): "${_keeperTutoringKo}"
[EXAMPLE_EN] (ONE natural example answer — NOT the only correct answer): "${_keeperTutoringAnswerEn}"
[USER_SPEECH]: "$userAnswer"

Judge OBJECTIVELY. The [KOREAN_PROMPT] is the source of truth for MEANING.

RULES — follow exactly:
1. MEANING CHECK (most important): Does [USER_SPEECH] express the SAME meaning as [KOREAN_PROMPT]?
   - Different wording, synonyms, or a different valid structure are FINE as long as the meaning matches [KOREAN_PROMPT]. Do not mark a real paraphrase wrong.
   - BUT if a content word changes the intended meaning (e.g. said "order" when the prompt means "arrive", wrong verb/noun, or a tense that changes the intent), it is WRONG. Do NOT praise it.
   - Ignore minor STT noise (punctuation, capitalization).
2. If the meaning matches AND grammar is correct: set "corrected" to the user's own sentence cleaned of STT noise only, and "explanation" to one short Korean praise line (you may append "다른 표현: [EXAMPLE_EN]").
3. If there is a real error: set "corrected" to an English sentence that is BOTH grammatical AND matches [KOREAN_PROMPT]'s meaning, and "explanation" to ENCOURAGING, constructive Korean feedback in 2-3 sentences. Do NOT merely say it is wrong: FIRST say what the user's sentence actually means as it stands, THEN show the specific small fix and the meaning it unlocks — e.g. "지금 문장은 '...' 뜻이에요. 'X'를 'Y'로 바꾸면 '...'가 됩니다." Be warm and positive; never scold.
4. "usage_tip_ko": Suggest 1-2 MORE NATURAL, more native-like or idiomatic ways to say the SAME meaning as "corrected" (a native-speaker upgrade). For each, put the English expression first, then a short Korean note on the nuance or feel it adds and why a native might prefer it. Aim at real spoken-English naturalness — idioms, natural phrasings, or common conversational add-ons (e.g. "though", "actually", "you know") — NOT a plain synonym swap and NOT just making the sentence longer. Write the notes in Korean. If "corrected" is already the most natural way and there is genuinely nothing valuable to add, use "".
5. Output ONLY JSON with exactly these keys: {"corrected": "...", "explanation": "...", "usage_tip_ko": "..."}''',
            },
          ],
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final jsonResult = jsonDecode(data['choices'][0]['message']['content']);
        _keeperTutoringCorrected =
            (jsonResult['corrected'] as String? ?? '').trim();
        _keeperTutoringCorrection =
            (jsonResult['explanation'] as String? ?? '').trim();
        _keeperTutoringUsageTip =
            (jsonResult['usage_tip_ko'] as String? ?? '').trim();
        _keeperDialogSetState?.call(() {});

        // STEP 4: 교정 문장 TTS 생성
        if (_keeperTutoringCorrected.isNotEmpty) {
          final audio = await _fetchTts(_keeperTutoringCorrected, 'nova');
          if (audio != null) {
            _keeperCorrectedAudio = audio;
            _keeperDialogSetState?.call(() {});
          }
        }
      }
    } catch (e) {
      debugPrint('[Keepers] correct error: $e');
    }
  }

  Future<void> _playKeeperCorrectedAudio() async {
    if (_keeperCorrectedAudio == null) return;
    if (_keeperIsPlayingCorrected) {
      await _keeperCorrectionPlayer?.stop();
      _keeperIsPlayingCorrected = false;
      _keeperDialogSetState?.call(() {});
      return;
    }
    _keeperCorrectionPlayer?.dispose();
    final player = AudioPlayer();
    _keeperCorrectionPlayer = player;
    _keeperIsPlayingCorrected = true;
    _keeperDialogSetState?.call(() {});

    player.onPlayerComplete.listen((_) {
      _keeperIsPlayingCorrected = false;
      _keeperDialogSetState?.call(() {});
    });
    BillingTicker.instance.resumeFromActivity('history_keeper_tts_start');
    await player.play(BytesSource(_keeperCorrectedAudio!));
    BillingTicker.instance.resumeFromActivity('history_keeper_tts_end');
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  기존 코드 (변경 없음)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _showBatchDeleteDialog() {
    if (_selectedDocIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("삭제할 대화 기록을 선택해주세요.",
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orangeAccent));
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("선택 기록 삭제",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
            "${_selectedDocIds.length}개의 대화 기록을 정말로 삭제하시겠습니까?\n복구할 수 없습니다.",
            style: const TextStyle(color: Colors.white70, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                for (String docId in _selectedDocIds) {
                  await currentUserReference!
                      .collection('chat_history')
                      .doc(docId)
                      .delete();
                }
                setState(() {
                  _selectedDocIds.clear();
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("선택한 기록이 삭제되었습니다.",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      backgroundColor: Colors.redAccent));
                }
              },
              child: const Text("삭제",
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  void _showOptionMenu(DocumentSnapshot doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 220,
        child: Column(
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            ListTile(
                leading: const Icon(Icons.edit, color: Colors.amber),
                title: const Text("제목 수정 (상단 고정)",
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(doc);
                }),
            ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title:
                    const Text("삭제하기", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteDialog(doc);
                }),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(DocumentSnapshot doc) {
    TextEditingController controller = TextEditingController();
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    if (data['custom_title'] != null) controller.text = data['custom_title'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("제목 수정", style: TextStyle(color: Colors.white)),
        content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                hintText: "예: 영어 면접 연습",
                hintStyle: TextStyle(color: Colors.white30),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.amber)))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                String newTitle = controller.text.trim();
                if (newTitle.isNotEmpty) {
                  await doc.reference
                      .update({'custom_title': newTitle, 'is_pinned': true});
                } else {
                  await doc.reference.update({
                    'custom_title': FieldValue.delete(),
                    'is_pinned': false
                  });
                }
              },
              child: const Text("저장",
                  style: TextStyle(
                      color: Colors.amber, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  void _showDeleteDialog(DocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("기록 삭제", style: TextStyle(color: Colors.white)),
        content: const Text("정말로 삭제하시겠습니까?",
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await doc.reference.delete();
              },
              child: const Text("삭제",
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // 📦 [Box 1: 사용설명서 팝업]
  void _showStudyRoomManual() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        title: Row(
          children: [
            const Icon(Icons.help_outline_rounded,
                color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "스터디룸 사용설명서",
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white38, size: 20),
              onPressed: () => Navigator.pop(ctx),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: SingleChildScrollView(
            child: _buildManualBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildManualBody() {
    final lines = _kManualText.split('\n');
    final widgets = <Widget>[];
    for (final line in lines) {
      if (RegExp(r'^━+$').hasMatch(line.trim())) {
        widgets.add(const SizedBox(height: 6));
        widgets
            .add(const Divider(color: Colors.white12, thickness: 1, height: 8));
      } else if (line.startsWith('📍 STEP')) {
        widgets.add(const SizedBox(height: 6));
        widgets.add(Text(line,
            style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                height: 1.7)));
      } else if (RegExp(r'^[🎯🎮🔁🎓📂❓📚]').hasMatch(line) &&
          line.length > 5) {
        widgets.add(Text(line,
            style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                height: 1.7)));
      } else if (line.startsWith('▸ ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(line,
              style: TextStyle(
                  color: Colors.amber.withValues(alpha: 0.7),
                  fontSize: 13,
                  height: 1.55)),
        ));
      } else {
        widgets.add(Text(line,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.55)));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

const String _kManualText = r'''
스터디룸에서는 대화방의 자료를 전달받아, 
입을 열어 말하는 훈련을 합니다.

🎧 소리 듣기 — 쉐도잉 연습
저장된 대화의 영어 문장을 원어민 발음으로 들으며
내 발음과 리듬을 맞춰가는 쉐도잉 훈련입니다.

🏋️ 실전 튜터링 — AI 코칭
같은 구조의 새 문장을 만들어 직접 말해보고
AI에게 교정과 피드백을 받습니다.
비슷한 문장을 반복 생성하며 패턴을 체득합니다.

🔄 Practice — 역할 교환 대화 연습
AI와 역할을 바꿔가며 실제 대화처럼 연습합니다.

✨ My Speech · Native English — 심화 훈련
내가 실제로 말한 것을 하나의 발화로 모은 My Speech와
같은 생각을 미국인이 처음부터 영어로 짠 Native English를
의미 단위(Chunk)별로 끊어 에코잉·쉐도잉으로 연습합니다.

🔊 볼륨 — 소리를 줄이고 쉐도잉하세요
따라 말하는 동안 볼륨을 줄이면
AI 목소리만 작아지고 내 목소리는 그대로 녹음됩니다.
AI 소리에 묻히지 않아 내 발음이 또렷하게 남으니
스스로 점검하며 주도적으로 연습할 수 있습니다.
녹음을 다시 들을 때는 볼륨을 올리세요.

💾 Keepers — 내 표현 보관함
마음에 드는 문장을 길게 누르면 저장.
기록을 지워도 Keepers는 남습니다.

⏸️ Auto Pause — 자동 과금 보호
60초 이상 반응이 없으면 자동으로 일시정지되어 과금이 멈춥니다.
다시 말을 시작하거나 화면을 터치하면 자동으로 재개됩니다.
자리를 비워도 요금 걱정 없이 안심하세요.''';
