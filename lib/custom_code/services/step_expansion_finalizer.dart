import 'package:cloud_firestore/cloud_firestore.dart';

import 'step_expansion_builder.dart';

// ====================================================================
// 🌱 [EXPANSION-FINALIZE] 유저가 방을 나간 뒤 P2/P3 자료를 만든다
// --------------------------------------------------------------------
// **여기서 처음으로 영어가 생긴다.** 방은 원어 상담만 했고, 진짜 원본은
// 대화 전체(transcript)다. 대화방이 매 턴 자라게 하던 문장은 더 이상
// P2의 출처가 아니다 — 그건 이제 턴 게이트일 뿐이다.
//
// 순서를 지키는 것이 이 파일의 전부다(개편안 §22).
//
//   유저 종료 → transcript는 이미 턴마다 저장돼 있다
//            → 방 문서를 `building`으로 표시하고 Practice를 잠근다
//            → Builder 실행
//            → 성공: expansions + final_sentence 저장, Practice 개방
//              실패: 실패 사유를 남긴다. **구경로로 조용히 대체하지 않는다.**
//
// ⚠️ 위젯 생명주기와 끊어서 돈다. 유저는 이미 방을 나갔고, Firestore 쓰기는
//   화면이 없어도 끝난다. 그래서 이 함수는 State를 만지지 않는다.
// ====================================================================

/// 방 문서의 `expansion_status` 값.
///
/// **구 세션에는 이 필드가 아예 없다.** 없음 = 옛 방식(줄별 expanded_sentence)
/// 이라는 뜻이고, 히스토리는 그걸 보고 옛 렌더로 간다.
class StepExpansionStatus {
  StepExpansionStatus._();

  /// Builder가 도는 중. 앱이 죽으면 여기서 멈춘 채 남는다 — 히스토리가
  /// 재시도를 걸 수 있어야 하는 상태다.
  static const String building = 'building';

  /// 사다리가 만들어졌다. 이때만 Practice를 연다.
  static const String ok = 'ok';

  /// 실패. 사유는 `expansion_failure`에 남는다. transcript는 멀쩡하다.
  static const String failed = 'failed';
}

/// `building`이 이만큼 묵으면 죽은 것으로 본다.
///
/// Builder는 길어도 40초다. 그보다 한참 지나도 `building`이면 만들던 중에
/// 앱이 죽은 것이다 — 그런 문서는 영원히 "정리 중"으로 남으므로 화면이
/// 다시 걸 수 있어야 한다.
const Duration kStepExpansionStaleAfter = Duration(minutes: 3);

/// 이 방의 사다리를 지금 다시 만들 수 있는 상태인가.
///
/// 실패했거나, `building`인 채로 [kStepExpansionStaleAfter]를 넘겼을 때다.
/// 갓 시작한 `building`은 아직 도는 중이라 건드리지 않는다.
bool canRetryStepExpansion({
  required String status,
  required DateTime? startedAt,
  DateTime? now,
}) {
  if (status == StepExpansionStatus.failed) return true;
  if (status != StepExpansionStatus.building) return false;
  // 시작 시각을 모르면 되돌릴 근거가 없다 — 재시도를 열어 준다.
  if (startedAt == null) return true;
  final elapsed = (now ?? DateTime.now()).difference(startedAt);
  return elapsed >= kStepExpansionStaleAfter;
}

/// 저장된 messages 문서에서 원어 대화를 추린다.
///
/// [stepExpansionTranscriptFrom]은 화면이 들고 있던 말풍선을 읽고, 이쪽은
/// Firestore에 남은 것을 읽는다. **재시도가 반드시 이 길로 온다** — 다시
/// 만들 때의 원본은 그때 나눈 대화지, 방이 계산해 뒀던 무엇이 아니다.
List<StepExpansionTurn> stepExpansionTranscriptFromMessages(
  List<Map<String, dynamic>> messages,
) {
  final turns = <StepExpansionTurn>[];
  for (final data in messages) {
    final role = (data['role'] ?? '').toString();
    if (role != 'HOST' && role != 'SYSTEM') continue;
    final text = (data['original_text'] ?? '').toString().trim();
    if (text.isEmpty || text == '...') continue;
    turns.add(StepExpansionTurn(isUser: role == 'HOST', text: text));
  }
  return turns;
}

/// `_localMessages`에서 원어 대화만 추려 Builder에 넘길 모양으로 만든다.
///
/// 화면 부스러기를 걸러내는 게 일의 절반이다 — 아직 확정되지 않은
/// `HOST_TEMP`, 아직 글자가 안 온 빈 AI 말풍선, 되묻기 자리표시자.
/// 이것들이 섞이면 Builder가 잡담을 의미 발전으로 오해한다.
List<StepExpansionTurn> stepExpansionTranscriptFrom(
  List<Map<String, dynamic>> localMessages,
) {
  final turns = <StepExpansionTurn>[];
  for (final message in localMessages) {
    final role = (message['role'] ?? '').toString();
    // 확정 전 미리보기는 대화가 아니다.
    if (role != 'HOST' && role != 'SYSTEM') continue;
    final text = (message['original'] ?? '').toString().trim();
    if (text.isEmpty || text == '...') continue;
    turns.add(StepExpansionTurn(isUser: role == 'HOST', text: text));
  }
  return turns;
}

/// 방 문서에 사다리를 박는다. 성공했을 때만 Practice가 열린다.
///
/// [roomRef]는 `users/{uid}/chat_history/{roomId}`다. 방 위젯이 들고 있는
/// 무타입 참조를 그대로 받는다. 이 함수가 도는 동안
/// 유저는 이미 다른 화면에 있다.
Future<void> finalizeStepExpansions({
  required DocumentReference<Object?> roomRef,
  required String apiKey,
  required List<StepExpansionTurn> transcript,
  required String originLang,
  required String targetLang,
  void Function(String tag, String message)? onLog,
}) async {
  void log(String tag, String message) => onLog?.call(tag, message);

  // 재시도도 이 함수를 탄다. 시작 시각을 여기서 갱신해야 두 번째 시도가
  // 곧바로 stale로 보이지 않는다.
  try {
    await roomRef.update(<String, dynamic>{
      'expansion_status': StepExpansionStatus.building,
      'expansion_started_at': FieldValue.serverTimestamp(),
      'has_practice': false,
    });
  } catch (error) {
    log('❌ [EXPANSION-SAVE-ERR]', '${error.runtimeType} $error');
    return;
  }

  final result = await StepExpansionBuilder.build(
    apiKey: apiKey,
    transcript: transcript,
    originLang: originLang,
    targetLang: targetLang,
  );

  if (!result.isUsable) {
    // 🚫 [NO-SILENT-FALLBACK] 여기서 대화방이 자라게 하던 문장을 대신
    //   집어넣고 싶어진다. 넣으면 안 된다 — 그건 사후 재구성이 아니라
    //   턴마다 이어 붙인 다른 물건이고, 실패했다는 사실이 지워져 다시
    //   만들 기회도 사라진다. 실패는 실패로 남긴다.
    try {
      await roomRef.update(<String, dynamic>{
        'expansion_status': StepExpansionStatus.failed,
        'expansion_failure': result.failure.name,
        'has_practice': false,
      });
    } catch (error) {
      log('❌ [EXPANSION-SAVE-ERR]', '${error.runtimeType} $error');
      return;
    }
    log('⚠️ [EXPANSION-FAILED]',
        'reason=${result.failure.name} turns=${transcript.length} → 재시도 가능');
    return;
  }

  try {
    await roomRef.update(<String, dynamic>{
      ...result.toJson(),
      'expansion_status': StepExpansionStatus.ok,
      'expansion_failure': FieldValue.delete(),
      'expansion_built_at': FieldValue.serverTimestamp(),
      // 🎓 [PRACTICE-GATE] Practice는 **자료가 실제로 생긴 뒤에만** 열린다.
      //   나가는 순간 미리 켜 두면, Builder가 실패한 방도 공부방에 연습으로
      //   떠서 눌렀을 때 빈 화면이 나온다.
      'has_practice': true,
    });
  } catch (error) {
    log('❌ [EXPANSION-SAVE-ERR]', '${error.runtimeType} $error');
    return;
  }
  log('🌱 [EXPANSION-OK]',
      'steps=${result.steps.length} finalLen=${result.finalSentence.length}');
}
