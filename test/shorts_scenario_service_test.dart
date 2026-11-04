import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/history_finalize.dart';
import 'package:stealth_vox/custom_code/services/shorts_scenario_service.dart';

Map<String, dynamic> _server() => {
      'usable': true,
      'title': '옷가게에서 더 작은 사이즈 찾기',
      'userRole': '손님',
      'partnerRole': '점원',
      'lines': [
        {
          'speaker': 'user',
          'text': 'Do you have this in a smaller size?',
          'meaning': '이거 더 작은 사이즈 있나요?',
        },
        {'speaker': 'partner', 'text': 'That is a small.', 'meaning': '그게 스몰이에요.'},
        {'speaker': 'user', 'text': '', 'meaning': '빈 문장은 버린다'},
        'not a map',
      ],
      'sourceUrl': 'https://www.youtube.com/shorts/QEw4oTtNUac',
    };

void main() {
  test('server result becomes a two-person dialogue', () {
    final d = parseShortsDialogue(_server());
    expect(d.title, '옷가게에서 더 작은 사이즈 찾기');
    expect(d.userRole, '손님');
    expect(d.partnerRole, '점원');
    expect(d.lines, hasLength(2));
    expect(d.lines.first.isUser, isTrue);
    expect(d.lines.last.isUser, isFalse);
    expect(d.sourceUrl, 'https://www.youtube.com/shorts/QEw4oTtNUac');
  });

  test('unusable or broken results throw the right code', () {
    Matcher code(String c) =>
        throwsA(isA<ShortsScenarioException>().having((e) => e.code, 'code', c));
    expect(() => parseShortsDialogue({'usable': false}), code('unusable'));
    expect(() => parseShortsDialogue({..._server(), 'lines': []}), code('unusable'));
    expect(
      () => parseShortsDialogue({
        ..._server(),
        'lines': [
          {'speaker': 'partner', 'text': 'A', 'meaning': '가'},
          {'speaker': 'partner', 'text': 'B', 'meaning': '나'},
        ],
      }),
      code('unusable'),
    );
    expect(() => parseShortsDialogue('x'), code('failed'));
  });

  test('room doc looks like a Scenario Talk room and starts as draft', () {
    final room = shortsRoomDoc(
      parseShortsDialogue(_server()),
      nativeLang: 'Korean',
      targetLang: 'English',
      createdAt: 'NOW',
    );
    expect(room['mode'], 'scenario_talk');
    expect(room['scenario_situation'], '옷가게에서 더 작은 사이즈 찾기');
    expect(room['user_role'], '손님');
    expect(room['ai_role'], '점원');
    expect(room['native_lang'], 'Korean');
    expect(room['target_lang'], 'English');
    expect(room['msg_count'], 2);
    expect(room['last_message'], '그게 스몰이에요.');
    expect(room['shorts_source_url'], 'https://www.youtube.com/shorts/QEw4oTtNUac');
    expect(room[kHistoryStateField], kHistoryStateDraft);
  });

  test('message docs keep the Shorts wording as Target and are one second apart', () {
    final base = DateTime.utc(2026, 11, 5, 0, 0, 0);
    final docs = shortsMessageDocs(parseShortsDialogue(_server()), base: base);
    expect(docs, hasLength(2));
    expect(docs[0]['role'], 'HOST');
    expect(docs[1]['role'], 'SYSTEM');
    expect(docs[0]['translated_text'], 'Do you have this in a smaller size?');
    expect(docs[0]['original_text'], '이거 더 작은 사이즈 있나요?');
    final t0 = (docs[0]['created_at'] as Timestamp).toDate();
    final t1 = (docs[1]['created_at'] as Timestamp).toDate();
    expect(t1.difference(t0), const Duration(seconds: 1));
  });

  test('function error codes map to screen copy codes', () {
    expect(shortsErrorCodeFor('invalid-argument'), 'notYoutube');
    expect(shortsErrorCodeFor('not-found'), 'unavailable');
    expect(shortsErrorCodeFor('resource-exhausted'), 'limit');
    expect(shortsErrorCodeFor('permission-denied'), 'noTime');
    expect(shortsErrorCodeFor('out-of-range'), 'adultOnly');
    expect(shortsErrorCodeFor('internal'), 'failed');
  });

  test('youtube link check', () {
    expect(looksLikeYoutubeLink('https://youtube.com/shorts/QEw4oTtNUac?si=x'), isTrue);
    expect(looksLikeYoutubeLink(' https://youtu.be/QEw4oTtNUac '), isTrue);
    expect(looksLikeYoutubeLink('https://www.tiktok.com/@a/video/1'), isFalse);
  });
}
