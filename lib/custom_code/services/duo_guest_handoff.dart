// ====================================================================
// 🔁 [DUO-HANDOFF] 익명으로 초대받아 대화한 사람이, 끝나고 **자기 계정으로
// 로그인했을 때** 방금 그 대화를 되찾는 길.
// --------------------------------------------------------------------
// 기존 회원이 로그아웃 상태로 초대를 받으면 앱은 그가 회원인지 알 수 없다.
// 그래서 익명 uid로 대화하고, 기록도 그 uid 아래 쌓인다. 그 뒤 구글 등으로
// **기존 계정**에 로그인하면 uid가 통째로 바뀐다(익명 계정에 link할 수 없는
// 자리다 — `social_auth_service`의 credential-already-in-use 갈래).
// 그러면 방금 한 대화가 화면에서 사라진 것처럼 보인다.
//
// 되찾는 방법은 **익명 문서를 옮기는 것이 아니라 공유 결과로 다시 만드는
// 것**이다.
//
//   duo_sessions/{roomId}/canonical/current   ← 하나뿐인 진짜 대화
//        │
//        └─▶ users/{내 회원 uid}/chat_history/{new}   ← 여기에 새로 짓는다
//
//   · 익명 uid와 회원 uid가 충돌할 일이 없다
//   · 호스트·게스트 양쪽이 같은 근거로 같은 대화를 복구한다
//   · 몇 번을 다시 돌려도 결과가 하나다(방 id로 이미 있는지 먼저 본다)
//
// 🔒 **기기에 roomId가 남아 있다는 것만으로는 복구하지 않는다.** 그 방의
// 참가자였다는 증거가 있어야 한다. 지금 구조에서 확보할 수 있는 증거는
// "통화 당시 내 익명 uid"이고, 그것은 세션 문서의 `partnerUid`(게스트) ·
// `hostUid`(호스트)와 대조할 수 있다. 이 값은 **그 기기에서 그 통화를 한
// 사람만** 가지고 있다.
//
// ⚠️ 익명 계정이 그대로 회원이 되는 정상 경로(linkWithCredential, uid 유지)는
// 이 파일이 건드리지 않는다. uid가 같으면 되찾을 것이 없으므로 그냥 표만
// 지운다.
// ====================================================================

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '/flutter_flow/flutter_flow_util.dart';
import 'duo_canonical.dart';
import 'duo_study_state.dart';

/// 통화 당시의 나를 증명하는 표. 기기에만 남는다.
@immutable
class DuoGuestClaim {
  const DuoGuestClaim({
    required this.roomId,
    required this.uid,
    required this.role,
    required this.savedAtMs,
    this.nativeLang = '',
    this.targetLang = '',
  });

  /// 어느 통화였나.
  final String roomId;

  /// 그 통화에서 쓰던 내 uid(익명). 세션 문서와 대조할 유일한 증거다.
  final String uid;

  /// 그 통화에서의 내 역할. 채널에 실린 값 그대로(HOST/GUEST).
  final String role;

  final int savedAtMs;

  /// 되살릴 방에 적어 둘 언어. canonical에는 없는 값이라 여기서 들고 간다.
  final String nativeLang;
  final String targetLang;

  bool get isValid => roomId.isNotEmpty && uid.isNotEmpty && role.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'room_id': roomId,
        'uid': uid,
        'role': role,
        'saved_at_ms': savedAtMs,
        if (nativeLang.isNotEmpty) 'native_lang': nativeLang,
        if (targetLang.isNotEmpty) 'target_lang': targetLang,
      };

  static DuoGuestClaim? fromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final claim = DuoGuestClaim(
        roomId: (decoded['room_id'] ?? '').toString(),
        uid: (decoded['uid'] ?? '').toString(),
        role: (decoded['role'] ?? '').toString(),
        savedAtMs: (decoded['saved_at_ms'] as num?)?.toInt() ?? 0,
        nativeLang: (decoded['native_lang'] ?? '').toString(),
        targetLang: (decoded['target_lang'] ?? '').toString(),
      );
      return claim.isValid ? claim : null;
    } catch (_) {
      return null;
    }
  }
}

/// 표가 늙으면 버린다. 며칠 뒤 로그인한 사람의 화면에 옛 통화가 새 대화처럼
/// 튀어나오지 않게 한다. 앱을 껐다 켜고 로그인하는 정도는 넉넉히 덮는다.
const Duration kDuoGuestClaimTtl = Duration(hours: 24);

/// 복구를 시도한 결과. 화면은 [restored]일 때만 무언가를 알린다.
enum DuoRestoreOutcome {
  /// 되찾을 표가 없다. 대부분의 로그인이 여기다.
  noClaim,

  /// 표가 너무 오래됐다.
  expired,

  /// uid가 그대로다(익명 → 같은 uid 회원). 되찾을 것이 없다.
  sameAccount,

  /// 그 통화의 참가자가 아니다. **다른 계정으로 로그인한 경우다.**
  notParticipant,

  /// 공유 결과가 아직 안 만들어졌다. 표를 남겨 두고 다음에 다시 본다.
  canonicalNotReady,

  /// 이미 그 방의 기록을 가지고 있다.
  alreadyPresent,

  /// 쓰다 만 복구본을 찾아 지우고 다시 지으려 한다. 이번 회차는 여기서
  /// 끝내고 다음 회차가 새로 짓는다.
  incompleteRetry,

  /// 새로 지었다.
  restored,

  /// 읽기·쓰기가 실패했다. 표는 남긴다.
  failed,
}

// ── 표 저장 ────────────────────────────────────────────────────────────

void rememberDuoGuestClaim(DuoGuestClaim claim) {
  if (!claim.isValid) return;
  FFAppState().duoGuestClaim = jsonEncode(claim.toJson());
  // 방 id와 역할만 적는다 — uid도 대화 내용도 로그에 남기지 않는다.
  debugPrint('[DUO-HANDOFF] claim_saved room=${claim.roomId} '
      'role=${claim.role}');
}

DuoGuestClaim? readDuoGuestClaim() =>
    DuoGuestClaim.fromJson(FFAppState().duoGuestClaim);

void clearDuoGuestClaim() {
  if (FFAppState().duoGuestClaim.isEmpty) return;
  FFAppState().duoGuestClaim = '';
  debugPrint('[DUO-HANDOFF] claim_cleared');
}

// ── 순수 판정 (테스트가 이 자리를 본다) ──────────────────────────────────

/// 표가 아직 쓸 만한가.
bool isDuoGuestClaimFresh(DuoGuestClaim claim, {DateTime? now}) {
  final DateTime at = DateTime.fromMillisecondsSinceEpoch(claim.savedAtMs);
  final DateTime ref = now ?? DateTime.now();
  final Duration age = ref.difference(at);
  return !age.isNegative && age <= kDuoGuestClaimTtl;
}

/// 🔒 이 사람이 정말 그 통화에 있었나.
///
/// **roomId만으로는 절대 통과시키지 않는다.** 대조할 수 있는 값은 세션 문서에
/// 이미 있는 것들뿐이고, 셋을 함께 본다.
///
///   ① 역할 — GUEST 표로 호스트 자리에 붙지 못한다. 그 반대도 마찬가지다.
///   ② 참가자 uid — `hostUid` · `partnerUid`
///   ③ `flush_done` 키 — "내 몫을 다 올렸다"고 그 uid로 찍힌 표시.
///      **이 값은 지워지지 않는다.** 같은 방에 다른 사람이 다시 초대돼
///      `partnerUid`가 덮여도, 먼저 대화한 사람의 자취는 여기 남는다.
///
/// ③이 필요한 이유가 실제로 있다: 호스트가 같은 방으로 다른 사람을 다시
/// 부르면 `partnerUid`가 새 게스트로 바뀐다. 그러면 ②만 보는 검증은 먼저
/// 대화한 사람의 복구를 영영 막는다.
bool claimMatchesSession({
  required DuoGuestClaim claim,
  required Map<String, dynamic>? session,
}) {
  if (session == null || claim.uid.isEmpty) return false;
  final String host = (session['hostUid'] ?? '').toString();
  final String partner = (session['partnerUid'] ?? '').toString();
  final Map<dynamic, dynamic> flushed =
      (session[kDuoFlushDoneField] as Map?) ?? const <dynamic, dynamic>{};
  final bool everFlushed =
      flushed.keys.any((k) => k.toString() == claim.uid);

  if (claim.role == 'HOST') return claim.uid == host;
  // GUEST 표가 호스트 uid와 같다면 표가 어긋난 것이다. 통과시키지 않는다.
  if (host.isNotEmpty && claim.uid == host) return false;
  return claim.uid == partner || everFlushed;
}

/// 표에 적힌 시각이 그 통화와 앞뒤가 맞는가.
///
/// 표는 **통화가 끝나는 순간** 찍히므로, 게스트가 들어온 시각보다 앞설 수
/// 없다. 며칠 전 방의 id를 들고 온 표는 여기서 걸린다.
///
/// ⚠️ 강한 검증이 아니다. `saved_at_ms`는 **기기 시계**이고 `partnerJoinedAt`은
/// 서버 시계라 둘이 정확히 맞지 않는다. 시계를 크게 틀어 둔 기기의 정상
/// 복구를 막는 쪽이 더 나쁘므로 창을 넉넉히 둔다 — 잡는 것은 **자릿수가
/// 다른 어긋남**뿐이다.
const Duration kDuoClaimClockSkewTolerance = Duration(hours: 6);

bool isClaimTemporallyPlausible({
  required DuoGuestClaim claim,
  required Map<String, dynamic>? session,
}) {
  final Timestamp? joined = session?['partnerJoinedAt'] as Timestamp?;
  if (joined == null) return true; // 옛 방에는 이 값이 없다 — 막지 않는다
  final DateTime saved = DateTime.fromMillisecondsSinceEpoch(claim.savedAtMs);
  return !saved
      .isBefore(joined.toDate().subtract(kDuoClaimClockSkewTolerance));
}

/// 복구가 만든 방에만 붙는 표식. 이 둘이 있어야 **복구본**이고, 그때만
/// 완결 여부를 따질 수 있다.
const String kDuoRestoreExpectedField = 'duo_restore_expected';
const String kDuoRestoreCompleteField = 'duo_restore_complete';

/// 이미 있는 방이 **온전한가.**
///
/// 세 갈래다.
///   · 복구본이 아니다(`duo_restore_expected` 없음) — 통화 중에 실제로 쌓인
///     방이다. 손대지 않는다. 온전한 것으로 본다.
///   · 복구본이고 완료 표식이 찍혔다 — 온전하다.
///   · 복구본인데 표식이 없다 — **줄을 쓰다 만 방이다.** 그대로 두면 반쯤
///     빈 대화가 영영 남는다.
bool restoredHistoryIsComplete({
  required Map<String, dynamic>? history,
  required int messageCount,
}) {
  if (history == null) return false;
  final bool isRestoreDoc = history.containsKey(kDuoRestoreExpectedField);
  if (!isRestoreDoc) {
    // 통화 중에 쌓인 방. 줄이 하나라도 있으면 온전한 기록이다.
    return messageCount > 0;
  }
  if (history[kDuoRestoreCompleteField] != true) return false;
  final int expected =
      (history[kDuoRestoreExpectedField] as num?)?.toInt() ?? 0;
  return messageCount >= expected;
}

/// 이 결과 뒤에 표를 남겨 두는가.
///
/// **틀린 계정으로 먼저 로그인한 사람의 기회를 뺏지 않는다.** 표가 있어도
/// 복구는 참가자 검증을 통과해야만 일어나므로, 남겨 두는 것이 위험을
/// 늘리지 않는다. 24시간 TTL이 마지막 빗장이다.
bool claimSurvives(DuoRestoreOutcome outcome) {
  switch (outcome) {
    case DuoRestoreOutcome.notParticipant: // 다른 계정으로 로그인했다
    case DuoRestoreOutcome.canonicalNotReady: // 아직 안 만들어졌다
    case DuoRestoreOutcome.failed: // 읽기·쓰기가 실패했다
    case DuoRestoreOutcome.incompleteRetry: // 쓰다 만 방을 다시 짓는 중이다
      return true;
    case DuoRestoreOutcome.noClaim:
    case DuoRestoreOutcome.expired:
    case DuoRestoreOutcome.sameAccount:
    case DuoRestoreOutcome.alreadyPresent:
    case DuoRestoreOutcome.restored:
      return false;
  }
}

/// 공유 결과 한 판을 **내 방의 줄들**로 옮긴다.
///
/// 대화에서의 역할(HOST/GUEST)을 내 방의 역할로 바꾼다 — 개인 히스토리는
/// 언제나 "내가 HOST, 상대가 SYSTEM"이다(듀오가 저장할 때부터 그렇다).
/// 감춘 줄도 그대로 옮긴다. 무엇을 보일지는 `study_state`가 정한다.
List<Map<String, dynamic>> duoCanonicalToHistoryMessages({
  required List<DuoCanonicalTurn> turns,
  required String myRole,
  required int canonicalVersion,
  int? fallbackBaseMs,
}) {
  final int base = fallbackBaseMs ?? DateTime.now().millisecondsSinceEpoch;
  final rows = <Map<String, dynamic>>[];
  for (var i = 0; i < turns.length; i++) {
    final turn = turns[i];
    // 시간이 없는 줄도 순서는 지켜야 한다. 목록이 `created_at`으로 정렬되므로
    // 없는 값은 앞줄 다음 밀리초로 채워 둔다.
    final int spokenMs = turn.spokenAtMs ?? (base + i);
    rows.add(<String, dynamic>{
      'role': turn.role == myRole ? 'HOST' : 'SYSTEM',
      'translated_text': '',
      'original_text': turn.text,
      'created_at': Timestamp.fromMillisecondsSinceEpoch(spokenMs),
      'spoken_at_ms': spokenMs,
      'duo_mode': 'direct',
      kStudyStateField: turn.state,
      'canonical_version': canonicalVersion,
      if (turn.sourceIds.isNotEmpty) 'channel_msg_id': turn.sourceIds.first,
    });
  }
  return rows;
}

/// Firestore 한 배치는 500 write가 한계다. 통화가 길면 줄이 그보다 많을 수
/// 있어(30분 통화의 짧은 주고받기) 나눠 쓴다. 방 문서 몫으로 한 칸 비워 둔
/// 여유를 두고 자른다.
const int kFirestoreBatchLimit = 450;

List<List<Map<String, dynamic>>> chunkForBatch(
  List<Map<String, dynamic>> rows, {
  int size = kFirestoreBatchLimit,
}) {
  final int step = size < 1 ? 1 : size;
  final chunks = <List<Map<String, dynamic>>>[];
  for (var i = 0; i < rows.length; i += step) {
    chunks.add(rows.sublist(i, i + step > rows.length ? rows.length : i + step));
  }
  return chunks;
}

// ── 실제 복구 ──────────────────────────────────────────────────────────

/// 로그인 콜백이 두 번 들어와도 한 번만 돈다.
bool _restoreInFlight = false;

/// 로그인 직후 한 번 부른다. 되찾을 것이 없으면 아무 일도 하지 않는다.
///
/// **정상 경로를 깨지 않는다.** uid가 그대로면(익명 승격) 표만 지우고 나간다.
///
/// 공유 결과는 통화가 끝난 뒤 상대 폰이 만든다(최대 20초 대기 + GPT 한 번).
/// 로그인은 대개 그보다 빠르므로, 아직 없으면 몇 번 더 두드린다. 그래도
/// 없으면 표를 남겨 두고 다음 로그인·다음 실행에서 다시 본다.
Future<DuoRestoreOutcome> restoreDuoHistoryAfterLogin({
  required String uid,
  DateTime? now,
  int attempts = 4,
  Duration retryDelay = const Duration(seconds: 12),
}) async {
  if (uid.isEmpty) return DuoRestoreOutcome.noClaim;
  final claim = readDuoGuestClaim();
  if (claim == null) return DuoRestoreOutcome.noClaim;
  if (!isDuoGuestClaimFresh(claim, now: now)) {
    _finish(DuoRestoreOutcome.expired, 'claim_expired', claim);
    return DuoRestoreOutcome.expired;
  }
  if (claim.uid == uid) {
    // 익명 계정이 그대로 회원이 됐다. 기록은 이미 이 uid 아래 있다.
    _finish(DuoRestoreOutcome.sameAccount, 'same_uid', claim);
    return DuoRestoreOutcome.sameAccount;
  }
  if (_restoreInFlight) {
    debugPrint('[DUO-HANDOFF] restore_skipped reason=in_flight '
        'room=${claim.roomId}');
    return DuoRestoreOutcome.noClaim;
  }
  _restoreInFlight = true;
  try {
    debugPrint('[DUO-HANDOFF] restore_started room=${claim.roomId} '
        'role=${claim.role} attempts=$attempts');
    DuoRestoreOutcome outcome = DuoRestoreOutcome.failed;
    for (var i = 0; i < (attempts < 1 ? 1 : attempts); i++) {
      if (i > 0) await Future<void>.delayed(retryDelay);
      try {
        outcome = await _restore(claim: claim, uid: uid);
      } catch (e) {
        // 실패한 자리가 어디든 표는 남긴다. 다음 실행에서 다시 온다.
        debugPrint('[DUO-HANDOFF] restore_failed_keep_claim '
            'room=${claim.roomId} error=${e.runtimeType}');
        outcome = DuoRestoreOutcome.failed;
      }
      // 다시 두드릴 값어치가 있는 둘: 아직 안 만들어졌다 / 쓰다 만 방을
      // 지우고 다시 지어야 한다.
      if (outcome != DuoRestoreOutcome.canonicalNotReady &&
          outcome != DuoRestoreOutcome.incompleteRetry) {
        break;
      }
    }
    _finish(outcome, outcome.name, claim);
    return outcome;
  } finally {
    _restoreInFlight = false;
  }
}

/// 결과에 따라 표를 지우거나 남기고, 한 줄만 남긴다.
/// **방 id와 결과만 적는다** — uid도 대화 내용도 로그에 넣지 않는다.
void _finish(DuoRestoreOutcome outcome, String tag, DuoGuestClaim claim) {
  final bool keep = claimSurvives(outcome);
  debugPrint('[DUO-HANDOFF] $tag room=${claim.roomId} '
      'claim=${keep ? 'kept' : 'clearing'}');
  if (!keep) clearDuoGuestClaim();
}

Future<DuoRestoreOutcome> _restore({
  required DuoGuestClaim claim,
  required String uid,
}) async {
  final db = FirebaseFirestore.instance;

  // ① 참가자 검증. **표는 지우지 않는다** — 다른 계정으로 잘못 로그인한
  //    사람이 곧바로 올바른 계정으로 다시 들어오면 그때 복구되어야 한다.
  //    복구는 어차피 이 검증을 통과해야만 일어나므로 남겨 두어도 위험이
  //    늘지 않는다. 마지막 빗장은 24시간 TTL이다.
  final sessionSnap = await duoSessionRef(claim.roomId).get();
  final session = sessionSnap.data();
  if (!claimMatchesSession(claim: claim, session: session)) {
    debugPrint('[DUO-HANDOFF] wrong_account room=${claim.roomId}');
    return DuoRestoreOutcome.notParticipant;
  }
  if (!isClaimTemporallyPlausible(claim: claim, session: session)) {
    debugPrint('[DUO-HANDOFF] not_participant reason=time room=${claim.roomId}');
    return DuoRestoreOutcome.notParticipant;
  }

  // ② 이미 있는가. 있다면 **온전한가**까지 본다 — 방 문서만 있고 줄이 없는
  //    복구본을 "있으니 됐다"로 넘기면 반쯤 빈 대화가 영영 남는다.
  final existing = await db
      .collection('users')
      .doc(uid)
      .collection('chat_history')
      .where(kDuoRoomIdField, isEqualTo: claim.roomId)
      .limit(1)
      .get();
  if (existing.docs.isNotEmpty) {
    final doc = existing.docs.first;
    final msgs = await doc.reference.collection('messages').get();
    final complete = restoredHistoryIsComplete(
      history: doc.data(),
      messageCount: msgs.docs.length,
    );
    if (complete) {
      debugPrint('[DUO-HANDOFF] existing_history_complete '
          'room=${claim.roomId} msgs=${msgs.docs.length}');
      return DuoRestoreOutcome.alreadyPresent;
    }
    debugPrint('[DUO-HANDOFF] existing_history_incomplete '
        'room=${claim.roomId} msgs=${msgs.docs.length} — 지우고 다시 짓는다');
    // 쓰다 만 복구본은 우리가 만든 것이라 지워도 잃을 것이 없다.
    for (final m in msgs.docs) {
      await m.reference.delete();
    }
    await doc.reference.delete();
    return DuoRestoreOutcome.incompleteRetry;
  }

  // ③ 공유 결과. 아직이면 표를 남겨 둔다.
  final canonSnap = await duoCanonicalRef(claim.roomId).get();
  final canon = canonSnap.data();
  if (canon == null || (canon['status'] ?? '').toString() != kCanonicalReady) {
    debugPrint('[DUO-HANDOFF] canonical_not_ready room=${claim.roomId} '
        'status=${canon?['status']}');
    return DuoRestoreOutcome.canonicalNotReady;
  }
  final int version = (canon['canonical_version'] as num?)?.toInt() ?? 0;
  final turns = <DuoCanonicalTurn>[
    for (final raw in (canon['turns'] as List? ?? const <dynamic>[]))
      if (DuoCanonicalTurn.fromMap(raw) != null)
        DuoCanonicalTurn.fromMap(raw)!
  ];
  if (turns.isEmpty) {
    debugPrint('[DUO-HANDOFF] restore_failed_keep_claim '
        'room=${claim.roomId} reason=empty_canonical');
    return DuoRestoreOutcome.failed;
  }

  // ④ 짓는다. **줄이 500을 넘을 수 있다** — 배치 하나에 다 담으면 그 순간
  //    통째로 거절당한다(Firestore 한 배치 500 write). 나눠 쓰되, 다 쓰기
  //    전까지는 완료 표식을 찍지 않는다. 중간에 끊기면 다음 로그인이
  //    "쓰다 만 방"으로 알아보고 지운 뒤 다시 짓는다.
  final rows = duoCanonicalToHistoryMessages(
    turns: turns,
    myRole: claim.role,
    canonicalVersion: version,
  );
  final visible = turns.where((t) => isStudyVisible(t.state)).toList();
  final historyRef =
      db.collection('users').doc(uid).collection('chat_history').doc();
  final Timestamp lastAt = rows.last['created_at'] as Timestamp;

  await historyRef.set(<String, dynamic>{
    'created_at': rows.first['created_at'],
    'last_active': lastAt,
    'last_message_time': lastAt,
    'room_name': 'Duo Connect Mode',
    'is_pinned': false,
    'msg_count': visible.length,
    'last_message': visible.isEmpty ? '' : visible.last.text,
    'native_lang':
        claim.nativeLang.isEmpty ? FFAppState().nativeLang : claim.nativeLang,
    'target_lang':
        claim.targetLang.isEmpty ? FFAppState().targetLang : claim.targetLang,
    kDuoRoomIdField: claim.roomId,
    // 이미 이 판으로 지었다. 방을 열 때 canonical을 다시 덧칠하지 않는다.
    kDuoCanonicalVersionField: version,
    kDuoCanonicalAppliedAtField: FieldValue.serverTimestamp(),
    kDuoRestoreExpectedField: rows.length,
    kDuoRestoreCompleteField: false,
  });

  for (final chunk in chunkForBatch(rows)) {
    final batch = db.batch();
    for (final row in chunk) {
      batch.set(historyRef.collection('messages').doc(), row);
    }
    await batch.commit();
  }

  // 마지막에 찍는다. 이 표식이 곧 "온전하다"는 뜻이다.
  await historyRef.update(<String, dynamic>{kDuoRestoreCompleteField: true});

  debugPrint('[DUO-HANDOFF] restored room=${claim.roomId} '
      'doc=${historyRef.id} turns=${turns.length} shown=${visible.length}');
  return DuoRestoreOutcome.restored;
}
