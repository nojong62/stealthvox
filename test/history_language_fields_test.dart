// 🏷️ [LANG-FIELDS] 유저가 고르는 언어는 **둘뿐이다.**
//
//   ChatLang  = 로비 "Origin (Chat Lang)"  = FFAppState().nativeLang
//   LearnLang = 로비 "Target (Learn Lang)" = FFAppState().targetLang
//
// History 문서의 `native_lang` / `target_lang` / `source_lang`은 유저 설정
// 이름이 아니라 **내부 저장 필드**다. 세 번째 언어 개념이 아니다.
//
//   native_lang  ← ChatLang
//   source_lang  ← ChatLang (줄 단위. 듀오는 말한 사람마다 다르다)
//   target_lang  ← LearnLang
//
// 여기서 지키는 것 셋:
//   ① 방 문서를 만드는 **모든** 경로가 두 필드를 짝으로 적는다
//      (예전에 한쪽 경로만 빠뜨린 적이 있다)
//   ② 두 필드가 서로 뒤바뀌지 않는다
//   ③ 언어 **감지값**이 이 필드에 직접 들어가지 않는다
//      — 기준은 유저가 확정한 ChatLang이다
//      (`origin_language_recheck_test.dart` 참고)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 히스토리 방 문서를 만들거나 고치는 **모든** 자리.
const List<String> _writers = <String>[
  'lib/custom_code/widgets/routine_mode_circle_talk.dart',
  'lib/custom_code/widgets/routine_mode_scenario_talk.dart',
  'lib/custom_code/widgets/routine_mode_duo.dart',
  'lib/custom_code/widgets/lobby_master.dart',
  'lib/custom_code/widgets/intro_master.dart',
  'lib/custom_code/services/duo_guest_handoff.dart',
];

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// `'<field>': <여기>` 의 오른쪽 값들.
List<String> _values(String src, String field) => RegExp(
      "'" + field + r"':\s*([^\n]*)",
    ).allMatches(src).map((m) => m.group(1)!.trim()).toList();

void main() {
  // ==========================================================================
  group('① 두 필드는 언제나 짝이다', () {
    for (final String path in _writers) {
      test('${path.split('/').last}: native_lang을 적으면 target_lang도 적는다', () {
        final String src = _read(path);
        final int natives = _values(src, 'native_lang').length;
        final int targets = _values(src, 'target_lang').length;
        expect(natives, targets,
            reason: '$path 에서 두 필드 수가 다르다 — 한쪽만 저장하는 경로가 있다');
      });
    }

    test('방 문서를 만드는 자리를 하나도 빠뜨리지 않았다', () {
      // 새 생성 경로가 생기면 이 목록에 넣어야 위 검사가 그 파일도 본다.
      final List<String> found = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String src = entity.readAsStringSync();
        if (src.contains("'native_lang':")) {
          found.add(entity.path.replaceAll(r'\', '/'));
        }
      }
      expect(found.toSet(), _writers.toSet(),
          reason: 'native_lang을 적는 파일이 늘거나 줄었다 — 목록을 맞출 것');
    });
  });

  // ==========================================================================
  group('② 두 필드가 뒤바뀌지 않는다', () {
    for (final String path in _writers) {
      final String src = _read(path);

      test('${path.split('/').last}: native_lang에는 ChatLang만 들어간다', () {
        for (final String v in _values(src, 'native_lang')) {
          expect(v.toLowerCase(), contains('native'),
              reason: 'native_lang에 ChatLang이 아닌 값이 들어간다: $v');
          expect(v.toLowerCase(), isNot(contains('targetlang')),
              reason: 'ChatLang 자리에 LearnLang이 들어갔다: $v');
        }
      });

      test('${path.split('/').last}: target_lang에는 LearnLang만 들어간다', () {
        for (final String v in _values(src, 'target_lang')) {
          expect(v.toLowerCase(), contains('target'),
              reason: 'target_lang에 LearnLang이 아닌 값이 들어간다: $v');
          expect(v.toLowerCase(), isNot(contains('nativelang')),
              reason: 'LearnLang 자리에 ChatLang이 들어갔다: $v');
        }
      });
    }
  });

  // ==========================================================================
  group('③ 감지값은 저장 필드에 닿지 않는다', () {
    for (final String path in _writers) {
      final String src = _read(path);

      test('${path.split('/').last}: 언어 필드에 감지값이 없다', () {
        for (final String field in <String>[
          'native_lang',
          'target_lang',
          'source_lang'
        ]) {
          for (final String v in _values(src, field)) {
            for (final String leak in <String>['detected', '_detected']) {
              expect(v, isNot(contains(leak)),
                  reason: '$field 에 감지값이 들어간다: $v');
            }
          }
        }
      });
    }
  });

  // ==========================================================================
  group('세 모드의 LearnLang 보정이 같다', () {
    // 예전에는 시나리오톡만 로비값을 날것으로 읽어, 빈 값이 그대로
    // `target_lang`에 저장될 수 있었다. 그 필드가 비면 히스토리가 동일 언어
    // 판정을 못 하고 글자 비교로 떨어진다.
    const String fallback =
        "FFAppState().targetLang.isNotEmpty ? FFAppState().targetLang : 'English'";

    test('서클톡 _targetLangName', () {
      expect(_read('lib/custom_code/widgets/routine_mode_circle_talk.dart'),
          contains(fallback));
    });

    test('시나리오톡 _targetLangName', () {
      expect(_read('lib/custom_code/widgets/routine_mode_scenario_talk.dart'),
          contains(fallback));
    });

    test('만능통역 _myTarget', () {
      expect(_read('lib/custom_code/widgets/routine_mode_duo.dart'),
          contains(fallback));
    });
  });
}
