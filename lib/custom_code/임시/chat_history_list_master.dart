// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom widgets
import '/custom_code/actions/index.dart'; // Imports custom actions
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import 'package:flutter/material.dart';
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '/auth/firebase_auth/auth_util.dart';

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

class _ChatHistoryListMasterState extends State<ChatHistoryListMaster> {
  String _selectedFilter = 'All';
  Set<String> _selectedDocIds = {};

  bool _isExpandRoom(String roomName) =>
      roomName.contains("Expand") || roomName.contains("Step.Ex");

  IconData _getIconForRoom(String roomName) {
    if (roomName.contains("Duo")) return Icons.people;
    if (roomName.contains("Clone")) return Icons.face;
    if (roomName.contains("Roleplay")) return Icons.smart_toy;
    if (_isExpandRoom(roomName)) return Icons.trending_up;
    if (roomName.contains("Shadowing")) return Icons.smart_toy;
    if (roomName.contains("NativeSync")) return Icons.mic_external_on;
    if (roomName.contains("Free Talk")) return Icons.forum;
    return Icons.chat_bubble_outline;
  }

  Color _getColorForRoom(String roomName) {
    if (roomName.contains("Duo")) return const Color(0xFF2563EB);
    if (roomName.contains("Clone")) return const Color(0xFF9333EA);
    if (roomName.contains("Roleplay")) return const Color(0xFF16A34A);
    if (_isExpandRoom(roomName)) return const Color(0xFFEA580C);
    if (roomName.contains("Shadowing")) return Colors.greenAccent;
    if (roomName.contains("NativeSync")) return Colors.orangeAccent;
    if (roomName.contains("Free Talk")) return Colors.pinkAccent;
    return Colors.white54;
  }

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
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              tooltip: '로비',
              icon: const Icon(Icons.home_rounded, color: Colors.white70),
              onPressed: () => context.pushNamed('Lobby'),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              tooltip: '스텔스룸',
              icon: const Icon(Icons.security, color: Colors.white70),
              onPressed: () => context.pushNamed('StealthRoom'),
            ),
          ],
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF3B82F6).withOpacity(0.5), width: 1.5),
          ),
          child: const Text(
            "Study Room",
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline_rounded,
                color: Colors.amber.withOpacity(0.75), size: 20),
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
            child: StreamBuilder<QuerySnapshot>(
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
                  Map<String, dynamic> data =
                      doc.data() as Map<String, dynamic>;
                  if (data['last_message'] == null) return false;
                  if (_selectedFilter == 'All') return true;
                  if (data['room_name'] == null) return false;
                  final rn = data['room_name'].toString();
                  if (_selectedFilter == 'Expand') return _isExpandRoom(rn);
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: _selectedFilter == 'All'
              ? [
                  _buildFilterChip('Duo', 'Duo', Icons.people),
                  _buildFilterChip('Clone', 'Clone', Icons.face),
                  _buildFilterChip('Roleplay', 'Roleplay', Icons.smart_toy),
                  _buildFilterChip('Expand', 'Expand', Icons.trending_up),
                ]
              : [
                  _buildDeleteActionChip(),
                  _buildFilterChip(_selectedFilter, _selectedFilter,
                      _getIconForRoom(_selectedFilter)),
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
              ? Colors.redAccent.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: _selectedDocIds.isNotEmpty
                  ? Colors.redAccent
                  : Colors.white24,
              width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_sweep,
                size: 16,
                color: _selectedDocIds.isNotEmpty
                    ? Colors.redAccent
                    : Colors.white54),
            const SizedBox(width: 6),
            Text("선택삭제",
                style: TextStyle(
                    color: _selectedDocIds.isNotEmpty
                        ? Colors.redAccent
                        : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            if (_selectedDocIds.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                    color: Colors.redAccent, shape: BoxShape.circle),
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
        setState(() {
          if (_selectedFilter == filterKey && filterKey != 'All') {
            _selectedFilter = 'All';
          } else {
            _selectedFilter = filterKey;
          }
          _selectedDocIds.clear();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? baseColor.withOpacity(0.2) : Colors.transparent,
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
              ? Border.all(color: Colors.amber.withOpacity(0.6), width: 1.5)
              : Border.all(
                  color:
                      isChecked ? _getColorForRoom(roomName) : Colors.white10,
                  width: isChecked ? 1.5 : 1.0),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.3),
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
                  activeColor: _getColorForRoom(roomName),
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
                color: _getColorForRoom(roomName).withOpacity(0.15),
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
                  color: Colors.amber.withOpacity(0.7),
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

const String _kManualText = r'''[스터디룸 완벽 활용 가이드]

1. 대화 목록 (History List)
• 아이콘으로 대화 성격을 확인하세요 (Duo, Clone, Roleplay, Expand).
• 상단 필터를 사용해 특정 연습 모드만 모아볼 수 있습니다.

2. 학습 모드 안내
• 실전 턴제: AI와 주고받는 자동 턴제 연습입니다. 내 차례엔 마이크가 자동 ON!
• 문장 확장: 긴 문장을 의미 단위(Chunk)로 쪼개어 정복하는 쉐도잉 모드입니다.

3. 🎓 실전 튜터링 (Step 4 Coaching)
• STEP 1 (응용): 대화 맥락을 살린 새로운 한국어 문장 생성.
• STEP 2 (도전): 내 입으로 직접 영어 답안 말하기.
• STEP 3 (교정): GPT의 문법/뉘앙스 교정 및 한국어 이유 설명.
• STEP 4 (체득): 교정된 문장 TTS 듣기 및 쉐도잉 복습.

4. 유용한 팁
• 'T'는 타겟 언어, 'S'는 해석 보기/숨기기입니다.
• 발화 유사도가 50%를 넘으면 다음 턴으로 자동 진행됩니다.''';
