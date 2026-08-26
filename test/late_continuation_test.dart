// 🔁 [LATE-CONTINUATION] Circle Talk 늦은 이어 말하기 규칙 테스트.
//
// 출발점은 실기기 동작이다:
//   "주말에는 친구하고" → (600ms 이상 공백) → "야구장에 가려고 해요"
// Server VAD가 앞쪽에서 speech_stopped를 주는 바람에 AI가 반쪽 문장에 답했다.
//
// 여기서 보는 것은 셋이다.
//   · 언제 "이어 말하기"로 볼 것인가 (창·재생 상태·잠정 턴)
//   · 두 전사를 어떻게 붙이는가 (기계적 정리만, 의미 추측 금지)
//   · 머뭇거림("어…", "음…")을 어떻게 가르는가
//
// 위젯 상태와 타이머가 필요한 부분(무효화·복구·중복 차단)은 순수 함수로
// 뺄 수 없어 실기기 시나리오로 남긴다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/widgets/routine_mode_circle_talk.dart';
import 'package:stealth_vox/custom_code/services/late_continuation.dart';

/// 위젯의 이어 말하기 배선을 이벤트 단위로 재현한다.
///
/// 시각은 인자로 주입해 타이머 없이 결정적으로 돌린다. 판정·병합·말풍선
/// 규칙은 **위젯이 쓰는 함수 그대로** 부른다 — 여기서 규칙을 다시 구현하면
/// 테스트가 자기 자신을 검증하게 된다.
class _TurnHarness {
  final List<UserTurnSegment> segments = <UserTurnSegment>[];
  final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];
  final List<String> assistantStartedWith = <String>[];
  final Set<String> _handledItems = <String>{};

  int _speechStoppedAtMs = -1;
  int _waitStartedAtMs = -1;
  int _candidate = 0;
  int _candidateSeq = 0;
  int _bubbleSeq = 0;
  String _hostBubbleId = '';
  String _aiBubbleId = '';

  /// 소켓이 아직 결과를 못 받은 발화가 있는가(`hasPendingUtterance`).
  bool serverPending = false;

  /// 지금 유저가 말하는 중인가(`isUserSpeaking`). **serverPending과 별개다** —
  /// 말하는 중에는 아직 committed가 안 나서 pending 장부가 빌 수 있다.
  bool userSpeaking = false;
  bool aiPlaybackStarted = false;
  bool abandoned = false;
  int invalidations = 0;

  bool get candidateAlive => _candidate != 0;
  int get assistantStarts => assistantStartedWith.length;
  String get userText => composeUserTurnText(segments.map((s) => s.text));

  /// 소켓의 `speech_stopped`. 여기서 유저는 말을 멈추고, 하드캡을 다시 잰다.
  void speechStopped({required int at}) {
    _speechStoppedAtMs = at;
    userSpeaking = false;
    _waitStartedAtMs = at;
  }

  /// 소켓의 `input_audio_buffer.committed`. 구간이 확정돼 전사 대기로 넘어간다.
  void committed() {
    userSpeaking = false;
    serverPending = true;
  }

  void speechStarted({required int at}) {
    userSpeaking = true; // 소켓이 콜백보다 먼저 _speechInFlight를 세운다
    final elapsed = _speechStoppedAtMs < 0 ? -1 : at - _speechStoppedAtMs;
    if (!shouldTreatAsLateContinuation(
      msSinceSpeechStopped: elapsed,
      candidateAlive: candidateAlive,
      aiPlaybackStarted: aiPlaybackStarted,
    )) {
      return;
    }
    _candidate = ++_candidateSeq;
    _waitStartedAtMs = at;
    // 이미 답변을 만들기 시작했을 때만 무효화한다.
    if (segments.isNotEmpty) {
      invalidations++;
      removeBubbleById(messages, _aiBubbleId);
      _aiBubbleId = '';
    }
  }

  void completed(String itemId,
      {required int order, required String text, required int at}) {
    // 위젯의 1차 중복 방어선(`_handledStreamingItemIds`)과 같은 자리. 같은
    // item_id의 재수신은 여기서 걸리고 파이프라인까지 내려가지 않는다.
    if (!_handledItems.add(itemId)) return;
    if (candidateAlive) {
      final added = mergeUserTurnSegments(
        segments,
        UserTurnSegment(itemId: itemId, order: order, text: text),
      );
      if (!added) return; // 같은 item_id 재수신
      _syncUserBubble();
      _resolve(safetyExpired: false);
      return;
    }
    // 후보가 없는 평소 경로 — 첫 조각으로 턴을 열고 바로 답변을 시작한다.
    segments.clear();
    mergeUserTurnSegments(
      segments,
      UserTurnSegment(itemId: itemId, order: order, text: text),
    );
    _syncUserBubble();
    _startAssistant();
  }

  /// 안전 타이머가 깨어났다. 위젯과 같은 순서로 판단한다 — 더 기다릴지 먼저
  /// 보고, 마무리할 때만 resolve로 넘어간다.
  ///
  /// 반환값은 "기다리기로 했는가"다.
  bool safetyTimerFired({required int at}) {
    final action = decideContinuationWait(
      isUserSpeaking: userSpeaking,
      serverHasPendingUtterance: serverPending,
      msSinceWaitStarted: _waitStartedAtMs < 0 ? 0 : at - _waitStartedAtMs,
    );
    if (action == ContinuationWaitAction.keepWaiting) return true;
    _resolve(safetyExpired: true);
    return false;
  }

  /// 하드캡까지 무시하고 강제로 마무리시키는 경로(테스트 편의).
  void safetyTimeout() => _resolve(safetyExpired: true);

  /// AI 답변이 화면에 붙는 시점(TTS 재생 전).
  void aiReplied(String text) {
    _aiBubbleId = 'ai-${++_bubbleSeq}';
    messages.add(<String, dynamic>{
      'role': 'SYSTEM',
      'target': text,
      'original': '',
      'msgId': _aiBubbleId,
    });
  }

  void _syncUserBubble() {
    if (bubbleIndexById(messages, _hostBubbleId) < 0) {
      _hostBubbleId = 'host-${++_bubbleSeq}';
    }
    upsertUserBubble(messages, id: _hostBubbleId, text: userText);
  }

  void _resolve({required bool safetyExpired}) {
    final decision = decideContinuationNext(
      isUserSpeaking: userSpeaking,
      serverHasPendingUtterance: serverPending,
      hasMeaningfulSegment:
          segments.any((s) => !isHesitationOnlyTranscript(s.text)),
      safetyExpired: safetyExpired,
    );
    switch (decision) {
      case ContinuationDecision.wait:
        return;
      case ContinuationDecision.startAssistant:
        _candidate = 0;
        _syncUserBubble();
        _startAssistant();
        return;
      case ContinuationDecision.abandon:
        _candidate = 0;
        abandoned = true;
        messages.removeWhere((m) => m['role'] == 'HOST_TEMP');
        return;
    }
  }

  void _startAssistant() => assistantStartedWith.add(userText);
}

void main() {
  group('이어 말하기 자격 (§C) — 기준은 speech_started 시각 하나다', () {
    bool decide({
      int msSinceSpeechStopped = 500,
      bool candidateAlive = false,
      bool aiPlaybackStarted = false,
    }) =>
        shouldTreatAsLateContinuation(
          msSinceSpeechStopped: msSinceSpeechStopped,
          candidateAlive: candidateAlive,
          aiPlaybackStarted: aiPlaybackStarted,
        );

    test('창 안에서 다시 말하기 시작하면 이어 말하기다', () {
      expect(decide(msSinceSpeechStopped: 500), isTrue);
    });

    test('1,100ms에 시작해도 창 안이다', () {
      expect(decide(msSinceSpeechStopped: 1100), isTrue);
    });

    test('경계값 1,200ms는 창 안으로 본다', () {
      expect(decide(msSinceSpeechStopped: 1200), isTrue);
    });

    test('1,201ms에 시작하면 이어 말하기가 아니다 — 새 발화다', () {
      expect(decide(msSinceSpeechStopped: 1201), isFalse);
    });

    test('앞 발화가 끝난 적이 없으면(음수) 이어 말하기가 아니다', () {
      expect(decide(msSinceSpeechStopped: -1), isFalse);
    });

    test('AI 음성이 이미 재생 중이면 합치지 않는다 — 재생 중 끼어들기는 별개 작업이다', () {
      expect(decide(aiPlaybackStarted: true), isFalse);
    });

    test('이미 잡아 둔 후보가 있으면 두 번 잡지 않는다', () {
      expect(decide(candidateAlive: true), isFalse);
    });

    test('앞 발화의 전사가 아직 안 왔어도 자격은 성립한다', () {
      // 자격 판정에 "붙일 문장이 있는가"는 들어가지 않는다. 전사는 나중에
      // 도착하고, 그 사이에 유저가 다시 말한 것은 분명한 사실이다.
      expect(decide(msSinceSpeechStopped: 700), isTrue);
    });
  });

  group('후보 확정 뒤의 행동 (§E·§F·§G)', () {
    test('서버가 아직 전사를 물고 있으면 창이 닫혔어도 기다린다', () {
      expect(
        decideContinuationNext(
          isUserSpeaking: false,
          serverHasPendingUtterance: true,
          hasMeaningfulSegment: true,
          safetyExpired: false,
        ),
        ContinuationDecision.wait,
      );
    });

    test('필요한 조각이 다 오면 답변을 시작한다', () {
      expect(
        decideContinuationNext(
          isUserSpeaking: false,
          serverHasPendingUtterance: false,
          hasMeaningfulSegment: true,
          safetyExpired: false,
        ),
        ContinuationDecision.startAssistant,
      );
    });

    test('머뭇거림만 있으면 시간이 남는 동안 더 기다린다 (§F)', () {
      expect(
        decideContinuationNext(
          isUserSpeaking: false,
          serverHasPendingUtterance: false,
          hasMeaningfulSegment: false,
          safetyExpired: false,
        ),
        ContinuationDecision.wait,
      );
    });

    test('안전 타임아웃이 나도 확보된 문장이 있으면 잃지 않고 시작한다 (§G)', () {
      expect(
        decideContinuationNext(
          isUserSpeaking: false,
          serverHasPendingUtterance: true, // 아직 물고 있어도
          hasMeaningfulSegment: true,
          safetyExpired: true,
        ),
        ContinuationDecision.startAssistant,
      );
    });

    test('안전 타임아웃까지 쓸 문장이 하나도 없으면 턴을 놓아준다', () {
      expect(
        decideContinuationNext(
          isUserSpeaking: false,
          serverHasPendingUtterance: false,
          hasMeaningfulSegment: false,
          safetyExpired: true,
        ),
        ContinuationDecision.abandon,
      );
    });
  });

  group('두 전사 합치기 (§E)', () {
    test('앞 전사 + 공백 하나 + 이어진 전사', () {
      expect(
        composeUserTurnText(['주말에는 친구하고', '야구장에 가려고 해요']),
        '주말에는 친구하고 야구장에 가려고 해요',
      );
    });

    test('뒤에 말이 더 붙는 조각의 임시 마침표는 떼고 붙인다', () {
      expect(
        composeUserTurnText(['주말에는 친구하고.', '야구장에 가려고 해요']),
        '주말에는 친구하고 야구장에 가려고 해요',
      );
    });

    test('마지막 조각의 마침표는 남긴다 — 문장이 실제로 거기서 끝났다', () {
      expect(
        composeUserTurnText(['주말에는 친구하고', '야구장에 가려고 해요.']),
        '주말에는 친구하고 야구장에 가려고 해요.',
      );
    });

    test('물음표·느낌표는 화자의 의도라 남긴다', () {
      expect(
        composeUserTurnText(['그래요?', '아니면 다음에 갈까요']),
        '그래요? 아니면 다음에 갈까요',
      );
    });

    test('앞뒤 공백과 중복 공백을 정리한다', () {
      expect(
        composeUserTurnText(['  주말에는   친구하고  ', '  야구장에  가려고 해요 ']),
        '주말에는 친구하고 야구장에 가려고 해요',
      );
    });

    test('빈 조각은 건너뛴다', () {
      expect(
        composeUserTurnText(['주말에는 친구하고', '   ', '야구장에 가려고 해요']),
        '주말에는 친구하고 야구장에 가려고 해요',
      );
    });

    test('조각이 하나뿐이면 그 문장 그대로다', () {
      expect(composeUserTurnText(['야구장에 가려고 해요']), '야구장에 가려고 해요');
    });

    test('문장을 다시 쓰거나 낱말을 보태지 않는다 — 글자는 조각의 합뿐이다', () {
      const first = '어제 회사에서';
      const next = '발표를 했어요';
      final merged = composeUserTurnText([first, next]);
      expect(merged, '$first $next');
      expect(merged.replaceAll(' ', '').length,
          (first + next).replaceAll(' ', '').length);
    });
  });

  group('발화 순서 정렬 (transcription.completed 도착 순서 ≠ 발화 순서)', () {
    List<UserTurnSegment> segmentsOf(List<UserTurnSegment> incoming) {
      final segments = <UserTurnSegment>[];
      for (final s in incoming) {
        mergeUserTurnSegments(segments, s);
      }
      return segments;
    }

    String textOf(List<UserTurnSegment> segments) =>
        composeUserTurnText(segments.map((s) => s.text));

    test('발화는 A→B인데 completed가 B→A로 도착해도 최종 문장은 A→B다', () {
      // 뒷말이 짧아 전사가 먼저 끝나 먼저 도착한 상황.
      final segments = segmentsOf(const [
        UserTurnSegment(itemId: 'item_B', order: 2, text: '야구장에 가려고 해요'),
        UserTurnSegment(itemId: 'item_A', order: 1, text: '주말에는 친구하고'),
      ]);
      expect(segments.map((s) => s.itemId), ['item_A', 'item_B']);
      expect(textOf(segments), '주말에는 친구하고 야구장에 가려고 해요');
    });

    test('A→머뭇거림→B의 completed 순서가 섞여도 실제 발화 순서로 합친다', () {
      // 도착 순서: B(3) → A(1) → 머뭇거림(2)
      final segments = segmentsOf(const [
        UserTurnSegment(itemId: 'item_B', order: 3, text: '야구장에 가려고 해요'),
        UserTurnSegment(itemId: 'item_A', order: 1, text: '주말에는 친구하고'),
        UserTurnSegment(itemId: 'item_um', order: 2, text: '어'),
      ]);
      expect(segments.map((s) => s.order), [1, 2, 3]);
      expect(textOf(segments), '주말에는 친구하고 어 야구장에 가려고 해요');
    });

    test('서로 다른 item_id면 전사가 같아도 두 발화를 모두 남긴다', () {
      // 유저가 정말 두 번 말한 경우. 글자로 중복 제거하면 한 번을 잃는다.
      final segments = segmentsOf(const [
        UserTurnSegment(itemId: 'item_1', order: 1, text: '정말 좋아요'),
        UserTurnSegment(itemId: 'item_2', order: 2, text: '정말 좋아요'),
      ]);
      expect(segments.length, 2);
      expect(textOf(segments), '정말 좋아요 정말 좋아요');
    });

    test('같은 item_id의 completed가 두 번 오면 한 번만 반영한다', () {
      final segments = <UserTurnSegment>[];
      final first = mergeUserTurnSegments(segments,
          const UserTurnSegment(itemId: 'item_1', order: 1, text: '정말 좋아요'));
      final second = mergeUserTurnSegments(segments,
          const UserTurnSegment(itemId: 'item_1', order: 1, text: '정말 좋아요'));
      expect(first, isTrue);
      expect(second, isFalse); // 새로 들어가지 않았다
      expect(segments.length, 1);
      expect(textOf(segments), '정말 좋아요');
    });

    test('같은 item_id면 순번이 달라 보여도 다시 넣지 않는다', () {
      final segments = <UserTurnSegment>[];
      mergeUserTurnSegments(segments,
          const UserTurnSegment(itemId: 'item_1', order: 1, text: '첫 문장'));
      final again = mergeUserTurnSegments(segments,
          const UserTurnSegment(itemId: 'item_1', order: 9, text: '첫 문장'));
      expect(again, isFalse);
      expect(segments.length, 1);
    });

    test('순번이 같은 조각은 들어온 순서를 지킨다 (안정 정렬)', () {
      // 순번을 못 받은 예외 상황. 그때는 도착 순서가 유일한 정보다.
      final segments = segmentsOf(const [
        UserTurnSegment(itemId: 'a', order: 0, text: '하나'),
        UserTurnSegment(itemId: 'b', order: 0, text: '둘'),
        UserTurnSegment(itemId: 'c', order: 0, text: '셋'),
      ]);
      expect(textOf(segments), '하나 둘 셋');
    });

    test('순서가 뒤집혀 도착해도 사용자 턴의 최종 문장은 하나다', () {
      // 화면 말풍선·GPT 입력·History가 모두 이 문자열 하나에서 나온다.
      final segments = segmentsOf(const [
        UserTurnSegment(itemId: 'item_B', order: 2, text: '야구장에 가려고 해요'),
        UserTurnSegment(itemId: 'item_A', order: 1, text: '주말에는 친구하고'),
        UserTurnSegment(itemId: 'item_B', order: 2, text: '야구장에 가려고 해요'),
      ]);
      expect(segments.length, 2); // 중복 item은 안 들어갔다
      final composed = textOf(segments);
      expect(composed, '주말에는 친구하고 야구장에 가려고 해요');
      // 조각이 몇 번 어떤 순서로 오든 합성 결과는 한 벌이다.
      expect(textOf(segments), composed);
    });
  });

  group('머뭇거림 판정 (§F)', () {
    test('"어"만으로는 답변을 확정하지 않는다', () {
      expect(isHesitationOnlyTranscript('어'), isTrue);
      expect(isHesitationOnlyTranscript('음…'), isTrue);
      expect(isHesitationOnlyTranscript('그'), isTrue);
      expect(isHesitationOnlyTranscript('어어어'), isTrue);
    });

    test('빈 전사도 머뭇거림 취급이다(여기서 답변을 확정하면 안 된다)', () {
      expect(isHesitationOnlyTranscript('   '), isTrue);
    });

    test('의미 있는 문장은 머뭇거림이 아니다', () {
      expect(isHesitationOnlyTranscript('야구장에 가려고 해요'), isFalse);
      expect(isHesitationOnlyTranscript('그래서 갔어요'), isFalse);
    });

    test('머뭇거림 뒤에 본문이 오면 셋이 한 사용자 턴으로 이어진다', () {
      // "주말에는 친구하고" → "어" → "야구장에 가려고 해요"
      final segments = <UserTurnSegment>[];
      mergeUserTurnSegments(segments,
          const UserTurnSegment(itemId: 'a', order: 1, text: '주말에는 친구하고'));
      const filler = '어';
      expect(isHesitationOnlyTranscript(filler), isTrue);
      mergeUserTurnSegments(segments,
          const UserTurnSegment(itemId: 'b', order: 2, text: filler));
      const body = '야구장에 가려고 해요';
      expect(isHesitationOnlyTranscript(body), isFalse);
      mergeUserTurnSegments(
          segments, const UserTurnSegment(itemId: 'c', order: 3, text: body));
      expect(composeUserTurnText(segments.map((s) => s.text)),
          '주말에는 친구하고 어 야구장에 가려고 해요');
    });
  });

  // ==================================================================
  // 창 뒤에 도착한 전사 (자격은 창 안에서 이미 확정됐다)
  // ------------------------------------------------------------------
  // 아래 시나리오는 위젯이 실제로 쓰는 함수들
  // (shouldTreatAsLateContinuation / mergeUserTurnSegments /
  //  decideContinuationNext / composeUserTurnText / upsertUserBubble)을
  // 그대로 엮어 이벤트 순서와 시각을 재현한다.
  //
  // ⚠️ 한계: 위젯의 타이머·비동기 배선까지는 재현하지 않는다. 그 부분은
  //   실기기 로그([CONT-DETECT] / [CONT-RESOLVE])로 확인해야 한다.
  // ==================================================================
  group('창 뒤 도착 전사 (전사 도착 시각으로 자격을 판단하지 않는다)', () {
    /// 한 사용자 턴을 이벤트 순서대로 돌리는 최소 재현기.
    /// 위젯과 같은 순서로 같은 함수를 부른다.
    late _TurnHarness turn;

    setUp(() => turn = _TurnHarness());

    test('1) B는 1,100ms에 시작, B completed는 1,300ms 도착 → A+B 병합', () {
      turn.speechStopped(at: 0); // A 발화 종료
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 600);
      expect(turn.assistantStarts, 1, reason: 'A만으로 한 번 시작했다');

      turn.speechStarted(at: 1100); // 창 안 → 후보 확정, 이전 답변 무효화
      expect(turn.candidateAlive, isTrue);
      expect(turn.invalidations, 1);

      turn.speechStopped(at: 1250);
      turn.completed('B', order: 2, text: '야구장에 가려고 해요', at: 1300);

      expect(turn.userText, '주말에는 친구하고 야구장에 가려고 해요');
      expect(turn.assistantStarts, 2, reason: 'A 한 번 + 합친 문장 한 번');
      expect(turn.assistantStartedWith.last, '주말에는 친구하고 야구장에 가려고 해요');
    });

    test('2) B가 창 안에서 시작, completed는 B→A이고 A는 창 종료 후 도착 → A+B 병합', () {
      turn.speechStopped(at: 0);
      turn.speechStarted(at: 900); // A 전사가 오기 전에 다시 말했다
      expect(turn.candidateAlive, isTrue);
      expect(turn.invalidations, 0, reason: '아직 시작한 답변이 없으니 무효화할 것도 없다');

      turn.speechStopped(at: 1150);
      turn.serverPending = true; // A가 아직 서버에 있다
      turn.completed('B', order: 2, text: '야구장에 가려고 해요', at: 1400);
      expect(turn.assistantStarts, 0, reason: 'A를 기다리는 중이다');

      turn.serverPending = false;
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 1800);

      expect(turn.userText, '주말에는 친구하고 야구장에 가려고 해요');
      expect(turn.assistantStarts, 1, reason: 'GPT는 합친 문장으로 한 번만');
    });

    test('3) 창 안에서 B 시작, A completed만 늦게 도착 → 2,500ms 안에 병합', () {
      turn.speechStopped(at: 0);
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 600);
      turn.speechStarted(at: 1000);
      turn.speechStopped(at: 1200);
      turn.serverPending = true;
      turn.completed('B', order: 2, text: '야구장에 가려고 해요', at: 1500);
      expect(turn.assistantStarts, 1, reason: '아직 서버가 물고 있어 기다린다');

      // 안전 타임아웃(2,500ms) 전에 마지막 조각이 도착했다.
      turn.serverPending = false;
      turn.completed('C', order: 3, text: '같이 가기로 했어요', at: 3000);

      expect(turn.userText, '주말에는 친구하고 야구장에 가려고 해요 같이 가기로 했어요');
      expect(turn.assistantStarts, 2);
    });

    test('4) B의 speech_started가 1,201ms → A와 합치지 않는다', () {
      turn.speechStopped(at: 0);
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 600);
      turn.speechStarted(at: 1201); // 창 밖

      expect(turn.candidateAlive, isFalse);
      expect(turn.invalidations, 0, reason: '앞 답변을 죽이지 않는다');
      expect(turn.userText, '주말에는 친구하고');
      expect(turn.assistantStarts, 1);
    });

    test('5) 후보 확정 후 타임아웃 → 확보된 문장을 잃지 않고 GPT 한 번', () {
      turn.speechStopped(at: 0);
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 600);
      turn.speechStarted(at: 1000); // 잡음이었다
      expect(turn.invalidations, 1);
      turn.speechStopped(at: 1600); // VAD가 곧 침묵을 확인한다

      turn.serverPending = true; // 서버는 뭔가 물고 있다고 하지만 끝내 안 온다
      turn.safetyTimeout(); // 하드캡 도달

      expect(turn.userText, '주말에는 친구하고', reason: '확보된 문장은 그대로다');
      expect(turn.assistantStarts, 2, reason: 'A 한 번 + 복구 한 번');
      expect(turn.abandoned, isFalse);
    });

    test('아무 문장도 확보 못 한 채 타임아웃이면 턴을 놓아준다', () {
      turn.speechStopped(at: 0);
      turn.speechStarted(at: 800); // 전사가 오기 전에 잡음
      turn.speechStopped(at: 1400);
      turn.serverPending = false;
      turn.safetyTimeout();

      expect(turn.assistantStarts, 0);
      expect(turn.abandoned, isTrue);
    });
  });

  group('말하는 중인 유저를 자르지 않는다', () {
    test('B가 말하는 중 A completed 도착, 서버 pending=false → GPT 0회', () {
      final turn = _TurnHarness();
      turn.speechStopped(at: 0); // A 종료
      turn.speechStarted(at: 800); // B 시작 — 아직 committed 전이다
      expect(turn.candidateAlive, isTrue);
      expect(turn.userSpeaking, isTrue);

      // B는 아직 말하는 중이라 pending 장부가 비어 있다.
      turn.serverPending = false;
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 900);

      expect(turn.assistantStarts, 0,
          reason: '말하는 중인 유저를 두고 A만으로 답하면 B가 통째로 버려진다');
      expect(turn.userText, '주말에는 친구하고');
    });

    test('이어서 B speech_stopped/committed/completed → A+B로 한 번 시작', () {
      final turn = _TurnHarness();
      turn.speechStopped(at: 0);
      turn.speechStarted(at: 800);
      turn.serverPending = false;
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 900);
      expect(turn.assistantStarts, 0);

      turn.speechStopped(at: 1400); // B가 말을 멈췄다
      turn.committed(); // 구간 확정 → 전사 대기
      expect(turn.assistantStarts, 0, reason: '전사를 아직 기다린다');

      turn.serverPending = false;
      turn.completed('B', order: 2, text: '야구장에 가려고 해요', at: 1900);

      expect(turn.userText, '주말에는 친구하고 야구장에 가려고 해요');
      expect(turn.assistantStarts, 1, reason: 'GPT는 합친 문장으로 한 번만');
    });

    test('B가 길게 말하는 동안 A completed와 타이머 만료 → B를 자르지 않는다', () {
      final turn = _TurnHarness();
      turn.speechStopped(at: 0);
      turn.speechStarted(at: 700); // B 시작, 아주 길게 말한다
      turn.serverPending = false;
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 900);

      // 하드캡(5,000ms)을 훌쩍 넘긴 시점에 타이머가 깨어나도 말하는 중이면
      // 기다린다. 시간으로 말을 자르지 않는다.
      expect(turn.safetyTimerFired(at: 3200), isTrue);
      expect(turn.safetyTimerFired(at: 9000), isTrue);
      expect(turn.safetyTimerFired(at: 20000), isTrue);
      expect(turn.assistantStarts, 0);

      turn.speechStopped(at: 21000); // 이제야 말이 끝났다 — 여기서 캡을 다시 잰다
      turn.committed();
      turn.serverPending = false;
      turn.completed('B', order: 2, text: '야구장에 가려고 해요 정말 오랜만이에요', at: 21600);

      expect(turn.userText, '주말에는 친구하고 야구장에 가려고 해요 정말 오랜만이에요');
      expect(turn.assistantStarts, 1);
    });

    test('말이 끝난 뒤에는 하드캡 5초에서 확보된 문장으로 마무리한다', () {
      final turn = _TurnHarness();
      turn.speechStopped(at: 0);
      turn.speechStarted(at: 800);
      turn.serverPending = false;
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 900);
      turn.speechStopped(at: 1500); // 대기 시작점
      turn.committed(); // serverPending = true — 그런데 전사가 끝내 안 온다

      // 2,500ms 시점: 아직 캡 안이라 기다린다.
      expect(turn.safetyTimerFired(at: 1500 + 2500), isTrue);
      expect(turn.assistantStarts, 0);
      // 5,000ms 시점: 캡 도달 → 확보된 A로 한 번만 답한다.
      expect(turn.safetyTimerFired(at: 1500 + 5000), isFalse);

      expect(turn.assistantStarts, 1);
      expect(turn.assistantStartedWith.single, '주말에는 친구하고');
      expect(turn.abandoned, isFalse);
    });
  });

  group('대기 판정 우선순위', () {
    test('말하는 중이면 안전 타임아웃으로도 확정되지 않는다', () {
      expect(
        decideContinuationNext(
          isUserSpeaking: true,
          serverHasPendingUtterance: false,
          hasMeaningfulSegment: true,
          safetyExpired: true, // 만료됐어도
        ),
        ContinuationDecision.wait,
      );
    });

    test('말하는 중이면 pending 장부가 비어도 기다린다', () {
      expect(
        decideContinuationNext(
          isUserSpeaking: true,
          serverHasPendingUtterance: false,
          hasMeaningfulSegment: true,
          safetyExpired: false,
        ),
        ContinuationDecision.wait,
      );
    });

    test('말이 끝나고 pending도 없으면 그때 시작한다', () {
      expect(
        decideContinuationNext(
          isUserSpeaking: false,
          serverHasPendingUtterance: false,
          hasMeaningfulSegment: true,
          safetyExpired: false,
        ),
        ContinuationDecision.startAssistant,
      );
    });

    test('말하는 중에는 하드캡을 재지 않는다', () {
      expect(
        decideContinuationWait(
          isUserSpeaking: true,
          serverHasPendingUtterance: false,
          msSinceWaitStarted: 60000,
        ),
        ContinuationWaitAction.keepWaiting,
      );
    });

    test('말이 끝난 뒤 서버 대기는 하드캡까지만', () {
      expect(
        decideContinuationWait(
          isUserSpeaking: false,
          serverHasPendingUtterance: true,
          msSinceWaitStarted: kFreeTalkContinuationHardCapMs - 1,
        ),
        ContinuationWaitAction.keepWaiting,
      );
      expect(
        decideContinuationWait(
          isUserSpeaking: false,
          serverHasPendingUtterance: true,
          msSinceWaitStarted: kFreeTalkContinuationHardCapMs,
        ),
        ContinuationWaitAction.resolveNow,
      );
    });

    test('말도 끝났고 서버도 한가하면 더 기다릴 이유가 없다', () {
      expect(
        decideContinuationWait(
          isUserSpeaking: false,
          serverHasPendingUtterance: false,
          msSinceWaitStarted: 0,
        ),
        ContinuationWaitAction.resolveNow,
      );
    });
  });

  group('순서가 뒤집혀도 말풍선은 각각 하나', () {
    test('GPT 1회 · 사용자 말풍선 1개 · AI 말풍선 1개', () {
      final turn = _TurnHarness();
      turn.speechStopped(at: 0);
      turn.speechStarted(at: 700);
      turn.speechStopped(at: 1100);
      turn.serverPending = true;
      turn.completed('B', order: 2, text: '야구장에 가려고 해요', at: 1500);
      turn.serverPending = false;
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 1900);
      // 늦게 한 번 더 도착한 같은 item — 반영되면 안 된다.
      turn.completed('B', order: 2, text: '야구장에 가려고 해요', at: 2000);

      expect(turn.assistantStarts, 1, reason: 'GPT 호출은 한 번');
      turn.aiReplied('네, 재밌겠네요!');

      final hostBubbles =
          turn.messages.where((m) => m['role'] == 'HOST').toList();
      final aiBubbles =
          turn.messages.where((m) => m['role'] == 'SYSTEM').toList();
      expect(hostBubbles.length, 1, reason: '사용자 말풍선은 하나');
      expect(aiBubbles.length, 1, reason: 'AI 말풍선은 하나');
      expect(hostBubbles.single['target'], '주말에는 친구하고 야구장에 가려고 해요');
      expect(turn.messages.where((m) => m['role'] == 'HOST_TEMP'), isEmpty);
    });

    test('무효화된 AI 말풍선은 화면에 남지 않는다', () {
      final turn = _TurnHarness();
      turn.speechStopped(at: 0);
      turn.completed('A', order: 1, text: '주말에는 친구하고', at: 600);
      turn.aiReplied('주말에 뭐 하세요?'); // 첫 답변이 화면에 붙었다
      expect(turn.messages.where((m) => m['role'] == 'SYSTEM').length, 1);

      turn.speechStarted(at: 900); // 이어 말하기 → 무효화
      expect(turn.messages.where((m) => m['role'] == 'SYSTEM'), isEmpty,
          reason: '취소된 AI 말풍선은 걷어낸다');

      turn.speechStopped(at: 1200);
      turn.completed('B', order: 2, text: '야구장에 가려고 해요', at: 1400);
      turn.aiReplied('야구장 좋죠!');

      expect(turn.messages.where((m) => m['role'] == 'HOST').length, 1);
      expect(turn.messages.where((m) => m['role'] == 'SYSTEM').length, 1);
      expect(turn.messages.where((m) => m['role'] == 'SYSTEM').single['target'],
          '야구장 좋죠!');
    });
  });

  group('복구 창 상수', () {
    test('창 기준값은 speech_stopped 기준 1,200ms다', () {
      expect(kFreeTalkContinuationWindowMs, 1200);
    });

    test('이어 발화 안전 타임아웃은 창보다 길다 — 짧으면 뒷말을 기다리다 끊긴다', () {
      expect(kFreeTalkContinuationTranscriptTimeoutMs,
          greaterThan(kFreeTalkContinuationWindowMs));
    });

    test('안전 타임아웃은 기존 전사 타임아웃보다 짧다 — 화면이 8초 멈추면 안 된다', () {
      expect(kFreeTalkContinuationTranscriptTimeoutMs,
          lessThan(kFreeTalkStreamingTranscriptTimeoutMs));
    });
  });
}
