// 🩺 [DUO-ORIGIN-CORRECT] 문맥 교정이 canonical에 붙는 자리.
//
// 여기서 지키는 것 넷.
//
//   1. 교정은 **구조 판정보다 먼저** 선다. 그래야 되먹임·중복 판정도 고쳐진
//      글 위에서 돈다.
//   2. **교정 전 글자는 사라지지 않는다.** canonical이 `raw_text`로 들고
//      다니고, 개인 방이 그것을 `original_text_raw`로 옮긴다.
//   3. **옛 canonical 문서는 그대로 읽힌다.** `raw_text`가 없어도 정상이다.
//   4. 모델에게는 HOST/GUEST가 아니라 A/B만 간다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_origin_corrector.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';
import 'package:stealth_vox/custom_code/services/history_text_model.dart';

/// 줄바꿈은 맞춰 읽는다 — 이 저장소는 CRLF다.
String _canonSource() => File('lib/custom_code/services/duo_canonical.dart')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

DuoSourceUtterance u(String id, String role, String text,
        {String lang = 'Korean'}) =>
    DuoSourceUtterance(
      id: id,
      role: role,
      text: text,
      spokenAtMs: 0,
      seq: 0,
      srcLang: lang,
    );

DuoCanonicalTurn turn(String id, String text) => DuoCanonicalTurn(
      role: 'HOST',
      text: text,
      sourceIds: <String>[id],
      state: kStudyStateIncluded,
    );

void main() {
  // ══════════════════════════════════════════════════════════════════
  group('DuoCanonicalTurn.rawText', () {
    test('고친 줄만 raw_text를 싣는다', () {
      final plain = turn('m1', '아까 기차표를 예매했어.');
      expect(plain.toMap().containsKey('raw_text'), isFalse);

      final fixed = plain.withRawText('아까 뒷지표를 예매했어.');
      expect(fixed.toMap()['raw_text'], '아까 뒷지표를 예매했어.');
      expect(fixed.text, '아까 기차표를 예매했어.');
      expect(fixed.wasCorrected, isTrue);
    });

    test('toMap → fromMap 왕복에 살아남는다', () {
      final fixed = turn('m1', '아까 기차표를 예매했어.').withRawText('아까 뒷지표를 예매했어.');
      final back = DuoCanonicalTurn.fromMap(fixed.toMap())!;
      expect(back.text, fixed.text);
      expect(back.rawText, fixed.rawText);
      expect(back.sourceIds, <String>['m1']);
      expect(back.wasCorrected, isTrue);
    });

    test('옛 문서에는 raw_text가 없다 — 그래도 정상으로 읽힌다', () {
      final back = DuoCanonicalTurn.fromMap(<String, dynamic>{
        'role': 'GUEST',
        'text': '표는 샀어?',
        'source_ids': <String>['m2'],
        'state': kStudyStateIncluded,
      })!;
      expect(back.rawText, '');
      expect(back.wasCorrected, isFalse);
      expect(back.text, '표는 샀어?');
    });

    test('같은 글자를 raw로 얹어도 교정으로 치지 않는다', () {
      final same = turn('m1', '표는 샀어?').withRawText('표는 샀어?');
      expect(same.wasCorrected, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('교정기에게 넘기는 대화', () {
    final source = <DuoSourceUtterance>[
      u('m1', 'HOST', '기차 언제 타?'),
      u('m2', 'GUEST', '내일 서울 가려고.'),
      u('m3', 'HOST', '표는 샀어?'),
      u('m4', 'GUEST', '아까 뒷지표를 예매했어.'),
    ];

    test('화자는 A/B로만 바뀐다', () {
      final out = duoOriginLinesOf(source);
      expect(out.map((l) => l.speaker).toList(), <String>['A', 'B', 'A', 'B']);
      expect(out.map((l) => l.id).toList(), <String>['m1', 'm2', 'm3', 'm4']);
    });

    test('role이 비어 있어도 처음 나온 순서로 갈라 준다', () {
      final out = duoOriginLinesOf(<DuoSourceUtterance>[
        u('m1', '', '어'),
        u('m2', 'GUEST', '응'),
        u('m3', '', '그래'),
      ]);
      expect(out.map((l) => l.speaker).toList(), <String>['A', 'B', 'A']);
    });

    test('가장 많이 쓰인 언어를 고른다', () {
      expect(duoDominantSourceLanguage(source), 'Korean');
      expect(
        duoDominantSourceLanguage(<DuoSourceUtterance>[
          u('m1', 'HOST', 'hi', lang: 'English'),
          u('m2', 'GUEST', '응', lang: 'Korean'),
          u('m3', 'HOST', 'yes', lang: 'English'),
        ]),
        'English',
      );
      expect(duoDominantSourceLanguage(const <DuoSourceUtterance>[]), '');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('교정을 타임라인에 얹는다', () {
    final source = <DuoSourceUtterance>[
      u('m1', 'HOST', '표는 샀어?'),
      u('m2', 'GUEST', '아까 뒷지표를 예매했어.'),
    ];

    test('고친 줄만 글자가 바뀐다', () {
      final out = applyDuoOriginCorrectionsToSource(
        source,
        <String, String>{'m2': '아까 기차표를 예매했어.'},
      );
      expect(out[0].text, '표는 샀어?');
      expect(out[1].text, '아까 기차표를 예매했어.');
      // 원본 목록은 그대로다 — 교정 전 글자를 나중에 찾아야 한다.
      expect(source[1].text, '아까 뒷지표를 예매했어.');
    });

    test('교정이 없으면 원본 목록을 그대로 돌려준다', () {
      expect(
        identical(
          applyDuoOriginCorrectionsToSource(source, const <String, String>{}),
          source,
        ),
        isTrue,
      );
    });

    test('고친 줄에만 교정 전 글자가 붙는다', () {
      final turns = <DuoCanonicalTurn>[
        turn('m1', '표는 샀어?'),
        turn('m2', '아까 기차표를 예매했어.'),
      ];
      final out = attachDuoOriginRawTexts(
        turns,
        source,
        <String, String>{'m2': '아까 기차표를 예매했어.'},
      );
      expect(out[0].rawText, '');
      expect(out[0].wasCorrected, isFalse);
      expect(out[1].rawText, '아까 뒷지표를 예매했어.');
      expect(out[1].wasCorrected, isTrue);
    });

    test('교정이 없으면 아무 줄에도 붙지 않는다', () {
      final turns = <DuoCanonicalTurn>[turn('m1', '표는 샀어?')];
      final out =
          attachDuoOriginRawTexts(turns, source, const <String, String>{});
      expect(out.single.rawText, '');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('제품 코드가 그 순서로 서 있는가', () {
    final String src = _canonSource();

    test('교정은 구조 판정보다 먼저 선다', () {
      final read = src.indexOf('final source = await readDuoSourceTimeline');
      final correct = src.indexOf('await correctDuoOriginTexts(');
      final reconcile = src.indexOf('await reconcileDuoConversation(');
      expect(read, greaterThanOrEqualTo(0));
      expect(correct, greaterThan(read));
      expect(reconcile, greaterThan(correct));
    });

    test('구조 판정은 교정된 글을 본다', () {
      expect(src, contains('source: effective'));
    });

    test('canonical 프롬프트의 "글자를 고치지 않는다" 계약은 그대로다', () {
      expect(src, contains('THIS PASS DOES NOT TRANSCRIBE OR EDIT SPEECH.'));
      expect(src, contains('Never return a text field.'));
      expect(src, contains('do not finish fragments, fix names or words'));
    });

    test('교정 모델은 구조 판정 모델과 다른 상수다', () {
      expect(kDuoOriginCorrectorModel, 'gpt-6-luna');
      expect(kDuoOriginCorrectorModel, isNot(kDuoCanonicalModel));
      expect(kDuoOriginCorrectorModel, isNot(kHistoryRepairModel));
      expect(src, contains('String correctorModel = kDuoOriginCorrectorModel'));
    });

    test('교정 실패가 canonical을 무너뜨리지 않는다', () {
      final correct = src.indexOf('await correctDuoOriginTexts(');
      final guard = src.indexOf('DuoOriginCorrectionResult.none()', correct);
      final reconcile = src.indexOf('await reconcileDuoConversation(', correct);
      expect(guard, greaterThan(correct));
      expect(guard, lessThan(reconcile));
    });

    test('개인 방에는 고친 줄에만 자취를 남긴다', () {
      expect(src, contains('if (corrected) kOriginCorrectionModelField'));
      expect(src, contains('if (corrected) kOriginCorrectionStageField'));
      expect(src, contains('final bool corrected = turn.wasCorrected;'));
    });

    test('소리가 있는 줄과 없는 줄을 갈라 적는다', () {
      final stage = src.indexOf('final String stage =');
      expect(stage, greaterThanOrEqualTo(0));
      final body = src.substring(stage, stage + 200);
      expect(body, contains('hasPcmById'));
      expect(body, contains('kOriginCorrectionVerifiable'));
      expect(body, contains('kOriginCorrectionUnverified'));
    });

    test('교정 전 글자는 이미 있으면 덮지 않는다', () {
      expect(src, contains('existingRaw.isNotEmpty ? existingRaw : currentText'));
      expect(
        src,
        contains(
            'if (headRaw.isNotEmpty && headRaw != turn.text)\n            kOriginalRawField: headRaw'),
      );
    });

    test('어느 모델이 고쳤는지는 그 판을 만든 쪽이 적는다', () {
      expect(src, contains("'corrector_model': correctorModel"));
      expect(src, contains("(data['corrector_model'] ?? kDuoOriginCorrectorModel)"));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('단계 이름', () {
    test('두 값은 서로 다르고, 뜻이 글자에 그대로 있다', () {
      expect(kOriginCorrectionVerifiable, 'context_verified_candidate');
      expect(kOriginCorrectionUnverified, 'context_unverified');
      expect(kOriginCorrectionModelField, 'origin_correction_model');
      expect(kOriginCorrectionStageField, 'origin_correction_stage');
    });
  });
}
