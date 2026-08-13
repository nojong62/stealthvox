// Google 인증에서 **UID 보존**을 지키는 두 가드의 규칙을 고정한다.
//
// 이 기능의 목적은 "기존 회원의 Firebase UID를 살린다" 하나뿐이다. 연결 결과가
// 다른 UID로 돌아오거나 google.com이 안 붙었는데 그대로 진행하면, 사용자
// 데이터를 엉뚱한 계정에 쓰게 된다. 그래서 두 가드는 통과 대신 **예외**로
// 흐름을 끊는다 — 여기서는 그 "끊김"이 실제로 일어나는지를 본다.

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/auth/google_credential.dart';

void main() {
  group('assertSameUid — 연결 전후 UID 동일성', () {
    test('같은 uid면 통과한다', () {
      expect(
        () => GoogleLinkGuards.assertSameUid('uid-1', 'uid-1', stage: 'link'),
        returnsNormally,
      );
    });

    test('uid가 바뀌면 던진다 — 데이터를 쓰기 전에 멈춰야 한다', () {
      expect(
        () => GoogleLinkGuards.assertSameUid('uid-1', 'uid-2', stage: 'link'),
        throwsA(isA<StateError>()),
      );
    });

    test('uid가 null이면 던진다', () {
      expect(
        () => GoogleLinkGuards.assertSameUid('uid-1', null, stage: 'link'),
        throwsA(isA<StateError>()),
      );
    });

    test('uid가 빈 문자열이면 던진다', () {
      expect(
        () => GoogleLinkGuards.assertSameUid('uid-1', '', stage: 'link'),
        throwsA(isA<StateError>()),
      );
    });

    test('예외 메시지에 단계가 남아 실패 지점을 알 수 있다', () {
      expect(
        () => GoogleLinkGuards.assertSameUid('a', 'b', stage: 'legacy_migration'),
        throwsA(predicate(
            (e) => e is StateError && e.message.contains('legacy_migration'))),
      );
    });
  });

  group('assertGoogleLinked — google.com 실제 연결 확인', () {
    test('google.com이 있으면 통과한다', () {
      expect(
        () => GoogleLinkGuards.assertGoogleLinked(['google.com'], stage: 'link'),
        returnsNormally,
      );
    });

    test('다른 provider와 섞여 있어도 google.com만 있으면 통과한다', () {
      expect(
        () => GoogleLinkGuards.assertGoogleLinked(
            ['password', 'google.com'],
            stage: 'link'),
        returnsNormally,
      );
    });

    test('provider 목록이 비면 던진다 — 커스텀 토큰 계정의 상태다', () {
      expect(
        () => GoogleLinkGuards.assertGoogleLinked(<String>[], stage: 'link'),
        throwsA(isA<StateError>()),
      );
    });

    test('null이면 던진다', () {
      expect(
        () => GoogleLinkGuards.assertGoogleLinked(null, stage: 'link'),
        throwsA(isA<StateError>()),
      );
    });

    test('다른 provider만 있으면 던진다 — 자동 병합을 통과로 오인하지 않는다', () {
      expect(
        () => GoogleLinkGuards.assertGoogleLinked(['password'], stage: 'sign_in'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
