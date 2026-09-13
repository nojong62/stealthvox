// 🔍 [ORIGIN-RESTORE] 사람이 하지 않은 말이 학습 자료로 남지 않는가.
//
// 이 파일이 지키는 두 가지가 다른 무엇보다 앞선다.
//
//   1. **PCM이 없으면 절대 고치지 않는다.** 문맥만으로 고치는 것은 "조금
//      이상하다"로 원문을 바꾸는 일과 구분되지 않는다.
//   2. **Target은 Origin을 고치지 못한다.** 영어에서 이상해 보여도 소리가
//      원문을 지지하면 원문이 남는다.
//
// 모델 호출은 주입이라 네트워크 없이 모든 갈래를 실제로 태운다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/origin_restoration.dart';

RestorationTurn user(String id, String text, {int? seq, String hint = ''}) =>
    RestorationTurn(
      id: id,
      isUser: true,
      text: text,
      pcmKey: seq == null ? '' : 'turn_$seq',
      subjectHint: hint,
    );

RestorationTurn ai(String id, String text) =>
    RestorationTurn(id: id, isUser: false, text: text);

OriginSuspect suspect(
  String turnId,
  String span,
  String candidate, {
  SuspectReason reason = SuspectReason.speakerConflict,
  SuspectConfidence confidence = SuspectConfidence.medium,
  String evidence = '',
}) =>
    OriginSuspect(
      turnId: turnId,
      span: span,
      candidate: candidate,
      reason: reason,
      confidence: confidence,
      targetEvidence: evidence,
    );

/// 정해진 답만 내놓는 탐지기.
SuspectDetector detector(List<OriginSuspect> out) =>
    (_) async => List<OriginSuspect>.of(out);

SuspectDetector get noSuspects => detector(const <OriginSuspect>[]);

/// 특정 발화 번호에 대해 정해진 재전사문을 주는 창고.
AcousticRechecker ears(Map<int, String?> heard) =>
    (key) async => heard[int.tryParse(key.replaceAll('turn_', '')) ?? -1];

void main() {
  // ══════════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════
  group('재청취 언어 — 실통화와 같은 조건으로 다시 듣는다', () {
    test('아는 언어 이름은 코드로 못 박는다', () {
      expect(restorationLanguageCode('Korean'), 'ko');
      expect(restorationLanguageCode('English'), 'en');
      expect(restorationLanguageCode('Japanese'), 'ja');
    });

    test('대소문자와 공백은 흡수한다', () {
      expect(restorationLanguageCode('  korean '), 'ko');
      expect(restorationLanguageCode('KOREAN'), 'ko');
    });

    test('표에 없는 이름은 빈 문자열이다 — 틀린 언어를 못 박느니 안 박는다', () {
      expect(restorationLanguageCode('Klingon'), '');
      expect(restorationLanguageCode(''), '');
      expect(restorationLanguageCode('   '), '');
    });
  });

  group('최소 수정 — 낱말 하나를 되살린다', () {
    test('한 낱말을 바꾼다', () {
      expect(
        applySpanPatch('네가 어제 병원에 갔다 왔잖아.', '네가', '내가'),
        '내가 어제 병원에 갔다 왔잖아.',
      );
    });

    test('조사 한 글자도 바꿀 수 있다', () {
      expect(
        applySpanPatch('동생이 학교에 갔어', '동생이', '동생은'),
        '동생은 학교에 갔어',
      );
    });

    test('원문에 없는 자리는 거절한다', () {
      // 모델이 지어낸 span이다.
      expect(applySpanPatch('내가 어제 갔어', '우리가', '내가'), isNull);
    });

    test('두 번 나오는 낱말은 거절한다', () {
      // 어느 것인지 알 수 없다. 첫 번째를 고르면 엉뚱한 자리를 고친다.
      expect(applySpanPatch('내가 내가 갔어', '내가', '네가'), isNull);
    });

    test('문장 전체 rewrite는 거절한다', () {
      expect(
        applySpanPatch(
          '이번 주 토요일에 연구회 모임이 한강공원에서 있다더라',
          '이번 주 토요일에 연구회 모임이 한강공원에서 있다더라',
          '이번 주 토요일에 연구회가 한강공원으로 옮겨진다더라',
        ),
        isNull,
      );
    });

    test('낱말 수가 바뀌면 거절한다 — 기존 가드를 우회하지 않는다', () {
      expect(applySpanPatch('내가 갔어', '내가', '내가 어제'), isNull);
      expect(applySpanPatch('내가 어제 갔어', '내가 어제', '내가'), isNull);
    });

    test('같은 글자로 바꾸는 것은 수정이 아니다', () {
      expect(applySpanPatch('내가 갔어', '내가', '내가'), isNull);
      expect(applySpanPatch('내가 갔어', '', '내가'), isNull);
      expect(applySpanPatch('내가 갔어', '내가', ''), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('소리가 판정한다', () {
    test('후보가 들리면 후보를 지지한다', () {
      expect(judgeAcoustic('내가 어제 병원에 갔어', '네가', '내가'),
          AcousticVerdict.supportsCandidate);
    });

    test('원문이 들리면 원문을 지킨다', () {
      expect(judgeAcoustic('네가 어제 병원에 갔어', '네가', '내가'),
          AcousticVerdict.supportsOriginal);
    });

    test('둘 다 들리면 알 수 없다', () {
      expect(judgeAcoustic('내가 네가 헷갈려', '네가', '내가'), AcousticVerdict.unclear);
    });

    test('둘 다 없으면 알 수 없다', () {
      expect(judgeAcoustic('어제 병원에 갔어', '네가', '내가'), AcousticVerdict.unclear);
    });

    test('들은 것이 없으면 소리가 없는 것이다', () {
      expect(judgeAcoustic(null, '네가', '내가'), AcousticVerdict.unavailable);
      expect(judgeAcoustic('', '네가', '내가'), AcousticVerdict.unavailable);
      expect(judgeAcoustic('   ', '네가', '내가'), AcousticVerdict.unavailable);
    });

    test('띄어쓰기 차이는 무시한다', () {
      expect(judgeAcoustic('내 가 아니고 내가 갔어', '네가', '내가'),
          AcousticVerdict.supportsCandidate);
    });
  });

  group('등급 — high는 소리가 있어야만 나온다', () {
    test('소리가 후보를 지지하면 high', () {
      expect(
        resolveConfidence(
            AcousticVerdict.supportsCandidate, SuspectConfidence.high),
        SuspectConfidence.high,
      );
      expect(
        resolveConfidence(
            AcousticVerdict.supportsCandidate, SuspectConfidence.medium),
        SuspectConfidence.high,
      );
    });

    test('문맥이 low면 소리가 맞아도 올리지 않는다', () {
      // "문법이 어색하다" 정도로 원문을 바꾸지 않는다.
      expect(
        resolveConfidence(
            AcousticVerdict.supportsCandidate, SuspectConfidence.low),
        SuspectConfidence.low,
      );
    });

    test('소리가 원문을 지지하면 low', () {
      expect(
        resolveConfidence(
            AcousticVerdict.supportsOriginal, SuspectConfidence.high),
        SuspectConfidence.low,
      );
    });

    test('소리가 없거나 불분명하면 medium', () {
      expect(
        resolveConfidence(AcousticVerdict.unavailable, SuspectConfidence.high),
        SuspectConfidence.medium,
      );
      expect(
        resolveConfidence(AcousticVerdict.unclear, SuspectConfidence.high),
        SuspectConfidence.medium,
      );
    });

    test('high만 반영한다', () {
      expect(shouldApply(SuspectConfidence.high), isTrue);
      expect(shouldApply(SuspectConfidence.medium), isFalse);
      expect(shouldApply(SuspectConfidence.low), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('응답 읽기', () {
    const known = <String>{'t1', 't2'};

    test('정상 응답을 읽는다', () {
      final out = parseOriginSuspects(
        '{"suspects":[{"turn_id":"t1","span":"네가","candidate":"내가",'
        '"reason":"speakerConflict","confidence":"high"}]}',
        knownTurnIds: known,
      );
      expect(out.single.turnId, 't1');
      expect(out.single.reason, SuspectReason.speakerConflict);
      expect(out.single.confidence, SuspectConfidence.high);
    });

    test('스네이크 표기도 받는다', () {
      final out = parseOriginSuspects(
        '{"suspects":[{"turn_id":"t1","span":"50분","candidate":"15분",'
        '"reason":"number_conflict"}]}',
        knownTurnIds: known,
      );
      expect(out.single.reason, SuspectReason.numberConflict);
      expect(out.single.confidence, SuspectConfidence.medium);
    });

    test('빈 배열은 정상이다', () {
      expect(
          parseOriginSuspects('{"suspects":[]}', knownTurnIds: known), isEmpty);
    });

    test('깨진 JSON은 빈 목록이다', () {
      expect(parseOriginSuspects('이건 JSON이 아니다', knownTurnIds: known), isEmpty);
      expect(parseOriginSuspects('', knownTurnIds: known), isEmpty);
    });

    test('모르는 turn id는 버린다', () {
      // 지어낸 id를 태우면 엉뚱한 줄을 고친다.
      final out = parseOriginSuspects(
        '{"suspects":[{"turn_id":"없는줄","span":"네가","candidate":"내가"}]}',
        knownTurnIds: known,
      );
      expect(out, isEmpty);
    });

    test('필드가 비면 버린다', () {
      final out = parseOriginSuspects(
        '{"suspects":[{"turn_id":"t1","span":"","candidate":"내가"},'
        '{"turn_id":"t1","span":"네가","candidate":""},'
        '{"turn_id":"t1","span":"내가","candidate":"내가"}]}',
        knownTurnIds: known,
      );
      expect(out, isEmpty);
    });

    test('같은 자리 같은 후보는 한 번만 본다', () {
      final out = parseOriginSuspects(
        '{"suspects":[{"turn_id":"t1","span":"네가","candidate":"내가"},'
        '{"turn_id":"t1","span":"네가","candidate":"내가"}]}',
        knownTurnIds: known,
      );
      expect(out.length, 1);
    });

    test('Target 검사는 근거 없이는 받지 않는다', () {
      // 근거가 없으면 모델이 번역을 건너뛰고 원문만 보고 답한 것이다.
      const body = '{"suspects":[{"turn_id":"t1","origin_span":"네가",'
          '"candidate_origin":"내가","issue":"subject_conflict"}]}';
      expect(
        parseOriginSuspects(body,
            knownTurnIds: known, requireTargetEvidence: true),
        isEmpty,
      );
      expect(
        parseOriginSuspects(body, knownTurnIds: known),
        hasLength(1),
      );
    });

    test('근거가 있으면 받는다', () {
      final out = parseOriginSuspects(
        '{"suspects":[{"turn_id":"t1","origin_span":"네가","candidate_origin":"내가",'
        '"target_evidence":"You thought it would be serious","issue":"speakerConflict"}]}',
        knownTurnIds: known,
        requireTargetEvidence: true,
      );
      expect(out.single.targetEvidence, contains('You thought'));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('폭주 차단 — 정확도 정책이 아니라 안전장치다', () {
    test('적은 수는 통과한다', () {
      expect(isSuspectOverflow(3, 10), isFalse);
      expect(isSuspectOverflow(1, 4), isFalse);
    });

    test('줄이 적은 방은 비율로 자르지 않는다', () {
      // 5줄 중 3건은 비율로는 넘치지만, 그 방에서는 한 건도 못 고치게 된다.
      expect(isSuspectOverflow(3, 5), isFalse);
    });

    test('많으면 막는다', () {
      expect(isSuspectOverflow(20, 100), isTrue);
      expect(isSuspectOverflow(10, 20), isTrue);
    });

    test('줄이 없으면 무조건 막는다', () {
      expect(isSuspectOverflow(5, 0), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('엔진 — 문맥과 소리가 함께 맞을 때만 고친다', () {
    Future<RestorationOutcome> run(
      List<RestorationTurn> turns, {
      required SuspectDetector detect,
      required AcousticRechecker heard,
      SuspectDetector? target,
    }) =>
        OriginRestorationEngine(
          roomId: 'r1',
          detectSuspects: detect,
          recheckAcoustic: heard,
          validateTarget: target ?? noSuspects,
        ).run(turns);

    test('둘 다 지지하면 고친다', () async {
      final out = await run(
        [user('t1', '네가 어제 병원에 갔다 왔잖아.', seq: 1)],
        detect: detector([suspect('t1', '네가', '내가')]),
        heard: ears({1: '내가 어제 병원에 갔다 왔잖아'}),
      );
      expect(out.corrections['t1'], '내가 어제 병원에 갔다 왔잖아.');
      expect(out.turns.single.text, '내가 어제 병원에 갔다 왔잖아.');
      expect(out.stats.corrected, 1);
    });

    test('소리가 원문을 지지하면 고치지 않는다', () async {
      final out = await run(
        [user('t1', '네가 그렇게 생각했는데 별일 아니었어.', seq: 1)],
        detect: detector(
            [suspect('t1', '네가', '내가', confidence: SuspectConfidence.high)]),
        heard: ears({1: '네가 그렇게 생각했는데 별일 아니었어'}),
      );
      expect(out.corrections, isEmpty);
      expect(out.stats.rejected, 1);
    });

    test('PCM이 없으면 고치지 않는다', () async {
      // AI 줄이거나 상한에 걸려 못 쓴 줄이다.
      final out = await run(
        [user('t1', '네가 어제 갔잖아')],
        detect: detector(
            [suspect('t1', '네가', '내가', confidence: SuspectConfidence.high)]),
        heard: ears(const {}),
      );
      expect(out.corrections, isEmpty);
      // 소리를 찾아갔다 못 찾은 것이 아니라 **처음부터 검사 대상이 아니다.**
      // 이 둘을 섞어 세면 pcm_missing으로 창고 상태를 판단할 수 없다.
      expect(out.stats.skippedNoAudio, 1);
      expect(out.stats.pcmMissing, 0);
      expect(out.stats.pcmRechecked, 0, reason: '읽을 소리가 없으면 부르지도 않는다');
    });

    test('PCM 파일이 사라졌으면 고치지 않는다', () async {
      final out = await run(
        [user('t1', '네가 어제 갔잖아', seq: 1)],
        detect: detector([suspect('t1', '네가', '내가')]),
        heard: ears({1: null}),
      );
      expect(out.corrections, isEmpty);
      // 이쪽은 진짜 장애다 — 열쇠가 있는데 파일을 못 읽었다.
      expect(out.stats.pcmMissing, 1);
      expect(out.stats.skippedNoAudio, 0);
    });

    test('재전사가 던져도 고치지 않고 계속 간다', () async {
      final out = await run(
        [user('t1', '네가 어제 갔잖아', seq: 1)],
        detect: detector([suspect('t1', '네가', '내가')]),
        heard: (_) async => throw Exception('timeout'),
      );
      expect(out.corrections, isEmpty);
      expect(out.abandoned, isFalse);
    });

    test('소리가 맞아도 패치가 성립하지 않으면 부르지 않는다', () async {
      final out = await run(
        [user('t1', '내가 내가 갔어', seq: 1)],
        detect: detector([suspect('t1', '내가', '네가')]),
        heard: ears({1: '네가 갔어'}),
      );
      expect(out.corrections, isEmpty);
      expect(out.stats.pcmRechecked, 0, reason: '헛도는 호출은 통째로 낭비다');
    });

    test('모르는 줄은 버린다', () async {
      final out = await run(
        [user('t1', '내가 갔어', seq: 1)],
        detect: detector([suspect('없는줄', '내가', '네가')]),
        heard: ears({1: '네가 갔어'}),
      );
      expect(out.corrections, isEmpty);
      expect(out.stats.rejected, 1);
    });

    test('탐지가 죽으면 원문 그대로 끝낸다', () async {
      final out = await run(
        [user('t1', '내가 갔어', seq: 1)],
        detect: (_) async => throw Exception('500'),
        heard: ears(const {}),
      );
      expect(out.abandoned, isTrue);
      expect(out.turns.single.text, '내가 갔어');
    });

    test('폭주하면 한 건도 반영하지 않는다', () async {
      final turns = <RestorationTurn>[
        for (var i = 1; i <= 10; i++) user('t$i', '내가 갔어 $i', seq: i),
      ];
      final out = await run(
        turns,
        detect: detector([
          for (var i = 1; i <= 8; i++) suspect('t$i', '내가', '네가'),
        ]),
        heard: ears({for (var i = 1; i <= 10; i++) i: '네가 갔어 $i'}),
      );
      expect(out.corrections, isEmpty);
      expect(out.stats.overflow, isTrue);
      expect(out.abandoned, isTrue);
      expect(out.stats.pcmRechecked, 0);
    });

    test('빈 대화는 조용히 끝난다', () async {
      final out = await run(
        const <RestorationTurn>[],
        detect: detector([suspect('t1', 'a', 'b')]),
        heard: ears(const {}),
      );
      expect(out.corrections, isEmpty);
      expect(out.stats.turns, 0);
    });

    test('AI 줄은 고쳐지지 않는다', () async {
      final out = await run(
        [ai('t1', '네가 그랬구나')],
        detect: detector([suspect('t1', '네가', '내가')]),
        heard: ears({1: '내가 그랬구나'}),
      );
      expect(out.corrections, isEmpty, reason: 'AI 줄에는 소리가 없다');
      expect(out.stats.skippedNoAudio, 1);
      expect(out.stats.pcmMissing, 0, reason: 'Duo 상대 발화도 이 갈래다');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('Target은 탐지기일 뿐이다', () {
    test('Target이 찾아낸 자리도 소리가 지지해야 고쳐진다', () async {
      final engine = OriginRestorationEngine(
        roomId: 'r1',
        detectSuspects: noSuspects,
        recheckAcoustic: ears({7: '내가 그렇게 생각했는데 별일 아니었어'}),
        validateTarget: detector([
          suspect('t1', '네가', '내가',
              evidence: 'You thought it would be serious'),
        ]),
      );
      final out = await engine.run([
        user('t1', '네가 그렇게 생각했는데 별일 아니었어.', seq: 7),
      ]);
      expect(out.corrections['t1'], '내가 그렇게 생각했는데 별일 아니었어.');
      expect(out.stats.targetSuspects, 1);
      expect(out.stats.secondRecheck, 1);
    });

    test('영어가 이상해도 소리가 원문을 지지하면 원문이 남는다', () async {
      // 이것이 이 파일에서 가장 중요한 시험이다. Target은 Origin을 고치는
      // 근거가 아니라 "다시 들어 보라"는 신호일 뿐이다.
      final engine = OriginRestorationEngine(
        roomId: 'r1',
        detectSuspects: noSuspects,
        recheckAcoustic: ears({7: '네가 그렇게 생각했는데 별일 아니었어'}),
        validateTarget: detector([
          suspect('t1', '네가', '내가',
              confidence: SuspectConfidence.high,
              evidence: 'You thought it would be serious'),
        ]),
      );
      final out = await engine.run([
        user('t1', '네가 그렇게 생각했는데 별일 아니었어.', seq: 7),
      ]);
      expect(out.corrections, isEmpty);
      expect(out.turns.single.text, '네가 그렇게 생각했는데 별일 아니었어.');
    });

    test('Target 검사가 죽어도 1차 복원은 살린다', () async {
      final engine = OriginRestorationEngine(
        roomId: 'r1',
        detectSuspects: detector([suspect('t1', '네가', '내가')]),
        recheckAcoustic: ears({1: '내가 어제 갔어'}),
        validateTarget: (_) async => throw Exception('timeout'),
      );
      final out = await engine.run([user('t1', '네가 어제 갔어', seq: 1)]);
      expect(out.corrections['t1'], '내가 어제 갔어');
    });

    test('같은 소리를 같은 까닭으로 두 번 보내지 않는다', () async {
      var calls = 0;
      final engine = OriginRestorationEngine(
        roomId: 'r1',
        detectSuspects: detector([suspect('t1', '네가', '내가')]),
        recheckAcoustic: (key) async {
          calls++;
          return '네가 어제 갔어'; // 원문을 지지 → 1차에서 기각
        },
        validateTarget: detector([
          suspect('t1', '네가', '내가', evidence: 'You went'),
        ]),
      );
      final out = await engine.run([user('t1', '네가 어제 갔어', seq: 1)]);
      expect(calls, 1, reason: '같은 turn·span·candidate라 캐시가 받는다');
      expect(out.stats.cacheHit, 1);
      expect(out.corrections, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('지시문', () {
    final origin = buildOriginSuspectInstructions(sourceName: 'Korean');
    final duoOrigin = buildOriginSuspectInstructions(
      sourceName: 'Korean',
      excludeProperNouns: true,
    );
    final target = buildTargetValidationInstructions(
        sourceName: 'Korean', targetLanguage: 'English');
    final duoTarget = buildTargetValidationInstructions(
      sourceName: 'Korean',
      targetLanguage: 'English',
      subjectOnly: true,
    );

    test('전체를 다시 쓰지 말라고 못 박는다', () {
      expect(origin, contains('You are NOT editing, rewriting'));
      expect(origin, contains('Never return a\nwhole sentence.'));
      expect(origin, contains('Never change the number of words.'));
    });

    test('어색함은 근거가 아니라고 적는다', () {
      expect(origin,
          contains('Awkward grammar. Real speech is often ungrammatical'));
      expect(origin, contains('it is not a suspect'));
      expect(target, contains('Awkward is not wrong.'));
    });

    test('3자를 두 사람으로 뭉개지 않는다', () {
      expect(origin,
          contains('Do not assume every subject is one of the two speakers'));
      expect(origin, contains('more than one'));
    });

    test('Target은 고치는 자리가 아니라고 적는다', () {
      expect(target, contains('YOU ARE A DETECTOR, NOT AN EDITOR.'));
      expect(target, contains('You never fix the English'));
      expect(target, contains('original PCM decides'));
      expect(target, contains('never translate it back into Korean'));
    });

    test('Target 근거를 요구한다', () {
      expect(target, contains('"target_evidence" is required.'));
    });

    test('Duo Origin 검사도 고유명사를 해결 대상으로 삼지 않는다', () {
      expect(duoOrigin,
          contains('Do not report names, places, companies, or products'));
      expect(duoOrigin, isNot(contains('properNounConflict')));
      expect(origin, contains('properNounConflict'),
          reason: '다른 모드의 기존 검사 범위는 바꾸지 않는다');
    });

    test('Duo 임시 Target은 주어·행위자만 검사하고 폐기한다', () {
      expect(duoTarget, contains('This Duo Direct pass checks ONLY'));
      expect(duoTarget, contains('"I" and "you"'));
      expect(duoTarget, contains('third person'));
      expect(duoTarget, contains('never output it, never save it'));
      expect(duoTarget, contains('never use it as the final Target'));
      expect(duoTarget, contains('Do not report names'));
      expect(duoTarget, contains('numbers, time, tense, negation'));
      expect(duoTarget, isNot(contains('properNounConflict')));
      expect(duoTarget, isNot(contains('numberConflict')));
    });

    test('없으면 없다고 답하게 한다', () {
      expect(
          origin, contains('Return {"suspects": []} when nothing contradicts'));
      expect(
          target, contains('Return {"suspects": []} when nothing contradicts'));
    });
  });

  _stateGroup();

  group('대화록 형식', () {
    test('turn id와 역할을 싣는다', () {
      final text = formatRestorationTranscript([
        user('t1', '어제 병원 갔어'),
        ai('t2', '괜찮았어?'),
      ]);
      expect(text, contains('[t1] USER: 어제 병원 갔어'));
      expect(text, contains('[t2] OTHER: 괜찮았어?'));
    });

    test('정해진 주어가 있으면 함께 싣는다', () {
      final text = formatRestorationTranscript([
        user('t1', '지금 취업 준비 중이야', hint: 'the user\'s younger sibling'),
      ]);
      expect(text, contains('SUBJECT: the user'));
    });
  });
}

// ══════════════════════════════════════════════════════════════════════
// 실패한 방이 영영 닫히지 않는가.
//
// 예전에는 네트워크 오류나 JSON 깨짐에도 완료 표시를 찍었다. 한 번 어긋난
// 방은 다시는 복원되지 않았고, 고칠 수 있었던 낱말이 되살아날 기회가 없었다.
// ══════════════════════════════════════════════════════════════════════
void _stateGroup() {
  group('복원 상태', () {
    test('한 번도 안 돈 방은 돈다', () {
      expect(shouldRunRestoration(null), isTrue);
      expect(shouldRunRestoration(const <String, dynamic>{}), isTrue);
      expect(
        shouldRunRestoration(const <String, dynamic>{'room_name': 'x'}),
        isTrue,
      );
    });

    test('정상으로 마친 방은 다시 돌지 않는다', () {
      expect(
        shouldRunRestoration(const <String, dynamic>{
          kOriginRestoreStateField: kOriginRestoreCompleted,
        }),
        isFalse,
      );
    });

    test('실패한 방은 다시 돈다', () {
      // 여기가 이 그룹의 핵심이다. timeout 한 번이 방을 영영 닫으면 안 된다.
      expect(
        shouldRunRestoration(const <String, dynamic>{
          kOriginRestoreStateField: kOriginRestoreFailed,
          kOriginRestoreAttemptsField: 1,
        }),
        isTrue,
      );
    });

    test('세 번 실패하면 그만둔다', () {
      expect(
        shouldRunRestoration(const <String, dynamic>{
          kOriginRestoreStateField: kOriginRestoreFailed,
          kOriginRestoreAttemptsField: kOriginRestoreMaxAttempts,
        }),
        isFalse,
      );
      expect(
        shouldRunRestoration(const <String, dynamic>{
          kOriginRestoreStateField: kOriginRestoreFailed,
          kOriginRestoreAttemptsField: kOriginRestoreMaxAttempts + 5,
        }),
        isFalse,
      );
    });

    test('상태 칸이 생기기 전에 완료된 방은 완료로 본다', () {
      // 그때는 그 표시가 완료를 뜻했다. 다시 돌면 고친 글을 원문으로 알고
      // 또 고치기 시작한다.
      expect(
        shouldRunRestoration(const <String, dynamic>{
          kOriginRestoredAtField: 'ts',
        }),
        isFalse,
      );
    });

    test('마지막 시도일 때만 소리를 버린다', () {
      expect(isLastRestorationAttempt(null), isFalse);
      expect(
        isLastRestorationAttempt(
            const <String, dynamic>{kOriginRestoreAttemptsField: 2}),
        isTrue,
        reason: '세 번이 상한이므로 이번 실패로 3이 되어 끝난다',
      );
      // 아직 기회가 남았으면 소리를 지키고 다음을 기다린다.
      expect(
        isLastRestorationAttempt(
            const <String, dynamic>{kOriginRestoreAttemptsField: 1}),
        isFalse,
      );
      expect(
        isLastRestorationAttempt(
            const <String, dynamic>{kOriginRestoreAttemptsField: 0}),
        isFalse,
      );
    });
  });

  group('실측 계수', () {
    test('소리가 무엇을 지지했는지 따로 센다', () async {
      // "많이 고쳤다"가 아니라 "애매한 것은 안 고쳤다"가 성공이라, 원문을
      // 지켜 낸 횟수와 판정 못 한 횟수가 고친 수만큼 중요하다.
      final engine = OriginRestorationEngine(
        roomId: 'r1',
        detectSuspects: detector([
          suspect('t1', '네가', '내가'),
          suspect('t2', '네가', '내가'),
          suspect('t3', '네가', '내가'),
        ]),
        recheckAcoustic: ears({
          1: '내가 갔어', // 후보 지지
          2: '네가 갔어', // 원문 지지
          3: '어제 갔어', // 불명확
        }),
        validateTarget: noSuspects,
      );
      final out = await engine.run([
        user('t1', '네가 갔어', seq: 1),
        user('t2', '네가 갔어', seq: 2),
        user('t3', '네가 갔어', seq: 3),
      ]);
      expect(out.stats.acousticCandidate, 1);
      expect(out.stats.acousticOriginal, 1);
      expect(out.stats.acousticUnclear, 1);
      expect(out.stats.corrected, 1);
      expect(out.stats.rejected, 2);
    });
  });
}
