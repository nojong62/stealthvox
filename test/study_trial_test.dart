// 🎟️ [STUDY-TRIAL] 체험 대화의 언어 짝(실장님 지시, 2026-10-15).
//   Chat Lang 한국어 → Learn Lang 영어, 나머지 11개 → 한국어.
//   폰 언어가 12개 밖이면 영어 대화를 연다.
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/study_trial.dart';

void main() {
  test('12개 언어, 한국어만 영어를 배운다', () {
    expect(kStudyTrialChatLanguages, hasLength(12));
    for (final lang in kStudyTrialChatLanguages) {
      expect(studyTrialLearnLangFor(lang),
          lang == 'Korean' ? 'English' : 'Korean');
    }
  });

  test('목록 밖 폰 언어는 영어 대화', () {
    expect(studyTrialChatLangForSystem('Japanese'), 'Japanese');
    expect(studyTrialChatLangForSystem('Thai'), 'English');
    expect(studyTrialChatLangForSystem(''), 'English');
  });

  test('짝이 틀리면 만들 수 없다', () {
    expect(studyTrialPairProblem(chatLang: 'Korean', learnLang: 'English'),
        isNull);
    expect(studyTrialPairProblem(chatLang: 'French', learnLang: 'Korean'),
        isNull);
    expect(studyTrialPairProblem(chatLang: 'Korean', learnLang: 'Japanese'),
        isNotNull);
    expect(studyTrialPairProblem(chatLang: 'French', learnLang: 'English'),
        isNotNull);
    expect(studyTrialPairProblem(chatLang: 'Thai', learnLang: 'Korean'),
        isNotNull);
  });

  test('방 표시는 Chat Lang과 함께 적힌다', () {
    expect(studyTrialRoomFields('German'), <String, dynamic>{
      kStudyTrialField: true,
      kStudyTrialChatLangField: 'German',
      'practice_settings': kStudyTrialPracticeSettings,
    });
    expect(kStudyTrialPracticeSettings, <String, dynamic>{
      'echoing': <String, dynamic>{'voice': 'google-female', 'repeat': 2},
      'shadowing': <String, dynamic>{'voice': 'google-male', 'speed': 0.87},
    });
  });
}
