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
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: DuoBoardService.watchPosts(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(_copy['loadFailed'],
                        style: const TextStyle(color: Colors.white70)),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                final uid = FirebaseAuth.instance.currentUser?.uid;
                final hasOwnActivePost =
                    docs.any((doc) => doc.data()['ownerUid'] == uid);

                return Column(
                  children: [
                    Expanded(
                      child: docs.isEmpty
                          ? Center(
                              child: Text(_copy['empty'],
                                  style:
                                      const TextStyle(color: Colors.white54)),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, index) {
                                final doc = docs[index];
                                final data = doc.data();
                                final mode =
                                    data['mode']?.toString() ?? 'interpreter';
                                final availability =
                                    data['availability']?.toString() ??
                                        'request';
                                final mine = data['ownerUid'] == uid;
                                final enabled = !mine && _claiming == null;
                                final readable = mine || _claiming == null;
                                return Card(
                                  color: const Color(0xFF202530),
                                  margin: EdgeInsets.zero,
                                  child: Stack(
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: enabled
                                            ? () => _selectPost(
                                                doc.id, availability)
                                            : null,
                                        child: Padding(
                                          padding: EdgeInsets.fromLTRB(
                                              14, 14, mine ? 46 : 14, 14),
                                          child: Row(
                                            children: [
                                              _BoardPostField(
                                                label: _copy['topic'],
                                                value:
                                                    data['topic']?.toString() ??
                                                        '',
                                                flex: 5,
                                                maxLines: 2,
                                                valueColor: readable
                                                    ? Colors.white
                                                    : Colors.white38,
                                                valueWeight: FontWeight.w700,
                                              ),
                                              const _BoardPostDivider(),
                                              _BoardPostField(
                                                label: _copy['mode'],
                                                value: mode == 'direct'
                                                    ? _copy['direct']
                                                    : _copy['interpreter'],
                                                flex: 3,
                                                valueColor: readable
                                                    ? const Color(0xFF93C5FD)
                                                    : Colors.white38,
                                              ),
                                              const _BoardPostDivider(),
                                              _BoardPostField(
                                                label: _copy['status'],
                                                value: availability == 'now'
                                                    ? _copy['now']
                                                    : _copy['request'],
                                                flex: 3,
                                                valueColor: readable
                                                    ? const Color(0xFF86EFAC)
                                                    : Colors.white38,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (mine)
                                        Positioned(
                                          top: 2,
                                          right: 0,
                                          child: IconButton(
                                            tooltip: 'Delete post',
                                            onPressed: _claiming == null
                                                ? () => _withdrawPost(doc.id)
                                                : null,
                                            icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 18),
                                            color: const Color(0xFFFCA5A5),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    // A host can publish only while no active own post exists.
                    if (widget.composeDraft != null && !hasOwnActivePost)
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ]),
      );
}

class _BoardPostDivider extends StatelessWidget {
  const _BoardPostDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 44,
        child: VerticalDivider(
          width: 17,
          thickness: 1,
          color: Colors.white12,
        ),
      );
}

class _BoardPostField extends StatelessWidget {
  const _BoardPostField({
    required this.label,
    required this.value,
    required this.flex,
    required this.valueColor,
    this.maxLines = 1,
    this.valueWeight = FontWeight.w600,
  });

  final String label;
  final String value;
  final int flex;
  final Color valueColor;
  final int maxLines;
  final FontWeight valueWeight;

  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: valueColor,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: valueWeight)),
          ],
        ),
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
