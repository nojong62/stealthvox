import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '/app_state.dart';
import '/custom_code/services/duo_invite_localization.dart';
import '/custom_code/services/duo_buddy_localization.dart';
import '/custom_code/services/duo_board_push_service.dart';
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
  bool showInactivePosts = false,
}) async {
  await DuoBoardService.ensureParticipantIdentity();
  if (!context.mounted) return null;
  return showModalBottomSheet<DuoBoardClaim>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF14171D),
    builder: (_) => DuoBoardSheet(
      composeDraft: composeDraft,
      showInactivePosts: showInactivePosts,
    ),
  );
}

Future<bool> showDuoBoardComposer(
  BuildContext context, {
  required String roomId,
  required String historyPath,
  required String mode,
  required String directLanguage,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF171A21),
    builder: (_) => _DuoBoardComposer(
      roomId: roomId,
      historyPath: historyPath,
      directLanguage: directLanguage,
    ),
  );
  return saved == true;
}

/// 서버가 `details.reason`으로 알려 준 거절 이유를 화면 언어로 바꾼다.
/// 모르는 이유면 null — 부르는 쪽이 원래 문구를 쓴다.
String? duoBoardErrorText(DuoInviteCopy copy, FirebaseFunctionsException error) {
  final details = error.details;
  final reason = details is Map ? details['reason']?.toString() : null;
  switch (reason) {
    case 'topic_rejected':
      return copy['topicRejected'];
    case 'one_post_per_guest':
      return copy['onePostOnly'];
    case 'daily_guest_limit':
      return copy['dailyGuestLimit'];
    case 'guest_daily_limit_personal':
      return copy['guestDailyLimitPersonal'];
    case 'host_daily_limit':
      return copy['hostDailyLimit'];
    case 'promo_closed':
      return copy['promoClosed'];
    case 'suspended':
      return copy['boardSuspended'];
    case 'requester_no_time':
      return DuoBuddyCopy.forSystemLocale()['requesterNoTime'];
  }
  return null;
}

/// 푸시 받기를 골랐으면 알림 권한과 토큰을 먼저 챙긴다. 권한이 없으면 0으로
/// 낮추고 안내한다 — 알림이 안 뜨는 폰으로 요청을 보내면 요청자가 헛되이 기다린다.
Future<int> duoBoardEnsurePushHours(BuildContext context, int hours) async {
  if (hours <= 0) return 0;
  var enabled = false;
  try {
    enabled = await DuoBoardPushService.enableForCurrentUser()
        .timeout(const Duration(seconds: 20));
  } catch (error) {
    debugPrint('[DuoBoard] push enable failed: $error');
  }
  if (enabled) return hours;
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(DuoBuddyCopy.forSystemLocale()['pushDenied'])));
  }
  return 0;
}

/// 푸시 받기 시간 풀다운(끄기·1·2·4·8시간).
class DuoBoardPushHoursPicker extends StatelessWidget {
  const DuoBoardPushHoursPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final copy = DuoBuddyCopy.forSystemLocale();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const Icon(Icons.notifications_active_outlined,
              color: Color(0xFF52D4C3), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(copy['pushFor'],
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          DropdownButton<int>(
            value: value,
            dropdownColor: const Color(0xFF232833),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            underline: const SizedBox.shrink(),
            items: [
              for (final hours in DuoBoardService.pushHourChoices)
                DropdownMenuItem(value: hours, child: Text(copy.hours(hours))),
            ],
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ]),
        Text(copy['pushHint'],
            style: const TextStyle(
                color: Colors.white54, fontSize: 11, height: 1.35)),
      ],
    );
  }
}

/// 이 폰에서 회원 로그인 이력이 있는가(Intro의 "이전 방식" 버튼과 같은 값).
bool duoBoardDeviceHasMemberLogin(String lastAuthProvider) =>
    const {'kakao', 'google', 'email'}.contains(lastAuthProvider.trim());

/// 초대자가 회원인지 비회원인지. 예전 글에는 값이 없고 그때는 회원만
/// 쓸 수 있었으므로 회원으로 본다.
bool duoBoardPostOwnerIsMember(Map<String, dynamic> data) =>
    data['ownerIsMember'] != false;

class _OwnerBadge extends StatelessWidget {
  const _OwnerBadge({required this.member, required this.copy});

  final bool member;
  final DuoInviteCopy copy;

  @override
  Widget build(BuildContext context) {
    final color = member ? const Color(0xFF52D4C3) : const Color(0xFFFBBF24);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        member ? copy['memberBadge'] : copy['guestBadge'],
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The composer owns its [TextEditingController] so it is disposed only after
/// the sheet route is gone. Disposing it right after `showModalBottomSheet`
/// returned broke the closing animation: the keyboard was still collapsing and
/// rebuilt the TextField with a dead controller (red screen on 2026-10-13,
/// right after a successful publish).
class _DuoBoardComposer extends StatefulWidget {
  const _DuoBoardComposer({
    required this.roomId,
    required this.historyPath,
    required this.directLanguage,
  });

  final String roomId;
  final String historyPath;
  final String directLanguage;

  @override
  State<_DuoBoardComposer> createState() => _DuoBoardComposerState();
}

class _DuoBoardComposerState extends State<_DuoBoardComposer> {
  final DuoInviteCopy copy = DuoInviteCopy.forSystemLocale();
  final TextEditingController topic = TextEditingController();
  int pushHours = DuoBoardService.defaultPushHours;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    topic.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final value = topic.text.trim();
    if (value.length < 2) {
      setState(() => error = copy['topicMinimum']);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final hours = await duoBoardEnsurePushHours(context, pushHours);
      if (!mounted) return;
      // Presence is best-effort. A slow/unavailable Realtime
      // Database must not prevent the Firestore post itself
      // from being created.
      try {
        await DuoBoardHostPresence.instance
            .ensureOnline()
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        debugPrint('[DuoBoard] host presence timed out before publish');
      } catch (presenceError) {
        debugPrint(
            '[DuoBoard] host presence unavailable before publish: $presenceError');
      }
      final originLanguage = widget.directLanguage.trim().isEmpty
          ? duoBoardViewerLanguage()
          : widget.directLanguage.trim();
      final postId = await DuoBoardService.publishPost(
          roomId: widget.roomId,
          historyPath: widget.historyPath,
          topic: value,
          // Orig. is the language the host will speak in
          // the Duo call, not the phone's UI language.
          topicLanguage: originLanguage,
          mode: 'interpreter',
          directLanguage: '',
          availability: 'request',
          pushHours: hours);
      debugPrint('[DuoBoard] post published: $postId pushHours=$hours');
      if (mounted) Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (publishError) {
      debugPrint('[DuoBoard] post publish failed: '
          '${publishError.code} ${publishError.details}');
      unawaited(DuoBoardHostPresence.instance.postEnded());
      if (!mounted) return;
      setState(() {
        saving = false;
        error = duoBoardErrorText(copy, publishError) ?? copy['postFailed'];
      });
    } catch (publishError) {
      debugPrint('[DuoBoard] post publish failed: $publishError');
      unawaited(DuoBoardHostPresence.instance.postEnded());
      if (!mounted) return;
      setState(() {
        saving = false;
        error = copy['postFailed'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        DuoBoardPushHoursPicker(
          value: pushHours,
          onChanged: (hours) => setState(() => pushHours = hours),
        ),
        const SizedBox(height: 12),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: saving ? null : _publish,
              child: Text(saving ? copy['posting'] : copy['post']),
            )),
      ]),
    );
  }
}

class DuoBoardSheet extends StatefulWidget {
  const DuoBoardSheet({
    super.key,
    this.composeDraft,
    this.showInactivePosts = false,
  });

  final DuoBoardComposeDraft? composeDraft;
  final bool showInactivePosts;
  @override
  State<DuoBoardSheet> createState() => _DuoBoardSheetState();
}

class _DuoBoardSheetState extends State<DuoBoardSheet> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _postsStream;
  String? _claiming;
  String? _error;
  final Map<String, bool> _pendingVisibility = {};
  DuoBoardPromo _promo = DuoBoardPromo.closed;
  bool _promoLoaded = false;
  StreamSubscription<DuoBoardPromo>? _promoSubscription;
  DuoInviteCopy get _copy => DuoInviteCopy.forSystemLocale();

  @override
  void initState() {
    super.initState();
    _postsStream = DuoBoardService.watchPosts();
    _promoSubscription = DuoBoardService.watchPromo().listen((promo) {
      if (mounted) {
        setState(() {
          _promo = promo;
          _promoLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _promoSubscription?.cancel();
    super.dispose();
  }

  /// 비회원 초대 버튼을 보일지. 홍보 스위치가 켜져 있고, 지금 사용자가
  /// 비회원이며, 아직 살아 있는 내 글이 없을 때만이다(폰 하나에 글 하나).
  ///
  /// 이 폰에서 회원으로 로그인한 적이 있으면 로그아웃 중이어도 숨긴다.
  /// 회원은 로그인해서 회원으로 쓰게 한다. `lastAuthProvider`는 로그아웃에서는
  /// 남고 탈퇴에서만 지워진다.
  bool _showGuestHostButton(bool hasOwnActivePost) {
    final user = FirebaseAuth.instance.currentUser;
    return _promo.guestPostsEnabled &&
        widget.composeDraft == null &&
        user != null &&
        user.isAnonymous &&
        !duoBoardDeviceHasMemberLogin(FFAppState().lastAuthProvider) &&
        !hasOwnActivePost;
  }

  void _startGuestHost() {
    Navigator.pop(context, const DuoBoardClaim.startGuestHost());
  }

  void _retryPosts() {
    if (!mounted) return;
    setState(() {
      _postsStream = DuoBoardService.watchPosts();
      _error = null;
    });
  }

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
    DuoBoardService.awaitingOwnRequest = true;
    try {
      presence = await DuoBoardService.startWaitingPresence(attemptId);
      final ticket = await DuoBoardService.requestPost(postId, attemptId);
      if (!mounted) return;
      final claim = await showDialog<DuoBoardClaim>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DuoWaitingDialog(
          requestId: ticket.requestId,
          attemptId: attemptId,
          presence: presence!,
          viaPush: ticket.viaPush,
          expiresAtMillis: ticket.expiresAtMillis,
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
          // 서버 문구(한국어 고정)는 쓰지 않는다. 폰 언어 문구만 보인다.
          _error = duoBoardErrorText(_copy, error) ?? _copy['requestFailed'];
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
    } finally {
      DuoBoardService.awaitingOwnRequest = false;
    }
  }

  Future<void> _withdrawPost(String postId) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
                title: Text(_copy['deleteTitle']),
                content: Text(_copy['deleteBody']),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: Text(_copy['cancel'])),
                  FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: Text(_copy['deleteConfirm']))
                ]));
    if (ok != true || !mounted) return;
    setState(() => _claiming = postId);
    try {
      await DuoBoardService.withdrawPost(postId);
      await DuoBoardHostPresence.instance.postEnded();
    } on FirebaseFunctionsException catch (error) {
      // 서버 문구는 한국어 고정이라 쓰지 않는다. 화면 언어 문구를 쓴다.
      debugPrint('[DuoBoard] withdraw failed: ${error.code} ${error.message}');
      if (mounted) setState(() => _error = _copy['deleteFailed']);
    } catch (_) {
      if (mounted) setState(() => _error = _copy['deleteFailed']);
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  /// 내 글의 푸시 받기 남은 시간("1:45"). 꺼져 있거나 끝났으면 null.
  String? _pushLeftLabel(Map<String, dynamic> data) {
    final until = data['pushUntil'];
    if (until is! Timestamp) return null;
    final left = until.toDate().difference(DateTime.now());
    if (left.inMinutes < 1) return null;
    final minutes = (left.inMinutes % 60).toString().padLeft(2, '0');
    return DuoBuddyCopy.forSystemLocale()
        .fill('pushLeft', {'t': '${left.inHours}:$minutes'});
  }

  /// 꺼진 내 글을 켤 때 푸시 받기 시간을 다시 고른다. null이면 취소.
  Future<int?> _askPushHours() {
    var hours = DuoBoardService.defaultPushHours;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF171A21),
          content: DuoBoardPushHoursPicker(
            value: hours,
            onChanged: (next) => setDialogState(() => hours = next),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_copy['cancel']),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, hours),
              child: Text(_copy['activatePost']),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePostVisibility(
      String postId, bool currentlyVisible) async {
    int pushHours = 0;
    if (!currentlyVisible) {
      final picked = await _askPushHours();
      if (picked == null || !mounted) return;
      pushHours = await duoBoardEnsurePushHours(context, picked);
      if (!mounted) return;
    }
    DuoBoardHostPresence.instance.postVisibilityChanged();
    final nextVisible = !currentlyVisible;
    setState(() {
      _claiming = postId;
      _error = null;
      _pendingVisibility[postId] = nextVisible;
    });
    try {
      if (!currentlyVisible) {
        try {
          await DuoBoardHostPresence.instance
              .ensureOnline()
              .timeout(const Duration(seconds: 3));
        } catch (error) {
          debugPrint('[DuoBoard] presence refresh before activation: $error');
        }
      }
      if (pushHours > 0) {
        // 시간을 켜면 서버가 글도 함께 활성으로 켠다.
        await DuoBoardService.setPushWindow(postId, pushHours);
      } else {
        await DuoBoardService.setPostVisibility(
          postId,
          enabled: nextVisible,
        );
      }
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() => _pendingVisibility.remove(postId));
        }
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        debugPrint(
            '[DuoBoard] visibility update failed: ${error.code} ${error.message}');
        setState(() {
          _pendingVisibility.remove(postId);
          _error = _copy['visibilityFailed'];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pendingVisibility.remove(postId);
          _error = _copy['visibilityFailed'];
        });
      }
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
              stream: _postsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_copy['loadFailed'],
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _retryPosts,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_copy['retry']),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allDocs = snapshot.data!.docs;
                final uid = FirebaseAuth.instance.currentUser?.uid;
                final docs = allDocs.where((doc) {
                  final data = doc.data();
                  final mine = data['ownerUid'] == uid;
                  final available = data['discoverable'] == true;
                  final isOpenInvitation = data['state'] != 'reserved';
                  if (!mine && !duoBoardPostOwnerIsMember(data)) {
                    // 비회원 글은 지금 받을 수 있을 때만 보인다. 꺼진 비회원
                    // 글은 대부분 주인이 떠났거나(기존 계정 로그인 등) 홍보가
                    // 끝난 글이라 기다려도 열리지 않는다.
                    return available &&
                        (!_promoLoaded || _promo.guestPostsEnabled);
                  }
                  return mine ||
                      available ||
                      (widget.showInactivePosts && isOpenInvitation);
                }).toList();
                docs.sort((a, b) {
                  final aData = a.data();
                  final bData = b.data();

                  bool isVisible(
                    QueryDocumentSnapshot<Map<String, dynamic>> doc,
                    Map<String, dynamic> data,
                  ) {
                    final pending = _pendingVisibility[doc.id];
                    return pending ??
                        (data['active'] == true &&
                            data['state'] != 'reserved' &&
                            data['discoverable'] == true &&
                            data['ownerPaused'] != true);
                  }

                  final activeOrder = (isVisible(b, bData) ? 1 : 0)
                      .compareTo(isVisible(a, aData) ? 1 : 0);
                  if (activeOrder != 0) return activeOrder;

                  // Within each visibility group, keep the original posting
                  // order newest-first. The document id makes equal/missing
                  // timestamps deterministic across stream refreshes.
                  int createdMillis(Map<String, dynamic> data) {
                    final value = data['createdAt'];
                    if (value is Timestamp) {
                      return value.millisecondsSinceEpoch;
                    }
                    if (value is DateTime) {
                      return value.millisecondsSinceEpoch;
                    }
                    return 0;
                  }

                  final byCreated = createdMillis(bData).compareTo(
                    createdMillis(aData),
                  );
                  return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
                });
                final hasOwnActivePost =
                    allDocs.any((doc) => doc.data()['ownerUid'] == uid);
                final showGuestHost = _showGuestHostButton(hasOwnActivePost);

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
                                final pendingVisibility =
                                    _pendingVisibility[doc.id];
                                // Show availability confirmed by the server;
                                // login recovery may still be in progress.
                                final available = pendingVisibility ??
                                    (mine
                                        ? data['active'] == true &&
                                            data['state'] != 'reserved' &&
                                            data['discoverable'] == true &&
                                            data['ownerPaused'] != true
                                        : data['discoverable'] == true);
                                final enabled =
                                    !mine && available && _claiming == null;
                                final readable = mine || _claiming == null;
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
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            _copy['topic'],
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .white54,
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          ),
                                                        ),
                                                        // 배지는 비회원 글에만 단다.
                                                        // 회원 글은 표시 없이 둔다.
                                                        if (!duoBoardPostOwnerIsMember(
                                                            data))
                                                          _OwnerBadge(
                                                            member: false,
                                                            copy: _copy,
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 5),
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                          child:
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
                                                                : Colors
                                                                    .white38,
                                                          ),
                                                        ),
                                                      ],
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
                                                    if (mine &&
                                                        _pushLeftLabel(data) !=
                                                            null)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 4),
                                                        child: Text(
                                                          _pushLeftLabel(
                                                              data)!,
                                                          style:
                                                              const TextStyle(
                                                            color: Color(
                                                                0xFF86EFAC),
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700,
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
                                                      VisualDensity.standard,
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
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.circle,
                                                        size: 13,
                                                        color: available
                                                            ? const Color(
                                                                0xFF22C55E)
                                                            : Colors.white30,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        available
                                                            ? _copy['active']
                                                            : _copy['inactive'],
                                                        style: TextStyle(
                                                          color: available
                                                              ? const Color(
                                                                  0xFF86EFAC)
                                                              : Colors.white38,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
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
                                                      VisualDensity.standard,
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
                    // 홍보 기간: 비회원도 가입 없이 초대글을 올린다.
                    if (showGuestHost)
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _copy['guestHostPitch'],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFDE68A),
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed:
                                      _claiming == null ? _startGuestHost : null,
                                  icon: const Icon(Icons.public_rounded,
                                      size: 18),
                                  label: Text(_copy['guestHostWrite']),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFB7791F),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 15),
                                  ),
                                ),
                              ),
                            ],
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
    this.viaPush = false,
    this.expiresAtMillis = 0,
  });

  final String requestId;
  final String attemptId;
  final DatabaseReference presence;

  /// 초대자 앱이 꺼져 있어 알림으로 불렀다. 서버가 더 오래 기다린다.
  final bool viaPush;
  final int expiresAtMillis;

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
        final copy = DuoInviteCopy.forSystemLocale();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
              content: Text(status == 'busy'
                  ? copy['hostBusy']
                  : copy['hostNoResponse'])),
        );
      }
    });
    // 서버 만료 시각에 5초를 더 준다(시계 차이). 값이 없는 옛 서버면 35초.
    final untilExpiry =
        widget.expiresAtMillis - DateTime.now().millisecondsSinceEpoch;
    final wait = untilExpiry > 0
        ? Duration(milliseconds: untilExpiry + 5000)
        : const Duration(seconds: 35);
    _timer = Timer(wait, () {
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
    final copy = DuoInviteCopy.forSystemLocale();
    return AlertDialog(
      title: Text(copy['requestSent']),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(widget.viaPush
              ? DuoBuddyCopy.forSystemLocale()['pushSent']
              : copy['waitingShort']),
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
