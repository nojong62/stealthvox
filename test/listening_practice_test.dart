// 🎧 [LISTENING PRACTICE] Step 1 ↔ Step 2 전환.
//
// 회귀로 강하게 고정하는 넷:
//   1. Step 1 기존 동작 불변 (프롬프트 블록·한글 가드·저장 키)
//   2. Step 2에서도 STT 언어는 ORIGIN 그대로
//   3. 전환은 상태 하나만 바꾼다 — 문맥·세션·STT·TTS를 건드리지 않는다
//   4. History 줄: HOST는 ORIGIN, Step 2 AI 줄은 source_lang 동봉
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/listening_practice.dart';
import 'package:stealth_vox/custom_code/widgets/first_utterance_context_judge.dart';

String _src(String path) => File(path).readAsStringSync();

const String _circle = 'lib/custom_code/widgets/routine_mode_circle_talk.dart';
const String _scenario =
    'lib/custom_code/widgets/routine_mode_scenario_talk.dart';

/// [name]으로 시작하는 메서드의 본문. 다음 최상위 메서드 선언 앞까지.
String _method(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: '$signature 없음');
  final rest = source.substring(start + signature.length);
  final next = RegExp(r'\n  (?:static |Future|Stream|void|String|bool|Widget|int|Map|List|ListeningStep)[^\n]*\(')
      .firstMatch(rest);
  return rest.substring(0, next?.start ?? rest.length);
}

void main() {
  group('정책 문자열', () {
    test('Step 2 출력 정책은 배울 언어로 말하고 유저 언어는 ORIGIN으로 읽는다', () {
      final policy = buildTargetOutputLanguagePolicy(
          nativeLang: 'Korean', targetLang: 'English');
      expect(policy, contains('Natural spoken English only'));
      expect(policy, contains('The user speaks Korean'));
      expect(policy, contains('Never switch back to Korean'));
      expect(policy, isNot(contains('Do NOT use the user\'s target')));
    });

    test('다른 배울 언어에도 같은 모양으로 붙는다', () {
      final policy = buildTargetOutputLanguagePolicy(
          nativeLang: 'Korean', targetLang: 'Japanese');
      expect(policy, contains('Natural spoken Japanese only'));
      expect(policy, contains('Never switch back to Korean'));
    });

    test('청취 연습 규칙은 시험하지 않는다', () {
      final rule = buildListeningPracticePolicy(
          nativeLang: 'Korean', targetLang: 'English');
      expect(rule, contains('LISTENING PRACTICE'));
      expect(rule, contains('shorter, plainer English'));
      expect(rule, contains('Never test, grade, or correct'));
      expect(rule, contains('Never press the same question more than once'));
    });

    test('마지막 규칙은 배울 언어만 쓰라고 못 박고 이전 답변 언어를 무시하게 한다', () {
      final rule = buildTargetLanguageFinalRule(
          nativeLang: 'Korean', targetLang: 'English');
      expect(rule, startsWith('[FINAL RULE'));
      expect(rule, contains('ENTIRE reply in English'));
      expect(rule, contains('Not one Korean word'));
      expect(rule, contains('earlier lines in this conversation may be in Korean'));
    });

    test('Step 1 정책은 이 기능 이전과 같다 — 배울 언어 금지 문구가 그대로다', () {
      final policy = buildNativeOutputLanguagePolicy('Korean');
      expect(policy, contains('Natural spoken Korean only'));
      expect(policy,
          contains("Do NOT use the user's target practice language in this room"));
    });
  });

  group('전환 가능 여부', () {
    test('배울 언어가 대화 언어와 다르면 Step 2를 열어 준다', () {
      expect(
          listeningStep2Available(nativeLang: 'Korean', targetLang: 'English'),
          isTrue);
      expect(
          listeningStep2Available(nativeLang: 'Korean', targetLang: 'Japanese'),
          isTrue);
    });
    test('같으면 잠근다 (대소문자·공백 무시)', () {
      expect(
          listeningStep2Available(nativeLang: 'Korean', targetLang: 'korean '),
          isFalse);
      expect(listeningStep2Available(nativeLang: '', targetLang: 'English'),
          isFalse);
    });
    test('toggled는 두 값 사이를 오간다', () {
      expect(ListeningStep.step1.toggled, ListeningStep.step2);
      expect(ListeningStep.step2.toggled, ListeningStep.step1);
      expect(ListeningStep.step1.value, 1);
      expect(ListeningStep.step2.value, 2);
    });
  });

  group('History 줄 필드', () {
    test('Step 1은 step=1만 남기고 source_lang을 만들지 않는다', () {
      expect(
          listeningStepFields(ListeningStep.step1,
              isAi: true, targetLang: 'English'),
          {'step': 1});
      expect(
          listeningStepFields(ListeningStep.step1,
              isAi: false, targetLang: 'English'),
          {'step': 1});
    });
    test('Step 2 AI 줄만 source_lang=배울 언어. HOST 줄은 ORIGIN이라 없다', () {
      expect(
          listeningStepFields(ListeningStep.step2,
              isAi: true, targetLang: 'English'),
          {'step': 2, 'source_lang': 'English'});
      expect(
          listeningStepFields(ListeningStep.step2,
              isAi: false, targetLang: 'English'),
          {'step': 2});
    });
  });

  group('답변 언어 판정', () {
    test('Step 2에 한국어가 나오면 어긋남', () {
      expect(
          replyMatchesListeningStep('오늘 정말 바빴겠네요.',
              step: ListeningStep.step2,
              nativeLang: 'Korean',
              targetLang: 'English'),
          isFalse);
      expect(
          replyMatchesListeningStep('That sounds exhausting. What kept you busy?',
              step: ListeningStep.step2,
              nativeLang: 'Korean',
              targetLang: 'English'),
          isTrue);
    });
    test('Step 2 일본어 배울 언어', () {
      expect(
          replyMatchesListeningStep('今日は忙しかったんですね。',
              step: ListeningStep.step2,
              nativeLang: 'Korean',
              targetLang: 'Japanese'),
          isTrue);
      expect(
          replyMatchesListeningStep('오늘 바빴겠네요.',
              step: ListeningStep.step2,
              nativeLang: 'Korean',
              targetLang: 'Japanese'),
          isFalse);
    });
    test('Step 1에 영어가 나오면 어긋남 — 라틴 문자끼리는 가리지 않는다', () {
      expect(
          replyMatchesListeningStep('That sounds exhausting.',
              step: ListeningStep.step1,
              nativeLang: 'Korean',
              targetLang: 'English'),
          isFalse);
      expect(
          replyMatchesListeningStep('Ça a l\'air fatigant.',
              step: ListeningStep.step2,
              nativeLang: 'Korean',
              targetLang: 'English'),
          isTrue);
    });
  });

  group('두 대화방 배선 — Step 1 불변', () {
    for (final path in <String>[_circle, _scenario]) {
      final source = _src(path);
      final name = path.contains('circle') ? '서클톡' : '시나리오톡';

      test('$name: 기본값은 Step 1', () {
        expect(source,
            contains('ListeningStep _listeningStep = ListeningStep.step1;'));
      });

      test('$name: Step 1 프롬프트는 예전 정책 그대로 쓴다', () {
        // 출력 정책은 step2일 때만 배울 언어 버전으로 갈린다.
        expect(source,
            contains(': buildNativeOutputLanguagePolicy(_nativeLangName());'));
        expect(source, contains('? buildTargetRegisterPolicy(targetLang)'));
        expect(source, contains('kKoreanPoliteSpeechPolicy'));
        expect(source, contains('final bool step2 = step == ListeningStep.step2;'));
      });

      test('$name: 턴 시작에 Step을 한 번 읽고 그 턴은 끝까지 같은 Step이다', () {
        expect(source, contains('final ListeningStep step = _listeningStep;'));
        expect(source, contains('Instructions(step: step)'));
      });

      test('$name: Step 2는 프롬프트 끝과 유저 말 바로 앞에 언어 규칙을 한 번 더 둔다', () {
        // 프롬프트 끝 — Step 1은 빈 문자열이라 끝이 전과 같다.
        expect(source, contains('final String finalLanguageRule = step2'));
        expect(source, contains("        : '';"));
        expect(source, contains('\$finalLanguageRule\'\'\';'));
        // 유저 메시지 앞 system 한 줄 — Step 2에서만.
        expect(source, contains('trailingSystemNote: step == ListeningStep.step2'));
        expect(source, contains(
            "if (trailingSystemNote != null && trailingSystemNote.trim().isNotEmpty)"));
      });

      test('$name: 전환은 상태 하나만 바꾼다 — 세션·STT·TTS·문맥은 그대로', () {
        final body = _method(source, 'void _setListeningStep(ListeningStep step)');
        expect(body, contains('setState(() => _listeningStep = step);'));
        expect(body, contains('resetBillingIdle();'));
        for (final forbidden in <String>[
          '_startConfiguredListening',
          '_stopEverything',
          'dispose(',
          '.clear()',
          '_recentHistory',
          '_localMessages',
          'stopAll(',
          '_pipelineGeneration++',
          'Deepgram',
          'Transcribe',
        ]) {
          expect(body, isNot(contains(forbidden)),
              reason: '$name 전환 핸들러가 $forbidden 를 건드린다');
        }
      });

      test('$name: STT 언어 결정에 Step이 끼지 않는다', () {
        expect(source,
            contains('String _nativeLangCode() => deepgramLanguageCode(_nativeLangName());'));
        for (final line in source.split('\n')) {
          if (!line.contains('_listeningStep') && !line.contains('step2')) {
            continue;
          }
          for (final stt in <String>[
            'language:',
            'lang:',
            '_sttLangCode',
            '_nativeLangCode',
            'Deepgram',
            'Transcribe',
          ]) {
            expect(line, isNot(contains(stt)),
                reason: '$name: Step이 STT 언어에 닿는다 → $line');
          }
        }
      });

      test('$name: History 줄에 step을 남기고 Step 2 AI 줄만 source_lang을 얹는다', () {
        expect(source,
            contains('...listeningStepFields(step, isAi: false, targetLang: _targetLangName())'));
        expect(source,
            contains('...listeningStepFields(step, isAi: true, targetLang: _targetLangName())'));
        expect(source,
            contains("if (line['source_lang'] != null) 'source_lang': line['source_lang'],"));
        expect(source, contains("if (line['step'] != null) 'step': line['step'],"));
        // HOST 줄의 original_text는 여전히 유저가 실제 말한 문장이다.
        expect(source, contains("'role': 'HOST',\n        'original_text': user"));
      });

      test('$name: 스위치는 배울 언어 == 대화 언어면 잠긴다', () {
        expect(source, contains('enabled: listeningStep2Available('));
        expect(source, contains('onChanged: _setListeningStep,'));
      });
    }

    test('서클톡: 한글 가드는 Step 1에서만 돈다', () {
      final body = _method(_src(_circle), 'Future<void> _speakSystemLine(String text,');
      expect(body, contains('(step ?? _listeningStep) == ListeningStep.step1'));
      expect(body, contains('if (nativeGuard &&'));
      // 가드 본체(한국어 되돌리기)는 그대로 남아 있다 — 지우지 않았다.
      expect(body, contains('FreeTalkBrain.generateCleanOriginal('));
      expect(body, contains("'조금 더 자세히 말씀해 주세요.'"));
    });

    test('서클톡: 정규 턴은 그 턴의 Step으로 말한다', () {
      expect(_src(_circle),
          contains('expectedPipelineGeneration: expectedPipelineGeneration, step: step);'));
    });

    test('시나리오톡: [REPLY]만 Step을 따르고 [CORRECTION]·되묻기는 대화 언어 그대로', () {
      final source = _src(_scenario);
      expect(source, contains('reply to that replacement meaning in \$replyLang>'));
      expect(source,
          contains('replacement meaning as one natural standalone line in \$nativeLang>'));
      expect(source,
          contains('final askBackOutputRule = buildHeardConfirmOutputRule(nativeLang);'));
      expect(source, contains('final String replyLang = step2 ? targetLang : nativeLang;'));
    });

    test('시나리오톡: 정정 경로의 저장 줄에도 Step이 붙는다', () {
      final source = _src(_scenario);
      final idx = source.indexOf('final correctedSystemLine = <String, dynamic>{');
      expect(idx, greaterThan(0));
      expect(source.substring(idx, idx + 400),
          contains('...listeningStepFields(step,\n              isAi: true'));
    });
  });

  group('ListeningStepSwitch', () {
    testWidgets('지금 Step 하나만 보이고, 누르면 다른 Step으로 넘어간다', (tester) async {
      ListeningStep? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListeningStepSwitch(
            step: ListeningStep.step1,
            enabled: true,
            onChanged: (s) => changed = s,
          ),
        ),
      ));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      await tester.tap(find.text('1'));
      expect(changed, ListeningStep.step2);
    });

    testWidgets('잠겨 있으면 눌러도 바뀌지 않는다', (tester) async {
      ListeningStep? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListeningStepSwitch(
            step: ListeningStep.step1,
            enabled: false,
            onChanged: (s) => changed = s,
          ),
        ),
      ));
      await tester.tap(find.text('1'));
      expect(changed, isNull);
    });

    testWidgets('여러 번 왕복해도 값만 오간다', (tester) async {
      var step = ListeningStep.step1;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListeningStepSwitch(
              step: step,
              enabled: true,
              onChanged: (s) => setState(() => step = s),
            ),
          ),
        ),
      ));
      for (final expected in <ListeningStep>[
        ListeningStep.step2,
        ListeningStep.step1,
        ListeningStep.step2,
      ]) {
        // 알약에는 지금 Step만 적혀 있다. 그걸 누르면 반대편으로 간다.
        await tester.tap(find.text(ListeningStepSwitch.labelOf(expected.toggled)));
        await tester.pump();
        expect(step, expected);
        expect(find.text(ListeningStepSwitch.labelOf(expected)), findsOneWidget);
      }
    });
  });
}
