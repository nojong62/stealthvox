import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'duo_origin_corrector.dart';
import 'duo_study_state.dart';
import 'history_finalize.dart';
import 'history_text_model.dart';
import 'origin_restoration.dart' show kMessagePcmKeyField;

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
//
// ⚠️ **직접 대화(`direct`) 전용이다.** 만능 통역은 릴레이 없이 STT→번역→TTS로
// 도는 서클톡과 같은 통신 로직이라, 상대에게 들린 것이 번역문이고 오간 것이
// 애초에 글자다. 정돈할 "두 사람의 실제 발화 한 시간축"이 없다.
// [readDuoSourceTimeline]은 직접 대화와 만능 통역을 **둘 다** 읽는다.
//
// 예전에는 `direct`만 읽었다. 그래서 통역 히스토리에는 정돈이 아예 돌지
// 않았고, 맥락에 안 맞는 두세 글자("Quickly", "No.")가 그대로 남았다.
// 통역이야말로 정돈이 필요한 쪽이다 — 상대 폰 스피커 소리와 잘린 조각이
// 섞여 들어오는 유일한 모드다(2026-09-04 실기기).
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

/// 개인 히스토리 방에 적는 통화 방식(`direct` · `interpreter`).
///
/// 두 방식은 방 이름이 같아서 목록에서 구별되지 않는다. 그런데 남는 글이
/// 다르다 — 직접 대화는 두 사람이 **실제로 한 말**이고, 만능 통역은 내가
/// **들은 번역문**이다. Replay가 걸리는 쪽도 직접 대화뿐이다.
///
/// **이 값이 없는 방은 옛 방이다.** 그때는 [kDuoCanonicalVersionField]가
/// 있는지로 가린다 — 그 값은 직접 대화에만 붙는다.
const String kDuoModeField = 'duo_mode';
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
    this.subject = '',
    this.rawText = '',
  });

  /// 말한 사람. 채널에 실린 `senderRole` 그대로(HOST/GUEST).
  final String role;
  final String text;

  /// 이 줄이 어느 source 문서에서 나왔는가. **추적의 핵심이다** — 조각을
  /// 이었으면 여럿이고, 감춘 줄이면 자기 자신 하나다.
  final List<String> sourceIds;
  final String state;
  final int? spokenAtMs;

  /// 🧭 [SUBJECT-HINT] 이 줄이 **누구 얘기인가**를 적은 참고용 주어.
  ///
  /// 한국어는 이미 통하는 주어를 생략하지만 영어는 못 한다. 그래서 배울글을
  /// 만들 때 누군가는 그 자리를 채워야 하는데, 지금까지는 GPT가 줄마다 따로
  /// 찍었고 그래서 같은 사람이 줄마다 he·they로 갈렸다.
  ///
  /// **3자가 나오는 줄에만 채운다.** 두 사람의 통화라 거의 모든 줄은 나
  /// 아니면 너이고, 그런 줄에는 아무것도 붙이지 않는다(붙이면 화면이
  /// `(나는)`으로 뒤덮인다).
  ///
  /// ⚠️ **[text]에 넣지 않는다.** 원문은 실제 발화 그대로 남아야 한다 —
  /// 확정된 원문 하나가 배울글·Practice·My English의 재료라, 참고 표시가
  /// 거기 섞이면 학습 자료에 괄호가 따라 들어간다.
  final String subject;

  /// 🩺 [ORIGIN-CORRECT] 문맥 교정이 [text]를 갈아 끼우기 **전**의 전사 원문.
  ///
  /// **고쳐진 줄에만 값이 있다.** 비어 있으면 이 줄은 gpt-transcribe가 적은
  /// 그대로라는 뜻이고, 옛 canonical 문서도 여기가 비어 있다.
  final String rawText;

  /// 문맥 교정이 손댄 줄인가.
  bool get wasCorrected =>
      rawText.trim().isNotEmpty && rawText.trim() != text.trim();

  /// 같은 줄에 교정 전 글자만 얹는다.
  DuoCanonicalTurn withRawText(String raw) => DuoCanonicalTurn(
        role: role,
        text: text,
        sourceIds: sourceIds,
        state: state,
        spokenAtMs: spokenAtMs,
        subject: subject,
        rawText: raw,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'role': role,
        'text': text,
        'source_ids': sourceIds,
        'state': state,
        if (spokenAtMs != null) 'spoken_at_ms': spokenAtMs,
        if (subject.isNotEmpty) 'subject': subject,
        // 고친 줄에만 싣는다. 옛 문서에는 이 칸이 없고, 없어도 정상이다.
        if (rawText.isNotEmpty) 'raw_text': rawText,
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
      subject: (raw['subject'] ?? '').toString().trim(),
      // 옛 canonical 문서에는 없다. 없으면 "교정 안 된 줄"과 같은 뜻이다.
      rawText: (raw['raw_text'] ?? '').toString().trim(),
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
    this.senderUid = '',
    this.sttSource = '',
    this.duoMode = '',
  });

  final String id;
  final String role;
  final String text;
  final int spokenAtMs;
  final int seq;
  final String srcLang;

  /// 말한 사람의 uid. **개인 방에서 내 줄인지 상대 줄인지를 이 값이 가른다.**
  ///
  /// 기본값을 두는 이유는 이 자료형이 테스트와 순수 함수에서 직접 만들어지기
  /// 때문이다. 채널 문서에 없으면 빈 값이고, 그때는 [role]로도 가를 수 있다.
  final String senderUid;

  /// 이 글자를 만든 PCM의 출처. 개인 방 줄의 `stt_source`가 된다.
  final String sttSource;

  /// `direct` / `interpreter`. **신규 줄 생성은 direct만 한다.**
  final String duoMode;

  /// 글자만 갈아 끼운 같은 줄. 문맥 교정이 쓴다.
  DuoSourceUtterance withText(String next) => DuoSourceUtterance(
        id: id,
        role: role,
        text: next,
        senderUid: senderUid,
        sttSource: sttSource,
        duoMode: duoMode,
        spokenAtMs: spokenAtMs,
        seq: seq,
        srcLang: srcLang,
      );
}

// ══════════════════════════════════════════════════════════════════════
// 🩺 문맥 교정 다리 — canonical과 [duo_origin_corrector] 사이
// ══════════════════════════════════════════════════════════════════════

/// 교정기에게 줄 대화. **화자는 A/B로만 준다**(`DuoOriginLine.speaker` 참고).
///
/// HOST/GUEST 두 값만 오지만, 옛 방·로봇 판에서 빈 role이 올 수 있다. 그때는
/// **처음 나온 순서대로** 글자를 매긴다 — 누가 누구인지는 몰라도 두 사람이
/// 번갈아 말한다는 사실만 있으면 된다.
List<DuoOriginLine> duoOriginLinesOf(List<DuoSourceUtterance> source) {
  final labels = <String, String>{};
  const alphabet = <String>['A', 'B', 'C', 'D'];
  final out = <DuoOriginLine>[];
  for (final u in source) {
    final String key = u.role.trim().toUpperCase();
    final String label = labels.putIfAbsent(
      key,
      () => labels.length < alphabet.length ? alphabet[labels.length] : 'X',
    );
    out.add(DuoOriginLine(id: u.id, speaker: label, text: u.text));
  }
  return out;
}

/// 이 통화에서 가장 많이 쓰인 언어 이름. 없으면 빈 문자열이다.
///
/// 직접 대화는 줄마다 언어가 다를 수 있어 하나로 못 박지 않는다 — 프롬프트가
/// 이 값을 "대개 이 언어다"로만 쓴다.
String duoDominantSourceLanguage(List<DuoSourceUtterance> source) {
  final counts = <String, int>{};
  for (final u in source) {
    final String lang = u.srcLang.trim();
    if (lang.isEmpty) continue;
    counts[lang] = (counts[lang] ?? 0) + 1;
  }
  if (counts.isEmpty) return '';
  var best = '';
  var bestCount = 0;
  counts.forEach((lang, seen) {
    if (seen > bestCount) {
      best = lang;
      bestCount = seen;
    }
  });
  return best;
}

/// 채택된 교정을 원본 타임라인에 얹는다. **원본 목록은 그대로 둔다.**
List<DuoSourceUtterance> applyDuoOriginCorrectionsToSource(
  List<DuoSourceUtterance> source,
  Map<String, String> corrections,
) {
  if (corrections.isEmpty) return source;
  return <DuoSourceUtterance>[
    for (final u in source)
      corrections.containsKey(u.id) && corrections[u.id]!.trim().isNotEmpty
          ? u.withText(corrections[u.id]!.trim())
          : u
  ];
}

/// 고쳐진 줄에 **교정 전 글자**를 얹는다.
///
/// canonical 한 줄은 source id 하나와 1:1이므로(`reconcileDuoConversation`),
/// 첫 id로 원본을 찾으면 된다.
List<DuoCanonicalTurn> attachDuoOriginRawTexts(
  List<DuoCanonicalTurn> turns,
  List<DuoSourceUtterance> original,
  Map<String, String> corrections,
) {
  if (corrections.isEmpty) return turns;
  final rawById = <String, String>{for (final u in original) u.id: u.text};
  return <DuoCanonicalTurn>[
    for (final t in turns)
      (t.sourceIds.isNotEmpty && corrections.containsKey(t.sourceIds.first))
          ? t.withRawText(rawById[t.sourceIds.first] ?? '')
          : t
  ];
}

/// 🚪 이 통화가 **[viewerUid]에게** 끝난 통화인가.
///
/// 공부방은 "통화 중에 잠깐 들여다보기"와 "끝난 통화 정리"를 갈라야 한다.
/// 예전에는 `ended_at` 하나로 갈랐는데 그 값은 **호스트만 쓴다.** 게스트가
/// 호스트보다 먼저 나가면(2026-09-16 실기기: 게스트 18.0초, 호스트 19.1초)
/// 게스트 공부방이 열리는 순간 아직 값이 없고, 게스트 폰은 "통화 중"으로
/// 오판해 canonical도 재전사도 건너뛴 채 실시간 줄만 보여 준다.
///
/// 내 `flush_done` 표시는 **내가 나가면서 직접 찍는 값**이다
/// ([markDuoFlushDone]). 그것이 있으면 나는 이 통화를 이미 끝냈다 — 상대가
/// 아직 안 나갔더라도 나에게는 정리할 통화다. 통화 중 들여다보기에는 이
/// 표시가 없다.
bool duoSessionEndedForViewer(
  Map<String, dynamic>? session, {
  required String viewerUid,
}) {
  if (session == null) return false;
  if (session[kDuoEndedAtField] != null) return true;
  final Object? marks = session[kDuoFlushDoneField];
  return viewerUid.isNotEmpty && marks is Map && marks[viewerUid] != null;
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
      final marks =
          (data?[kDuoFlushDoneField] as Map?) ?? const <dynamic, dynamic>{};
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
    return await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
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
    // 📝 [KEEP-ALL] 듀오의 두 모드를 다 읽는다. 받는 문턱은 낮추고 지우는
    //   일은 여기서 맥락을 보고 한다 — 잡아 두고 나중에 고르는 쪽이,
    //   들어올 때 버려서 유저가 한 말을 잃는 것보다 낫다.
    //   값은 `routine_mode_duo.dart`의 kDuoModeDirect / kDuoModeInterpreter다.
    //   그 상수는 위젯에 있고 서비스가 위젯을 부르지 않는다 — 글자로 적는다.
    final String mode = (data['duoMode'] ?? '').toString();
    if (mode != 'direct' && mode != 'interpreter') continue;
    list.add(DuoSourceUtterance(
      id: doc.id,
      role: (data['senderRole'] ?? '').toString(),
      text: text,
      spokenAtMs: (data['spokenAt'] as num?)?.toInt() ??
          (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
          0,
      seq: (data['seq'] as num?)?.toInt() ?? 0,
      srcLang: (data['srcLang'] ?? '').toString(),
      // 🆕 여태 읽고 버리던 값들이다. 개인 방에 **없는 줄을 새로 만들려면**
      //   이 셋이 있어야 한다 — 누구 줄인지(senderUid), 소리가 어디서 왔는지
      //   (sttSource), 어느 방식의 통화인지(duoMode).
      senderUid: (data['senderUid'] ?? '').toString(),
      sttSource: (data['sttSource'] ?? '').toString(),
      duoMode: mode,
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
    '''You organize the records of one phone call between two people.

THIS PASS DOES NOT TRANSCRIBE OR EDIT SPEECH.
Every source text is immutable. GPT Transcribe and the later PCM-backed Origin
Restoration own the words. Never correct, complete, punctuate, translate, normalize
speech level, or otherwise rewrite a source line. Never return a text field.

Your jobs are structural only:
- Return every source id exactly once.
- Put ids in the real conversational order only when question/answer context makes an
  obvious clock-order error clear. When uncertain, preserve the supplied order.
- Classify a near-identical cross-speaker pickup as echo only when timing and text both
  make it clear. Genuine repetition is not echo.
- Classify an exact same-moment repeat as duplicate only with strong evidence.
- Keep every other line included. Odd wording is never an artifact.
- Optionally return a short subject hint only for an explicitly established third person.
  Never return I/you subject hints and never alter text to agree with a hint.

Do not merge source ids. One output turn must contain exactly one source id. In
particular, do not finish fragments, fix names or words, change endings, or normalize
honorific speech. Origin Restoration can change a short Origin span later, and only
after that span's PCM supports the change.

Return strict JSON only:
{"turns":[{"ids":["<one source id>"],"state":"included","subject":""}]}
Allowed states are included, echo, and duplicate. Return every source id exactly once.
Do not include role or text.''';

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

    final byId = <String, DuoSourceUtterance>{for (final u in source) u.id: u};
    final seen = <String>{};
    final turns = <DuoCanonicalTurn>[];
    for (final item in list) {
      if (item is! Map) continue;
      final ids = <String>[
        for (final id in (item['ids'] as List? ?? const <dynamic>[]))
          if (byId.containsKey(id.toString())) id.toString()
      ];
      if (ids.isEmpty) continue;
      // canonical은 글자의 주인이 아니다. 모델이 text를 고치거나 여러
      // 발화를 합쳐 돌려줘도 무시하고 source의 1차 STT를 그대로 쓴다.
      // 한 줄에 source id 하나만 남겨 pcm_key와 1:1 대응도 지킨다.
      for (final id in ids) {
        if (!seen.add(id)) continue;
        final original = byId[id]!;
        final state = _stateFromModel(item['state']);
        turns.add(DuoCanonicalTurn(
          role: original.role,
          text: original.text,
          sourceIds: <String>[id],
          state: state == kStudyStateMerged ? kStudyStateIncluded : state,
          spokenAtMs: original.spokenAtMs,
          subject: (item['subject'] ?? '').toString().trim(),
        ));
      }
    }

    // 🧭 [ORDER] **모델이 돌려준 순서를 그대로 쓴다.**
    //
    //   예전에는 여기서 `spokenAtMs`로 다시 정렬했다. 그러면 모델이 맥락으로
    //   바로잡은 순서가 그 자리에서 도로 지워진다 — 두 폰의 시계가 어긋나서
    //   생긴 뒤엉킴을 고치라고 시켜 놓고, 고친 결과를 버리고 있었다.
    //
    //   시각은 이제 **빠진 줄을 끼워 넣을 자리를 찾는 데에만** 쓴다.

    // 🧭 [FAIL-OPEN] 모델이 통째로 빠뜨린 원본은 **원문 그대로 되살린다.**
    //   빠진 것이 판단인지 실수인지 알 수 없고, 근거 없이 사람 말을 감추지
    //   않는다.
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
      // 되살린 줄은 시각으로 자리를 찾는다. 모델이 이미 세운 순서는 흔들지
      // 않고, 그 사이에 끼워 넣기만 한다.
      for (final m in missing) {
        turns.insert(_insertionIndexByTime(turns, m.spokenAtMs), m);
      }
    }
    // 🔎 모델이 순서를 얼마나 바꿨는지 한 줄로 남긴다. 실기기에서 "왜 순서가
    //   이런가"를 물을 때 볼 것이 이 숫자뿐이다.
    debugPrint('[DUO-CANON] turns=${turns.length} '
        'reordered=${_countOutOfTimeOrder(turns)}');
    return turns.isEmpty ? null : turns;
  } catch (e) {
    debugPrint('[DUO-CANON] gpt_failed=${e.runtimeType}');
    return null;
  }
}

/// 시각으로 끼워 넣을 자리. 이미 선 순서는 건드리지 않는다.
///
/// 모델이 맥락으로 순서를 바꿨으면 `spokenAtMs`는 더 이상 오름차순이 아니다.
/// 그래도 **처음으로 더 늦은 줄 앞**이 사람이 기대하는 자리다.
int _insertionIndexByTime(List<DuoCanonicalTurn> turns, int? spokenAtMs) {
  final int at = spokenAtMs ?? 0;
  for (int i = 0; i < turns.length; i++) {
    if ((turns[i].spokenAtMs ?? 0) > at) return i;
  }
  return turns.length;
}

/// 시각순과 어긋난 줄이 몇 개인가. **경고가 아니라 계측이다** —
/// 두 폰의 시계가 어긋났으면 이 값이 0이 아닌 것이 정상이다.
int _countOutOfTimeOrder(List<DuoCanonicalTurn> turns) {
  var moved = 0;
  for (int i = 1; i < turns.length; i++) {
    if ((turns[i].spokenAtMs ?? 0) < (turns[i - 1].spokenAtMs ?? 0)) moved++;
  }
  return moved;
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
    case 'artifact':
      return kStudyStateHiddenArtifact;
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
  // 🩺 문맥 교정기. 호출부는 이 값을 넘기지 않는다 — 구조 판정 모델과 다른
  //   축이고, 되돌릴 때도 이 한 줄만 보면 된다.
  String correctorModel = kDuoOriginCorrectorModel,
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
    // 🩺 [ORIGIN-CORRECT] **구조 판정보다 먼저 글자를 본다.**
    //
    //   전사는 발화 하나를 그 자리에서 옮겼고, 지금은 통화 전체가 있다.
    //   잘못 들린 낱말을 여기서 되살려 두면 그 뒤의 판단이 전부 고쳐진 글
    //   위에서 돈다 — 구조 판정도, 개인 방의 원문도, PCM 재검증의 대상도.
    //
    //   실패는 전부 "원 전사 유지"다. 교정이 안 되는 것과 대화가 안 만들어
    //   지는 것은 전혀 다른 무게라, 이 호출이 canonical을 무너뜨리지 않는다.
    final correction = await correctDuoOriginTexts(
      apiKey: apiKey,
      model: correctorModel,
      sourceName: duoDominantSourceLanguage(source),
      lines: duoOriginLinesOf(source),
    ).catchError((Object e) {
      debugPrint('[DUO-ORIGIN-CORRECT] failed=${e.runtimeType}');
      return const DuoOriginCorrectionResult.none();
    });
    final effective =
        applyDuoOriginCorrectionsToSource(source, correction.corrections);

    final reconciled = await reconcileDuoConversation(
      apiKey: apiKey,
      model: model,
      // 교정된 글로 구조를 본다. 되먹임·중복 판정도 같은 글 위에서 돈다.
      source: effective,
    );
    // 🔤 교정 전 글자를 canonical에 함께 싣는다. 개인 방이 이 값을
    //   `original_text_raw`로 옮겨, 무엇이 어떻게 들렸는지가 남는다.
    final turns = attachDuoOriginRawTexts(
      reconciled ?? fallbackCanonical(effective),
      source,
      correction.corrections,
    );
    final int version = DateTime.now().millisecondsSinceEpoch;
    await duoCanonicalRef(roomId).set(<String, dynamic>{
      'status': kCanonicalReady,
      'writer_uid': uid,
      'canonical_version': version,
      'source_count': source.length,
      'shown_count': turns.where((t) => isStudyVisible(t.state)).length,
      'model': reconciled == null ? 'fallback_merge' : model,
      // 🩺 고친 줄이 하나라도 있을 때만 적는다. 개인 방이 이 값을 그 줄의
      //   `origin_correction_model`로 옮긴다 — 옛 판과 섞이지 않게.
      if (correction.corrections.isNotEmpty) 'corrector_model': correctorModel,
      'corrected_count': correction.corrections.length,
      'corrector_overflow': correction.overflow,
      'both_flush_marks': bothDone,
      'turns': <Map<String, dynamic>>[for (final t in turns) t.toMap()],
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('[DUO-CANON] ready room=$roomId source=${source.length} '
        'turns=${turns.length} '
        'shown=${turns.where((t) => isStudyVisible(t.state)).length} '
        'model=${reconciled == null ? 'fallback_merge' : model} '
        'corrected=${correction.corrections.length} '
        'correctorOverflow=${correction.overflow} '
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

// ══════════════════════════════════════════════════════════════════════
// 🧱 개인 방에 옮길 줄을 **미리 세운다** — 판정은 전부 여기 순수 함수에 있다
// ══════════════════════════════════════════════════════════════════════

/// 개인 방의 줄 하나를 어떻게 할 것인가.
///
/// **이 객체는 Firestore를 모른다.** 무엇을 만들고 무엇을 고칠지는 여기서
/// 다 정해지고, [applyDuoCanonicalToHistory]는 그대로 실행만 한다.
@immutable
class DuoCanonicalRowPlan {
  const DuoCanonicalRowPlan({
    required this.sourceId,
    required this.turn,
    required this.isHead,
    required this.studyState,
    required this.createdAtMs,
    required this.create,
  });

  /// 채널 원본 문서 id. **개인 방 문서 id이자 `channel_msg_id`다.**
  final String sourceId;
  final DuoCanonicalTurn turn;

  /// 이 줄이 turn의 대표인가. 아니면 흡수된 조각이다.
  final bool isHead;

  /// 대표는 turn의 상태를, 흡수된 조각은 언제나 [kStudyStateMerged]를 갖는다.
  final String studyState;

  /// 단조 증가로 확정된 시각. **canonical 순서가 이 값을 정한다.**
  final int createdAtMs;

  /// 참이면 개인 방에 없던 줄이라 새로 만든다. 거짓이면 기존 줄을 고친다.
  final bool create;
}

/// ⏱️ canonical 순서를 **시각으로 옮겨 적는다.**
///
/// 공부방은 `created_at` 오름차순으로만 읽는다. 그런데 canonical의 순서는
/// 시각순이 아니다 — 두 폰의 시계가 어긋나 뒤엉킨 자리를 모델이 맥락으로
/// 바로잡은 결과이고, 그 재정렬은 [reconcileDuoConversation]에서 **일부러
/// 되살린 동작**이다(🧭 [ORDER]). 여기서 `spokenAtMs`를 그대로 쓰면 그
/// 수정이 마지막 단계에서 통째로 지워진다.
///
/// 그래서 **시간 기준은 spokenAt이되, 정렬 권한은 canonical 순서가 갖는다.**
///
///   후보가 null·0이거나 앞 줄 이하 → 앞 줄 +1ms
///   그 외                          → 실제 spokenAtMs 그대로
///
/// 시계가 정상인 구간은 진짜 발화 시각이 남고, 어긋난 구간에서만 canonical
/// 순서가 이긴다. 같은 입력이면 언제나 같은 결과라 재적용에도 안전하다.
///
/// ⚠️ **`spokenAtMs`가 없는 옛 canonical turn을 0으로 쓰면 안 된다.** 1970년이
/// 되어 대화 맨 위에 박힌다. 위 규칙이 그 값을 앞 줄 +1ms로 흡수한다.
///
/// 흡수된 조각(`sourceIds.skip(1)`)은 언제나 대표 바로 뒤에 선다 — 화면에는
/// 안 뜨지만 기록의 자리는 대표 옆이다.
///
/// ⚠️ **1970년을 만들지 않는다.** 시각을 모르는 줄에 0이나 1을 적으면 그 줄은
/// 1970-01-01이 되어 대화 맨 위에 박힌다 — 순서만 맞고 시각은 거짓인 기록이다.
/// 모르는 줄은 **가장 가까운 진짜 시각 옆에** 세운다:
///
///   ① `turn.spokenAtMs` — 대표 줄의 시각
///   ② `source.spokenAtMs` — 채널 원본의 시각. 옛 canonical 문서에는 ①이
///      없지만 원본에는 `createdAt` 폴백이 있어서, 여기서 진짜 시각을 얻는다
///   ③ 앞 줄 +1ms — 기준축이 이미 잡힌 뒤의 빈칸
///   ④ **기준축보다 앞에 있는 빈칸은 뒤에서 앞으로 −1ms씩** 메운다
///   ⑤ 통화 전체에 진짜 시각이 하나도 없으면 [fallbackBaseMs]에서 펼친다
///
/// [fallbackBaseMs]는 호출부가 주는 현실적인 기준이다(내 방 줄의 `created_at`,
/// 없으면 지금 시각). 이 값이 0이어도 여기서 0을 쓰지는 않는다.
Map<String, int> assignDuoCanonicalCreatedAtMs(
  List<DuoCanonicalTurn> turns, {
  required int fallbackBaseMs,
  Map<String, DuoSourceUtterance> sourceById =
      const <String, DuoSourceUtterance>{},
}) {
  // ① canonical 순서 그대로 펴고, 줄마다 후보 시각을 모은다.
  final ids = <String>[];
  final candidates = <int?>[];
  final seen = <String>{};
  for (final turn in turns) {
    for (var i = 0; i < turn.sourceIds.length; i++) {
      final String id = turn.sourceIds[i];
      if (id.isEmpty || !seen.add(id)) continue;
      int? c = i == 0 ? turn.spokenAtMs : null;
      // 대표 줄의 시각이 없으면 원본의 시각을 본다. 흡수된 조각도 자기
      // 시각이 있으면 그것을 쓴다 — 대표 +1ms보다 진짜에 가깝다.
      if (c == null || c <= 0) c = sourceById[id]?.spokenAtMs;
      ids.add(id);
      candidates.add((c == null || c <= 0) ? null : c);
    }
  }
  if (ids.isEmpty) return <String, int>{};

  // ②③ 앞에서 뒤로. 기준축이 잡히기 전까지는 비워 둔다.
  final at = List<int?>.filled(ids.length, null);
  int? prev;
  for (var i = 0; i < ids.length; i++) {
    final int? c = candidates[i];
    if (c != null && (prev == null || c > prev)) {
      at[i] = c;
    } else if (prev != null) {
      at[i] = prev + 1;
    }
    if (at[i] != null) prev = at[i];
  }

  final int firstKnown = at.indexWhere((v) => v != null);
  // ⑤ 진짜 시각이 하나도 없는 옛 문서. 호출부가 준 기준에서 펼친다.
  if (firstKnown < 0) {
    final int base = fallbackBaseMs > 0
        ? fallbackBaseMs
        : DateTime.now().millisecondsSinceEpoch;
    return <String, int>{for (var i = 0; i < ids.length; i++) ids[i]: base + i};
  }
  // ④ 기준축 앞의 빈칸을 뒤에서 앞으로 메운다. 첫 발화 **직전**에 서게 된다.
  for (var i = firstKnown - 1; i >= 0; i--) {
    at[i] = at[i + 1]! - 1;
  }
  // 기준축이 비정상으로 작아 1970 근처로 내려갔으면 통째로 기준을 바꾼다.
  if (at.first! <= 0) {
    final int base = fallbackBaseMs > 0
        ? fallbackBaseMs
        : DateTime.now().millisecondsSinceEpoch;
    return <String, int>{for (var i = 0; i < ids.length; i++) ids[i]: base + i};
  }
  return <String, int>{for (var i = 0; i < ids.length; i++) ids[i]: at[i]!};
}

/// 🧱 무엇을 만들고 무엇을 고칠 것인가.
///
/// [existingIds]는 개인 방에 이미 있는 `channel_msg_id`들이고,
/// [userLockedIds]는 사용자가 손댄 줄이다. [myUid]는 개인 방 주인이다.
///
/// **없는 줄을 만드는 조건은 셋이다.**
///   ① source 원본이 손에 있다 — 없으면 채울 칸을 모른다
///   ② `duoMode == 'direct'` — 통역 기록의 본문은 내가 **들은** 번역문이라,
///      상대 원문을 새 줄로 만들면 그 정책이 깨진다
///   ③ `senderUid`가 있다 — 없으면 내 줄인지 상대 줄인지 가릴 수 없고,
///      틀리면 상대가 한 말이 내 말로 남는다. **모르면 안 만든다.**
///
/// 기존 줄을 고치는 쪽은 예전 그대로다 — 두 모드 다 지나간다.
List<DuoCanonicalRowPlan> planDuoCanonicalRows({
  required List<DuoCanonicalTurn> turns,
  required Map<String, DuoSourceUtterance> sourceById,
  required Set<String> existingIds,
  required Set<String> userLockedIds,
  required String myUid,
  required int fallbackBaseMs,
}) {
  // 시각은 **거르기 전에** 배정한다. 잠긴 줄 하나 때문에 나머지 줄의 시각이
  // 흔들리면 재적용마다 방의 순서가 조금씩 달라진다.
  final createdAt = assignDuoCanonicalCreatedAtMs(
    turns,
    fallbackBaseMs: fallbackBaseMs,
    sourceById: sourceById,
  );
  final plans = <DuoCanonicalRowPlan>[];
  final seen = <String>{};
  for (final turn in turns) {
    if (turn.sourceIds.isEmpty) continue;
    for (var i = 0; i < turn.sourceIds.length; i++) {
      final String id = turn.sourceIds[i];
      if (id.isEmpty || !seen.add(id)) continue;
      // 사용자가 손댄 줄은 확정 전이라도 덮지 않는다. 예전과 같다.
      if (userLockedIds.contains(id)) continue;
      final bool exists = existingIds.contains(id);
      final DuoSourceUtterance? src = sourceById[id];
      if (!exists) {
        if (src == null) continue;
        if (src.duoMode != 'direct') continue;
        if (src.senderUid.trim().isEmpty) continue;
      }
      plans.add(DuoCanonicalRowPlan(
        sourceId: id,
        turn: turn,
        isHead: i == 0,
        studyState: i == 0 ? turn.state : kStudyStateMerged,
        createdAtMs: createdAt[id] ?? 0,
        create: !exists,
      ));
    }
  }
  return plans;
}

/// 🧱 새로 만드는 줄 하나의 내용.
///
/// **기존 `_saveHistoryMessage`가 쓰는 칸과 같은 뜻을 유지한다.** 화면과
/// 공부방이 두 종류의 줄을 구별하지 못해야 한다.
///
/// 🚫 **`pcm_key`를 만들지 않는다.** 이 칸은 "이 폰에 그 소리가 있다"는
/// 표시이고, 그 표시가 곧 원문 복원이 다시 들어도 되는 줄이라는 뜻이다.
/// 상대 발화는 상대 폰 마이크에서 나왔으므로 내 창고에 없다 — 여기에 열쇠를
/// 적으면 복원이 **없는 소리를 재검증할 수 있다고 오판한다.**
///
/// ⚠️ **내 발화라도 여기서는 못 적는다. 값이 없어서다.**
/// 창고의 열쇠는 발화 id(`duo_direct_utt_7`)인데, 채널 문서는 그 값을 싣지
/// 않는다(`_uploadMyMessage`가 올리는 칸에 없다). [plan]의 `sourceId`는
/// Firestore 자동 id라 둘을 잇는 고리가 없고, `speaker_seq`로 유추하는 길도
/// 막혀 있다 — 수용된 전사마다 오르는 번호와 발화마다 오르는 번호는 버려진
/// 발화가 하나만 있어도 어긋난다. **없는 근거로 열쇠를 지어내지 않는다.**
///
/// 잃는 것은 없다. 내 발화는 통화 중에 이미 줄이 생기며 열쇠가 박히고, 그
/// 줄은 이 함수가 아니라 update 경로로 간다(거기서는 예전처럼
/// `context_verified_candidate`가 찍힌다). 여기로 오는 내 발화는 "업로드는
/// 됐는데 로컬 저장이 실패한" 줄뿐이고, 그때는 애초에 소리가 어느 줄에도
/// 묶여 있지 않았다.
Map<String, dynamic> buildDuoCanonicalNewRowData({
  required DuoCanonicalRowPlan plan,
  required DuoSourceUtterance source,
  required String myUid,
  required int canonicalVersion,
  required String correctorModel,
}) {
  final DuoCanonicalTurn turn = plan.turn;
  final String text = plan.isHead ? turn.text : source.text;
  final String raw = plan.isHead ? turn.rawText.trim() : '';
  final bool corrected = plan.isHead && turn.wasCorrected;
  return <String, dynamic>{
    // 내 말이면 HOST, 상대 말이면 SYSTEM. 개인 기록마다 값이 다른 칸이다.
    'role': source.senderUid == myUid ? 'HOST' : 'SYSTEM',
    'original_text': text,
    // 직접 대화의 배울글은 공부방이 나중에 만든다. 여기서는 비운다.
    'translated_text': '',
    'created_at': Timestamp.fromMillisecondsSinceEpoch(plan.createdAtMs),
    'channel_msg_id': plan.sourceId,
    if (source.duoMode.isNotEmpty) kDuoModeField: source.duoMode,
    if (source.seq != 0) 'speaker_seq': source.seq,
    if (source.spokenAtMs != 0) 'spoken_at_ms': source.spokenAtMs,
    if (source.senderUid.isNotEmpty) 'speaker_uid': source.senderUid,
    if (source.role.isNotEmpty) 'speaker_role': source.role,
    if (source.sttSource.isNotEmpty) 'stt_source': source.sttSource,
    if (source.srcLang.isNotEmpty) 'source_lang': source.srcLang,
    // 🔤 교정 전 전사 원문. 고쳐진 줄에만 값이 있다.
    if (raw.isNotEmpty && raw != text) kOriginalRawField: raw,
    // 🩺 이 폰에 소리가 없으므로 되짚을 길이 없는 선 교정이다.
    if (corrected) kOriginCorrectionModelField: correctorModel,
    if (corrected) kOriginCorrectionStageField: kOriginCorrectionUnverified,
    if (plan.isHead && turn.subject.isNotEmpty)
      kMessageSubjectHintField: turn.subject,
    kStudyStateField: plan.studyState,
    'canonical_version': canonicalVersion,
  };
}

/// 공유 결과를 내 공부방에 옮긴다.
///
/// 같은 판(`canonical_version`)을 두 번 옮기지 않는다. 통화가 끝나는 순간에
/// 못 옮겼어도 나중에 방을 열 때 이 함수가 다시 맞춘다.
///
/// 원본 메시지 문서는 **지우지 않는다.** 보일지 말지와 글자만 맞춘다.
///
/// 🛡️ [사용자 편집 보호] 가드가 두 겹이다.
///   ① 방 — 사용자가 확정한 방은 한 줄도 건드리지 않는다([roomData]).
///   ② 줄 — 사용자가 손댄 줄은 확정 전이라도 덮지 않는다.
/// 두 겹이어야 하는 이유: 방 가드만 두면 DRAFT에서 한 줄을 고친 **직후**
/// 새 판이 도착할 때 그 수정이 조용히 지워진다.
///
/// [roomData]는 호출부가 이미 읽어 둔 방 문서다. 안 넘기면 여기서 한 번 읽는다.
Future<bool> applyDuoCanonicalToHistory({
  required DocumentReference<Map<String, dynamic>> historyRef,
  required String roomId,
  int? appliedVersion,
  Map<String, dynamic>? roomData,
}) async {
  if (roomId.isEmpty) return false;
  try {
    var room = roomData;
    if (room == null) {
      try {
        room = (await historyRef.get()).data();
      } catch (_) {}
    }
    if (!duoCanonicalMayApplyToRoom(room)) {
      debugPrint('[DUO-CANON] skip_finalized room=$roomId');
      return false;
    }
    final snap = await duoCanonicalRef(roomId).get();
    final data = snap.data();
    if (data == null) return false;
    if ((data['status'] ?? '').toString() != kCanonicalReady) return false;
    final int version = (data['canonical_version'] as num?)?.toInt() ?? 0;
    if (appliedVersion != null && appliedVersion == version) return false;

    final turns = <DuoCanonicalTurn>[
      for (final raw in (data['turns'] as List? ?? const <dynamic>[]))
        if (DuoCanonicalTurn.fromMap(raw) != null)
          DuoCanonicalTurn.fromMap(raw)!
    ];
    if (turns.isEmpty) return false;
    // 어느 모델이 고쳤는지는 **그 판을 만든 쪽**이 적어 둔다. 읽는 폰의
    // 상수를 찍으면, 두 폰의 앱 판이 다를 때 없는 사실이 기록된다.
    final String correctorModel =
        (data['corrector_model'] ?? kDuoOriginCorrectorModel).toString();

    // 🧱 [ROW-CREATE] 채널 원본을 한 번 더 읽는다. **canonical 문서 스키마를
    //   늘리지 않기 위해서다** — 두 폰의 앱 판이 다를 수 있으므로 공유 문서에
    //   칸을 더하는 쪽보다, 이미 있는 컬렉션을 읽는 쪽이 옛 판과 안전하다.
    //   개인 방에 없는 줄을 만들려면 senderUid·sttSource·duoMode가 필요하다.
    final sourceById = <String, DuoSourceUtterance>{};
    try {
      for (final u in await readDuoSourceTimeline(roomId)) {
        sourceById[u.id] = u;
      }
    } catch (e) {
      // 못 읽어도 **고치는 일은 예전대로 돈다.** 만드는 일만 못 할 뿐이다.
      debugPrint(
          '[DUO-CANON] source_read_failed room=$roomId ${e.runtimeType}');
    }

    // 내 방의 줄을 채널 문서 id로 찾을 수 있어야 옮길 수 있다.
    final msgSnap = await historyRef.collection('messages').get();
    final byChannelId = <String, DocumentReference<Map<String, dynamic>>>{};
    // 갈아 끼우기 전의 글자. 이미 한 번 남겨 뒀으면 그것이 원문이다.
    final rawTextById = <String, String>{};
    // 갈아 끼우기 **직전**의 글자. `rawTextById`와 다르다 — 그쪽은 맨 처음
    // 원문이라 두 번째 정돈에서는 지금 글자와 다를 수 있다.
    final curTextById = <String, String>{};
    // 🎧 이 폰에 그 발화의 소리가 있는가. 문맥 교정이 PCM 재검증을 받을 수
    //   있는 줄인지가 여기서 갈린다 — Duo는 내 마이크 소리만 내 창고에 있다.
    final hasPcmById = <String, bool>{};
    // 🛡️ 사용자가 손댄 줄. 확정 전이라도 정돈이 덮지 못한다.
    final userLocked = <String>{};
    // ⏱️ 시각을 하나도 못 찾았을 때 쓸 현실적인 기준. 내 방 줄의 `created_at`
    //   중 가장 늦은 값이고, 그것도 없으면 지금 시각이다. **0은 쓰지 않는다.**
    var fallbackBaseMs = 0;
    // 참고 주어만 따로 잠근다. 줄을 안 고쳤어도 주어는 고쳤을 수 있다.
    final userLockedSubject = <String>{};
    for (final doc in msgSnap.docs) {
      final data = doc.data();
      final String channelId = (data['channel_msg_id'] ?? '').toString().trim();
      if (channelId.isEmpty) continue;
      if (!duoCanonicalMayApplyToMessage(data)) userLocked.add(channelId);
      // 🧭 참고 주어를 사용자가 직접 고쳤으면 정돈이 덮지 않는다. 줄 자체를
      //   고친 것과는 별개다 — 글자는 그대로 두고 주어만 바로잡을 수 있다.
      if (data[kMessageSubjectHintEditedField] != null) {
        userLockedSubject.add(channelId);
      }
      byChannelId[channelId] = doc.reference;
      final String existingRaw =
          (data[kOriginalRawField] ?? '').toString().trim();
      final String currentText =
          (data['original_text'] ?? '').toString().trim();
      rawTextById[channelId] =
          existingRaw.isNotEmpty ? existingRaw : currentText;
      // 🎯 [TARGET-SYNC] 지금 화면에 있는 글자. 정돈이 이걸 바꾸면 그 줄의
      //   배울글은 더 이상 그 줄의 번역이 아니다.
      curTextById[channelId] = currentText;
      hasPcmById[channelId] =
          (data[kMessagePcmKeyField] ?? '').toString().trim().isNotEmpty;
      // ⏱️ 시각을 모르는 옛 줄이 1970년으로 가지 않도록, 이 방이 실제로
      //   존재했던 시각을 모아 둔다.
      final Object? createdAt = data['created_at'];
      if (createdAt is Timestamp) {
        final int ms = createdAt.millisecondsSinceEpoch;
        if (ms > fallbackBaseMs) fallbackBaseMs = ms;
      }
    }
    // 🧱 [ROW-CREATE] **비어 있어도 돌아간다.** 예전에는 여기서 곧장 물러났고,
    //   그래서 개인 방에 줄이 하나도 없으면 canonical이 아무것도 못 옮겼다.
    //   통화 중에 줄을 만들지 않는 구조로 가려면 이 문이 열려 있어야 한다.
    final String myUid = historyRef.parent.parent?.id ?? '';
    final plans = planDuoCanonicalRows(
      turns: turns,
      sourceById: sourceById,
      existingIds: byChannelId.keys.toSet(),
      userLockedIds: userLocked,
      myUid: myUid,
      fallbackBaseMs: fallbackBaseMs > 0
          ? fallbackBaseMs
          : DateTime.now().millisecondsSinceEpoch,
    );
    final planById = <String, DuoCanonicalRowPlan>{
      for (final p in plans) p.sourceId: p
    };

    final batch = FirebaseFirestore.instance.batch();
    var applied = 0;
    var created = 0;
    for (final turn in turns) {
      if (turn.sourceIds.isEmpty) continue;
      // 이은 줄은 첫 조각이 대표가 되고, 나머지는 그 줄에 흡수됐다고 적는다.
      final headPlan = planById[turn.sourceIds.first];
      final head = headPlan == null || headPlan.create
          ? null
          : byChannelId[turn.sourceIds.first];
      if (head != null) {
        // 🔤 [원문 보존] 정돈이 글자를 갈아 끼우기 전의 전사 원문을 남긴다.
        //   문장으로 세우는 일을 열어 준 만큼, **실제로 들린 글자**가
        //   어디에도 안 남는 상태를 만들면 안 된다. 이미 있으면 덮지 않는다 —
        //   가장 처음 것이 원문이다.
        final headRaw =
            (rawTextById[turn.sourceIds.first] ?? '').toString().trim();
        // 🔤 [PERSONAL-ORIGIN] canonical의 turn.text는 양쪽이 공유하는
        //   원본 타임라인이다. 통역 방에서는 두 언어가 섞일 수 있으므로,
        //   통화 중 개인 방에 이미 저장된 Origin 문장을 보존한다.
        final String curText = curTextById[turn.sourceIds.first] ?? '';
        final String personalText = curText.isNotEmpty ? curText : turn.text;
        // 🩺 [ORIGIN-CORRECT] 문맥 교정이 손댄 줄에만 자취를 남긴다.
        //
        //   `context_verified_candidate` — 이 폰에 소리가 있다. 이어지는
        //     원문 복원이 같은 소리를 다시 듣고 뒤집을 수 있는 **후보**다.
        //   `context_unverified` — 이 폰에는 소리가 없다(상대 발화). 문맥만
        //     보고 선 교정이라, 여기서는 되짚을 길이 없다.
        //
        //   안 고친 줄에는 아무것도 찍지 않는다 — 찍으면 "무엇이 교정된
        //   줄인가"를 데이터로 셀 수 없게 된다.
        final bool corrected = turn.wasCorrected;
        final String stage = (hasPcmById[turn.sourceIds.first] ?? false)
            ? kOriginCorrectionVerifiable
            : kOriginCorrectionUnverified;
        batch.update(head, <String, dynamic>{
          'original_text': personalText,
          if (headRaw.isNotEmpty && headRaw != personalText)
            kOriginalRawField: headRaw,
          if (corrected) kOriginCorrectionModelField: correctorModel,
          if (corrected) kOriginCorrectionStageField: stage,
          // 🧭 [SUBJECT-HINT] 3자가 나오는 줄에만 값이 있다. 없으면 빈 문자열을
          //   써서 **지난 판의 값을 지운다** — 정돈이 다시 돌아 "이 줄은 3자
          //   얘기가 아니었다"고 판단했는데 옛 주어가 남아 있으면, 화면이
          //   틀린 사람을 가리킨 채 굳는다.
          if (!userLockedSubject.contains(turn.sourceIds.first))
            kMessageSubjectHintField: turn.subject,
          kStudyStateField: turn.state,
          'canonical_version': version,
          // ⏱️ [ORDER] 기존 줄도 canonical 순서 기준으로 맞춘다. 신규 줄만
          //   맞추면 두 종류가 섞여 순서가 다시 깨진다 —
          //   기존 줄의 `created_at`은 "전사가 끝난 시각"이라 말한 시각보다
          //   뒤에 있고, 신규 줄은 말한 시각에 서기 때문이다.
          if (headPlan != null)
            'created_at':
                Timestamp.fromMillisecondsSinceEpoch(headPlan.createdAtMs),
        });
        applied++;
      }
      for (final id in turn.sourceIds.skip(1)) {
        // 흡수 표시도 덮어쓰기다 — 사용자가 남기기로 한 줄을 감추게 된다.
        final plan = planById[id];
        if (plan == null || plan.create) continue;
        final ref = byChannelId[id];
        if (ref == null) continue;
        batch.update(ref, <String, dynamic>{
          kStudyStateField: kStudyStateMerged,
          'canonical_version': version,
          'created_at': Timestamp.fromMillisecondsSinceEpoch(plan.createdAtMs),
        });
      }
    }

    // 🧱 [ROW-CREATE] 개인 방에 없던 줄을 만든다. **문서 id가 곧 sourceId다** —
    //   같은 채널 원본에서 나온 줄은 개인 방에도 하나뿐임이 구조로 보장되고,
    //   canonical이 여러 번 돌아도 같은 문서에 덮어쓰기로 끝난다.
    for (final plan in plans) {
      if (!plan.create) continue;
      final DuoSourceUtterance? src = sourceById[plan.sourceId];
      if (src == null) continue;
      batch.set(
        historyRef.collection('messages').doc(plan.sourceId),
        buildDuoCanonicalNewRowData(
          plan: plan,
          source: src,
          myUid: myUid,
          canonicalVersion: version,
          correctorModel: correctorModel,
        ),
        SetOptions(merge: true),
      );
      created++;
    }

    if (applied == 0 && created == 0) return false;
    await batch.commit();
    await historyRef.update(<String, dynamic>{
      kDuoCanonicalVersionField: version,
      kDuoCanonicalAppliedAtField: FieldValue.serverTimestamp(),
      'msg_count': turns.where((t) => isStudyVisible(t.state)).length,
    });
    debugPrint('[DUO-CANON] applied room=$roomId version=$version '
        'turns=${turns.length} applied=$applied created=$created '
        'source=${sourceById.length} existing=${byChannelId.length}');
    return true;
  } catch (e) {
    debugPrint('[DUO-CANON] apply_failed=${e.runtimeType}');
    return false;
  }
}
