import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '/custom_code/services/duo_board_service.dart';
import '/custom_code/services/duo_board_push_service.dart';

class DuoBoardComposeDraft {
  const DuoBoardComposeDraft({
    required this.roomId,
    required this.historyPath,
    required this.mode,
    required this.directLanguage,
  });

  final String roomId;
  final String historyPath;
  final String mode;
  final String directLanguage;
}

Future<DuoBoardClaim?> showDuoBoardSheet(
  BuildContext context, {
  DuoBoardComposeDraft? composeDraft,
}) async {
  await DuoBoardService.ensureParticipantIdentity();
  if (!context.mounted) return null;
  return showModalBottomSheet<DuoBoardClaim>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF14171D),
    builder: (_) => DuoBoardSheet(composeDraft: composeDraft),
  );
}

Future<bool> showDuoBoardComposer(
  BuildContext context, {
  required String roomId,
  required String historyPath,
  required String mode,
  required String directLanguage,
}) async {
  final topic = TextEditingController();
  var saving = false;
  String? error;
  var availability = 'now';
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF171A21),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setLocal) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 22, 22, 22 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Duo 게시판에 올리기',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(mode == 'direct' ? 'Direct · $directLanguage' : 'Interpreter',
              style: const TextStyle(color: Color(0xFF93C5FD))),
          const SizedBox(height: 18),
          TextField(
            controller: topic,
            autofocus: true,
            maxLength: 80,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: '대화 주제',
              hintText: '예: 여행 이야기',
              errorText: error,
              filled: true,
              fillColor: const Color(0xFF232833),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'now', label: Text('🟢 지금 가능')),
              ButtonSegment(value: 'request', label: Text('⚪ 요청 가능')),
            ],
            selected: {availability},
            onSelectionChanged: saving
                ? null
                : (value) async {
                    final next = value.first;
                    if (next == 'request') {
                      var enableNotifications =
                          await DuoBoardPushService.isAuthorized;
                      if (!enableNotifications && sheetContext.mounted) {
                        final enable = await showDialog<bool>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Duo 요청을 알려드릴까요?'),
                            content: const Text(
                              '앱을 나가도 대화를 원하는 사람이 생기면 알려드릴 수 있습니다. StealthVox 알림을 허용해 주세요.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('나중에'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('알림 켜기'),
                              ),
                            ],
                          ),
                        );
                        enableNotifications = enable == true;
                      }
                      if (enableNotifications) {
                        await DuoBoardPushService.enableForCurrentMember();
                      }
                    }
                    if (sheetContext.mounted) {
                      setLocal(() => availability = next);
                    }
                  },
          ),
          const SizedBox(height: 20),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final value = topic.text.trim();
                        if (value.length < 2) {
                          setLocal(() => error = '주제를 두 글자 이상 입력해 주세요.');
                          return;
                        }
                        setLocal(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await DuoBoardService.publishPost(
                              roomId: roomId,
                              historyPath: historyPath,
                              topic: value,
                              mode: mode,
                              directLanguage: directLanguage,
                              availability: availability);
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        } catch (_) {
                          setLocal(() {
                            saving = false;
                            error = '등록하지 못했습니다. 잠시 후 다시 시도해 주세요.';
                          });
                        }
                      },
                child: Text(saving ? '등록 중…' : '게시하기'),
              )),
        ]),
      ),
    ),
  );
  topic.dispose();
  return saved == true;
}

class DuoBoardSheet extends StatefulWidget {
  const DuoBoardSheet({super.key, this.composeDraft});

  final DuoBoardComposeDraft? composeDraft;
  @override
  State<DuoBoardSheet> createState() => _DuoBoardSheetState();
}

class _DuoBoardSheetState extends State<DuoBoardSheet> {
  String? _claiming;
  String? _error;

  Future<void> _writePost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() => _error = '게시글 작성은 로그인한 회원만 가능합니다.');
      return;
    }
    final draft = widget.composeDraft;
    if (draft == null) {
      setState(() => _error = 'Duo 대화방의 초대 아이콘에서 글쓰기를 시작해 주세요.');
      return;
    }
    final posted = await showDuoBoardComposer(
      context,
      roomId: draft.roomId,
      historyPath: draft.historyPath,
      mode: draft.mode,
      directLanguage: draft.directLanguage,
    );
    if (posted && mounted) {
      setState(() => _error = null);
    }
  }

  Future<void> _selectPost(String postId, String availability) async {
    setState(() {
      _claiming = postId;
      _error = null;
    });
    DatabaseReference? presence;
    try {
      if (availability == 'now') {
        final claim = await DuoBoardService.claimNow(postId);
        if (mounted) Navigator.pop(context, claim);
        return;
      }
      presence = await DuoBoardService.startWaitingPresence(postId);
      final requestId = await DuoBoardService.requestPost(postId);
      if (!mounted) return;
      final claim = await showDialog<DuoBoardClaim>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _DuoWaitingDialog(
          requestId: requestId,
          presence: presence!,
        ),
      );
      if (claim != null && mounted) Navigator.pop(context, claim);
    } catch (_) {
      await presence?.remove();
      if (mounted) {
        setState(() {
          _claiming = null;
          _error = availability == 'now'
              ? '이미 다른 사용자가 선점했거나 초대가 만료되었습니다.'
              : '다른 요청자가 기다리는 중이거나 요청을 보낼 수 없습니다.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99))),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(children: [
                const Icon(Icons.forum_outlined, color: Color(0xFF52D4C3)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Duo 초대 게시판',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                ),
                FilledButton.icon(
                  onPressed: _writePost,
                  icon: const Icon(Icons.edit_rounded, size: 17),
                  label: const Text('글쓰기'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2D8F83),
                    foregroundColor: Colors.white,
                  ),
                ),
              ])),
          const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('상대를 찾은 뒤 기존 Duo 통화로 연결됩니다.',
                      style: TextStyle(color: Colors.white54)))),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(_error!,
                    style: const TextStyle(color: Color(0xFFFCA5A5)))),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF191E27),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(children: [
              Expanded(
                flex: 5,
                child: Text('대화 주제',
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                flex: 3,
                child: Text('방식',
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                flex: 3,
                child: Text('상태',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: DuoBoardService.watchPosts(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                    child: Text('게시글을 불러오지 못했습니다.',
                        style: TextStyle(color: Colors.white70)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                    child: Text('아직 올라온 초대가 없습니다.',
                        style: TextStyle(color: Colors.white54)));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final mode = data['mode']?.toString() ?? 'interpreter';
                  final availability =
                      data['availability']?.toString() ?? 'request';
                  final mine = data['ownerUid'] ==
                      FirebaseAuth.instance.currentUser?.uid;
                  final enabled = !mine && _claiming == null;
                  return Card(
                    color: const Color(0xFF202530),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: enabled
                          ? () => _selectPost(doc.id, availability)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 16),
                        child: Row(children: [
                          Expanded(
                            flex: 5,
                            child: Text(data['topic']?.toString() ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color:
                                        enabled ? Colors.white : Colors.white38,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              mode == 'direct' ? 'Direct' : 'Interpreter',
                              style: TextStyle(
                                  color: enabled
                                      ? const Color(0xFF93C5FD)
                                      : Colors.white38,
                                  fontSize: 12),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              availability == 'now' ? '🟢 지금 가능' : '⚪ 요청 가능',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color:
                                      enabled ? Colors.white70 : Colors.white38,
                                  fontSize: 11),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              );
            },
          )),
        ]),
      );
}

class _DuoWaitingDialog extends StatefulWidget {
  const _DuoWaitingDialog({
    required this.requestId,
    required this.presence,
  });

  final String requestId;
  final DatabaseReference presence;

  @override
  State<_DuoWaitingDialog> createState() => _DuoWaitingDialogState();
}

class _DuoWaitingDialogState extends State<_DuoWaitingDialog> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _timer;
  bool _matched = false;

  @override
  void initState() {
    super.initState();
    _subscription =
        DuoBoardService.watchRequest(widget.requestId).listen((snap) {
      final data = snap.data();
      if (!mounted || data?['status'] != 'matched') return;
      _matched = true;
      Navigator.pop(
        context,
        DuoBoardClaim(
          roomId: data?['roomId']?.toString() ?? '',
          ownerUid: data?['ownerUid']?.toString() ?? '',
        ),
      );
    });
    _timer = Timer(const Duration(minutes: 5), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    unawaited(widget.presence.onDisconnect().cancel());
    unawaited(widget.presence.remove());
    if (!_matched) unawaited(DuoBoardService.cancelRequest(widget.requestId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Duo 요청을 보냈습니다'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text('작성자가 돌아오기를 기다리고 있습니다.\n대기 시간은 최대 5분입니다.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('대기 취소'),
          ),
        ],
      );
}
