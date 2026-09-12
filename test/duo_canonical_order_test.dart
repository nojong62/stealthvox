// DUO-CANON은 단어를 고치는 층이 아니라 두 폰 기록의 구조만 맞추는 층이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';

String _source() => File('lib/custom_code/services/duo_canonical.dart')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

void main() {
  final canonical = _source();

  group('구조 정돈만 허용한다', () {
    test('명백한 질문·답변 시계 오류만 순서를 바꾼다', () {
      expect(canonical, contains('question/answer context'));
      expect(canonical, contains('When uncertain, preserve the supplied order.'));
      expect(
        canonical,
        isNot(contains(
            'turns.sort((a, b) => (a.spokenAtMs ?? 0).compareTo(b.spokenAtMs ?? 0));')),
      );
    });

    test('echo와 duplicate만 숨길 수 있다', () {
      expect(canonical, contains('Allowed states are included, echo, and duplicate.'));
      expect(kStudyStateHiddenEcho, 'hidden_echo');
      expect(kStudyStateHiddenDuplicate, 'hidden_duplicate');
      expect(canonical, isNot(contains('Allowed states are included, echo, duplicate, and artifact')));
    });

    test('어색한 문장은 artifact로 지우지 않는다', () {
      expect(canonical, contains('Odd wording is never an artifact.'));
      expect(canonical, contains('Keep every other line included.'));
    });

    test('모델이 빠뜨린 줄은 원문 그대로 되살린다', () {
      expect(canonical, contains('[FAIL-OPEN]'));
      expect(canonical, contains('restored_missing='));
    });
  });

  group('원문과 최종 Target 경계', () {
    test('canonical 모델 응답의 role과 text를 신뢰하지 않는다', () {
      expect(canonical, contains('Do not include role or text.'));
      expect(canonical, contains('role: original.role'));
      expect(canonical, contains('text: original.text'));
    });

    test('Replay를 부르지 않는다', () {
      for (final gone in <String>['buildDuoReplay', 'replay/current', 'DuoReplayScript']) {
        expect(canonical, isNot(contains(gone)));
      }
    });

    test('레거시 적용 코드도 삭제하지 않는다', () {
      expect(canonical, contains('applyDuoCanonicalToHistory'));
      expect(canonical, isNot(contains('batch.delete')));
      expect(canonical, contains('kOriginalRawField'));
    });
  });
}