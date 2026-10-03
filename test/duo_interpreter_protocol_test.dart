import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_interpreter_protocol.dart';

String _region(String source, String start, String end) {
  final from = source.indexOf(start);
  final to = source.indexOf(end, from + start.length);
  expect(from, greaterThanOrEqualTo(0), reason: 'missing start: $start');
  expect(to, greaterThan(from), reason: 'missing end: $end');
  return source.substring(from, to);
}

void main() {
  group('Duo Interpreter room protocol decision', () {
    test('both callable-capable peers can select callable_pc_v2 later', () {
      expect(
        chooseDuoInterpreterProtocol(
          hostCallablePcV2: true,
          partnerCallablePcV2: true,
          rolloutEnabled: true,
        ),
        kDuoInterpreterProtocolCallablePcV2,
      );
    });

    test('production rollout remains forced to legacy WebRTC', () {
      expect(kDuoCallablePcV2RolloutEnabled, isFalse);
      expect(
        chooseDuoInterpreterProtocol(
          hostCallablePcV2: true,
          partnerCallablePcV2: true,
        ),
        kDuoInterpreterProtocolLegacyWebrtcV1,
      );
      expect(
        duoInterpreterCallableCapability(remoteCandidate: 'callable'),
        isFalse,
      );
    });

    for (final pair in <(bool, bool)>[
      (true, false),
      (false, true),
      (false, false),
    ]) {
      test('mixed/legacy capabilities $pair select legacy', () {
        expect(
          chooseDuoInterpreterProtocol(
            hostCallablePcV2: pair.$1,
            partnerCallablePcV2: pair.$2,
            rolloutEnabled: true,
          ),
          kDuoInterpreterProtocolLegacyWebrtcV1,
        );
      });
    }

    test('Remote Config candidate parsing is exact and normalized', () {
      expect(
        duoInterpreterCallableCapability(
          remoteCandidate: ' CALLABLE ',
          rolloutEnabled: true,
        ),
        isTrue,
      );
      for (final value in <String>['webrtc', 'firestore', 'callable2', '']) {
        expect(
          duoInterpreterCallableCapability(
            remoteCandidate: value,
            rolloutEnabled: true,
          ),
          isFalse,
        );
      }
    });

    test('only the two staged room protocols are recognized', () {
      expect(
        isKnownDuoInterpreterProtocol(kDuoInterpreterProtocolLegacyWebrtcV1),
        isTrue,
      );
      expect(
        isKnownDuoInterpreterProtocol(kDuoInterpreterProtocolCallablePcV2),
        isTrue,
      );
      expect(isKnownDuoInterpreterProtocol('callable_audio_v3'), isFalse);
    });
  });

  group('Duo Interpreter lifecycle wiring', () {
    // ⚠️ **줄바꿈을 맞춰 읽는다.** 아래 단언들은 `\n`이 든 여러 줄 문자열을
    //   그대로 찾는데, 이 저장소는 blob이 LF이고 `core.autocrlf` 때문에 작업
    //   트리가 CRLF가 되는 순간이 있다(`git stash`·`checkout` 직후). 그때
    //   이 파일만 정규화를 안 해서 **코드는 멀쩡한데 테스트가 깨졌다**
    //   (2026-09-14, 원인 찾는 데 한참 걸렸다).
    //
    //   다른 소스 기반 테스트들은 이미 같은 방식을 쓴다
    //   (`duo_canonical_test.dart`·`origin_restoration_runner_lifecycle_test.dart`).
    final duo = File('lib/custom_code/widgets/routine_mode_duo.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('host capability is included in the initial room create write', () {
      final create = _region(
        duo,
        "await _duoSessionRef!.set({",
        "      } else {",
      );
      expect(create, contains("'hostUid': user.uid"));
      expect(create, contains('kDuoHostCallablePcV2Field:'));
    });

    test('guest seat claim and capability share one atomic update', () {
      final join = _region(
        duo,
        "await _duoSessionRef!.update({\n        'isPartnerJoined': true,",
        "      });\n      // 호스트 언어는",
      );
      expect(join, contains("'partnerUid': guestUid"));
      expect(join, contains('kDuoPartnerCallablePcV2Field:'));
      expect(
          join,
          isNot(contains("await _duoSessionRef!.update({\n"
              "        kDuoPartnerCallablePcV2Field")));
    });

    test('host alone resolves mode and protocol in one transaction', () {
      final lock = _region(
        duo,
        'Future<DuoLockedCallResolution?> _lockHostCallResolution(',
        '  void _listenForPartnerJoined()',
      );
      expect(lock, contains('runTransaction<DuoLockedCallResolution?>'));
      expect(lock, contains("data['hostUid']?.toString() != _myUid"));
      expect(lock, contains('transaction.update(ref'));
      expect(lock, contains('kDuoResolvedModeField: resolution.mode'));
      expect(lock, contains('update[kDuoInterpreterProtocolField] = protocol'));
    });

    test('new guest waits for the host resolution before transport starts', () {
      final join = _region(
        duo,
        'Future<void> _joinAsGuest(String roomId) async {',
        '  /// 🔵 [INTERP-LIVE]',
      );
      final wait = join.indexOf('await _waitForCallResolution()');
      final messages = join.indexOf('_listenForMessages();');
      final start = join.indexOf("_maybeAutoStartInterpreter('guest_joined')");
      expect(wait, greaterThanOrEqualTo(0));
      expect(messages, greaterThan(wait));
      expect(start, greaterThan(messages));
    });

    test('old host rooms explicitly preserve the legacy compatibility path',
        () {
      expect(duo, contains('!data.containsKey(kDuoHostCallablePcV2Field)'));
      expect(
          duo,
          contains("_adoptOldRoomInterpreterProtocol("
              "'guest_join_old_host')"));
      final compatibility = _region(
        duo,
        'void _adoptOldRoomInterpreterProtocol(',
        '  bool _adoptInterpreterProtocol(',
      );
      expect(
        compatibility,
        contains('_interpTransport = kDuoInterpTransportWebrtc;'),
      );
      expect(compatibility, isNot(contains('_pinInterpTransport(reason)')));
    });

    test('room protocol overrides phone-local transport for new rooms', () {
      final adopt = _region(
        duo,
        'bool _adoptInterpreterProtocol(',
        '  Future<DuoLockedCallResolution?> _waitForCallResolution()',
      );
      expect(adopt, contains('_interpTransport = kDuoInterpTransportWebrtc;'));
      expect(adopt, contains('current != null && current != protocol'));
    });

    test('Direct transport remains independent', () {
      expect(
        duo,
        contains(
            "const String kDuoTransportRemoteConfigKey = 'DuoDirectTransport';"),
      );
      final direct = _region(
        duo,
        'bool get _useWebrtcTransport =>',
        'String get _directSttSource',
      );
      expect(direct, isNot(contains('_interpreterProtocol')));
      expect(direct, isNot(contains('kDuoInterpreterProtocolField')));
    });
  });
}
