// 🩺 [DUO-ORIGIN-CORRECT] 사람이 하지 않은 말이 학습 자료로 남지 않는가.
//
// 이 파일이 지키는 것 셋.
//
//   1. **되살리는 것만 통과한다.** 잘못 들린 낱말 하나를 문맥으로 되살리는
//      일과, 문장을 다듬는 일은 다르다. 다듬기는 전부 거절이다.
//   2. **숫자와 고유명사는 문맥으로 못 고친다.** 그 판단은 소리가 한다.
//   3. **폭주하면 통째로 버린다.** 무너진 응답에서 고른 몇 개도 근거가 없다.
//
// 모델 호출은 주입이라 네트워크 없이 모든 갈래를 실제로 태운다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_origin_corrector.dart';

List<DuoOriginLine> lines(List<String> texts) => <DuoOriginLine>[
      for (var i = 0; i < texts.length; i++)
        DuoOriginLine(
          id: 'm${i + 1}',
          speaker: i.isEven ? 'A' : 'B',
          text: texts[i],
        )
    ];

/// 정해진 JSON만 돌려주는 모델.
DuoOriginModelCall says(Object body) =>
    (_) async => body is String ? body : jsonEncode(body);

/// 아무 말도 못 하는 모델.
DuoOriginModelCall get silent => (_) async => null;

Map<String, dynamic> fix(String id, String text) =>
    <String, dynamic>{'id': id, 'text': text};

void main() {
  // ══════════════════════════════════════════════════════════════════
  group('되살리기 — 잘못 들린 낱말 하나', () {
    test('뒷지표 → 기차표', () {
      expect(
        isMinimalOriginCorrection('아까 뒷지표를 예매했어.', '아까 기차표를 예매했어.'),
        isTrue,
      );
    });

    test('띄어쓰기가 흔들려도 같은 교정이다 — 어절 수로 세지 않는다', () {
      expect(
        isMinimalOriginCorrection('아까 뒷 지표를 예매했어.', '아까 기차표를 예매했어.'),
        isTrue,
      );
    });

    test('문장 끝의 낱말도 되살린다', () {
      expect(isMinimalOriginCorrection('내일 서울 갈려고', '내일 서울 가려고'), isTrue);
    });

    test('띄어쓰기만 고친 것은 교정이 아니다 — 되살린 낱말이 없다', () {
      expect(isMinimalOriginCorrection('아까 기차 표를 샀어', '아까 기차표를 샀어'), isFalse);
    });

    test('같은 글자는 교정이 아니다', () {
      expect(isMinimalOriginCorrection('밥 먹었어', '밥 먹었어'), isFalse);
      expect(isMinimalOriginCorrection(' 밥 먹었어 ', '밥 먹었어'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('다듬기는 전부 거절한다', () {
    test('문장 전체를 다시 쓰면 거절', () {
      expect(
        isMinimalOriginCorrection(
          '이번 주 토요일에 연구회 모임이 한강공원에서 있다더라!',
          '이번 주 토요일에 연구회가 한강공원으로 옮겨진다더라!',
        ),
        isFalse,
      );
    });

    test('조사를 바꾸면 거절', () {
      expect(isMinimalOriginCorrection('밥을 먹었어', '밥은 먹었어'), isFalse);
      expect(isMinimalOriginCorrection('학교에 갔어', '학교로 갔어'), isFalse);
    });

    test('어미를 바꾸면 거절 — 반말이 존댓말이 되지 않는다', () {
      expect(isMinimalOriginCorrection('밥 먹었어', '밥 먹었다'), isFalse);
      expect(isMinimalOriginCorrection('밥 먹었어요', '밥 먹었습니다'), isFalse);
    });

    test('없던 말을 보태면 거절', () {
      expect(
        isMinimalOriginCorrection('어제 갔어', '어제 병원에 다녀왔다고 말했어'),
        isFalse,
      );
    });

    test('말을 지우면 거절', () {
      expect(
        isMinimalOriginCorrection('어제 병원에 갔다 왔잖아 진짜로', '어제 갔잖아'),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('숫자와 고유명사는 소리가 판단한다', () {
    test('3시 → 4시는 거절', () {
      expect(isMinimalOriginCorrection('3시에 만나자', '4시에 만나자'), isFalse);
    });

    test('한글 수사도 단위로 걸린다 — 세시 → 네시', () {
      expect(isMinimalOriginCorrection('세시에 만나자', '네시에 만나자'), isFalse);
    });

    test('금액이 달라지면 거절', () {
      expect(isMinimalOriginCorrection('12000원 냈어', '13000원 냈어'), isFalse);
    });

    test('사람 이름은 거절 — 호칭이 붙은 자리', () {
      expect(
        isMinimalOriginCorrection('김민수 씨한테 물어봤어', '김민석 씨한테 물어봤어'),
        isFalse,
      );
    });

    test('지명은 거절 — 자리 표식이 붙은 자리', () {
      expect(isMinimalOriginCorrection('강남역에서 만나자', '강북역에서 만나자'), isFalse);
    });

    test('라틴 문자가 낀 자리는 거절 — 제품·상호는 소리로 확인한다', () {
      expect(isMinimalOriginCorrection('Naver에 올렸어', 'Never에 올렸어'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('응답 읽기 — 모르는 것은 버린다', () {
    final textById = <String, String>{
      'm1': '아까 뒷지표를 예매했어.',
      'm2': '언제 타?',
    };

    test('모르는 id는 무시한다', () {
      final out = parseDuoOriginCorrections(
        jsonEncode(<String, dynamic>{
          'corrections': <Map<String, dynamic>>[fix('nope', '아무 말')]
        }),
        textById: textById,
      );
      expect(out, isEmpty);
    });

    test('같은 id가 두 번 오면 하나만 본다', () {
      final out = parseDuoOriginCorrections(
        jsonEncode(<String, dynamic>{
          'corrections': <Map<String, dynamic>>[
            fix('m1', '아까 기차표를 예매했어.'),
            fix('m1', '아까 비행기표를 예매했어.'),
          ]
        }),
        textById: textById,
      );
      expect(out.length, 1);
      expect(out.single.corrected, '아까 기차표를 예매했어.');
    });

    test('빈 후보와 같은 글자는 무시한다', () {
      final out = parseDuoOriginCorrections(
        jsonEncode(<String, dynamic>{
          'corrections': <Map<String, dynamic>>[
            fix('m1', ''),
            fix('m2', '언제 타?'),
          ]
        }),
        textById: textById,
      );
      expect(out, isEmpty);
    });

    test('JSON이 깨지면 빈 목록이다', () {
      expect(parseDuoOriginCorrections('{oops', textById: textById), isEmpty);
      expect(parseDuoOriginCorrections('', textById: textById), isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('폭주 가드 — 넘치면 통째로 버린다', () {
    List<DuoOriginProposal> many(int n) => <DuoOriginProposal>[
          for (var i = 0; i < n; i++)
            DuoOriginProposal(
              id: 'm$i',
              raw: '아까 뒷지표를 예매했어.',
              corrected: '아까 기차표를 예매했어.',
            )
        ];

    test('10턴에 3개까지는 적용한다', () {
      final out = screenDuoOriginCorrections(many(3), turns: 10);
      expect(out.overflow, isFalse);
      expect(out.accepted, 3);
    });

    test('10턴에 4개면 전부 버린다', () {
      final out = screenDuoOriginCorrections(many(4), turns: 10);
      expect(out.overflow, isTrue);
      expect(out.accepted, 0);
      expect(out.proposed, 4);
    });

    test('30턴은 4개까지, 5개면 버린다', () {
      expect(screenDuoOriginCorrections(many(4), turns: 30).overflow, isFalse);
      expect(screenDuoOriginCorrections(many(5), turns: 30).overflow, isTrue);
    });

    test('100턴은 15개까지, 16개면 버린다', () {
      expect(screenDuoOriginCorrections(many(15), turns: 100).overflow, isFalse);
      expect(screenDuoOriginCorrections(many(16), turns: 100).overflow, isTrue);
    });

    test('가드에 걸린 것은 그 줄만 빠진다 — 나머지는 산다', () {
      final out = screenDuoOriginCorrections(<DuoOriginProposal>[
        const DuoOriginProposal(
          id: 'm1',
          raw: '아까 뒷지표를 예매했어.',
          corrected: '아까 기차표를 예매했어.',
        ),
        const DuoOriginProposal(
          id: 'm2',
          raw: '3시에 만나자',
          corrected: '4시에 만나자',
        ),
      ], turns: 20);
      expect(out.overflow, isFalse);
      expect(out.corrections.keys, <String>['m1']);
      expect(out.rejected, contains('m2:not_minimal'));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('한 통화를 통째로 태운다', () {
    final call = lines(<String>[
      '기차 언제 타?',
      '내일 서울 가려고.',
      '표는 샀어?',
      '아까 뒷지표를 예매했어.',
    ]);

    test('문맥이 확실하면 그 줄만 고친다', () async {
      final out = await resolveDuoOriginCorrections(
        lines: call,
        call: says(<String, dynamic>{
          'corrections': <Map<String, dynamic>>[fix('m4', '아까 기차표를 예매했어.')]
        }),
      );
      expect(out.corrections, <String, String>{'m4': '아까 기차표를 예매했어.'});
      expect(out.proposed, 1);
      expect(out.overflow, isFalse);
    });

    test('모델이 아무 말도 못 하면 원 전사를 지킨다', () async {
      final out = await resolveDuoOriginCorrections(lines: call, call: silent);
      expect(out.corrections, isEmpty);
      expect(out.overflow, isFalse);
    });

    test('호출이 터져도 원 전사를 지킨다', () async {
      final out = await resolveDuoOriginCorrections(
        lines: call,
        call: (_) async => throw StateError('boom'),
      );
      expect(out.corrections, isEmpty);
    });

    test('빈 대화는 모델을 부르지 않는다', () async {
      var called = false;
      final out = await resolveDuoOriginCorrections(
        lines: const <DuoOriginLine>[],
        call: (_) async {
          called = true;
          return null;
        },
      );
      expect(called, isFalse);
      expect(out.corrections, isEmpty);
    });

    test('모델에게 주는 대화는 시간순 전체이고 화자는 A/B뿐이다', () async {
      String? seen;
      await resolveDuoOriginCorrections(
        lines: call,
        call: (payload) async {
          seen = payload;
          return null;
        },
      );
      final decoded = jsonDecode(seen!) as Map<String, dynamic>;
      final sent = (decoded['lines'] as List).cast<Map<String, dynamic>>();
      expect(sent.length, 4);
      expect(sent.map((l) => l['speaker']).toSet(), <String>{'A', 'B'});
      expect(sent.first['id'], 'm1');
      expect(sent.last['text'], '아까 뒷지표를 예매했어.');
      // HOST/GUEST라는 낱말이 모델에게 가지 않는다.
      expect(seen, isNot(contains('HOST')));
      expect(seen, isNot(contains('GUEST')));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('지시문', () {
    test('금지 항목이 프롬프트에 그대로 적혀 있다', () {
      final p = buildDuoOriginCorrectorPrompt('Korean');
      expect(p, contains('Most of this call is in Korean'));
      expect(p, contains('NEVER TOUCH THESE'));
      expect(p, contains("people's names"));
      expect(p, contains('Do not fix grammar'));
      expect(p, contains('returning nothing is a'));
    });

    test('언어를 모르면 못 박지 않는다', () {
      final p = buildDuoOriginCorrectorPrompt('   ');
      expect(p, contains('the language the speakers are already using'));
    });
  });
}
