import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/recording_scenario_service.dart';
import 'package:stealth_vox/custom_code/services/shorts_scenario_service.dart';

void main() {
  test('file extension decides the audio type; unknown or missing is null', () {
    expect(recordingMimeTypeFor('통화 녹음 홍길동_2611.m4a'), 'audio/mp4');
    expect(recordingMimeTypeFor('a.MP3'), 'audio/mpeg');
    expect(recordingMimeTypeFor('a.wav'), 'audio/wav');
    expect(recordingMimeTypeFor('a.3gp'), isNull);
    expect(recordingMimeTypeFor('a.amr'), isNull);
    expect(recordingMimeTypeFor('a.pdf'), isNull);
    expect(recordingMimeTypeFor('noextension'), isNull);
    expect(recordingMimeTypeFor('trailingdot.'), isNull);
  });

  test('server error codes map to screen reasons', () {
    expect(recordingErrorCodeFor('invalid-argument'), 'badFile');
    expect(recordingErrorCodeFor('resource-exhausted'), 'limit');
    expect(recordingErrorCodeFor('permission-denied'), 'noTime');
    expect(recordingErrorCodeFor('out-of-range'), 'adultOnly');
    expect(recordingErrorCodeFor('unavailable'), 'failed');
  });

  test('a recording room carries its own source, shorts rooms keep theirs', () {
    const dialogue = ShortsDialogue(
      title: '병원 예약 바꾸기',
      userRole: '환자',
      partnerRole: '접수 직원',
      lines: [
        ShortsLine(isUser: true, text: 'Can I move it?', meaning: '옮길 수 있나요?'),
        ShortsLine(isUser: false, text: 'Sure.', meaning: '네.'),
      ],
    );
    final room = shortsRoomDoc(dialogue,
        nativeLang: 'Korean',
        targetLang: 'English',
        createdAt: 0,
        source: 'recording');
    expect(room['source'], 'recording');
    expect(room.containsKey('shorts_source_url'), isFalse);
    expect(
      shortsRoomDoc(dialogue,
          nativeLang: 'Korean', targetLang: 'English', createdAt: 0)['source'],
      'shorts',
    );
    final messages =
        shortsMessageDocs(dialogue, base: DateTime(2026, 11, 14), source: 'recording');
    expect(messages.every((m) => m['source'] == 'recording'), isTrue);
  });
}
