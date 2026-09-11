// 📝 [HISTORY] 수정 전 히스토리는 **내가 들은 대화 언어만** 보여준다
//
// 2026-09-11 실기기(호스트 S25 / 게스트). 게스트 폰 히스토리 한 줄에 원문과
// 번역이 나란히 떴다. 어느 쪽이 내가 들은 말인지 읽는 사람이 못 가린다.
//
//   10:34:47  [INTERP-DATA] send ok=true lang=English len=46   ← 호스트가 영어로 말함
//   게스트(native=Korean / target=English)가 이 줄을 받으면
//   `rawIsMyTargetLang`이 참이 되어 raw(English)가 `translated_text`로,
//   spoken(Korean)이 `original_text`로 동시에 저장됐다. 둘 다 그려진다.
//
// 방침: **본문은 내가 들은 말 하나뿐.** 배울글 자리는 복원·수정이 끝난 뒤에
//   채운다. 다만 원문을 버리지는 않는다 — `partner_origin_text`에 남기고
//   화면만 가린다. 표시 문제를 데이터를 지워서 푸는 길(6b30e66b)로 돌아가지
//   않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _duo = 'lib/custom_code/widgets/routine_mode_duo.dart';
const String _histList = 'lib/custom_code/widgets/chat_history_list_master.dart';
const String _hist = 'lib/custom_code/widgets/chat_history_master.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _region(String src, String start, String end) {
  final int a = src.indexOf(start);
  if (a < 0) throw StateError('없는 자리: $start');
  final int b = src.indexOf(end, a + 1);
  if (b < a) throw StateError('없는 자리: $end');
  return src.substring(a, b);
}

/// 통역에서 상대 발화를 저장하는 호출 전부를 긁어온다.
List<String> _interpSaveCalls(String duo) {
  final List<String> out = <String>[];
  int from = 0;
  while (true) {
    final int a = duo.indexOf('_saveHistoryMessage(', from);
    if (a < 0) break;
    final int b = duo.indexOf(');', a);
    final String call = duo.substring(a, b + 2);
    from = b + 2;
    if (call.contains('mode: kDuoModeInterpreter')) out.add(call);
  }
  return out;
}

/// 이번 수정의 대상 — **번역이 성공한 상대 발화** 두 갈래.
/// 스트리밍과 블로킹이 같은 모양이어야 한다.
List<String> _partnerTurnCalls(String duo) => _interpSaveCalls(duo)
    .where((String c) => c.contains("'SYSTEM'") && c.contains('spoken,'))
    .toList();

/// 내가 한 말을 저장하는 갈래 — 원래부터 `spoken` 하나만 넣었다.
List<String> _myTurnCalls(String duo) => _interpSaveCalls(duo)
    .where((String c) => !c.contains("'SYSTEM'"))
    .toList();

void main() {
  final String duo = _read(_duo);
  final String histList = _read(_histList);
  final String hist = _read(_hist);

  // ── ① 두 갈래가 모두 고쳐졌는가 ────────────────────────────────────
  group('① 스트리밍·블로킹 두 갈래', () {
    test('번역된 상대 발화 갈래는 둘이다 — 스트리밍과 블로킹', () {
      expect(_partnerTurnCalls(duo).length, 2,
          reason: '갈래가 늘었으면 이 시험도 같이 늘려야 한다');
    });

    test('둘 다 배울글 자리를 비우고 미룬다', () {
      for (final String call in _partnerTurnCalls(duo)) {
        expect(call, contains('deferTarget: true'),
            reason: '미루지 않으면 raw가 본문(translated_text)으로 올라간다');
        // 첫 인자(target)가 빈 문자열이어야 한다.
        final String firstArg = call
            .substring(call.indexOf('(') + 1, call.indexOf(','))
            .trim();
        expect(firstArg, "''",
            reason: '배울글은 복원·수정이 끝난 뒤에 채운다. 지금 넣으면 두 줄이 같이 뜬다');
      }
    });

    test('raw를 배울글로 싣던 예외가 사라졌다', () {
      expect(duo, isNot(contains('rawIsMyTargetLang')),
          reason: '이 분기가 원문과 번역을 한 줄에 같이 띄운 원인이었다');
    });
  });

  // ── ② 원문은 버리지 않는다 ─────────────────────────────────────────
  group('② 저장과 표시를 가른다', () {
    test('두 갈래 모두 상대 원문과 그 언어를 함께 넘긴다', () {
      for (final String call in _partnerTurnCalls(duo)) {
        expect(call, contains('partnerOriginText: raw'));
        expect(call, contains('partnerOriginLang: srcLang'));
      }
    });

    test('저장부가 두 칸을 실제로 쓴다', () {
      final String body = _region(
          duo, 'Future<void> _saveHistoryMessage(', 'void _rememberGuestHandoffClaim(');
      expect(body, contains("'partner_origin_text': partnerOriginText.trim()"));
      expect(body, contains("'partner_origin_lang': partnerOriginLang"));
    });

    test('빈 원문은 칸을 만들지 않는다', () {
      final String body = _region(
          duo, 'Future<void> _saveHistoryMessage(', 'void _rememberGuestHandoffClaim(');
      expect(
          body,
          contains(
              'if (partnerOriginText != null && partnerOriginText.trim().isNotEmpty)'));
    });
  });

  // ── ③ 화면은 그 칸을 읽지 않는다 ───────────────────────────────────
  group('③ 표시 계층은 원문 칸을 모른다', () {
    test('히스토리 화면 둘 다 partner_origin_* 을 읽지 않는다', () {
      for (final String src in <String>[hist, histList]) {
        expect(src, isNot(contains('partner_origin_text')),
            reason: '읽는 순간 저장·표시를 가른 의미가 없어진다');
        expect(src, isNot(contains('partner_origin_lang')));
      }
    });

    test('본문은 여전히 original_text / translated_text 두 칸으로 그린다', () {
      expect(hist, contains("data['translated_text']"));
      expect(hist, contains("data['original_text']"));
    });
  });

  // ── ④ 직접 대화는 건드리지 않았다 ──────────────────────────────────
  group('④ Direct 회귀 없음', () {
    test('미루기 기본 규칙이 그대로다', () {
      final String body = _region(
          duo, 'Future<void> _saveHistoryMessage(', 'void _rememberGuestHandoffClaim(');
      expect(body, contains('deferTarget ?? (mode == kDuoModeDirect)'),
          reason: '호출부가 말 안 하면 예전 규칙(직접 대화만 미룸) 그대로여야 한다');
    });

    test('직접 대화 저장 호출은 통역 인자를 쓰지 않는다', () {
      int from = 0;
      int checked = 0;
      while (true) {
        final int a = duo.indexOf('_saveHistoryMessage(', from);
        if (a < 0) break;
        final int b = duo.indexOf(');', a);
        final String call = duo.substring(a, b + 2);
        from = b + 2;
        if (!call.contains('mode: kDuoModeDirect')) continue;
        checked++;
        expect(call, isNot(contains('partnerOriginText')),
            reason: '통역 전용 칸이다');
      }
      expect(checked, greaterThan(0), reason: '직접 대화 저장 호출을 못 찾았다');
    });
  });

  // ── ⑤ 일부러 손대지 않은 갈래 ─────────────────────────
  group('⑤ 손대지 않은 갈래', () {
    test('번역이 실패한 줄은 여전히 원문이 본문이다', () {
      final String body = _region(duo, 'Future<void> _saveUntranslatedIncoming(',
          'void _notePartnerSpoke(');
      expect(body, contains('raw.trim()'),
          reason: '이 줄은 내 대화 언어로 된 버전이 애초에 없다 — '
              '원문까지 감추면 발화가 통째로 사라진다(KEEP-ALL)');
      expect(body, isNot(contains('partnerOriginText')),
          reason: '본문이 이미 원문이다. 또 넣으면 같은 글이 두 칸에 중복된다');
    });

    test('내가 한 말은 원래부터 대화 언어 하나뿐이다', () {
      final List<String> mine = _myTurnCalls(duo);
      expect(mine, isNotEmpty);
      for (final String call in mine) {
        expect(call, isNot(contains('partnerOriginText')),
            reason: '내 발화에는 “상대 원문”이란 것이 없다');
      }
    });
  });
}
