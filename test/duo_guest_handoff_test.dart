import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_guest_handoff.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';

const String kAnonUid = 'anon-abc';
const String kHostUid = 'host-xyz';
const String kRoom = 'room-1';

DuoGuestClaim claim({
  String uid = kAnonUid,
  String role = 'GUEST',
  int? savedAtMs,
}) =>
    DuoGuestClaim(
      roomId: kRoom,
      uid: uid,
      role: role,
      savedAtMs: savedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      nativeLang: 'Korean',
      targetLang: 'English',
    );

DuoCanonicalTurn turn(String role, String text, int ms,
        {String state = kStudyStateIncluded, List<String>? ids}) =>
    DuoCanonicalTurn(
      role: role,
      text: text,
      sourceIds: ids ?? <String>['src-$ms'],
      state: state,
      spokenAtMs: ms,
    );

void main() {
  group('표는 기기에만 남고, 왕복해도 그대로다', () {
    test('직렬화 왕복', () {
      final original = claim();
      final restored = DuoGuestClaim.fromJson(jsonEncode(original.toJson()));
      expect(restored, isNotNull);
      expect(restored!.roomId, kRoom);
      expect(restored.uid, kAnonUid);
      expect(restored.role, 'GUEST');
      expect(restored.nativeLang, 'Korean');
      expect(restored.targetLang, 'English');
    });

    test('깨진 값·빈 값은 표가 아니다', () {
      expect(DuoGuestClaim.fromJson(null), isNull);
      expect(DuoGuestClaim.fromJson(''), isNull);
      expect(DuoGuestClaim.fromJson('{{{'), isNull);
      expect(DuoGuestClaim.fromJson('{"room_id":"","uid":"a","role":"GUEST"}'),
          isNull);
      expect(DuoGuestClaim.fromJson('{"room_id":"r","uid":"","role":"GUEST"}'),
          isNull);
    });

    test('오래된 표는 버린다 — 며칠 뒤 로그인에 옛 통화가 살아나지 않는다', () {
      final now = DateTime(2026, 8, 29, 12);
      expect(
        isDuoGuestClaimFresh(
            claim(
                savedAtMs: now
                    .subtract(const Duration(minutes: 3))
                    .millisecondsSinceEpoch),
            now: now),
        isTrue,
      );
      expect(
        isDuoGuestClaimFresh(
            claim(
                savedAtMs:
                    now.subtract(const Duration(hours: 30)).millisecondsSinceEpoch),
            now: now),
        isFalse,
      );
    });
  });

  group('🔒 참가자 검증 — roomId만으로는 절대 붙지 않는다 (케이스 6)', () {
    test('그 방의 게스트였으면 통과', () {
      expect(
        claimMatchesSession(
          claim: claim(),
          session: <String, dynamic>{
            'hostUid': kHostUid,
            'partnerUid': kAnonUid,
          },
        ),
        isTrue,
      );
    });

    test('그 방의 호스트였어도 통과', () {
      expect(
        claimMatchesSession(
          claim: claim(uid: kHostUid, role: 'HOST'),
          session: <String, dynamic>{
            'hostUid': kHostUid,
            'partnerUid': kAnonUid,
          },
        ),
        isTrue,
      );
    });

    test('다른 계정으로 로그인한 사람의 표는 막힌다', () {
      expect(
        claimMatchesSession(
          claim: claim(uid: 'someone-else'),
          session: <String, dynamic>{
            'hostUid': kHostUid,
            'partnerUid': kAnonUid,
          },
        ),
        isFalse,
      );
    });

    test('세션 문서가 없거나 참가자가 안 적혀 있으면 막힌다', () {
      expect(claimMatchesSession(claim: claim(), session: null), isFalse);
      expect(
        claimMatchesSession(claim: claim(), session: <String, dynamic>{}),
        isFalse,
      );
    });

    test('역할이 어긋난 표는 막힌다 — GUEST 표로 호스트 자리에 붙지 못한다', () {
      expect(
        claimMatchesSession(
          claim: claim(uid: kHostUid, role: 'GUEST'),
          session: <String, dynamic>{
            'hostUid': kHostUid,
            'partnerUid': kAnonUid,
          },
        ),
        isFalse,
      );
    });

    test('HOST 표는 partnerUid와 같아도 통과하지 않는다', () {
      expect(
        claimMatchesSession(
          claim: claim(uid: kAnonUid, role: 'HOST'),
          session: <String, dynamic>{
            'hostUid': kHostUid,
            'partnerUid': kAnonUid,
          },
        ),
        isFalse,
      );
    });

    test('같은 방에 다른 사람이 다시 초대돼 partnerUid가 덮여도 flush_done이 남는다', () {
      expect(
        claimMatchesSession(
          claim: claim(),
          session: <String, dynamic>{
            'hostUid': kHostUid,
            'partnerUid': 'later-guest',
            kDuoFlushDoneField: <String, dynamic>{kAnonUid: 1, kHostUid: 1},
          },
        ),
        isTrue,
      );
    });

    test('flush_done에도 없는 남의 표는 여전히 막힌다', () {
      expect(
        claimMatchesSession(
          claim: claim(uid: 'stranger'),
          session: <String, dynamic>{
            'hostUid': kHostUid,
            'partnerUid': 'later-guest',
            kDuoFlushDoneField: <String, dynamic>{kAnonUid: 1},
          },
        ),
        isFalse,
      );
    });
  });

  group('시간 정합성 — 들어오기도 전에 찍힌 표는 앞뒤가 안 맞는다', () {
    final joined = DateTime(2026, 8, 29, 10);
    Map<String, dynamic> session() => <String, dynamic>{
          'hostUid': kHostUid,
          'partnerUid': kAnonUid,
          'partnerJoinedAt': Timestamp.fromDate(joined),
        };

    test('통화가 끝난 뒤 찍힌 표는 통과', () {
      expect(
        isClaimTemporallyPlausible(
          claim: claim(
              savedAtMs: joined
                  .add(const Duration(minutes: 12))
                  .millisecondsSinceEpoch),
          session: session(),
        ),
        isTrue,
      );
    });

    test('며칠 전 표는 막힌다', () {
      expect(
        isClaimTemporallyPlausible(
          claim: claim(
              savedAtMs: joined
                  .subtract(const Duration(days: 3))
                  .millisecondsSinceEpoch),
          session: session(),
        ),
        isFalse,
      );
    });

    test('기기 시계가 조금 어긋난 정도로는 막지 않는다', () {
      expect(
        isClaimTemporallyPlausible(
          claim: claim(
              savedAtMs: joined
                  .subtract(const Duration(hours: 2))
                  .millisecondsSinceEpoch),
          session: session(),
        ),
        isTrue,
      );
    });

    test('입장 시각이 없는 옛 방은 막지 않는다', () {
      expect(
        isClaimTemporallyPlausible(
          claim: claim(),
          session: <String, dynamic>{'hostUid': kHostUid},
        ),
        isTrue,
      );
    });
  });

  group('이미 있는 방이 온전한가 (케이스 3)', () {
    test('통화 중에 쌓인 방(복구본이 아님) + 줄 있음 → 온전하다', () {
      expect(
        restoredHistoryIsComplete(
          history: <String, dynamic>{kDuoRoomIdField: kRoom},
          messageCount: 14,
        ),
        isTrue,
      );
    });

    test('방 문서만 있고 줄이 하나도 없으면 온전하지 않다', () {
      expect(
        restoredHistoryIsComplete(
          history: <String, dynamic>{kDuoRoomIdField: kRoom},
          messageCount: 0,
        ),
        isFalse,
      );
    });

    test('복구본인데 완료 표식이 없으면 — 줄이 좀 있어도 — 쓰다 만 방이다', () {
      expect(
        restoredHistoryIsComplete(
          history: <String, dynamic>{
            kDuoRoomIdField: kRoom,
            kDuoRestoreExpectedField: 600,
            kDuoRestoreCompleteField: false,
          },
          messageCount: 450,
        ),
        isFalse,
      );
    });

    test('복구본 + 완료 표식 + 줄 수가 채워졌으면 온전하다', () {
      expect(
        restoredHistoryIsComplete(
          history: <String, dynamic>{
            kDuoRoomIdField: kRoom,
            kDuoRestoreExpectedField: 600,
            kDuoRestoreCompleteField: true,
          },
          messageCount: 600,
        ),
        isTrue,
      );
    });

    test('완료 표식이 찍혔는데 줄이 모자라면 믿지 않는다', () {
      expect(
        restoredHistoryIsComplete(
          history: <String, dynamic>{
            kDuoRoomIdField: kRoom,
            kDuoRestoreExpectedField: 600,
            kDuoRestoreCompleteField: true,
          },
          messageCount: 12,
        ),
        isFalse,
      );
    });
  });

  group('표를 언제 남기고 언제 지우는가', () {
    test('틀린 계정으로 먼저 로그인해도 표는 남는다 (케이스 1)', () {
      expect(claimSurvives(DuoRestoreOutcome.notParticipant), isTrue);
    });

    test('공유 결과가 아직이면 남는다 (케이스 4)', () {
      expect(claimSurvives(DuoRestoreOutcome.canonicalNotReady), isTrue);
    });

    test('복구가 실패하면 남는다 (케이스 5)', () {
      expect(claimSurvives(DuoRestoreOutcome.failed), isTrue);
      expect(claimSurvives(DuoRestoreOutcome.incompleteRetry), isTrue);
    });

    test('복구에 성공하면 지운다 (케이스 6)', () {
      expect(claimSurvives(DuoRestoreOutcome.restored), isFalse);
    });

    test('되찾을 이유가 사라진 경우도 지운다', () {
      expect(claimSurvives(DuoRestoreOutcome.sameAccount), isFalse);
      expect(claimSurvives(DuoRestoreOutcome.alreadyPresent), isFalse);
      expect(claimSurvives(DuoRestoreOutcome.expired), isFalse);
      expect(claimSurvives(DuoRestoreOutcome.noClaim), isFalse);
    });

    test('틀린 계정 → 올바른 계정 순서로 로그인하면 두 번째에 복구된다 (케이스 1·2)', () {
      // 첫 번째: 남의 계정 — 통과하지 못하고, 표는 살아남는다.
      final wrong = claimMatchesSession(
        claim: claim(),
        session: <String, dynamic>{
          'hostUid': kHostUid,
          'partnerUid': 'someone-else',
        },
      );
      expect(wrong, isFalse);
      expect(claimSurvives(DuoRestoreOutcome.notParticipant), isTrue);
      // 두 번째: 표가 그대로 있으므로 같은 검증을 다시 밟는다.
      final right = claimMatchesSession(
        claim: claim(),
        session: <String, dynamic>{
          'hostUid': kHostUid,
          'partnerUid': kAnonUid,
        },
      );
      expect(right, isTrue);
    });
  });

  group('배치 한도 (500 write)', () {
    List<Map<String, dynamic>> rows(int n) => List<Map<String, dynamic>>.generate(
        n, (i) => <String, dynamic>{'i': i});

    test('짧은 통화는 한 배치로 끝난다', () {
      expect(chunkForBatch(rows(40)).length, 1);
    });

    test('한도를 넘으면 나눠 쓴다 — 통째로 거절당하지 않는다', () {
      final chunks = chunkForBatch(rows(1001));
      expect(chunks.length, 3);
      expect(chunks.every((c) => c.length <= kFirestoreBatchLimit), isTrue);
      expect(chunks.fold<int>(0, (n, c) => n + c.length), 1001);
    });

    test('줄이 없으면 배치도 없다', () {
      expect(chunkForBatch(rows(0)), isEmpty);
    });
  });

  group('공유 결과 → 내 방의 줄 (케이스 4)', () {
    final turns = <DuoCanonicalTurn>[
      turn('HOST', '여보세요?', 100),
      turn('GUEST', '응, 나야.', 200),
      turn('HOST', '음…', 300, state: kStudyStateHiddenHesitation),
      turn('GUEST', '지금 갈게.', 400, ids: <String>['s1', 's2']),
    ];

    test('게스트였던 사람의 방에서는 자기 말이 HOST, 상대가 SYSTEM이다', () {
      final rows = duoCanonicalToHistoryMessages(
        turns: turns,
        myRole: 'GUEST',
        canonicalVersion: 7,
      );
      expect(rows.map((r) => r['role']),
          <String>['SYSTEM', 'HOST', 'SYSTEM', 'HOST']);
    });

    test('호스트였던 사람의 방에서는 반대가 된다', () {
      final rows = duoCanonicalToHistoryMessages(
        turns: turns,
        myRole: 'HOST',
        canonicalVersion: 7,
      );
      expect(rows.map((r) => r['role']),
          <String>['HOST', 'SYSTEM', 'HOST', 'SYSTEM']);
    });

    test('감춘 줄도 지우지 않고 그대로 옮긴다 — 보일지는 study_state가 정한다', () {
      final rows = duoCanonicalToHistoryMessages(
        turns: turns,
        myRole: 'GUEST',
        canonicalVersion: 7,
      );
      expect(rows.length, turns.length);
      expect(rows[2][kStudyStateField], kStudyStateHiddenHesitation);
      expect(isStudyVisible(rows[2][kStudyStateField]), isFalse);
      expect(isStudyVisible(rows[0][kStudyStateField]), isTrue);
    });

    test('말한 순서가 created_at으로 남는다 — 목록이 그 순서로 그린다', () {
      final rows = duoCanonicalToHistoryMessages(
        turns: turns,
        myRole: 'GUEST',
        canonicalVersion: 7,
      );
      final times = rows
          .map((r) => (r['created_at'] as Timestamp).millisecondsSinceEpoch)
          .toList();
      expect(times, <int>[100, 200, 300, 400]);
      for (var i = 1; i < times.length; i++) {
        expect(times[i] > times[i - 1], isTrue);
      }
    });

    test('시간이 없는 줄도 순서를 잃지 않는다', () {
      final rows = duoCanonicalToHistoryMessages(
        turns: <DuoCanonicalTurn>[
          const DuoCanonicalTurn(
              role: 'HOST',
              text: 'a',
              sourceIds: <String>['x'],
              state: kStudyStateIncluded),
          const DuoCanonicalTurn(
              role: 'GUEST',
              text: 'b',
              sourceIds: <String>['y'],
              state: kStudyStateIncluded),
        ],
        myRole: 'GUEST',
        canonicalVersion: 1,
        fallbackBaseMs: 1000,
      );
      final times = rows
          .map((r) => (r['created_at'] as Timestamp).millisecondsSinceEpoch)
          .toList();
      expect(times, <int>[1000, 1001]);
    });

    test('채널 원본 고리를 남긴다 — 나중에 같은 판을 두 번 덧칠하지 않게', () {
      final rows = duoCanonicalToHistoryMessages(
        turns: turns,
        myRole: 'GUEST',
        canonicalVersion: 7,
      );
      expect(rows[3]['channel_msg_id'], 's1');
      expect(rows.every((r) => r['canonical_version'] == 7), isTrue);
    });

    test('배울글은 비워 둔다 — 공부방이 만든다(회원이 되어야 만들어진다)', () {
      final rows = duoCanonicalToHistoryMessages(
        turns: turns,
        myRole: 'GUEST',
        canonicalVersion: 7,
      );
      expect(rows.every((r) => r['translated_text'] == ''), isTrue);
      expect(rows[0]['original_text'], '여보세요?');
    });
  });
}
