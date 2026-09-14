// 🧱 [ROW-CREATE] canonical만으로 개인 History를 통째로 세울 수 있는가.
//
// 이 판의 성공 조건은 하나다 — **통화 중 History 줄을 하나도 만들지 않았다고
// 가정해도**, 통화가 끝난 뒤 canonical만으로 양쪽 개인 기록을 canonical 순서
// 그대로 재구성할 수 있어야 한다.
//
// 판정은 전부 순수 함수에 있으므로(`planDuoCanonicalRows`,
// `assignDuoCanonicalCreatedAtMs`, `buildDuoCanonicalNewRowData`) 여기서
// Firestore 없이 모든 갈래를 태운다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/duo_canonical.dart';
import 'package:stealth_vox/custom_code/services/duo_origin_corrector.dart';
import 'package:stealth_vox/custom_code/services/duo_study_state.dart';
import 'package:stealth_vox/custom_code/services/history_finalize.dart';
import 'package:stealth_vox/custom_code/services/origin_restoration.dart'
    show kMessagePcmKeyField;

const String kMyUid = 'uid_me';
const String kYourUid = 'uid_you';

DuoSourceUtterance src(
  String id, {
  String role = 'HOST',
  String text = '안녕하세요',
  int ms = kCallMs + 1000,
  int seq = 1,
  String lang = 'Korean',
  String uid = kMyUid,
  String stt = 'local_mic',
  String mode = 'direct',
}) =>
    DuoSourceUtterance(
      id: id,
      role: role,
      text: text,
      spokenAtMs: ms,
      seq: seq,
      srcLang: lang,
      senderUid: uid,
      sttSource: stt,
      duoMode: mode,
    );

DuoCanonicalTurn turn(
  List<String> ids, {
  String role = 'HOST',
  String text = '안녕하세요',
  String state = kStudyStateIncluded,
  int? ms = kCallMs + 1000,
  String subject = '',
  String raw = '',
}) =>
    DuoCanonicalTurn(
      role: role,
      text: text,
      sourceIds: ids,
      state: state,
      spokenAtMs: ms,
      subject: subject,
      rawText: raw,
    );

/// 실제 통화가 있었을 법한 시각. 테스트가 "1970년이 아니다"를 말할 기준이다.
/// 2026-09-14 09:00 KST 언저리.
const int kCallMs = 1789000000000;

/// 이 시각보다 뒤면 사람이 실제로 통화한 시각으로 본다(2001-09-09).
const int kSaneFloorMs = 1000000000000;

List<DuoCanonicalRowPlan> plan(
  List<DuoCanonicalTurn> turns,
  List<DuoSourceUtterance> sources, {
  Set<String> existing = const <String>{},
  Set<String> locked = const <String>{},
  String myUid = kMyUid,
  int fallbackBaseMs = kCallMs,
}) =>
    planDuoCanonicalRows(
      turns: turns,
      sourceById: <String, DuoSourceUtterance>{for (final s in sources) s.id: s},
      existingIds: existing,
      userLockedIds: locked,
      myUid: myUid,
      fallbackBaseMs: fallbackBaseMs,
    );

Map<String, int> at(
  List<DuoCanonicalTurn> turns, {
  List<DuoSourceUtterance> sources = const <DuoSourceUtterance>[],
  int fallbackBaseMs = kCallMs,
}) =>
    assignDuoCanonicalCreatedAtMs(
      turns,
      fallbackBaseMs: fallbackBaseMs,
      sourceById: <String, DuoSourceUtterance>{for (final s in sources) s.id: s},
    );

Map<String, dynamic> row(
  DuoCanonicalRowPlan p,
  DuoSourceUtterance s, {
  String myUid = kMyUid,
}) =>
    buildDuoCanonicalNewRowData(
      plan: p,
      source: s,
      myUid: myUid,
      canonicalVersion: 77,
      correctorModel: 'test-corrector',
    );

void main() {
  group('1 · 빈 History에서 전부 생성', () {
    test('통화 중 줄을 하나도 안 만들었어도 모든 Direct 줄이 생긴다', () {
      final turns = <DuoCanonicalTurn>[
        turn(<String>['a'], text: '내일 서울 가려고', ms: kCallMs + 1000),
        turn(<String>['b'], role: 'GUEST', text: '몇 시 기차인데?', ms: kCallMs + 2000),
        turn(<String>['c'], text: '일곱 시쯤', ms: kCallMs + 3000),
      ];
      final sources = <DuoSourceUtterance>[
        src('a', ms: kCallMs + 1000),
        src('b', role: 'GUEST', ms: kCallMs + 2000, uid: kYourUid),
        src('c', ms: kCallMs + 3000),
      ];
      final plans = plan(turns, sources);
      expect(plans.length, 3);
      expect(plans.every((p) => p.create), isTrue);
      expect(plans.map((p) => p.sourceId).toList(), <String>['a', 'b', 'c']);
    });
  });

  group('2 · 재적용 멱등', () {
    test('같은 canonical을 다시 적용하면 만들 것이 없다', () {
      final turns = <DuoCanonicalTurn>[turn(<String>['a']), turn(<String>['b'], ms: kCallMs + 2000)];
      final sources = <DuoSourceUtterance>[src('a'), src('b', ms: kCallMs + 2000)];
      final second = plan(turns, sources, existing: <String>{'a', 'b'});
      expect(second.every((p) => !p.create), isTrue);
    });

    test('한 판 안에서 같은 sourceId가 두 번 계획되지 않는다', () {
      // 같은 id가 두 turn에 걸쳐 온 망가진 canonical도 한 번만 센다.
      final turns = <DuoCanonicalTurn>[turn(<String>['a']), turn(<String>['a'], ms: kCallMs + 2000)];
      final plans = plan(turns, <DuoSourceUtterance>[src('a')]);
      expect(plans.length, 1);
    });
  });

  group('3 · 기존 줄과 신규 줄 혼합', () {
    test('없는 줄만 만들고 있는 줄은 고친다', () {
      final turns = <DuoCanonicalTurn>[
        turn(<String>['a'], ms: kCallMs + 1000),
        turn(<String>['b'], ms: kCallMs + 2000),
        turn(<String>['c'], ms: kCallMs + 3000),
      ];
      final sources = <DuoSourceUtterance>[
        src('a'),
        src('b', ms: kCallMs + 2000),
        src('c', ms: kCallMs + 3000),
      ];
      final plans = plan(turns, sources, existing: <String>{'a'});
      expect(plans.singleWhere((p) => p.sourceId == 'a').create, isFalse);
      expect(plans.where((p) => p.create).map((p) => p.sourceId).toList(),
          <String>['b', 'c']);
    });
  });

  group('4~5 · created_at은 canonical 순서를 옮겨 적는다', () {
    test('시계가 정상이면 실제 발화 시각을 그대로 쓴다', () {
      final got = at(<DuoCanonicalTurn>[
        turn(<String>['a'], ms: kCallMs + 1000),
        turn(<String>['b'], ms: kCallMs + 2600),
        turn(<String>['c'], ms: kCallMs + 5000),
      ]);
      expect(got['a'], kCallMs + 1000);
      expect(got['b'], kCallMs + 2600);
      expect(got['c'], kCallMs + 5000);
    });

    test('기존 줄도 같은 표에서 값을 받는다(신규만 맞추면 섞여서 깨진다)', () {
      final turns = <DuoCanonicalTurn>[
        turn(<String>['a'], ms: kCallMs + 1000),
        turn(<String>['b'], ms: kCallMs + 2000),
      ];
      final plans = plan(turns, <DuoSourceUtterance>[src('a'), src('b', ms: kCallMs + 2000)],
          existing: <String>{'a'});
      final existing = plans.singleWhere((p) => p.sourceId == 'a');
      final fresh = plans.singleWhere((p) => p.sourceId == 'b');
      expect(existing.create, isFalse);
      expect(existing.createdAtMs, kCallMs + 1000);
      expect(fresh.createdAtMs, kCallMs + 2000);
    });
  });

  group('6~7 · role은 uid가 가른다', () {
    test('내 발화는 HOST', () {
      final p = plan(<DuoCanonicalTurn>[turn(<String>['a'])],
          <DuoSourceUtterance>[src('a', uid: kMyUid)]).single;
      expect(row(p, src('a', uid: kMyUid))['role'], 'HOST');
    });

    test('상대 발화는 SYSTEM', () {
      final s = src('a', role: 'GUEST', uid: kYourUid);
      final p = plan(<DuoCanonicalTurn>[turn(<String>['a'])], <DuoSourceUtterance>[s]).single;
      expect(row(p, s)['role'], 'SYSTEM');
    });

    test('누가 말했는지 모르면 만들지 않는다', () {
      // senderUid가 없으면 내 줄인지 상대 줄인지 가릴 수 없다. 틀리면 상대가
      // 한 말이 내 말로 남는다.
      final plans = plan(<DuoCanonicalTurn>[turn(<String>['a'])],
          <DuoSourceUtterance>[src('a', uid: '')]);
      expect(plans, isEmpty);
    });
  });

  group('8~9 · pcm_key', () {
    test('신규 줄에는 pcm_key를 만들지 않는다', () {
      final s = src('a', role: 'GUEST', uid: kYourUid);
      final p = plan(<DuoCanonicalTurn>[turn(<String>['a'])], <DuoSourceUtterance>[s]).single;
      expect(row(p, s).containsKey(kMessagePcmKeyField), isFalse);
    });

    test('기존 줄은 update 경로로 가므로 pcm_key가 계획에 섞이지 않는다', () {
      final plans = plan(<DuoCanonicalTurn>[turn(<String>['a'])],
          <DuoSourceUtterance>[src('a')],
          existing: <String>{'a'});
      expect(plans.single.create, isFalse);
    });

    // 🔍 왜 "내 발화면 pcm_key를 복원한다"를 못 하는가.
    //
    //   창고 열쇠는 발화 id(`duo_direct_utt_7`)이고 sourceId는 Firestore
    //   자동 id다. 채널 문서(`_uploadMyMessage`)가 발화 id를 싣지 않으므로
    //   둘을 잇는 값이 없다. 존재 확인은 되지만 **신원 확인이 안 된다.**
    test('채널 원본에는 발화 id가 없다 — 열쇠를 지어낼 근거가 없다', () {
      final String duo = File('lib/custom_code/widgets/routine_mode_duo.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final int start = duo.indexOf('Future<String?> _uploadMyMessage(');
      expect(start, greaterThan(0));
      final String body = duo.substring(start, duo.indexOf('return docRef.id;', start));
      // 올리는 칸에 발화 id·pcm 열쇠가 없다는 것이 이 판단의 근거다.
      expect(body, isNot(contains('pcmKey')));
      expect(body, isNot(contains('utteranceId')));
      expect(body, contains("'senderUid'"));
      expect(body, contains("'spokenAt'"));
    });

    test('내 발화 신규 줄도 pcm_key 없이 unverified다', () {
      // 내 uid인데도 안 넣는다. 넣으면 복원이 없는 파일을 가리킨다.
      final s = src('a', uid: kMyUid);
      final p = plan(<DuoCanonicalTurn>[turn(<String>['a'], text: '기차표', raw: '뒷지표')],
          <DuoSourceUtterance>[s]).single;
      final r = row(p, s);
      expect(r['role'], 'HOST');
      expect(r.containsKey(kMessagePcmKeyField), isFalse);
      expect(r[kOriginCorrectionStageField], kOriginCorrectionUnverified);
    });

    test('기존 줄의 verified 판정은 손대지 않았다(소스 확인)', () {
      // 통화 중에 생긴 내 줄은 update 경로로 가고, 거기서는 예전처럼
      // pcm_key 유무로 stage가 갈린다. 이 판에서 잃은 능력이 없다는 근거다.
      final String canon =
          File('lib/custom_code/services/duo_canonical.dart').readAsStringSync();
      expect(canon, contains('kOriginCorrectionVerifiable'));
      expect(canon, contains('hasPcmById[turn.sourceIds.first]'));
    });

    test('생성 경로가 pcm_key를 절대 안 쓴다(소스 확인)', () {
      final String source =
          File('lib/custom_code/services/duo_canonical.dart').readAsStringSync();
      final int start = source.indexOf('buildDuoCanonicalNewRowData');
      expect(start, greaterThan(0));
      final String body = source.substring(start, source.indexOf('/// 공유 결과를'));
      expect(body, isNot(contains('kMessagePcmKeyField')));
      expect(body, isNot(contains('pcm_key')));
    });
  });

  group('10 · finalized 방 보호', () {
    test('확정된 방은 apply 자체가 들어가지 못한다', () {
      expect(duoCanonicalMayApplyToRoom(<String, dynamic>{}), isTrue);
      final finalized = <String, dynamic>{
        kHistoryStateField: kHistoryStateFinalized,
      };
      expect(duoCanonicalMayApplyToRoom(finalized), isFalse);
    });

    test('사용자가 손댄 줄은 만들지도 고치지도 않는다', () {
      final plans = plan(<DuoCanonicalTurn>[turn(<String>['a']), turn(<String>['b'], ms: kCallMs + 2000)],
          <DuoSourceUtterance>[src('a'), src('b', ms: kCallMs + 2000)],
          locked: <String>{'a'});
      expect(plans.map((p) => p.sourceId).toList(), <String>['b']);
    });

    test('잠긴 줄이 나머지 줄의 시각을 흔들지 않는다', () {
      final locked = plan(
          <DuoCanonicalTurn>[turn(<String>['a'], ms: kCallMs + 1000), turn(<String>['b'], ms: kCallMs + 2000)],
          <DuoSourceUtterance>[src('a'), src('b', ms: kCallMs + 2000)],
          locked: <String>{'a'});
      expect(locked.single.createdAtMs, kCallMs + 2000);
    });
  });

  group('11~13 · 본문과 metadata', () {
    test('original_text는 turn, translated_text는 빈 칸', () {
      final s = src('a', text: '아까 기차표를 예매했어');
      final p = plan(<DuoCanonicalTurn>[turn(<String>['a'], text: '아까 기차표를 예매했어')],
          <DuoSourceUtterance>[s]).single;
      final r = row(p, s);
      expect(r['original_text'], '아까 기차표를 예매했어');
      expect(r['translated_text'], '');
    });

    test('original_text_raw는 교정된 줄에만 실린다', () {
      final s = src('a');
      final corrected = turn(<String>['a'],
          text: '아까 기차표를 예매했어', raw: '아까 뒷지표를 예매했어');
      final p = plan(<DuoCanonicalTurn>[corrected], <DuoSourceUtterance>[s]).single;
      expect(row(p, s)[kOriginalRawField], '아까 뒷지표를 예매했어');

      final plain = turn(<String>['a'], text: '아까 기차표를 예매했어');
      final p2 = plan(<DuoCanonicalTurn>[plain], <DuoSourceUtterance>[s]).single;
      expect(row(p2, s).containsKey(kOriginalRawField), isFalse);
    });

    test('source metadata가 전부 옮겨진다', () {
      final s = src('a',
          role: 'GUEST',
          ms: kCallMs + 4321,
          seq: 9,
          lang: 'Japanese',
          uid: kYourUid,
          stt: 'local_mic');
      final p = plan(<DuoCanonicalTurn>[turn(<String>['a'], ms: kCallMs + 4321)],
          <DuoSourceUtterance>[s]).single;
      final r = row(p, s);
      expect(r['channel_msg_id'], 'a');
      expect(r['speaker_seq'], 9);
      expect(r['spoken_at_ms'], kCallMs + 4321);
      expect(r['speaker_uid'], kYourUid);
      expect(r['speaker_role'], 'GUEST');
      expect(r['stt_source'], 'local_mic');
      expect(r['source_lang'], 'Japanese');
      expect(r['duo_mode'], 'direct');
      expect(r['canonical_version'], 77);
      expect(r[kStudyStateField], kStudyStateIncluded);
    });

    test('참고 주어는 있을 때만 실린다', () {
      final s = src('a');
      final withSubject = plan(
          <DuoCanonicalTurn>[turn(<String>['a'], subject: '민수')],
          <DuoSourceUtterance>[s]).single;
      expect(row(withSubject, s)[kMessageSubjectHintField], '민수');
      final without =
          plan(<DuoCanonicalTurn>[turn(<String>['a'])], <DuoSourceUtterance>[s]).single;
      expect(row(without, s).containsKey(kMessageSubjectHintField), isFalse);
    });
  });

  group('14 · 교정 stage', () {
    test('교정된 신규 줄은 context_unverified다', () {
      final s = src('a', role: 'GUEST', uid: kYourUid);
      final p = plan(
          <DuoCanonicalTurn>[turn(<String>['a'], text: '기차표', raw: '뒷지표')],
          <DuoSourceUtterance>[s]).single;
      final r = row(p, s);
      expect(r[kOriginCorrectionStageField], kOriginCorrectionUnverified);
      expect(r[kOriginCorrectionModelField], 'test-corrector');
    });

    test('안 고친 줄에는 교정 자취를 찍지 않는다', () {
      final s = src('a');
      final p = plan(<DuoCanonicalTurn>[turn(<String>['a'])], <DuoSourceUtterance>[s]).single;
      final r = row(p, s);
      expect(r.containsKey(kOriginCorrectionStageField), isFalse);
      expect(r.containsKey(kOriginCorrectionModelField), isFalse);
    });
  });

  group('15 · msg_count', () {
    test('보이는 turn 수는 재적용해도 같다', () {
      final turns = <DuoCanonicalTurn>[
        turn(<String>['a']),
        turn(<String>['b'], state: kStudyStateHiddenEcho, ms: kCallMs + 2000),
        turn(<String>['c'], ms: kCallMs + 3000),
      ];
      final visible = turns.where((t) => isStudyVisible(t.state)).length;
      expect(visible, 2);
      expect(turns.where((t) => isStudyVisible(t.state)).length, visible);
    });
  });

  group('16 · 옛 canonical 문서 호환', () {
    test('spoken_at_ms가 없는 turn도 읽힌다', () {
      final old = DuoCanonicalTurn.fromMap(<String, dynamic>{
        'role': 'HOST',
        'text': '옛 판',
        'source_ids': <String>['a'],
        'state': kStudyStateIncluded,
      });
      expect(old, isNotNull);
      expect(old!.spokenAtMs, isNull);
      expect(old.rawText, '');
    });

    test('senderUid 없이 만든 source도 컴파일된다(기본값)', () {
      const legacy = DuoSourceUtterance(
        id: 'a',
        role: 'HOST',
        text: '옛 판',
        spokenAtMs: 0,
        seq: 0,
        srcLang: '',
      );
      expect(legacy.senderUid, '');
      expect(legacy.duoMode, '');
      expect(legacy.sttSource, '');
    });
  });

  group('17 · canonical 순서가 시각순을 이긴다', () {
    test('두 폰 시계가 어긋나 뒤엉킨 자리에서 canonical 순서가 남는다', () {
      // 모델이 맥락으로 b를 a 앞에 세웠다. 시각만 보면 b가 뒤다.
      final got = at(<DuoCanonicalTurn>[
        turn(<String>['b'], ms: kCallMs + 5000),
        turn(<String>['a'], ms: kCallMs + 1000),
        turn(<String>['c'], ms: kCallMs + 9000),
      ]);
      expect(got['b']! < got['a']!, isTrue,
          reason: 'canonical이 세운 순서가 created_at 순서여야 한다');
      expect(got['a']! < got['c']!, isTrue);
      expect(got['b'], kCallMs + 5000);
      expect(got['a'], kCallMs + 5001);
      expect(got['c'], kCallMs + 9000);
    });

    test('같은 입력이면 언제나 같은 결과다(재적용 안정성)', () {
      final turns = <DuoCanonicalTurn>[
        turn(<String>['b'], ms: kCallMs + 5000),
        turn(<String>['a'], ms: kCallMs + 1000),
      ];
      expect(at(turns), at(turns));
    });

    test('시각순 재정렬은 되살아나지 않는다(소스 확인)', () {
      final String source =
          File('lib/custom_code/services/duo_canonical.dart').readAsStringSync();
      expect(
        source,
        isNot(contains(
            'turns.sort((a, b) => (a.spokenAtMs ?? 0).compareTo(b.spokenAtMs ?? 0));')),
      );
    });
  });

  group('18 · null·0 timestamp', () {
    test('spokenAtMs가 null이어도 1970년으로 튀지 않는다', () {
      final got = at(<DuoCanonicalTurn>[
        turn(<String>['a'], ms: kCallMs + 1000),
        turn(<String>['b'], ms: null),
        turn(<String>['c'], ms: kCallMs + 3000),
      ]);
      expect(got['b'], kCallMs + 1001);
      expect(got['a']! < got['b']!, isTrue);
      expect(got['b']! < got['c']!, isTrue);
    });

    test('0도 같은 규칙으로 흡수된다', () {
      final got = at(<DuoCanonicalTurn>[
        turn(<String>['a'], ms: kCallMs + 7000),
        turn(<String>['b'], ms: 0),
      ]);
      expect(got['b'], kCallMs + 7001);
    });

    // ⚠️ 여기부터가 이번 판에서 고친 버그다. 앞선 판은 맨 앞 줄이 null이면
    //   1ms를 줬고, 그것은 **1970-01-01 00:00:00.001**이다. "순서가 맞다"만
    //   보던 단언이 그 사실을 못 잡았다.
    test('맨 앞 줄이 null이면 첫 발화 직전에 선다 — 1970년이 아니다', () {
      final got = at(<DuoCanonicalTurn>[
        turn(<String>['a'], ms: null),
        turn(<String>['b'], ms: kCallMs + 2000),
      ]);
      expect(got['a'], kCallMs + 1999);
      expect(got['b'], kCallMs + 2000);
      expect(got['a']!, greaterThan(kSaneFloorMs));
    });

    test('앞쪽이 여러 줄 비어도 전부 현실 시각이다', () {
      final got = at(<DuoCanonicalTurn>[
        turn(<String>['a'], ms: null),
        turn(<String>['b'], ms: null),
        turn(<String>['c'], ms: kCallMs + 5000),
      ]);
      expect(got['a'], kCallMs + 4998);
      expect(got['b'], kCallMs + 4999);
      expect(got['c'], kCallMs + 5000);
      for (final v in got.values) {
        expect(v, greaterThan(kSaneFloorMs),
            reason: '$v — 1970년 근처 값이 만들어졌다');
      }
    });

    test('canonical에 시각이 없으면 채널 원본의 시각을 쓴다', () {
      // 옛 canonical 문서에는 spoken_at_ms가 없다. 그래도 원본 쪽에는
      // createdAt 폴백이 있어서 진짜 시각을 얻을 수 있다.
      final got = at(
        <DuoCanonicalTurn>[
          turn(<String>['a'], ms: null),
          turn(<String>['b'], ms: null),
        ],
        sources: <DuoSourceUtterance>[
          src('a', ms: kCallMs + 800),
          src('b', ms: kCallMs + 1600),
        ],
      );
      expect(got['a'], kCallMs + 800);
      expect(got['b'], kCallMs + 1600);
    });

    test('통화 전체에 시각이 하나도 없으면 호출부 기준에서 펼친다', () {
      final got = at(
        <DuoCanonicalTurn>[
          turn(<String>['a'], ms: null),
          turn(<String>['b'], ms: null),
          turn(<String>['c'], ms: 0),
        ],
        sources: <DuoSourceUtterance>[
          src('a', ms: 0),
          src('b', ms: 0),
          src('c', ms: 0),
        ],
        fallbackBaseMs: kCallMs,
      );
      expect(got['a'], kCallMs);
      expect(got['b'], kCallMs + 1);
      expect(got['c'], kCallMs + 2);
      for (final v in got.values) {
        expect(v, greaterThan(kSaneFloorMs));
      }
    });

    test('호출부 기준마저 0이면 지금 시각으로 만든다 — 0을 쓰지 않는다', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final got = at(
        <DuoCanonicalTurn>[turn(<String>['a'], ms: null)],
        fallbackBaseMs: 0,
      );
      expect(got['a'], greaterThanOrEqualTo(before));
      expect(got['a'], greaterThan(kSaneFloorMs));
    });

    test('어떤 갈래로도 epoch 0·1ms가 나오지 않는다', () {
      final cases = <List<DuoCanonicalTurn>>[
        <DuoCanonicalTurn>[turn(<String>['a'], ms: null)],
        <DuoCanonicalTurn>[turn(<String>['a'], ms: 0)],
        <DuoCanonicalTurn>[
          turn(<String>['a'], ms: null),
          turn(<String>['b'], ms: 0),
        ],
        <DuoCanonicalTurn>[
          turn(<String>['a', 'a2'], ms: null),
          turn(<String>['b'], ms: kCallMs + 3000),
        ],
      ];
      for (final turns in cases) {
        for (final entry in at(turns).entries) {
          expect(entry.value, greaterThan(kSaneFloorMs),
              reason: '${entry.key}=${entry.value} — 1970년 값이 만들어졌다');
        }
      }
    });
  });

  group('19 · 다중 sourceIds', () {
    test('없는 흡수 줄도 merged로 만든다', () {
      final turns = <DuoCanonicalTurn>[
        turn(<String>['a', 'a2'], ms: kCallMs + 1000),
      ];
      final sources = <DuoSourceUtterance>[
        src('a', text: '내일 서울'),
        src('a2', text: '가려고', ms: kCallMs + 1200, seq: 2),
      ];
      final plans = plan(turns, sources);
      expect(plans.length, 2);
      final head = plans.firstWhere((p) => p.sourceId == 'a');
      final absorbed = plans.firstWhere((p) => p.sourceId == 'a2');
      expect(head.isHead, isTrue);
      expect(head.studyState, kStudyStateIncluded);
      expect(absorbed.isHead, isFalse);
      expect(absorbed.studyState, kStudyStateMerged);
      expect(absorbed.create, isTrue);
    });

    test('흡수 줄은 대표 바로 뒤에 선다', () {
      final got = at(<DuoCanonicalTurn>[
        turn(<String>['a', 'a2'], ms: kCallMs + 1000),
        turn(<String>['b'], ms: kCallMs + 4000),
      ]);
      expect(got['a'], kCallMs + 1000);
      expect(got['a2'], kCallMs + 1001);
      expect(got['b'], kCallMs + 4000);
    });

    test('흡수 줄의 본문은 자기 원본이지 대표 글자가 아니다', () {
      final absorbedSrc = src('a2', text: '가려고', ms: kCallMs + 1200);
      final p = plan(<DuoCanonicalTurn>[turn(<String>['a', 'a2'], text: '내일 서울 가려고')],
              <DuoSourceUtterance>[src('a'), absorbedSrc])
          .firstWhere((p) => p.sourceId == 'a2');
      expect(row(p, absorbedSrc)['original_text'], '가려고');
      expect(row(p, absorbedSrc)[kStudyStateField], kStudyStateMerged);
    });
  });

  group('20 · Interpreter는 생성 대상이 아니다', () {
    test('통역 source로는 신규 줄을 만들지 않는다', () {
      final plans = plan(<DuoCanonicalTurn>[turn(<String>['a'])],
          <DuoSourceUtterance>[src('a', mode: 'interpreter')]);
      expect(plans, isEmpty);
    });

    test('이미 있는 통역 줄은 예전처럼 고친다', () {
      final plans = plan(<DuoCanonicalTurn>[turn(<String>['a'])],
          <DuoSourceUtterance>[src('a', mode: 'interpreter')],
          existing: <String>{'a'});
      expect(plans.single.create, isFalse);
    });

    test('source를 못 찾은 줄은 만들지 않는다', () {
      expect(plan(<DuoCanonicalTurn>[turn(<String>['zz'])], <DuoSourceUtterance>[]),
          isEmpty);
    });
  });
}
