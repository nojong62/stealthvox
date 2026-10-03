import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '/app_state.dart';
import '/custom_code/services/duo_invite_localization.dart';
import '/custom_code/services/duo_board_service.dart';
import '/custom_code/services/duo_board_host_presence.dart';
import '/custom_code/services/duo_board_topic_translation.dart';

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
          const SizedBox(height: 8),
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
                          // Presence is best-effort. A slow/unavailable Realtime
                          // Database must not prevent the Firestore post itself
                          // from being created.
                          try {
                            await DuoBoardHostPresence.instance
                                .ensureOnline()
                                .timeout(const Duration(seconds: 5));
                          } on TimeoutException {
                            debugPrint(
                                '[DuoBoard] host presence timed out before publish');
                          } catch (presenceError) {
                            debugPrint(
                                '[DuoBoard] host presence unavailable before publish: $presenceError');
                          }
                          await DuoBoardService.publishPost(
                              roomId: roomId,
                              historyPath: historyPath,
                              topic: value,
                              topicLanguage: FFAppState().chatLang.isNotEmpty
                                  ? FFAppState().chatLang
                                  : duoBoardViewerLanguage(),
                              mode: 'interpreter',
                              directLanguage: '',
                              availability: 'request');
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        } catch (publishError) {
                          debugPrint(
                              '[DuoBoard] post publish failed: $publishError');
                          unawaited(DuoBoardHostPresence.instance.postEnded());
                          if (!sheetContext.mounted) return;
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
  DuoInviteCopy get _copy =>
      DuoInviteCopy.forLanguage(duoBoardViewerLanguage());

  Future<void> _writePost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() => _error = _copy['loginOnly']);
      return;
    }
    final draft = widget.composeDraft;
    if (draft == null || draft.mode != 'interpreter') {
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
    final attemptId = DuoBoardService.createRequestAttemptId();
    try {
      presence = await DuoBoardService.startWaitingPresence(attemptId);
      final requestId = await DuoBoardService.requestPost(postId, attemptId);
      if (!mounted) return;
      final claim = await showDialog<DuoBoardClaim>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DuoWaitingDialog(
          requestId: requestId,
          attemptId: attemptId,
          presence: presence!,
        ),
      );
      if (claim != null && mounted) {
        Navigator.pop(context, claim);
        return;
      }
      if (mounted) setState(() => _claiming = null);
    } on FirebaseFunctionsException catch (error) {
      debugPrint('[DuoBoard] request failed: ${error.code} ${error.message}');
      await presence?.remove();
      if (mounted) {
        setState(() {
          _claiming = null;
          _error = error.message ?? _copy['requestFailed'];
        });
      }
    } catch (error) {
      debugPrint('[DuoBoard] request failed: $error');
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
      await DuoBoardHostPresence.instance.postEnded();
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Could not delete the post.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not delete the post.');
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  Future<void> _togglePostVisibility(
      String postId, bool currentlyVisible) async {
    setState(() {
      _claiming = postId;
      _error = null;
    });
    try {
      if (!currentlyVisible) {
        try {
          await DuoBoardHostPresence.instance
              .ensureOnline()
              .timeout(const Duration(seconds: 5));
        } catch (error) {
          debugPrint('[DuoBoard] presence refresh before activation: $error');
        }
      }
      await DuoBoardService.setPostVisibility(
        postId,
        enabled: !currentlyVisible,
      );
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        debugPrint(
            '[DuoBoard] visibility update failed: ${error.code} ${error.message}');
        setState(() => _error = _copy['visibilityFailed']);
      }
    } catch (_) {
      if (mounted) setState(() => _error = _copy['visibilityFailed']);
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                final allDocs = snapshot.data!.docs;
                final uid = FirebaseAuth.instance.currentUser?.uid;
                final docs = allDocs
                    .where((doc) =>
                        doc.data()['discoverable'] == true ||
                        doc.data()['ownerUid'] == uid)
                    .toList();
                final hasOwnActivePost =
                    allDocs.any((doc) => doc.data()['ownerUid'] == uid);

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
                                final mine = data['ownerUid'] == uid;
                                final enabled = !mine && _claiming == null;
                                final readable = mine || _claiming == null;
                                final available = data['discoverable'] == true;
                                return Card(
                                  color: const Color(0xFF202530),
                                  margin: EdgeInsets.zero,
                                  child: Stack(
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: enabled
                                            ? () =>
                                                _selectPost(doc.id, 'request')
                                            : null,
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(_copy['topic'],
                                                        style: const TextStyle(
                                                            color:
                                                                Colors.white54,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                    const SizedBox(height: 5),
                                                    _TranslatedBoardTopic(
                                                      text: data['topic']
                                                              ?.toString() ??
                                                          '',
                                                      sourceLanguage:
                                                          data['topicLanguage']
                                                                  ?.toString() ??
                                                              '',
                                                      color: readable
                                                          ? Colors.white
                                                          : Colors.white38,
                                                    ),
                                                    if (duoBoardNeedsTranslation(
                                                      sourceLanguage:
                                                          data['topicLanguage']
                                                                  ?.toString() ??
                                                              '',
                                                      targetLanguage:
                                                          duoBoardViewerLanguage(),
                                                    ))
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                top: 4),
                                                        child: Text(
                                                          'Powered by Google Translate',
                                                          style: TextStyle(
                                                            color:
                                                                Colors.white38,
                                                            fontSize: 8,
                                                            height: 1.1,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              if (mine)
                                                IconButton(
                                                  tooltip: available
                                                      ? _copy['deactivatePost']
                                                      : _copy['activatePost'],
                                                  onPressed: _claiming == null
                                                      ? () =>
                                                          _togglePostVisibility(
                                                              doc.id, available)
                                                      : null,
                                                  icon: Icon(
                                                    Icons.circle,
                                                    size: 17,
                                                    color: available
                                                        ? const Color(
                                                            0xFF22C55E)
                                                        : Colors.white30,
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                )
                                              else if (_claiming == doc.id)
                                                const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              else
                                                Tooltip(
                                                  message: available
                                                      ? _copy['active']
                                                      : _copy['inactive'],
                                                  child: Icon(
                                                    Icons.circle,
                                                    size: 15,
                                                    color: available
                                                        ? const Color(
                                                            0xFF22C55E)
                                                        : Colors.white30,
                                                  ),
                                                ),
                                              if (mine) ...[
                                                IconButton(
                                                  tooltip: _copy['deletePost'],
                                                  onPressed: _claiming == null
                                                      ? () =>
                                                          _withdrawPost(doc.id)
                                                      : null,
                                                  icon: const Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                      size: 21),
                                                  color:
                                                      const Color(0xFFFCA5A5),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    // A host can publish only while no active own post exists.
                    if (widget.composeDraft?.mode == 'interpreter' &&
                        !hasOwnActivePost)
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

class _TranslatedBoardTopic extends StatelessWidget {
  const _TranslatedBoardTopic({
    required this.text,
    required this.sourceLanguage,
    required this.color,
  });

  final String text;
  final String sourceLanguage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final targetLanguage = duoBoardViewerLanguage();
    return FutureBuilder<String>(
      initialData: text,
      future: DuoBoardTopicTranslation.translate(
        text: text,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      ),
      builder: (_, snapshot) => Text(
        snapshot.data ?? text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 14,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DuoWaitingDialog extends StatefulWidget {
  const _DuoWaitingDialog({
    required this.requestId,
    required this.attemptId,
    required this.presence,
  });

  final String requestId;
  final String attemptId;
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
      if (!mounted) return;
      if (data?['attemptId']?.toString() != widget.attemptId) return;
      final status = data?['status']?.toString();
      if (status == 'matched') {
        _matched = true;
        Navigator.pop(
          context,
          DuoBoardClaim(
            roomId: data?['roomId']?.toString() ?? '',
            ownerUid: data?['ownerUid']?.toString() ?? '',
          ),
        );
      } else if (status == 'busy' ||
          status == 'timeout' ||
          status == 'expired' ||
          status == 'cancelled') {
        Navigator.pop(context);
        final copy = DuoInviteCopy.forLanguage(duoBoardViewerLanguage());
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
              content: Text(status == 'busy'
                  ? copy['hostBusy']
                  : copy['hostNoResponse'])),
        );
      }
    });
    _timer = Timer(const Duration(seconds: 35), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    unawaited(widget.presence.onDisconnect().cancel());
    unawaited(widget.presence.remove());
    if (!_matched) {
      unawaited(
          DuoBoardService.cancelRequest(widget.requestId, widget.attemptId));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = DuoInviteCopy.forLanguage(duoBoardViewerLanguage());
    return AlertDialog(
      title: Text(copy['requestSent']),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(copy['waitingShort']),
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
