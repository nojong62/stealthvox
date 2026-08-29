import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'duo_study_state.dart';

// ====================================================================
// 🧩 [DUO-CANONICAL] 한 통화 = 하나의 대화 기록.
// --------------------------------------------------------------------
// 예전에는 두 폰이 각자 자기 히스토리 방에서 따로 GPT를 불러 정돈했다. 같은
// 통화인데 호스트와 게스트의 기록이 서로 다른 대화처럼 보였다(2026-08-28 확인).
//
// 이제 세 계층을 분리한다.
//
//   SOURCE     `duo_sessions/{roomId}/messages`
//              양쪽 폰이 각자 자기 마이크로 만든 전사. **근거이자 원본이다.**
//              canonical을 만들면서 고치지도 지우지도 않는다.
//
//   CANONICAL  `duo_sessions/{roomId}/canonical/current`
//              두 사람 몫을 한 시간축으로 합쳐 **한 번만** 정돈한 결과.
//              누가 만들든 결과는 하나다.
//
//   PERSONAL   `users/{uid}/chat_history/{id}/messages`
//              각자 공부방에서 읽는 형태로 옮겨 놓은 사본. 각 폰이 자기 것만
//              쓴다 — 남의 개인 기록에 손대지 않는다(권한도 그렇게 되어 있다).
//
// **canonical은 요약이 아니다.** 오간 순서를 그대로 두고, 갈라진 조각을 잇고,
// 되먹임·중복·말 고르는 소리만 감춘다. 무엇이 중요한 말인지는 판단하지 않는다.
// ====================================================================

/// 세션 문서에 참가자별로 찍는 "나는 더 이상 말을 안 올린다" 표시.
///
/// 화면에서 나갔다는 뜻이 **아니다.** 마지막 발화 flush와 채널 업로드까지
/// 끝났다는 뜻이라야 한다. 이게 없으면 내가 먼저 나간 순간 canonical이 돌아
/// 상대의 마지막 한마디를 빠뜨린다.
const String kDuoFlushDoneField = 'flush_done';

/// 세션이 끝났다는 표시. 직접 대화는 문서를 지우지 않고 이 값을 남긴다 —
/// canonical과 source가 그 아래 살아 있어야 하기 때문이다.
const String kDuoEndedAtField = 'ended_at';

/// 공유 결과가 사는 자리.
const String kDuoCanonicalCollection = 'canonical';
const String kDuoCanonicalDoc = 'current';

/// 개인 히스토리 방이 어느 통화였는지 가리키는 고리.
/// **이 값이 없는 방은 옛 방이다** — canonical을 쓰지 않고 예전 방식으로 둔다.
const String kDuoRoomIdField = 'duo_room_id';
const String kDuoCanonicalVersionField = 'duo_canonical_version';
const String kDuoCanonicalAppliedAtField = 'duo_canonical_applied_at';

/// canonical 상태.
const String kCanonicalPending = 'pending';
const String kCanonicalBuilding = 'building';
const String kCanonicalReady = 'ready';
const String kCanonicalFailed = 'failed';

/// 상대 표시를 기다리는 상한. 앱이 죽거나 네트워크가 끊기면 표시가 영영
/// 안 오므로 무한정 기다리지 않는다. 화면은 이미 나가 있으므로 이 대기가
/// 사용자를 붙잡지는 않는다.
const Duration kDuoFlushWaitTimeout = Duration(seconds: 20);

/// 남이 잡아 둔 작업이 죽은 것으로 볼 시간. 이 시간이 지나면 뺏을 수 있다.
const Duration kDuoCanonicalClaimStale = Duration(seconds: 90);

/// GPT 한 번의 상한.
const Duration kDuoCanonicalGptTimeout = Duration(seconds: 40);

/// 정돈된 한 줄.
class DuoCanonicalTurn {
  const DuoCanonicalTurn({
    required this.role,
    required this.text,
    required this.sourceIds,
    required this.state,
    this.spokenAtMs,
  });

  /// 말한 사람. 채널에 실린 `senderRole` 그대로(HOST/GUEST).
  final String role;
  final String text;

  /// 이 줄이 어느 source 문서에서 나왔는가. **추적의 핵심이다** — 조각을
  /// 이었으면 여럿이고, 감춘 줄이면 자기 자신 하나다.
  final List<String> sourceIds;
  final String state;
  final int? spokenAtMs;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'role': role,
        'text': text,
        'source_ids': sourceIds,
        'state': state,
        if (spokenAtMs != null) 'spoken_at_ms': spokenAtMs,
      };

  static DuoCanonicalTurn? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final String text = (raw['text'] ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DuoCanonicalTurn(
      role: (raw['role'] ?? '').toString(),
      text: text,
      sourceIds: <String>[
        for (final id in (raw['source_ids'] as List? ?? const <dynamic>[]))
          id.toString()
      ],
      state: (raw['state'] ?? kStudyStateIncluded).toString(),
      spokenAtMs: (raw['spoken_at_ms'] as num?)?.toInt(),
    );
  }
}

/// 채널에 실린 원본 한 줄.
class DuoSourceUtterance {
  const DuoSourceUtterance({
    required this.id,
    required this.role,
    required this.text,
    required this.spokenAtMs,
    required this.seq,
    required this.srcLang,
  });

  final String id;
  final String role;
  final String text;
  final int spokenAtMs;
  final int seq;
  final String srcLang;
}

/// 세션 문서.
DocumentReference<Map<String, dynamic>> duoSessionRef(String roomId) =>
    FirebaseFirestore.instance.collection('duo_sessions').doc(roomId);

/// 공유 결과 문서.
DocumentReference<Map<String, dynamic>> duoCanonicalRef(String roomId) =>
    duoSessionRef(roomId)
        .collection(kDuoCanonicalCollection)
        .doc(kDuoCanonicalDoc);

/// 🚩 "나는 더 이상 말을 안 올린다"를 세션 문서에 남긴다.
///
/// 반드시 마지막 전사 flush와 채널 업로드가 끝난 뒤에 부른다.
Future<void> markDuoFlushDone({
  required String roomId,
  required String uid,
}) async {
  if (roomId.isEmpty || uid.isEmpty) return;
  try {
    await duoSessionRef(roomId).set(<String, dynamic>{
      kDuoFlushDoneField: <String, dynamic>{uid: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true));
  } catch (e) {
    debugPrint('[DUO-CANON] flush_mark_failed=${e.runtimeType}');
  }
}

/// 양쪽 표시가 다 찍혔는지 본다. 상한을 넘으면 있는 것만으로 진행한다 —
/// 한쪽 앱이 죽었을 때 대화가 영영 안 만들어지는 쪽이 더 나쁘다.
Future<bool> _awaitBothFlushMarks({
  required String roomId,
  required String myUid,
}) async {
  final deadline = DateTime.now().add(kDuoFlushWaitTimeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final snap = await duoSessionRef(roomId).get();
      final data = snap.data();
      final marks = (data?[kDuoFlushDoneField] as Map?) ?? const <dynamic, dynamic>{};
      // 상대가 애초에 없었던 방(혼자 있다 나감)도 진행할 수 있어야 한다.
      final bool partnerJoined = data?['isPartnerJoined'] == true;
      if (marks.length >= 2 || (!partnerJoined && marks.containsKey(myUid))) {
        return true;
      }
    } catch (e) {
      debugPrint('[DUO-CANON] flush_read_failed=${e.runtimeType}');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  debugPrint('[DUO-CANON] flush_wait_timeout room=$roomId — 있는 것만으로 만든다');
  return false;
}

/// 🔒 작업을 나 하나만 잡는다.
///
/// `_amIHost` 한 줄로는 부족하다 — 호스트가 먼저 죽으면 대화가 영영 안 만들어
/// 진다. 그래서 상태를 트랜잭션으로 바꿔 잡고, 남이 잡아 둔 채 멈춘 지 오래면
/// 뺏는다. 두 폰이 동시에 GPT를 부르는 일은 트랜잭션이 막는다.
Future<bool> _claimCanonical({
  required String roomId,
  required String uid,
  required bool preferred,
}) async {
  final ref = duoCanonicalRef(roomId);
  try {
    return await FirebaseFirestore.instance
        .runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      final String status = (data?['status'] ?? kCanonicalPending).toString();
      if (status == kCanonicalReady) return false;
      if (status == kCanonicalBuilding) {
        final Timestamp? claimedAt = data?['updated_at'] as Timestamp?;
        final bool stale = claimedAt == null ||
            DateTime.now().difference(claimedAt.toDate()) >
                kDuoCanonicalClaimStale;
        if (!stale) return false;
        debugPrint('[DUO-CANON] stale_claim_takeover room=$roomId');
      }
      tx.set(
          ref,
          <String, dynamic>{
            'status': kCanonicalBuilding,
            'writer_uid': uid,
            'preferred_writer': preferred,
            'updated_at': FieldValue.serverTimestamp(),
            if (data == null) 'created_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return true;
    }).timeout(const Duration(seconds: 12));
  } catch (e) {
    debugPrint('[DUO-CANON] claim_failed=${e.runtimeType}');
    return false;
  }
}

/// 채널에서 양쪽 발화를 읽어 **말한 순서**로 세운다.
///
/// 문서가 만들어진 순서가 아니라 `spokenAt`을 본다 — 네트워크 사정으로 늦게
/// 올라온 줄이 대화 뒤로 밀리면 주고받은 차례가 뒤집힌다.
Future<List<DuoSourceUtterance>> readDuoSourceTimeline(String roomId) async {
  final snap = await duoSessionRef(roomId).collection('messages').get();
  final list = <DuoSourceUtterance>[];
  for (final doc in snap.docs) {
    final data = doc.data();
    final String text = (data['text'] ?? '').toString().trim();
    if (text.isEmpty) continue;
    if ((data['duoMode'] ?? '').toString() != 'direct') continue;
    list.add(DuoSourceUtterance(
      id: doc.id,
      role: (data['senderRole'] ?? '').toString(),
      text: text,
      spokenAtMs: (data['spokenAt'] as num?)?.toInt() ??
          (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
          0,
      seq: (data['seq'] as num?)?.toInt() ?? 0,
      srcLang: (data['srcLang'] ?? '').toString(),
    ));
  }
  list.sort((a, b) {
    final byTime = a.spokenAtMs.compareTo(b.spokenAtMs);
    return byTime != 0 ? byTime : a.seq.compareTo(b.seq);
  });
  return list;
}

/// GPT가 안 되거나 실패했을 때의 결과.
///
/// **글자를 잃지 않는다.** 시간순으로 세운 원본을 그대로 대화로 삼는다.
/// 정돈이 안 됐을 뿐 오간 말은 전부 남는다.
List<DuoCanonicalTurn> fallbackCanonical(List<DuoSourceUtterance> source) => [
      for (final u in source)
        DuoCanonicalTurn(
          role: u.role,
          text: u.text,
          sourceIds: <String>[u.id],
          state: kStudyStateIncluded,
          spokenAtMs: u.spokenAtMs,
        )
    ];

const String _canonicalPrompt =
    '''You are given ONE phone call between two people, already transcribed. Each line came from that speaker's own phone.

Your job is CLEANUP, not selection. You never decide what matters in a conversation. Keep what they said and tidy only the mess speech-to-text made.

KEEP EVERY TURN A PERSON ACTUALLY SPOKE, however short or ordinary: questions, answers, agreements, refusals, reactions, greetings, self-corrections. Never drop a turn because it looks unimportant or not worth studying. Importance is not yours to judge. Keep the two speakers in the order they actually spoke; never merge different speakers and never reorder the call.

Judge every turn by its CONVERSATIONAL FUNCTION in context, never by its length or wording:
  "Are you going tomorrow?" / "어."  -> agreement. included
  "Not today, Friday."      / "아."  -> realization. included
  "What did you say?"       / "어?"  -> asking again. included
  "I think that..."         / "음... 흠..." while holding your own turn -> thinking aloud. hesitation

States you may assign:
  included    - a real turn in the conversation. THIS IS THE DEFAULT.
  merged      - a fragment of one sentence that you joined into a neighbouring turn of the SAME speaker. Only when no real turn by the other speaker sits between them.
  hesitation  - real voice, but only filling the speaker's own pause; no reply, question, reaction or agreement.
  echo        - this speaker's phone picked up the OTHER speaker's voice from the loudspeaker. Requires the other speaker to have a near-identical line at almost the same time. A person genuinely repeating what they heard is NOT echo.
  duplicate   - the same moment stored twice by the recognizer. Matching words alone never justify this.

If you are unsure, choose "included". Wrongly keeping a line costs little; wrongly hiding one loses what a person said.

For turns you keep, tidy only the surface: spacing, punctuation, and a mis-hearing that the surrounding turns clearly settle. Never add facts, fix the speaker's grammar, improve their style, complete an uncertain fragment, summarize, compress, or translate.

Return strict JSON only:
{"turns":[{"ids":["<source id>"],"role":"HOST","text":"...","state":"included"}]}
"ids" lists every source id that became this turn, in order. Return every source id exactly once across all turns.''';

/// GPT-4.1-mini로 한 번 정돈한다. 실패하면 null — 호출부가 폴백을 쓴다.
Future<List<DuoCanonicalTurn>?> reconcileDuoConversation({
  required String apiKey,
  required String model,
  required List<DuoSourceUtterance> source,
}) async {
  if (apiKey.isEmpty || source.isEmpty) return null;
  try {
    final payload = <String, dynamic>{
      'turns': [
        for (final u in source)
          <String, dynamic>{
            'id': u.id,
            'role': u.role,
            'text': u.text,
            'spoken_at_ms': u.spokenAtMs,
          }
      ]
    };
    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, dynamic>{
            'model': model,
            'temperature': 0.1,
            'max_tokens': 4000,
            'response_format': <String, String>{'type': 'json_object'},
            'messages': <Map<String, String>>[
              <String, String>{'role': 'system', 'content': _canonicalPrompt},
              <String, String>{'role': 'user', 'content': jsonEncode(payload)},
            ],
          }),
        )
        .timeout(kDuoCanonicalGptTimeout);
    if (response.statusCode != 200) {
      debugPrint('[DUO-CANON] gpt_status=${response.statusCode}');
      return null;
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final content = body['choices']?[0]?['message']?['content']?.toString();
    if (content == null || content.trim().isEmpty) return null;
    final decoded = jsonDecode(content);
    final list = decoded['turns'];
    if (list is! List) return null;

    final byId = <String, DuoSourceUtterance>{
      for (final u in source) u.id: u
    };
    final seen = <String>{};
    final turns = <DuoCanonicalTurn>[];
    for (final item in list) {
      if (item is! Map) continue;
      final ids = <String>[
        for (final id in (item['ids'] as List? ?? const <dynamic>[]))
          if (byId.containsKey(id.toString())) id.toString()
      ];
      if (ids.isEmpty) continue;
      final text = (item['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      seen.addAll(ids);
      turns.add(DuoCanonicalTurn(
        role: (item['role'] ?? byId[ids.first]!.role).toString(),
        text: text,
        sourceIds: ids,
        state: _stateFromModel(item['state']),
        spokenAtMs: byId[ids.first]!.spokenAtMs,
      ));
    }

    // 🧭 [FAIL-OPEN] 모델이 통째로 빠뜨린 원본은 **원문 그대로 되살린다.**
    //   빠진 것이 판단인지 실수인지 알 수 없고, 근거 없이 사람 말을 감추지
    //   않는다. 되살린 줄은 말한 순서 자리로 돌아간다.
    final missing = <DuoCanonicalTurn>[];
    for (final u in source) {
      if (seen.contains(u.id)) continue;
      missing.add(DuoCanonicalTurn(
        role: u.role,
        text: u.text,
        sourceIds: <String>[u.id],
        state: kStudyStateIncluded,
        spokenAtMs: u.spokenAtMs,
      ));
    }
    if (missing.isNotEmpty) {
      debugPrint('[DUO-CANON] restored_missing=${missing.length}');
      turns.addAll(missing);
    }
    turns.sort((a, b) => (a.spokenAtMs ?? 0).compareTo(b.spokenAtMs ?? 0));
    return turns.isEmpty ? null : turns;
  } catch (e) {
    debugPrint('[DUO-CANON] gpt_failed=${e.runtimeType}');
    return null;
  }
}

String _stateFromModel(Object? raw) {
  switch ((raw ?? '').toString().trim().toLowerCase()) {
    case 'merged':
      return kStudyStateMerged;
    case 'hesitation':
      return kStudyStateHiddenHesitation;
    case 'echo':
      return kStudyStateHiddenEcho;
    case 'duplicate':
      return kStudyStateHiddenDuplicate;
    default:
      // 모르는 값은 보이는 쪽. 감추는 쪽이 기본이 되면 안 된다.
      return kStudyStateIncluded;
  }
}

/// 통화가 끝난 뒤 한 번 돌아 공유 결과를 만든다.
///
/// 양쪽 표시를 기다리고, 트랜잭션으로 작업을 잡고, GPT를 한 번 부른다.
/// 이미 남이 만들었거나 만들고 있으면 조용히 물러난다.
Future<void> buildDuoCanonical({
  required String roomId,
  required String uid,
  required bool isHost,
  required String apiKey,
  required String model,
}) async {
  if (roomId.isEmpty || uid.isEmpty) return;
  try {
    // 호스트가 먼저 잡도록 살짝 양보한다. 우선권일 뿐 보장은 트랜잭션이 한다.
    if (!isHost) {
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    final bothDone = await _awaitBothFlushMarks(roomId: roomId, myUid: uid);
    final claimed =
        await _claimCanonical(roomId: roomId, uid: uid, preferred: isHost);
    if (!claimed) {
      debugPrint('[DUO-CANON] skip room=$roomId — 다른 쪽이 맡았다');
      return;
    }
    final source = await readDuoSourceTimeline(roomId);
    if (source.isEmpty) {
      await duoCanonicalRef(roomId).set(<String, dynamic>{
        'status': kCanonicalFailed,
        'reason': 'no_source',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    final reconciled = await reconcileDuoConversation(
      apiKey: apiKey,
      model: model,
      source: source,
    );
    final turns = reconciled ?? fallbackCanonical(source);
    final int version = DateTime.now().millisecondsSinceEpoch;
    await duoCanonicalRef(roomId).set(<String, dynamic>{
      'status': kCanonicalReady,
      'writer_uid': uid,
      'canonical_version': version,
      'source_count': source.length,
      'shown_count': turns.where((t) => isStudyVisible(t.state)).length,
      'model': reconciled == null ? 'fallback_merge' : model,
      'both_flush_marks': bothDone,
      'turns': <Map<String, dynamic>>[for (final t in turns) t.toMap()],
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('[DUO-CANON] ready room=$roomId source=${source.length} '
        'turns=${turns.length} '
        'shown=${turns.where((t) => isStudyVisible(t.state)).length} '
        'model=${reconciled == null ? 'fallback_merge' : model} '
        'bothMarks=$bothDone');
  } catch (e) {
    debugPrint('[DUO-CANON] build_failed=${e.runtimeType}');
    try {
      await duoCanonicalRef(roomId).set(<String, dynamic>{
        'status': kCanonicalFailed,
        'reason': e.runtimeType.toString(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

/// 공유 결과를 내 공부방에 옮긴다.
///
/// 같은 판(`canonical_version`)을 두 번 옮기지 않는다. 통화가 끝나는 순간에
/// 못 옮겼어도 나중에 방을 열 때 이 함수가 다시 맞춘다.
///
/// 원본 메시지 문서는 **지우지 않는다.** 보일지 말지와 글자만 맞춘다.
Future<bool> applyDuoCanonicalToHistory({
  required DocumentReference<Map<String, dynamic>> historyRef,
  required String roomId,
  int? appliedVersion,
}) async {
  if (roomId.isEmpty) return false;
  try {
    final snap = await duoCanonicalRef(roomId).get();
    final data = snap.data();
    if (data == null) return false;
    if ((data['status'] ?? '').toString() != kCanonicalReady) return false;
    final int version = (data['canonical_version'] as num?)?.toInt() ?? 0;
    if (appliedVersion != null && appliedVersion == version) return false;

    final turns = <DuoCanonicalTurn>[
      for (final raw in (data['turns'] as List? ?? const <dynamic>[]))
        if (DuoCanonicalTurn.fromMap(raw) != null) DuoCanonicalTurn.fromMap(raw)!
    ];
    if (turns.isEmpty) return false;

    // 내 방의 줄을 채널 문서 id로 찾을 수 있어야 옮길 수 있다.
    final msgSnap = await historyRef.collection('messages').get();
    final byChannelId = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final doc in msgSnap.docs) {
      final String channelId =
          (doc.data()['channel_msg_id'] ?? '').toString().trim();
      if (channelId.isNotEmpty) byChannelId[channelId] = doc.reference;
    }
    if (byChannelId.isEmpty) return false;

    final batch = FirebaseFirestore.instance.batch();
    var applied = 0;
    for (final turn in turns) {
      if (turn.sourceIds.isEmpty) continue;
      // 이은 줄은 첫 조각이 대표가 되고, 나머지는 그 줄에 흡수됐다고 적는다.
      final head = byChannelId[turn.sourceIds.first];
      if (head != null) {
        batch.update(head, <String, dynamic>{
          'original_text': turn.text,
          kStudyStateField: turn.state,
          'canonical_version': version,
        });
        applied++;
      }
      for (final id in turn.sourceIds.skip(1)) {
        final ref = byChannelId[id];
        if (ref == null) continue;
        batch.update(ref, <String, dynamic>{
          kStudyStateField: kStudyStateMerged,
          'canonical_version': version,
        });
      }
    }
    if (applied == 0) return false;
    await batch.commit();
    await historyRef.update(<String, dynamic>{
      kDuoCanonicalVersionField: version,
      kDuoCanonicalAppliedAtField: FieldValue.serverTimestamp(),
      'msg_count': turns.where((t) => isStudyVisible(t.state)).length,
    });
    debugPrint('[DUO-CANON] applied room=$roomId version=$version '
        'turns=${turns.length} applied=$applied');
    return true;
  } catch (e) {
    debugPrint('[DUO-CANON] apply_failed=${e.runtimeType}');
    return false;
  }
}
