// ====================================================================
// 📚 [STUDY-STATE] 히스토리 한 줄이 공부방에 보이는가.
// --------------------------------------------------------------------
// 듀오 직접 대화는 통화가 끝나면 **양쪽의 실제 대화 흐름을 그대로 유지하면서**,
// 되먹임(echo)·중복 전사·갈라진 조각·명백한 전사 잡음 같은 **기술적으로 생긴
// 찌꺼기만** 정돈해 공부방에 보여 준다.
//
// **실제 사람이 한 발화를 중요도가 낮다는 이유로 숨기지 않는다.** 무엇이
// 중요한 말인지는 판단하지 않는다 — 인사도, "응"도, 되묻는 한마디도 두 사람이
// 실제로 주고받은 대화다. 애매하면 [kStudyStateIncluded]로 둔다.
//
// 예전에는 정돈에서 빠진 줄을 Firestore 문서째 지웠고, 실기기 한 통화에서
// 14줄 중 7줄이 영구히 사라졌다(2026-08-28). 이제 원본 줄은 언제나 남고,
// 이 필드가 **보일지 말지만** 정한다.
//
//   SOURCE    — messages 컬렉션의 모든 문서. 지우지 않는다.
//   CANONICAL — 그중 보이는 줄. 사용자가 읽는 하나의 대화.
//
// 필드가 없는 옛 문서는 보이는 것으로 친다 — 마이그레이션은 하지 않는다.
// ====================================================================

/// 표시 여부를 적는 필드 이름.
const String kStudyStateField = 'study_state';

/// 공부방에 보인다. 필드가 없어도 같은 뜻이고, **판단이 애매하면 이쪽이다.**
const String kStudyStateIncluded = 'included';

/// 상대 스피커 소리가 내 마이크로 들어와 내 발화처럼 전사된 줄.
/// 반대편 화자에게 거의 같은 시각에 같은 말이 있어야 이 판정을 붙인다.
const String kStudyStateHiddenEcho = 'hidden_echo';

/// 같은 발화가 전사·저장 과정 때문에 두 번 이상 생긴 줄.
/// **사람이 실제로 되풀이해 말한 것은 중복이 아니다** — 글자가 같다는 이유만으로
/// 붙이지 않는다.
const String kStudyStateHiddenDuplicate = 'hidden_duplicate';

/// 사람이 낸 소리가 아닌 것을 전사기가 글로 만든 줄.
const String kStudyStateHiddenArtifact = 'hidden_artifact';

/// 사람이 실제로 낸 소리이지만, 자기 차례를 붙들고 말을 고르던 발성일 뿐
/// 대답·물음·반응 어느 것도 아닌 줄("음…", "흠…").
///
/// **전사 잡음이 아니다** — 실제 음성이므로 [kStudyStateHiddenArtifact]와
/// 구별해서 적는다. 판정은 글자 수나 단어 목록이 아니라 앞뒤 문맥에서
/// 나온다. "어."가 대답이면 [kStudyStateIncluded]다. 애매하면 보이는 쪽이다.
const String kStudyStateHiddenHesitation = 'hidden_hesitation';

/// 같은 사람의 한 발화가 여러 조각으로 갈라진 것 중, 합쳐진 줄에 흡수된 조각.
/// 조각 문서는 그대로 남고 합쳐진 결과가 보인다.
const String kStudyStateMerged = 'merged';

/// 정돈·교정이 글을 갈아 끼우기 전의 전사 원문을 담는 필드.
/// 히스토리 교정 경로가 이미 쓰던 이름을 그대로 쓴다.
const String kOriginalRawField = 'original_text_raw';

/// 공부방이 그리지 않는 상태들. **전부 기술적 사유다** — 말의 중요도로
/// 숨기는 상태는 여기에 만들지 않는다.
const Set<String> kStudyStateHidden = <String>{
  kStudyStateHiddenEcho,
  kStudyStateHiddenHesitation,
  kStudyStateHiddenDuplicate,
  kStudyStateHiddenArtifact,
  kStudyStateMerged,
};

/// 이 줄을 공부방에 그리는가.
///
/// 값이 없거나 모르는 값이면 **그린다.** 새 상태가 생겼을 때 옛 앱이 줄을
/// 통째로 숨겨 대화가 비어 보이는 쪽보다, 조금 더 보이는 쪽이 안전하다.
bool isStudyVisible(Object? studyState) {
  final String state = (studyState ?? '').toString().trim();
  if (state.isEmpty) return true;
  return !kStudyStateHidden.contains(state);
}
