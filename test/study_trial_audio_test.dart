// 🎟️🔊 [STUDY-TRIAL-AUDIO] 소리 경로는 폰마다 같아야 한다 — 관리자 폰이
//   올린 파일을 체험자 폰이 같은 이름으로 찾는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/study_trial_audio.dart';

void main() {
  test('경로는 고정값이다 (FNV-1a 64 + 바이트 길이)', () {
    expect(StudyTrialAudio.objectPath('', ''),
        'study_trial_audio/af63f14c8602103b_1.wav');
  });

  test('칸 이름이나 문장이 다르면 경로도 다르다', () {
    final a = StudyTrialAudio.objectPath('ns_female', '안녕하세요');
    expect(a, startsWith('study_trial_audio/'));
    expect(a, endsWith('.wav'));
    expect(StudyTrialAudio.objectPath('ns_male', '안녕하세요'), isNot(a));
    expect(StudyTrialAudio.objectPath('ns_female', '안녕하세요.'), isNot(a));
    expect(StudyTrialAudio.objectPath('ns_female', '안녕하세요'), a);
  });
}
