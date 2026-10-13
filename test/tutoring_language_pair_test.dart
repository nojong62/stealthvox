// 🎓 [TUTORING] 튜터링은 원문 언어 문제를 배울 언어로 말해 보는 연습이다
//
// 예전에는 이 연습이 **한국어 → 영어로 박혀** 있었다. 프롬프트에 "input
// English sentence", "create ONE new Korean sentence"가 글자 그대로 들어
// 있었고, 전사는 `language: 'en'` 고정, 채점 프롬프트는 "English tutor for a
// Korean learner"였다.
//
// 그래서 일본어를 배우는 사람에게도 한국어 문장을 주고 영어로 답하라고 했다.
// 방 문서에 `native_lang`/`target_lang`이 이미 있는데 아무도 안 읽었다.
//
// 짝은 이렇게만 성립한다.
//   문제 문장   = 원문 언어 (native_lang)  ← 이 사람이 편한 말
//   말하는 답   = 배울 언어 (target_lang)
//   피드백      = 원문 언어              ← 못 알아들으면 교정이 아니다
//   전사 언어   = 배울 언어              ← 말하는 것이 그 언어니까

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _hist = 'lib/custom_code/widgets/chat_history_master.dart';
const String _keep = 'lib/custom_code/widgets/chat_history_list_master.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 자리: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 자리: $end');
  return src.substring(a, b);
}

void main() {
  final String hist = _read(_hist);

  /// 문제를 만드는 곳.
  final String gen = _region(hist, 'Future<void> _generateAppText(',
      '// 📦 [Box 18-B: 실전 튜터링 - 녹음 시작]');

  /// 전사하고 채점하는 곳.
  final String judge = _region(hist, 'Future<void> _stopAppRecordAndProcess(',
      'Step 3: TTS 생성');

  // ── ① 언어를 방 문서에서 읽는다 ────────────────────────────────
  group('① 언어는 방 문서에서 온다', () {
    test('원문 언어 이름을 주는 자리가 있다', () {
      expect(hist, contains('String _sessionNativeLangName()'));
      expect(_flat(hist),
          contains("final name = (_sessionNativeLang ?? '').trim();"));
    });

    test('문제 만들기가 두 언어를 다 집어 온다', () {
      expect(gen, contains('final String promptLang = _sessionNativeLangName();'));
      expect(gen, contains('final String targetLang = _sessionTargetLangName();'));
    });

    test('채점도 두 언어를 다 집어 온다', () {
      expect(judge, contains('final String promptLang = _sessionNativeLangName();'));
      expect(judge, contains('final String targetLang = _sessionTargetLangName();'));
    });
  });

  // ── ② 하드코딩이 없다 ──────────────────────────────────────────
  group('② 한국어→영어가 박혀 있지 않다', () {
    test('문제 만들기 프롬프트에 언어 이름이 박혀 있지 않다', () {
      for (final String frozen in <String>[
        'input English sentence',
        'NEW Korean sentence',
        'natural English answer',
        'recently used Korean sentences',
        '새 한국어 문장',
        '영어 정답',
      ]) {
        expect(gen, isNot(contains(frozen)), reason: frozen);
      }
    });

    test('채점 프롬프트에 언어 이름이 박혀 있지 않다', () {
      for (final String frozen in <String>[
        'English tutor for a Korean learner',
        '[KOREAN_PROMPT]',
        '[EXAMPLE_EN]',
        'corrected_en"',
        'spoken-English naturalness',
      ]) {
        expect(judge, isNot(contains(frozen)), reason: frozen);
      }
    });

    test('전사 언어가 en 고정이 아니다', () {
      expect(judge, contains("request.fields['language'] = "
          'deepgramLanguageCode(targetLang);'));
      expect(judge, isNot(contains("request.fields['language'] = 'en'")));
    });
  });

  // ── ③ 짝이 맞는가 ──────────────────────────────────────────────
  group('③ 문제는 원문 언어, 답은 배울 언어', () {
    test('문제는 원문 언어로, 답은 배울 언어로 만들게 시킨다', () {
      final String flat = _flat(gen);
      expect(flat, contains(r'NEW $promptLang sentence'));
      // 다트 문자열이 여러 줄로 이어 붙어 있어 조각으로 본다.
      expect(flat, contains(r'natural $targetLang'));
      expect(flat, contains(r'answer for that new $promptLang sentence'));
      expect(flat, contains(r'input $targetLang sentence'));
    });

    test('채점은 배울 언어 선생이고 학습자는 원문 언어 사용자다', () {
      expect(judge,
          contains(r'strict but fair $targetLang tutor for a $promptLang-speaking learner'));
    });

    test('피드백은 원문 언어로 쓰게 한다 — 못 알아들으면 교정이 아니다', () {
      expect(judge, contains(r'praise line written in $promptLang'));
      expect(judge, contains(r'constructive feedback written in $promptLang'));
      expect(judge, contains(r'Write the notes in $promptLang'));
    });

    test('화면 문구도 배울 언어를 따라간다', () {
      expect(
          _flat(hist),
          contains("_surfaceCopy['speakSentenceIn'].replaceAll('{language}', "
              'koreanLanguageDisplayName(_sessionTargetLangName())),'));
    });
  });

  // ── ④ 이름이 거짓말하지 않는다 ─────────────────────────────────
  group('④ 이름과 키', () {
    test('영어·한국어를 못 박던 이름이 사라졌다', () {
      expect(hist, isNot(contains('_appAnswerEn')));
      expect(hist, isNot(contains('_appRecentKoSentences')));
      expect(hist, contains('_appAnswerTarget'));
      expect(hist, contains('_appRecentPromptSentences'));
    });

    test('JSON 키가 언어 중립이다', () {
      expect(_flat(gen), contains(r'{"prompt": "new $promptLang sentence"'));
      expect(judge,
          contains('{"corrected": "...", "reason": "...", "usage_tip": "..."}'));
    });

    test('옛 키로 온 응답도 읽는다 — 캐시가 섞여 와도 빈 화면이 되지 않는다', () {
      expect(_flat(gen), contains("jsonResult['prompt'] ?? jsonResult['ko']"));
      expect(_flat(gen), contains("jsonResult['answer'] ?? jsonResult['en']"));
      expect(_flat(judge), contains("jr['corrected'] ?? jr['corrected_en']"));
      expect(_flat(judge), contains("jr['reason'] ?? jr['reason_ko']"));
      expect(_flat(judge), contains("jr['usage_tip'] ?? jr['usage_tip_ko']"));
    });
  });

  // ── ⑤ Keepers 튜터링 ───────────────────────────────────────────
  //
  // 빌드 184(2026-10-01)부터 언어 짝을 묻지 않는다. 저장 당시 언어가 키퍼
  // 문서에 있고, 없으면 출처 히스토리 방에서, 그것도 없으면 로비에서 읽는다.
  group('⑤ Keepers — 저장 당시 언어 짝을 쓴다', () {
    final String keep = _read(_keep);
    final String kgen = _region(keep, 'Future<void> _generateKeeperAppText(',
        'Future<void> _playKeeperCorrectedAudio');
    final String kjudge =
        _region(keep, 'Future<void> _correctKeeperAnswer(', 'STEP 4');
    final String langs = _region(keep,
        'Future<List<String>> _keeperTutoringLanguages(',
        'Future<void> _showKeeperTutoringPopup(');

    test('키퍼 문서의 언어가 먼저다', () {
      expect(_flat(langs),
          contains("String native = (keeperData['native_lang'] ?? '').toString().trim();"));
      expect(_flat(langs),
          contains("String target = (keeperData['target_lang'] ?? '').toString().trim();"));
    });

    test('구버전 키퍼는 출처 방에서 복원한다', () {
      expect(langs, contains("keeperData['source_room_id']"));
      expect(_flat(langs), contains("(sourceData['native_lang'] ?? '')"));
      expect(_flat(langs), contains("(sourceData['target_lang'] ?? '')"));
    });

    test('마지막 기본값은 로비 설정이다', () {
      expect(langs, contains('FFAppState().chatLang'));
      expect(langs, contains('FFAppState().targetLang'));
    });

    test('복원한 언어는 키퍼에 채워 둔다 — 실패해도 연습은 돈다', () {
      expect(_flat(langs),
          contains("collection('keepers').doc(keeperId).update({"));
      expect(langs, contains('lang_backfill_failed'));
    });

    test('시트를 열 때 짝을 정하고 바로 문제를 만든다', () {
      final String open =
          _region(keep, 'Future<void> _showKeeperTutoringPopup(', 'showModalBottomSheet');
      expect(open, contains('await _keeperTutoringLanguages(keeperId, keeperData);'));
      expect(open, contains('_keeperTutoringNative = languages[0];'));
      expect(open, contains('_keeperTutoringTarget = languages[1];'));
      expect(open, contains('_generateKeeperAppText(baseText);'));
    });

    test('Keepers 프롬프트도 언어 짝을 따라간다', () {
      expect(kgen, contains('final String promptLang = _keeperTutoringNative;'));
      expect(kgen, contains('final String targetLang = _keeperTutoringTarget;'));
      expect(kjudge, contains('final String promptLang = _keeperTutoringNative;'));
      for (final String frozen in <String>[
        'input English sentence',
        'NEW Korean sentence',
        'English tutor for a Korean learner',
        '[KOREAN_PROMPT]',
      ]) {
        expect(kgen + kjudge, isNot(contains(frozen)), reason: frozen);
      }
    });

    test('Keepers 전사도 배울 언어로 한다', () {
      expect(_flat(keep),
          contains('deepgramLanguageCode(_keeperTutoringTarget)'));
      expect(keep, isNot(contains("request.fields['language'] = 'en'")));
    });

    test('Keepers 쪽 이름도 거짓말하지 않는다', () {
      expect(keep, isNot(contains('_keeperTutoringKo')));
      expect(keep, isNot(contains('_keeperTutoringAnswerEn')));
      expect(keep, isNot(contains('_keeperRecentKoSentences')));
    });
  });

  // ── ⑥ 시트가 제스처 바에 안 걸린다 ───────────────────────
  group('⑥ Keepers 시트 하단 여백', () {
    final String keep = _read(_keep);

    test('키퍼 튜터링 시트가 시스템 영역을 비켜 준다', () {
      final String sheet = _region(keep,
          'Future<void> _showKeeperTutoringPopup(', '.whenComplete(');
      expect(_flat(sheet),
          contains('padding: EdgeInsets.only( bottom: MediaQuery.of(ctx).padding.bottom + 24, )'),
          reason: '맨 아래 단추가 제스처 바에 걸렸다');
    });

    test('히스토리 쪽 시트와 같은 값을 쓴다', () {
      // 같은 기능인데 둘이 다르게 앉으면 다른 화면처럼 보인다.
      expect(_flat(_read(_hist)),
          contains('bottom: MediaQuery.of(ctx).padding.bottom + 24'));
    });
  });
}
