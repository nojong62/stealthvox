// ====================================================================
// 🎧 [DUO-FINAL] 통화가 끝난 뒤, 보존해 둔 소리로 원문을 다시 확정한다
// --------------------------------------------------------------------
// 통화 중 전사는 빨라야 한다 — 그 글자가 곧바로 번역돼 상대에게 간다. 그래서
// 서버가 발화를 자르는 대로 받아 쓰고 넘어간다.
//
// **History에 남는 글자는 그럴 이유가 없다.** 통화가 끝나면 그 발화의 소리가
// 앞 여유까지 붙은 한 덩이로 창고에 있다(`DuoSocketPcmCapture`). 같은 소리를
// 한 번 더, 이번에는 급하지 않게 들어서 원문을 확정한다.
//
//   original_text_raw   통화 중 실시간 전사 — **그대로 보존한다**
//   original_text       통화 후 재전사 결과 — 여기만 갈아 끼운다
//   translated_text     **건드리지 않는다**
//
// 둘 다 남기는 것이 이 판의 핵심이다. 나중에 "실시간이 얼마나 틀렸고 재전사가
// 얼마나 고쳤나"를 셀 수 있어야 다음 단계(문맥 교정)를 값으로 판단할 수 있다.
//
// ⚠️ **이 파일에는 문맥이 없다.** 같은 소리를 다시 듣는 일만 한다. 앞뒤 말을
//   보고 낱말을 고치는 일(`duo_origin_corrector`)도, 소리로 되짚는 일
//   (`origin_restoration`)도 이 단계에 섞지 않는다. 섞으면 어느 층이 무엇을
//   고쳤는지 영영 못 가린다.
//
// 🚫 **발화의 정체를 바꾸지 않는다.** 순서·화자·utteranceId는 그대로다.
//   여기서 바뀌는 것은 한 칸(`original_text`)뿐이다.
// ====================================================================

import 'package:flutter/foundation.dart';

import 'origin_pcm_store.dart';

// ══════════════════════════════════════════════════════════════════════
// 방 단위 표시 — 이 통화가 새 파이프라인을 탔는가
// ══════════════════════════════════════════════════════════════════════

/// 재전사 한 판이 **끝까지 돌았다.** 중간에 끊긴 판에는 안 찍는다.
///
/// 이 값이 있어야 PCM을 지울 수 있고, 원문 복원을 건너뛸지 판단할 수 있다.
const String kDuoFinalRoomCompletedField = 'duo_final_completed_at';

/// 그 판에서 실제로 글자를 확정한 줄 수. **0이면 새 경로가 아무것도 못 한 것**이다.
const String kDuoFinalRoomSuccessField = 'duo_final_success_count';

/// 소리를 들었는데 글자를 못 만든 줄 수. 그 줄은 실시간 원문이 남아 있다.
const String kDuoFinalRoomFailField = 'duo_final_fail_count';

/// 🔁 이 방은 **이미 한 판을 끝까지 돌렸는가.**
///
/// 끝까지 돈 판은 마지막에 그 방의 소리를 지운다. 그러니 두 번째 판은 무엇도
/// 더 할 수 없다 — 모든 줄이 `alreadyFinal`이라 `retranscribed=0`이 나오고,
/// 그 0이 방 표시를 덮어쓰면 **한 번 얻은 우회가 풀린다.**
///
/// 실기기에서 그대로 나왔다(2026-09-15). 공부방에 두 번째로 들어가자
/// `success=2`가 `success=0`으로 내려앉았고, 소리가 없는 채로 원문 복원이
/// 다시 돌아 3.3초를 헛되이 썼다.
///
/// 표시가 있으면 판을 열지 않는다. 표시가 없다는 것은 지난 판이 중간에
/// 끊겼다는 뜻이고(그때는 소리도 남아 있다), 그 방은 다시 시도할 값이 있다.
bool duoFinalRoomAlreadyDone(Map<String, dynamic>? room) =>
    room != null && room[kDuoFinalRoomCompletedField] != null;

/// 🧭 이 방에서 **원문 복원(`origin_restoration`)을 건너뛸 것인가.**
///
/// 새 경로가 한 줄이라도 글자를 확정했으면 건너뛴다. 그 줄들은 이미 원본
/// 소리로 다시 들은 결과이고, 그 위에 "의심점만 다시 듣는" 층을 또 얹으면
/// **앞 단계가 고친 것을 뒤 단계가 되돌리는** 상호작용이 생긴다.
///
/// 전사가 끝내 실패해 `pending`이면 성공이 0줄이어도 복원을 건너뛴다.
/// 실패한 줄은 실시간 원문을 보여 주되 PCM을 보존하고, 다음 History 진입에서
/// 같은 `gpt-transcribe`로 다시 처리한다. 이때 기존 복원을 먼저 돌리면 그
/// 러너가 PCM을 지워 재처리 기회가 사라진다.
///
/// PCM 자체가 없어서 성공 0줄로 **완료된** 옛 방만 기존 복원을 그대로 둔다.
bool duoFinalSupersedesRestoration(Map<String, dynamic>? room) {
  if (room == null) return false;
  if (room[kRoomTranscriptionStateField] == kRoomTranscriptionPending) {
    return true;
  }
  if (room[kDuoFinalRoomCompletedField] == null) return false;
  final Object? success = room[kDuoFinalRoomSuccessField];
  return success is int && success > 0;
}

/// 이 줄의 원문을 통화 후 재전사로 확정했다. **성공한 줄에만 찍는다.**
///
/// 두 번 돌지 않게 하는 빗장이자, 나중에 "몇 줄이 재전사를 거쳤나"를 세는 값이다.
const String kDuoFinalTranscribedAtField = 'duo_final_transcribed_at';

/// 재전사가 실제로 글자를 바꿨는가. **바뀐 줄에만 찍는다.**
///
/// 이 값이 있는 줄이 곧 "실시간 전사가 틀렸던 줄"이다. 다음 단계를 값으로
/// 판단하려면 이 수가 필요하다.
const String kDuoFinalChangedField = 'duo_final_changed';

/// 한 줄을 어떻게 할 것인가.
enum DuoFinalAction {
  /// 소리로 다시 들어 원문을 갈아 끼운다.
  retranscribe,

  /// 건너뛴다. 까닭은 [DuoFinalPlan.skipReason]에 있다.
  skip,
}

/// 재전사 대상 한 줄. **Firestore를 모른다** — 판정에 필요한 값만 담는다.
@immutable
class DuoFinalRow {
  const DuoFinalRow({
    required this.docId,
    required this.pcmKey,
    required this.originalText,
    required this.originalRaw,
    required this.sourceLang,
    required this.alreadyFinal,
    required this.userEdited,
  });

  final String docId;

  /// 이 줄의 소리를 가리키는 열쇠. **비어 있으면 되들을 소리가 없다** —
  /// 상대 발화가 여기 해당한다(그 소리는 상대 폰에 있다).
  final String pcmKey;

  final String originalText;

  /// 이미 남아 있는 실시간 전사. 있으면 **덮지 않는다.**
  final String originalRaw;

  /// 이 줄을 말한 언어. 재전사에 못 박는다 — 자동 감지로 두면 짧은 발화에서
  /// 언어가 흔들린다.
  final String sourceLang;

  /// 이미 재전사를 마쳤는가([kDuoFinalTranscribedAtField]).
  final bool alreadyFinal;

  /// 사용자가 손댄 줄인가. **사람이 고친 글을 기계가 덮지 않는다.**
  final bool userEdited;
}

/// 판정 하나.
@immutable
class DuoFinalPlan {
  const DuoFinalPlan({
    required this.docId,
    required this.action,
    this.pcmKey = '',
    this.languageCode = '',
    this.skipReason = '',
  });

  final String docId;
  final DuoFinalAction action;
  final String pcmKey;

  /// 재전사에 못 박을 언어 코드. 표에 없는 언어면 빈 값이고, 그때는 안 넘긴다.
  final String languageCode;
  final String skipReason;

  bool get shouldRetranscribe => action == DuoFinalAction.retranscribe;
}

/// 건너뛰는 까닭. 로그와 테스트가 같은 글자를 쓴다.
class DuoFinalSkip {
  static const String noPcm = 'no_pcm_key';
  static const String alreadyFinal = 'already_final';
  static const String userEdited = 'user_edited';
  static const String emptyText = 'empty_text';
}

/// 🧭 이 줄을 다시 들을 것인가. **순수 함수다.**
///
/// 되들을 소리가 없거나(상대 발화), 이미 끝났거나, 사람이 손댔으면 건너뛴다.
DuoFinalPlan planDuoFinalRow(
  DuoFinalRow row, {
  required String Function(String sourceName) languageCodeOf,
}) {
  if (row.pcmKey.trim().isEmpty) {
    return DuoFinalPlan(
        docId: row.docId,
        action: DuoFinalAction.skip,
        skipReason: DuoFinalSkip.noPcm);
  }
  if (row.alreadyFinal) {
    return DuoFinalPlan(
        docId: row.docId,
        action: DuoFinalAction.skip,
        skipReason: DuoFinalSkip.alreadyFinal);
  }
  // 🛡️ 사람이 고친 글을 기계가 덮지 않는다. 확정 전이라도 그렇다.
  if (row.userEdited) {
    return DuoFinalPlan(
        docId: row.docId,
        action: DuoFinalAction.skip,
        skipReason: DuoFinalSkip.userEdited);
  }
  // 본문이 비어 있으면 되살릴 대상이 아니다.
  if (row.originalText.trim().isEmpty && row.originalRaw.trim().isEmpty) {
    return DuoFinalPlan(
        docId: row.docId,
        action: DuoFinalAction.skip,
        skipReason: DuoFinalSkip.emptyText);
  }
  return DuoFinalPlan(
    docId: row.docId,
    action: DuoFinalAction.retranscribe,
    pcmKey: row.pcmKey.trim(),
    languageCode: languageCodeOf(row.sourceLang),
  );
}

/// 🧭 재전사 결과를 실제로 반영할 것인가, 반영한다면 무엇을 쓸 것인가.
///
/// **빈 글로 덮지 않는다.** 재전사가 실패하거나 빈 글을 돌려주면 실시간 원문이
/// 그대로 남는다 — 소리를 못 들은 것과 말이 없었던 것은 다르다.
///
/// 돌려주는 맵이 비어 있으면 **쓸 것이 없다는 뜻**이다.
Map<String, Object?> buildDuoFinalUpdate({
  required String liveText,
  required String existingRaw,
  required String? finalText,
  required Object finalizedAt,
}) {
  final String next = (finalText ?? '').trim();
  final String live = liveText.trim();
  if (next.isEmpty) return const <String, Object?>{};

  final bool changed = next != live;
  return <String, Object?>{
    'original_text': next,
    // 🔤 실시간 전사를 남긴다. **이미 있으면 덮지 않는다** — 가장 처음 것이
    //   원문이고, 두 번째 판이 그것을 지우면 비교할 기준이 사라진다.
    if (existingRaw.trim().isEmpty && live.isNotEmpty)
      'original_text_raw': live,
    kDuoFinalTranscribedAtField: finalizedAt,
    // 바뀐 줄에만 찍는다. 이 수가 곧 "실시간이 틀렸던 줄"의 수다.
    if (changed) kDuoFinalChangedField: true,
  };
}

/// 한 판의 결과. **발화 내용은 담지 않는다** — 세는 것만 센다.
@immutable
class DuoFinalStats {
  const DuoFinalStats({
    this.rows = 0,
    this.retranscribed = 0,
    this.changed = 0,
    this.failed = 0,
    this.skippedNoPcm = 0,
    this.skippedOther = 0,
  });

  final int rows;
  final int retranscribed;
  final int changed;
  final int failed;
  final int skippedNoPcm;
  final int skippedOther;

  DuoFinalStats copyWith({
    int? rows,
    int? retranscribed,
    int? changed,
    int? failed,
    int? skippedNoPcm,
    int? skippedOther,
  }) =>
      DuoFinalStats(
        rows: rows ?? this.rows,
        retranscribed: retranscribed ?? this.retranscribed,
        changed: changed ?? this.changed,
        failed: failed ?? this.failed,
        skippedNoPcm: skippedNoPcm ?? this.skippedNoPcm,
        skippedOther: skippedOther ?? this.skippedOther,
      );

  @override
  String toString() => 'rows=$rows retranscribed=$retranscribed '
      'changed=$changed failed=$failed '
      'skippedNoPcm=$skippedNoPcm skippedOther=$skippedOther';
}
