import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '/app_state.dart';
import '/custom_code/services/duo_invite_localization.dart';
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
  final copy = DuoInviteCopy.forLanguage(FFAppState().chatLang);
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
          Text(copy['composerTitle'],
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
              mode == 'direct'
                  ? '${copy['direct']} · $directLanguage'
                  : copy['interpreter'],
              style: const TextStyle(color: Color(0xFF93C5FD))),
          const SizedBox(height: 18),
          TextField(
            controller: topic,
            autofocus: true,
            maxLength: 80,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: copy['topic'],
              hintText: copy['topicHint'],
              errorText: error,
              filled: true,
              fillColor: const Color(0xFF232833),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'now', label: Text(copy['now'])),
              ButtonSegment(value: 'request', label: Text(copy['request'])),
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
                            title: Text(copy['notifyTitle']),
                            content: Text(copy['notifyBody']),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: Text(copy['later']),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: Text(copy['enable']),
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
                          setLocal(() => error = copy['topicMinimum']);
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
                            error = copy['postFailed'];
                          });
                        }
                      },
                child: Text(saving ? copy['posting'] : copy['post']),
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
  DuoInviteCopy get _copy => DuoInviteCopy.forLanguage(FFAppState().chatLang);

  Future<void> _writePost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() => _error = _copy['loginOnly']);
      return;
    }
    final draft = widget.composeDraft;
    if (draft == null) {
      setState(() => _error = _copy['writeFromRoom']);
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
              ? _copy['claimFailed']
              : _copy['requestFailed'];
        });
      }
    }
  }

  Future<void> _withdrawPost(String postId) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
                title: const Text('Delete post?'),
                content:
                    const Text('Remove your Duo invitation from the board?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Delete'))
                ]));
    if (ok != true || !mounted) return;
    setState(() => _claiming = postId);
    try {
      await DuoBoardService.withdrawPost(postId);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not delete the post.');
    } finally {
      if (mounted) setState(() => _claiming = null);
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
                Expanded(
                  child: Text(_copy['boardTitle'],
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                ),
              ])),
          Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_copy['boardSubtitle'],
                      style: const TextStyle(color: Colors.white54)))),
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
            child: Row(children: [
              Expanded(
                flex: 5,
                child: Text(_copy['topic'],
                    style: const TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                flex: 3,
                child: Text(_copy['mode'],
                    style: const TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                flex: 3,
                child: Text(_copy['status'],
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: DuoBoardService.watchPosts(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: Text(_copy['loadFailed'],
                        style: const TextStyle(color: Colors.white70)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return Center(
                    child: Text(_copy['empty'],
                        style: const TextStyle(color: Colors.white54)));
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
                              mode == 'direct'
                                  ? _copy['direct']
                                  : _copy['interpreter'],
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
                              availability == 'now'
                                  ? _copy['now']
                                  : _copy['request'],
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color:
                                      enabled ? Colors.white70 : Colors.white38,
                                  fontSize: 11),
                            ),
                          ),
                          if (mine)
                            IconButton(
                                tooltip: 'Delete post',
                                onPressed: _claiming == null
                                    ? () => _withdrawPost(doc.id)
                                    : null,
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 19),
                                color: const Color(0xFFFCA5A5),
                                visualDensity: VisualDensity.compact),
                        ]),
                      ),
                    ),
                  );
                },
              );
            },
          )),
          // Only a Duo host has a private room draft to publish. Intro and
          // Lobby open the board for joining, so they intentionally have no
          // write action.
          if (widget.composeDraft != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _writePost,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(_copy['write']),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2D8F83),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ),
            ),
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
  Widget build(BuildContext context) {
    final copy = DuoInviteCopy.forLanguage(FFAppState().chatLang);
    return AlertDialog(
      title: Text(copy['requestSent']),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text(copy['waiting']),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(copy['cancelWaiting']),
        ),
      ],
    );
  }
}
