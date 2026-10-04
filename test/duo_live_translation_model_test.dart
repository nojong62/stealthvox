import 'package:flutter_test/flutter_test.dart';
import 'package:stealth_vox/custom_code/services/history_text_model.dart';

void main() {
  test('Duo live translation uses the isolated GPT-4o mini configuration', () {
    expect(kDuoLiveTranslationModel, 'gpt-4o-mini');
    expect(kDuoLiveTranslationTemperature, 0);
    expect(kDuoLiveTranslationModelOptions, <String, dynamic>{
      'model': 'gpt-4o-mini',
      'temperature': 0,
    });
    expect(kDuoLiveTranslationModelOptions.containsKey('reasoning_effort'),
        isFalse);
  });

  test('shared post-processing remains on GPT-6 Luna none', () {
    expect(kPostProcessModel, 'gpt-6-luna');
    expect(kPostProcessReasoningEffort, 'none');
  });
}
