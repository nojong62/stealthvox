import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/history_text_model.dart';

void main() {
  test('Duo live translation uses the isolated GPT-6 Luna none configuration',
      () {
    expect(kDuoLiveTranslationModel, 'gpt-6-luna');
    expect(kDuoLiveTranslationReasoningEffort, 'none');
    expect(kDuoLiveTranslationModelOptions, <String, dynamic>{
      'model': 'gpt-6-luna',
      'reasoning_effort': 'none',
    });
    // Luna는 temperature를 받지 않는 형식으로 부른다.
    expect(kDuoLiveTranslationModelOptions.containsKey('temperature'),
        isFalse);
  });

  test('shared post-processing remains on GPT-6 Luna none', () {
    expect(kPostProcessModel, 'gpt-6-luna');
    expect(kPostProcessReasoningEffort, 'none');
  });

  test('in-conversation text work never reasons — reply speed comes first', () {
    expect(kLiveTextReasoningEffort, 'none');
  });
}
