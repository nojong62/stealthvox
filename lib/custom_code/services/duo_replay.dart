// ====================================================================
// 🎬 [DUO-REPLAY] canonical 위에 얹는 학습용 대화 복원층.
// --------------------------------------------------------------------
//   SOURCE      duo_sessions/{room}/messages          두 사람이 올린 원문
//   CANONICAL   duo_sessions/{room}/canonical/current 가린다. 아무것도 안 지운다
//   REPLAY      duo_sessions/{room}/replay/current    세운다. 튄 줄을 뺀다  ← 이 파일
//   PERSONAL    users/{uid}/chat_history/...          각자 공부방
//
// **두 계층은 섞이지 않는다.**
//   · Replay의 입력은 canonical이다. raw transcript를 직접 읽지 않는다.
//   · Replay는 canonical 문서도, 개인 History 원문도 **건드리지 않는다.**
//     `applyDuoCanonicalToHistory` 같은 덮어쓰기 경로를 타지 않는다.
//   · Replay가 실패해도 canonical과 History는 그대로다. 화면은 원본을 보여준다.
//
// 그래서 canonical의 FAIL-OPEN 원칙(빠진 줄은 원문으로 되살린다)은 그대로
// 살아 있고, "문맥에서 튄 줄을 뺀다"는 판단은 전부 이 위층에서만 일어난다.
// 실제로 한 말은 언제나 canonical에 남아 있으므로 여기서 빼도 잃지 않는다.
//
// 💰 **비용은 통화 중에 생기지 않는다.** 통화가 끝나고 canonical이 확정된
// 뒤 한 번만 부른다. 줄마다 부르지 않는다.
// ====================================================================

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'duo_canonical.dart';
import 'duo_replay_rules.dart';
import 'duo_study_state.dart';

/// 복원된 대화가 사는 자리. canonical 옆에 나란히 둔다 — 새 최상위 컬렉션을
/// 만들지 않는다.
const String kDuoReplayCollection = 'replay';
const String kDuoReplayDoc = 'current';

/// Replay 상태. canonical과 같은 낱말을 쓴다 — 읽는 쪽이 헷갈리지 않게.
const String kReplayReady = 'ready';
const String kReplayFailed = 'failed';

/// 어느 canonical 판에서 만들었는가. 이 값이 지금 canonical과 다르면 옛 Replay다.
const String kDuoReplayCanonicalVersionField = 'canonical_version';

/// 모델 호출 상한. 통화가 끝난 뒤라 사용자를 붙잡지 않는다.
const Duration kDuoReplayGptTimeout = Duration(seconds: 40);

/// 복원에 쓰는 모델. canonical과 따로 둔다 — 하는 일이 다르다.
const String kDuoReplayModel = 'gpt-4.1-mini';

/// 복원된 대화 문서.
DocumentReference<Map<String, dynamic>> duoReplayRef(String roomId) =>
    duoSessionRef(roomId)
        .collection(kDuoReplayCollection)
        .doc(kDuoReplayDoc);

/// canonical 문서에서 Replay 입력을 만든다.
///
/// **canonical만 읽는다.** raw transcript를 직접 읽지 않는 것이 이 계층의 규칙이다.
List<ReplaySourceLine> replaySourceFromCanonical(Map<String, dynamic> data) {
  final raw = data['turns'];
  if (raw is! List) return const <ReplaySourceLine>[];
  final lines = <ReplaySourceLine>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! Map) continue;
    final String text = (item['text'] ?? '').toString().trim();
    if (text.isEmpty) continue;
    final ids = <String>[
      for (final id in (item['source_ids'] as List? ?? const <dynamic>[]))
        id.toString()
    ];
    lines.add(ReplaySourceLine(
      // canonical 줄의 대표 원본 id. 그 고리로 Original Call과 이어진다.
      id: ids.isNotEmpty ? ids.first : 'canon_$i',
      role: (item['role'] ?? '').toString(),
      text: text,
      spokenAtMs: (item['spoken_at_ms'] as num?)?.toInt(),
      state: (item['state'] ?? '').toString(),
    ));
  }
  lines.sort((a, b) => (a.spokenAtMs ?? 0).compareTo(b.spokenAtMs ?? 0));
  return lines;
}

/// 모델을 한 번 부른다. 실패하면 null — 호출부가 원본으로 되돌린다.
Future<ReplayResult?> reconstructReplay({
  required String apiKey,
  required String model,
  required List<ReplaySourceLine> source,
  http.Client? client,
}) async {
  if (apiKey.isEmpty || source.isEmpty) return null;
  final http.Client c = client ?? http.Client();
  try {
    final response = await c
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
              <String, String>{'role': 'system', 'content': kReplayPrompt},
              <String, String>{
                'role': 'user',
                'content': jsonEncode(buildReplayPayload(source)),
              },
            ],
          }),
        )
        .timeout(kDuoReplayGptTimeout);
    if (response.statusCode != 200) {
      debugPrint('[DUO-REPLAY] gpt_status=${response.statusCode}');
      return null;
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final content = body['choices']?[0]?['message']?['content']?.toString();
    if (content == null || content.trim().isEmpty) return null;
    return parseReplayResponse(content: content, source: source);
  } catch (e) {
    debugPrint('[DUO-REPLAY] gpt_failed=${e.runtimeType}');
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// 통화가 끝나고 canonical이 확정된 뒤 **한 번** 돈다.
///
/// ⚠️ **어떤 실패도 canonical·History로 번지지 않는다.** 여기서 하는 쓰기는
/// `replay/current` 하나뿐이고, 그 쓰기마저 실패하면 조용히 물러난다.
/// 화면은 Replay가 없으면 원본을 그대로 보여준다.
Future<void> buildDuoReplay({
  required String roomId,
  required String apiKey,
  String model = kDuoReplayModel,
  http.Client? client,
}) async {
  if (roomId.isEmpty || apiKey.isEmpty) return;
  try {
    final canonSnap = await duoCanonicalRef(roomId).get();
    final canon = canonSnap.data();
    if (canon == null || (canon['status'] ?? '') != kCanonicalReady) {
      debugPrint('[DUO-REPLAY] skip room=$roomId — canonical이 아직 없다');
      return;
    }
    final int canonVersion =
        (canon['canonical_version'] as num?)?.toInt() ?? 0;

    // 같은 canonical 판으로 이미 만들었으면 다시 만들지 않는다.
    final existing = await duoReplayRef(roomId).get();
    final existingData = existing.data();
    if (existingData != null &&
        (existingData['status'] ?? '') == kReplayReady &&
        (existingData[kDuoReplayCanonicalVersionField] as num?)?.toInt() ==
            canonVersion) {
      debugPrint('[DUO-REPLAY] skip room=$roomId — 같은 판이 이미 있다');
      return;
    }

    final prepared = prepareReplaySource(replaySourceFromCanonical(canon));
    if (prepared.isEmpty) {
      debugPrint('[DUO-REPLAY] skip room=$roomId — 세울 줄이 없다');
      return;
    }

    final result = await reconstructReplay(
      apiKey: apiKey,
      model: model,
      source: prepared,
      client: client,
    );
    if (result == null) {
      await _writeFailure(roomId, 'gpt_unavailable', canonVersion);
      return;
    }

    final verdict = judgeReplay(
      result: result,
      sourceCount: prepared.length,
      sourceSpeakers: prepared.map((l) => l.role).toSet().length,
    );
    if (verdict.fallsBack) {
      debugPrint(
          '[DUO-REPLAY] fallback room=$roomId reasons=${verdict.reasons.join(",")}');
      await _writeFailure(roomId, verdict.reasons.join(','), canonVersion);
      return;
    }

    await duoReplayRef(roomId).set(<String, dynamic>{
      'status': kReplayReady,
      kDuoReplayCanonicalVersionField: canonVersion,
      'model': model,
      'source_count': prepared.length,
      'turn_count': result.turns.length,
      'dropped_count': result.dropped.length,
      'turns': <Map<String, dynamic>>[
        for (final t in result.turns)
          <String, dynamic>{
            'role': t.role,
            'text': t.text,
            'source_ids': t.sourceIds,
          }
      ],
      // 무엇을 왜 뺐는지 남긴다. 화면에 쓰지는 않지만, 규칙이 지나쳤는지
      // 되짚을 근거가 이것뿐이다.
      'dropped': <Map<String, dynamic>>[
        for (final d in result.dropped)
          <String, dynamic>{'id': d.id, 'reason': d.reason}
      ],
      'warnings': <String>[for (final w in result.warnings) w.toString()],
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('[DUO-REPLAY] ready room=$roomId source=${prepared.length} '
        'turns=${result.turns.length} dropped=${result.dropped.length} '
        'warnings=${result.warnings.length} model=$model');
  } catch (e) {
    // canonical과 History는 이미 확정돼 있다. 여기서 죽어도 잃는 것이 없다.
    debugPrint('[DUO-REPLAY] build_failed=${e.runtimeType}');
    try {
      await _writeFailure(roomId, e.runtimeType.toString(), null);
    } catch (_) {}
  }
}

Future<void> _writeFailure(
    String roomId, String reason, int? canonVersion) async {
  await duoReplayRef(roomId).set(<String, dynamic>{
    'status': kReplayFailed,
    'reason': reason,
    if (canonVersion != null) kDuoReplayCanonicalVersionField: canonVersion,
    'updated_at': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// 화면이 읽어 갈 한 줄.
class DuoReplayLine {
  const DuoReplayLine({
    required this.role,
    required this.text,
    required this.sourceIds,
  });

  final String role;
  final String text;
  final List<String> sourceIds;
}

/// 복원된 대화. 없으면 null — 그때 화면은 원본을 그대로 보여준다.
class DuoReplayScript {
  const DuoReplayScript({
    required this.lines,
    required this.canonicalVersion,
    required this.droppedCount,
  });

  final List<DuoReplayLine> lines;
  final int canonicalVersion;
  final int droppedCount;

  bool get isUsable => lines.isNotEmpty;
}

/// `replay/current` 문서 하나를 화면이 쓸 모양으로 읽는다.
///
/// **쓸 수 없는 것은 전부 null이다** — 없는 문서, `status=failed`, 모양이
/// 깨진 문서가 다 같은 답으로 떨어진다. 화면은 null이면 Original Call을
/// 그대로 보여주면 되므로 이유를 구별할 필요가 없다(fail-open).
///
/// 순수 함수다. 1회 조회([readDuoReplay])와 실시간 구독이 **같은 이 함수**를
/// 쓴다 — 두 벌이면 한쪽만 고쳐져 조회와 구독의 판정이 갈린다.
DuoReplayScript? parseDuoReplayDoc(Map<String, dynamic>? data) {
  if (data == null) return null;
  if ((data['status'] ?? '') != kReplayReady) return null;
  final raw = data['turns'];
  if (raw is! List || raw.isEmpty) return null;
  final lines = <DuoReplayLine>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final String text = (item['text'] ?? '').toString().trim();
    if (text.isEmpty) continue;
    lines.add(DuoReplayLine(
      role: (item['role'] ?? '').toString(),
      text: text,
      sourceIds: <String>[
        for (final id in (item['source_ids'] as List? ?? const <dynamic>[]))
          id.toString()
      ],
    ));
  }
  if (lines.isEmpty) return null;
  return DuoReplayScript(
    lines: lines,
    canonicalVersion:
        (data[kDuoReplayCanonicalVersionField] as num?)?.toInt() ?? 0,
    droppedCount: (data['dropped_count'] as num?)?.toInt() ?? 0,
  );
}

/// 저장된 Replay를 읽는다. **읽기 실패는 조용히 null이다** — 공부방이
/// Replay 때문에 안 열리는 일은 없어야 한다.
Future<DuoReplayScript?> readDuoReplay(String roomId) async {
  if (roomId.isEmpty) return null;
  try {
    final snap = await duoReplayRef(roomId).get();
    return parseDuoReplayDoc(snap.data());
  } catch (e) {
    debugPrint('[DUO-REPLAY] read_failed=${e.runtimeType}');
    return null;
  }
}

/// `replay/current`를 지켜본다. **문서가 아직 없어도 구독은 유지된다** —
/// 통화 종료 뒤 canonical → Replay 순으로 만들어지는 동안 화면이 열려 있고,
/// 다 만들어지는 순간을 이 흐름이 잡는다.
///
/// 오류는 스트림을 끊지 않고 `null`로 흘려보낸다. Replay는 곁가지라서
/// 권한·네트워크 문제로 공부방이 망가지면 안 된다.
Stream<DuoReplayScript?> watchDuoReplay(String roomId) {
  if (roomId.isEmpty) return const Stream<DuoReplayScript?>.empty();
  return duoReplayRef(roomId).snapshots().map((snap) {
    try {
      return parseDuoReplayDoc(snap.data());
    } catch (e) {
      debugPrint('[DUO-REPLAY] watch_parse_failed=${e.runtimeType}');
      return null;
    }
  }).handleError((Object e) {
    debugPrint('[DUO-REPLAY] watch_failed=${e.runtimeType}');
  });
}

/// 이 방에 Replay가 걸리는가. **직접 대화만이다.**
bool duoRoomHasReplay(Map<String, dynamic> room) =>
    (room[kDuoModeField] ?? '').toString() == 'direct' &&
    (room[kDuoRoomIdField] ?? '').toString().trim().isNotEmpty;

/// 공부방이 쓰는 표시 이름. 화면 두 곳이 같은 낱말을 쓰게 한다.
const String kOriginalCallLabel = 'Original Call';
const String kConversationReplayLabel = 'Conversation Replay';

/// 정돈층이 감춘 줄인가. 화면이 Replay와 원본을 오갈 때 같은 규칙을 본다.
bool isReplayHiddenState(String state) => !isStudyVisible(state);

// ====================================================================
// 🖥️ [REPLAY-VIEW] 화면이 Replay를 어떻게 받아들이는가.
// --------------------------------------------------------------------
// 위젯 밖에 두는 이유는 하나다: **규칙을 시험으로 고정하기 위해서**다.
// 늦게 도착한 Replay, 같은 판의 반복 도착, 실패로 바뀐 Replay를 화면이
// 어떻게 다뤄야 하는지는 위젯 안 setState 사이에 숨어 있으면 안 된다.
//
// 지키는 것 셋.
//   ① **사용자 선택권.** Replay가 생겨도 보고 있던 화면을 바꾸지 않는다.
//      선택지가 하나 늘어날 뿐이다.
//   ② **다시 그리지 않는다.** 같은 판이 여러 번 와도 화면은 가만히 있는다.
//   ③ **사라지면 되돌아간다.** Replay가 없어졌는데 그 탭을 보고 있으면
//      빈 화면이 남는다. 그때만 Original로 되돌린다.
// ====================================================================

class DuoReplayViewState {
  DuoReplayScript? _script;
  bool _showReplay = false;

  /// 마지막으로 반영한 판. 같은 판이 다시 오면 화면을 건드리지 않는다.
  int _appliedVersion = -1;

  DuoReplayScript? get script => _script;

  /// 전환 줄을 보여줄 것인가. 쓸 수 있는 Replay가 있을 때만 참이다.
  bool get hasReplay => _script != null && _script!.isUsable;

  /// 지금 Replay 판을 보고 있는가. Replay가 없으면 언제나 거짓이다.
  bool get showReplay => _showReplay && hasReplay;

  /// 사용자가 탭을 눌렀다. **Replay가 없으면 그쪽으로 못 간다.**
  void select({required bool replay}) {
    if (replay && !hasReplay) return;
    _showReplay = replay;
  }

  /// 조회나 구독이 새 결과를 가져왔다.
  ///
  /// 반환값은 **화면을 다시 그려야 하는가**다. 거짓이면 `setState`를 부르지
  /// 않는다 — 같은 판이 반복해서 오는 동안 목록이 계속 다시 그려지면
  /// 스크롤이 흔들린다.
  bool apply(DuoReplayScript? next) {
    if (next == null || !next.isUsable) {
      // 없어졌다(실패로 바뀌었거나, 문서가 지워졌거나, 모양이 깨졌거나).
      if (_script == null) return false;
      _script = null;
      _appliedVersion = -1;
      // 보고 있던 판이 사라졌으니 원본으로 되돌린다. 빈 화면을 남기지 않는다.
      _showReplay = false;
      return true;
    }
    if (_script != null && _appliedVersion == next.canonicalVersion) {
      return false; // 같은 판이다. 가만히 둔다.
    }
    _script = next;
    _appliedVersion = next.canonicalVersion;
    // ⚠️ `_showReplay`는 **건드리지 않는다.** 원본을 보고 있던 사람을
    //    Replay로 끌고 가지 않는다. 이미 Replay를 보고 있었다면 그 자리에서
    //    새 내용으로 바뀐다.
    return true;
  }
}
