// 📝 [KEEP-ALL] 유저가 한 말은 잃지 않는다 — 지우는 일은 나중에 맥락이 한다
//
// 2026-09-04 실기기(호스트 S25 / 게스트 Fold 5)에서 게스트가 한 말 두 개가
// 호스트 히스토리에 없었다. 게스트 폰에는 남아 있었다. 원인이 둘이었다.
//
// ① 마지막 말이 큐에 있는 채로 방이 닫혔다
//     14:52:22  receive seq=10 len=13     ← 앞 턴 재생 중이라 큐에서 대기
//     14:52:24  channel_state=closed
//     14:52:25  partner_left → _incomingQueue.clear()
//   `SRC-LANG` 줄조차 안 찍혔다 — 꺼내지지도 못하고 지워졌다.
//
// ② 짧은 말은 번역이 비면 턴을 통째로 버렸다
//     14:50:45  receive seq=2 len=5
//     14:50:47  ⚠️ [INTERP-TRANSLATE] failed rawLen=5
//   주석에 "히스토리에도 남기지 않는다"고 적혀 있었다. 소리를 못 내는 것과
//   말이 없었던 것으로 하는 것은 다르다.
//
// ③ 그리고 정돈은 `direct`만 읽었다. 통역 히스토리에는 청소부가 없었다.
// ④ 조각을 만드는 것은 600ms VAD였다. 듀오에는 이어 붙이는 장치가 없다.
//
// 방침: **받는 문턱은 낮추고, 지우는 일은 맥락을 보고 나중에 한다.**

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';
const String _canon = 'lib/custom_code/services/duo_canonical.dart';
const String _stt = 'lib/custom_code/services/openai_streaming_transcribe_session.dart';
const String _cont = 'lib/custom_code/services/late_continuation.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 자리: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 자리: $end');
  return src.substring(a, b);
}

void main() {
  final String duo = _read(_duo);
  final String canon = _read(_canon);
  final String stt = _read(_stt);
  final String cont = _read(_cont);

  // ── ① 퇴장할 때 큐를 버리지 않는다 ──────────────────────────────────
  group('① 큐에 남은 마지막 말을 남긴다', () {
    test('비우기 전에 저장한다', () {
      final String body = _region(
          duo,
          'Future<void> _handleInterpreterPartnerLeft(String reason) async {',
          '_interpTts?.stopAll(reason: reason);');
      expect(body, contains('await _drainQueueToHistory(reason);'));
      expect(body, isNot(contains('_incomingQueue.clear();')),
          reason: '여기서 바로 비우면 큐에 있던 마지막 말이 사라진다');
    });

    test('저장한 뒤에 비운다 — 순서가 뒤집히면 아무 소용이 없다', () {
      final String body = _region(duo,
          'Future<void> _drainQueueToHistory(String reason) async {',
          'Future<void> _saveUntranslatedIncoming(');
      final int copy = body.indexOf('List<Map<String, dynamic>>.from(_incomingQueue)');
      final int clear = body.indexOf('_incomingQueue.clear();\n    _lgDuo');
      expect(copy, greaterThan(-1));
      expect(clear, greaterThan(copy), reason: '먼저 복사하고 나서 비워야 한다');
    });

    test('번역도 재생도 하지 않는다 — 방은 이미 끝났다', () {
      final String body = _region(duo,
          'Future<void> _drainQueueToHistory(String reason) async {',
          'Future<void> _saveUntranslatedIncoming(');
      for (final String forbidden in <String>[
        'translateForSpeech',
        '_speakPartner',
        'TtsAdapter',
      ]) {
        expect(body, isNot(contains(forbidden)),
            reason: '$forbidden — 정리 중에 기다리면 종료가 그만큼 늦어진다');
      }
    });

    test('직접 대화는 이 길로 오지 않는다', () {
      final String body = _region(duo,
          'Future<void> _drainQueueToHistory(String reason) async {',
          'Future<void> _saveUntranslatedIncoming(');
      expect(body, contains('if (_isDirectMode || _incomingQueue.isEmpty) {'));
    });

    test('무엇을 몇 개 남겼는지 로그에 남는다', () {
      expect(duo, contains("'queue_to_history reason="));
      expect(duo, contains("left=\${left.length}"));
    });
  });

  // ── ② 번역이 실패해도 글자는 남긴다 ────────────────────────────────
  group('② 옮기지 못해도 말이 없었던 것으로 하지 않는다', () {
    test('실패 자리에서 저장한다', () {
      final String body = _region(duo,
          'if (translated == null || translated.trim().isEmpty) {',
          'spoken = translated.trim();');
      expect(body,
          contains("await _saveUntranslatedIncoming(data, raw, srcLang, 'translate_failed');"));
    });

    test('저장이 return보다 먼저다', () {
      final String body = _region(duo,
          'if (translated == null || translated.trim().isEmpty) {',
          'spoken = translated.trim();');
      final int save = body.indexOf('_saveUntranslatedIncoming');
      final int ret = body.indexOf('return;');
      expect(save, greaterThan(-1));
      expect(save, lessThan(ret));
    });

    test('재생은 여전히 안 한다 — 틀린 목소리로 읽는 문제는 그대로 막는다', () {
      expect(duo, contains('**원문을 그대로 재생하지 않는다.**'));
      final String body = _region(duo,
          'if (translated == null || translated.trim().isEmpty) {',
          'spoken = translated.trim();');
      expect(body, contains('_setInterpPartnerPhase(InterpPartnerPhase.idle);'));
      expect(body, isNot(contains('_speakPartner')));
    });

    test('옛 주석("히스토리에도 남기지 않는다")이 사라졌다', () {
      expect(duo, isNot(contains('히스토리에도 남기지\n      //   않는다')));
      expect(duo, contains('재생은 접고 글자만 남긴다'));
    });
  });

  group('② 상대 언어를 그대로, 그 언어라고 적어서 남긴다', () {
    String saver() => _region(duo,
        'Future<void> _saveUntranslatedIncoming(',
        '/// 📢 상대가 "이 문장을 소리 낸다"고 알려 왔다.');

    test('원문 자리에 상대 언어를 넣는다', () {
      expect(saver(), contains("      '',\n      raw.trim(),\n      'SYSTEM',"));
    });

    test('무슨 언어인지 같이 적는다', () {
      // 이걸 빼면 공부방이 내 대화 언어로 착각해 배울글을 잘못 짓는다.
      expect(saver(), contains('sourceLang: srcLang,'));
    });

    test('배울글 자리는 비우고 공부방에 넘긴다', () {
      expect(saver(), contains('deferTarget: true,'));
    });

    test('말한 순서와 사람을 잃지 않는다', () {
      for (final String field in <String>[
        'seq:',
        'spokenAt:',
        'speakerUid:',
        'speakerRole:',
      ]) {
        expect(saver(), contains(field), reason: '$field 가 빠졌다');
      }
    });

    test('통역 기록으로 남는다', () {
      expect(saver(), contains('mode: kDuoModeInterpreter,'));
    });

    test('왜 남겼는지 로그에 남는다', () {
      expect(saver(), contains('saved_untranslated why='));
    });
  });

  // ── ③ 정돈이 통역도 읽는다 ─────────────────────────────────────────
  group('③ 정돈이 통역 히스토리도 읽는다', () {
    test('두 모드를 다 읽는다', () {
      expect(canon,
          contains("if (mode != 'direct' && mode != 'interpreter') continue;"));
    });

    test("'direct'만 읽던 줄이 사라졌다", () {
      expect(canon,
          isNot(contains("if ((data['duoMode'] ?? '').toString() != 'direct') continue;")));
    });

    test('왜 넓혔는지 적어 뒀다', () {
      expect(canon, contains('통역이야말로 정돈이 필요한 쪽이다'));
    });

    test('정돈 규칙 자체는 안 건드렸다', () {
      // 읽는 범위만 넓혔다. 무엇을 지울지 정하는 프롬프트는 그대로다.
      expect(canon, contains('READ THE WHOLE CALL BEFORE YOU DECIDE ANYTHING'));
      expect(canon, contains("case 'artifact':"));
    });
  });

  // ── ④ 조각내지 않는다 ──────────────────────────────────────────────
  group('④ 한 문장을 조각내지 않는다', () {
    test('듀오는 1500ms를 쓴다', () {
      expect(duo, contains('const int kDuoVadSilenceDurationMs = 1500;'));
    });

    test('듀오의 두 경로가 같은 종료 기준을 쓴다', () {
      // 침묵을 재는 주체가 OpenAI Server VAD에서 Deepgram으로 옮겼다.
      // 값은 같은 뜻으로 이어진다 — 한 문장 안의 600~1100ms 쉼에서 끊기지
      // 않게 하는 것이 목적이다.
      final endpoint =
          _read('lib/custom_code/services/duo_deepgram_endpoint.dart');
      expect(endpoint, contains('const int kDuoUtteranceEndMs = 1500;'));
      expect(endpoint,
          contains(r"'&utterance_end_ms=$kDuoUtteranceEndMs'"));
      // 직접 대화와 통역이 같은 파이프라인을 쓰므로 값도 하나다.
      expect(
          RegExp(r'DuoSttPipeline\(').allMatches(duo).length,
          2,
          reason: '직접 대화와 통역 둘 다 같은 사람의 같은 말버릇을 듣는다');
    });

    test('서클톡·시나리오톡의 기본값은 600 그대로다', () {
      expect(stt, contains('const int kStreamingSttVadSilenceDurationMs = 600;'));
    });

    test('그 두 모드는 값을 덮지 않는다', () {
      for (final String path in <String>[
        'lib/custom_code/widgets/routine_mode_circle_talk.dart',
        'lib/custom_code/widgets/routine_mode_scenario_talk.dart',
      ]) {
        expect(_read(path), isNot(contains('vadSilenceDurationMs:')),
            reason: '$path — 그쪽은 이어 붙이는 장치가 이미 있다');
      }
    });

    test('그 장치가 실제로 그 두 모드에만 있다', () {
      expect(cont, contains('const int kFreeTalkContinuationWindowMs = 1200;'));
      // 주석으로 언급은 한다(왜 1500인지 설명이 거기 있다). **import**가
      // 없다는 것이 요점이다 — 장치를 안 쓴다.
      expect(duo, isNot(contains("import '/custom_code/services/late_continuation.dart'")),
          reason: '듀오에 그 장치가 없다는 것이 1500을 쓰는 이유다');
    });

    test('실측 근거를 값 옆에 적어 뒀다', () {
      // 다음 사람이 "느리다"며 600으로 되돌리는 것을 막는다.
      expect(duo, contains('1164'));
      expect(duo, contains('4957'));
      expect(duo, contains('1.2초와 5초 사이가 비어 있다'));
    });
  });

  // ── 건드리지 않은 것 ───────────────────────────────────────────────
  group('받는 문턱과 방어선은 그대로다', () {
    test('세기 문턱은 −42.0 그대로다', () {
      final String gate =
          _read('lib/custom_code/services/duo_transcript_gate.dart');
      expect(gate, contains('kDuoMinUtteranceRmsDbfs = -42.0'));
    });

    test('상대 폰 소리 필터는 살아 있다', () {
      expect(duo, contains('_looksLikePartnerEcho(t)'));
      expect(
          RegExp(r'_announceSpokenToPartner\(spoken\);').allMatches(duo).length,
          2);
    });

    test('VAD 문턱과 앞소리는 안 건드렸다', () {
      expect(stt, contains('vadThreshold'));
      expect(stt, contains('kStreamingSttVadPrefixPaddingMs = 300'));
    });
  });
}
